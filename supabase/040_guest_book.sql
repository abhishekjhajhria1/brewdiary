-- ============================================================================
-- brewdiary — the venue GUEST BOOK: a first-party CRM, done the legal way.
--
-- A bar wants to know its regulars. That's legitimate — so a venue may keep a
-- little book on the guests it actually serves. What makes this a normal CRM and
-- NOT surveillance is one line, enforced here in the database:
--
--   ── FIRST-PARTY ONLY ──────────────────────────────────────────────────────
--   Everything a venue sees about a guest is either (a) an interaction that
--   happened AT THIS VENUE (a room they joined, a card staff punched, a tab staff
--   recorded, a perk given) or (b) a note THIS VENUE'S OWN STAFF typed. There is
--   NO join to public.entries anywhere below — a guest's diary (what they drink at
--   home or at another bar, their moods, their notes) is NEVER visible to a venue.
--   And nothing takes two venue_ids, so one bar can never see another's book.
--
--   This is the deliberate revision of the "we will never build a per-guest list"
--   line in 026: we won't hand a bar a churn list of strangers or anyone's activity
--   elsewhere — but a venue keeping first-party notes on its own guests, with the
--   guest able to see and delete them, is a CRM every business lawfully runs.
--
--   THE GUEST'S RIGHTS (what keeps it lawful — GDPR/DPDP transparency):
--     • a venue can only open a book on a guest who has actually been to it
--       (has_venue_interaction), never an arbitrary user they looked up;
--     • the guest can SEE every venue that keeps a note on them (my_venue_books)
--       and DELETE any of them (RLS delete policy), no questions asked;
--     • notes are staff-written only (server-enforced), like every other reward-
--       adjacent write in this app — a guest can't be made to author their own file.
--
-- Runs on top of 002..039.
-- ============================================================================

-- One editable card per (venue, guest): the subjective bit a CRM actually adds —
-- staff notes and tags. The factual history (visits, tabs, perks) is DERIVED live
-- by venue_guest_card(), never duplicated here.
create table if not exists public.venue_guest_notes (
  venue_id   uuid not null references public.venues(id) on delete cascade,
  subject_id uuid not null references public.profiles(id) on delete cascade,
  body       text not null default '' check (char_length(body) <= 2000),
  tags       text[] not null default '{}' check (cardinality(tags) <= 12),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (venue_id, subject_id)
);

alter table public.venue_guest_notes enable row level security;

-- READ: this venue's staff (their CRM), or the guest themself (transparency).
drop policy if exists venue_guest_notes_read on public.venue_guest_notes;
create policy venue_guest_notes_read on public.venue_guest_notes for select
  using (public.is_venue_staff(venue_id, auth.uid()) or subject_id = auth.uid());

-- DELETE: the guest can forget themselves anywhere; staff can clear their own book.
-- (No INSERT/UPDATE policy: writes go only through set_guest_note() below, so the
--  interaction gate and staff check can't be bypassed by a direct table write —
--  the same "staff-recorded only" rule the rest of the app uses.)
drop policy if exists venue_guest_notes_forget on public.venue_guest_notes;
create policy venue_guest_notes_forget on public.venue_guest_notes for delete
  using (subject_id = auth.uid() or public.is_venue_staff(venue_id, auth.uid()));

-- Has this guest ever actually been to this venue? A room they joined, or a card
-- staff punched. The gate that stops a venue opening a book on a stranger.
create or replace function public.has_venue_interaction(vid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.party_members m
      join public.parties r on r.id = m.party_id
     where r.venue_id = vid and m.user_id = uid and m.status = 'approved'
    union all
    select 1 from public.venue_checkins c
     where c.venue_id = vid and c.user_id = uid
  );
$$;
revoke all on function public.has_venue_interaction(uuid, uuid) from public;
grant execute on function public.has_venue_interaction(uuid, uuid) to authenticated;

-- Staff write a guest's note/tags. Enforces: caller is this venue's staff, the
-- guest has actually been here, and there's no block between them. Upsert.
create or replace function public.set_guest_note(vid uuid, uid uuid, in_body text, in_tags text[])
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_venue_staff(vid, me) then
    raise exception 'only this venue''s staff can keep a guest book';
  end if;
  if not public.has_venue_interaction(vid, uid) then
    raise exception 'you can only note a guest who has been to your venue';
  end if;
  if public.blocked_between(me, uid) then
    raise exception 'cannot note this guest';
  end if;

  insert into public.venue_guest_notes (venue_id, subject_id, body, tags, updated_by, updated_at)
  values (vid, uid, left(coalesce(in_body, ''), 2000), (coalesce(in_tags, array[]::text[]))[1:12], me, now())
  on conflict (venue_id, subject_id) do update
    set body = excluded.body, tags = excluded.tags, updated_by = excluded.updated_by, updated_at = now();
end; $$;
revoke all on function public.set_guest_note(uuid, uuid, text, text[]) from public;
grant execute on function public.set_guest_note(uuid, uuid, text, text[]) to authenticated;

-- The card a staff member sees for one guest. FIRST-PARTY ONLY: every figure is
-- scoped to (vid, uid) and this venue's own records. NO join to public.entries.
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
    (select body from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select tags from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select updated_at from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid);
end; $$;
revoke all on function public.venue_guest_card(uuid, uuid) from public;
grant execute on function public.venue_guest_card(uuid, uuid) to authenticated;

-- The guest's own view: every venue that keeps a note on them. Transparency, and
-- the list they delete from. Only the subjective note is shown — the factual
-- history is the venue's own business record.
create or replace function public.my_venue_books()
returns table (venue_id uuid, venue_name text, body text, tags text[], updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select n.venue_id, v.name, n.body, n.tags, n.updated_at
  from public.venue_guest_notes n
  join public.venues v on v.id = n.venue_id
  where n.subject_id = auth.uid()
  order by n.updated_at desc;
$$;
revoke all on function public.my_venue_books() from public;
grant execute on function public.my_venue_books() to authenticated;
