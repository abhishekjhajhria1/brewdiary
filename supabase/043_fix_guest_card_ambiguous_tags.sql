-- ============================================================================
-- brewdiary — fix: venue_guest_card() crashed on an ambiguous `tags` reference.
--
-- ── THE BUG ─────────────────────────────────────────────────────────────────
-- 040 declares the function's OUT column `tags text[]`, and then selects
--
--     (select tags from public.venue_guest_notes n where …)
--
-- unqualified. In PL/pgSQL that name resolves to BOTH the OUT parameter and the
-- table column, so Postgres refuses it at runtime:
--
--     column reference "tags" is ambiguous
--     It could refer to either a PL/pgSQL variable or a table column.
--
-- This is a RUNTIME error, not a load-time one, which is why the migration applied
-- cleanly and every gate stayed green: the build can't see it, no unit test can
-- reach it (the function is server-side), and nothing else calls it. The effect is
-- that the guest book has never actually opened — any staff member tapping a guest
-- got an exception. Exactly the class of failure db:verify exists to catch, and it
-- only surfaced once the harness stopped masking real errors as "transaction aborted".
--
-- ── THE FIX ─────────────────────────────────────────────────────────────────
-- Qualify the column: `n.tags`. Nothing else about the function changes — same
-- signature, same first-party guarantee (no join to public.entries anywhere, so a
-- guest's diary still never reaches a venue), same is_venue_staff gate.
--
-- The sibling selects were already safe by accident: the OUT names `note` and
-- `note_updated_at` differ from the columns `body` and `updated_at`, so only `tags`
-- collided. They are qualified here anyway, so the next edit can't reintroduce this.
--
-- Runs on top of 002..042.
-- ============================================================================

create or replace function public.venue_guest_card(vid uuid, uid uuid)
returns table (
  visits int,
  first_seen timestamptz,
  last_seen timestamptz,
  tabs int,
  total_spend numeric,   -- this venue's own till data for this guest (owner-side, exact)
  perks_claimed int,
  has_earned boolean,
  been_here boolean,      -- false ⇒ no book may be kept (never interacted)
  note text,
  tags text[],
  note_updated_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_venue_staff(vid, me) then
    raise exception 'only this venue''s staff can read its guest book';
  end if;

  return query
  with seen as (
    select m.joined_at as at
      from public.party_members m join public.parties r on r.id = m.party_id
     where r.venue_id = vid and m.user_id = uid and m.status = 'approved'
    union all
    select c.created_at from public.venue_checkins c
     where c.venue_id = vid and c.user_id = uid
  )
  select
    (select count(*)::int from seen),
    (select min(at) from seen),
    (select max(at) from seen),
    (select count(*)::int from public.spend_events se join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.subject_user_id = uid),
    (select coalesce(sum(se.amount), 0)::numeric from public.spend_events se join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.subject_user_id = uid),
    (select count(*)::int from public.perk_redemptions pr where pr.venue_id = vid and pr.user_id = uid),
    (exists (select 1 from public.perk_status(vid, uid) ps where ps.earned)),
    public.has_venue_interaction(vid, uid),
    -- qualified: n.body / n.tags / n.updated_at — never bare column names, which
    -- collide with this function's OUT parameters.
    (select n.body       from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select n.tags       from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select n.updated_at from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid);
end; $$;
revoke all on function public.venue_guest_card(uuid, uuid) from public;
grant execute on function public.venue_guest_card(uuid, uuid) to authenticated;
