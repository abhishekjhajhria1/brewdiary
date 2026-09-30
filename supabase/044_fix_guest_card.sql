-- ============================================================================
-- brewdiary — FIX: venue_guest_card() failed on EVERY call.
--
-- ── THE BUG ─────────────────────────────────────────────────────────────────
-- 040 declared venue_guest_card() as a PL/pgSQL function that RETURNS TABLE (…,
-- tags text[], …) — and inside it read the column of the same name:
--
--     (select tags from public.venue_guest_notes n where …)
--
-- In PL/pgSQL an OUT parameter is a variable, so `tags` could mean the variable or
-- the column, and Postgres refuses to guess:
--
--     ERROR: column reference "tags" is ambiguous
--
-- That is a RUNTIME error, so the migration applied cleanly, db:audit (which reads
-- the definition, never runs it) stayed green, and the bar dashboard's Guest Book
-- could never open a single guest card. Caught by running db:verify against a fresh
-- local schema (scripts/db-local.sh).
--
-- ── THE FIX ─────────────────────────────────────────────────────────────────
-- Qualify every column read from venue_guest_notes with its alias. Same signature,
-- same rows, same privacy line: first-party only, still NO join to public.entries.
-- Runs on top of 002..043.
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
    (select min(s.at) from seen s),
    (select max(s.at) from seen s),
    (select count(*)::int from public.spend_events se join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.subject_user_id = uid),
    (select coalesce(sum(se.amount), 0)::numeric from public.spend_events se join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.subject_user_id = uid),
    (select count(*)::int from public.perk_redemptions pr where pr.venue_id = vid and pr.user_id = uid),
    (exists (select 1 from public.perk_status(vid, uid) ps where ps.earned)),
    public.has_venue_interaction(vid, uid),
    (select n.body       from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select n.tags       from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select n.updated_at from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid);
end; $$;
revoke all on function public.venue_guest_card(uuid, uuid) from public;
grant execute on function public.venue_guest_card(uuid, uuid) to authenticated;
