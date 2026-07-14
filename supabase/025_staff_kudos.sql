-- ============================================================================
-- brewdiary — "Staff kudos": a guest thanks the bartender, by name.
--
-- Staff churn is a bar's second-biggest pain, and people don't quit because they
-- lost a leaderboard — they quit because nobody ever noticed. So this is a thank
-- you, not a rating.
--
-- ── THE LEGAL SHAPE (this is why it looks smaller than a bar will want) ──────
-- Customer feedback attached to a NAMED EMPLOYEE is *employee monitoring* under
-- GDPR. It needs a lawful basis, a DPIA, and — in Germany, France, Poland,
-- Belgium, the Netherlands, Austria and Sweden — WORKS-COUNCIL CONSULTATION, and
-- skipping that is a separate violation from GDPR itself. A bar cannot consent on
-- its staff's behalf, and employee "consent" is weak anyway (power imbalance).
--
-- So the design is deliberately reduced, and these are hard rules:
--   1. POSITIVE ONLY. There is no negative, no rating, no score, no stars. A guest
--      can thank; they can never complain here. (Same rule as vibe.)
--   2. THE STAFF MEMBER sees their own thanks. That's who it's for.
--   3. A MANAGER SEES A VENUE-LEVEL COUNT ONLY — never a per-person league table.
--      That is the line between "we noticed our team was thanked 40 times" and
--      "rank my bartenders for me", and the second one is the one that turns us
--      into a data-protection problem in seven EU states. `venue_kudos_total()`
--      returns ONE number on purpose. DO NOT add a per-staff breakdown for
--      managers. A bar will ask. The answer is no.
--   4. Staff can switch it off (`venue_staff.thankable`) and then they cannot be
--      thanked at all — an opt-out that actually works.
--
-- Runs on top of schema.sql + 002..024. Idempotent-ish (does NOT drop the table).
-- ============================================================================

-- Being thankable is ON by default (a guest can already see your face and your
-- name badge; being thanked is not surveillance) but any staff member can turn it
-- off for themselves, and then they vanish from the list entirely.
alter table public.venue_staff add column if not exists thankable boolean not null default true;

create table if not exists public.staff_kudos (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id)   on delete cascade,
  staff_id   uuid not null references public.profiles(id) on delete cascade, -- who was thanked
  from_user  uuid          references public.profiles(id) on delete set null, -- who said it
  party_id   uuid          references public.parties(id)  on delete set null, -- which night
  reason     text not null check (reason in (
    'looked after us', 'great recommendation', 'made the night', 'quick and kind'
  )),
  created_at timestamptz not null default now()
);
create index if not exists staff_kudos_staff_idx on public.staff_kudos (staff_id, created_at desc);
create index if not exists staff_kudos_venue_idx on public.staff_kudos (venue_id, created_at desc);

-- One guest may thank one staff member once per reason per night. Stops a table of
-- six from inflating one bartender, and stops anyone spamming.
create unique index if not exists staff_kudos_dedupe
  on public.staff_kudos (party_id, from_user, staff_id, reason);

alter table public.staff_kudos enable row level security;

-- READ: only the person who was thanked, and the person who said it. NOT the
-- manager — that is the whole point (see rule 3 above).
drop policy if exists staff_kudos_read on public.staff_kudos;
create policy staff_kudos_read on public.staff_kudos for select to authenticated
  using (staff_id = auth.uid() or from_user = auth.uid());

-- No insert policy: kudos go through thank_staff() below, which checks the guest
-- was actually in that room and that the staff member is thankable.

-- ── who can I thank tonight? (names only, and only those who opted in) ───────
create or replace function public.room_staff(pid uuid)
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.display_name, 'the bar')
  from public.parties room
  join public.venue_staff vs on vs.venue_id = room.venue_id and vs.thankable
  join public.profiles p on p.id = vs.user_id
  where room.id = pid
    and room.venue_id is not null
    and public.is_party_member(pid, auth.uid())   -- you must be IN the room
  order by 2;
$$;
revoke all on function public.room_staff(uuid) from public;
grant execute on function public.room_staff(uuid) to authenticated;

-- ── the thank you ────────────────────────────────────────────────────────────
create or replace function public.thank_staff(pid uuid, sid uuid, why text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); vid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_party_member(pid, me) then raise exception 'not in this room'; end if;

  select room.venue_id into vid from public.parties room where room.id = pid;
  if vid is null then raise exception 'not a venue room'; end if;

  if not exists (
    select 1 from public.venue_staff vs
    where vs.venue_id = vid and vs.user_id = sid and vs.thankable
  ) then
    raise exception 'that person is not taking thanks';
  end if;

  begin
    insert into public.staff_kudos (venue_id, staff_id, from_user, party_id, reason)
    values (vid, sid, me, pid, why);
  exception when unique_violation then
    return false;   -- already said it; a harmless no-op
  end;
  return true;
end; $$;
revoke all on function public.thank_staff(uuid, uuid, text) from public;
grant execute on function public.thank_staff(uuid, uuid, text) to authenticated;

-- ── what the STAFF MEMBER sees: their own thanks ─────────────────────────────
create or replace function public.my_kudos(vid uuid)
returns table (reason text, n int)
language sql stable security definer set search_path = public as $$
  select k.reason, count(*)::int
  from public.staff_kudos k
  where k.venue_id = vid and k.staff_id = auth.uid()
  group by k.reason
  order by 2 desc;
$$;
revoke all on function public.my_kudos(uuid) from public;
grant execute on function public.my_kudos(uuid) to authenticated;

-- ── what a MANAGER sees: ONE NUMBER. Not a league table. ─────────────────────
-- "Your team was thanked 40 times this month." That is the whole feature. There is
-- deliberately NO per-staff breakdown here, and adding one would make us an
-- employee-monitoring tool — DPIA + works councils in seven EU states. Don't.
create or replace function public.venue_kudos_total(vid uuid, since_days int default 30)
returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int
  from public.staff_kudos k
  where k.venue_id = vid
    and k.created_at > now() - make_interval(days => greatest(since_days, 1))
    and public.is_venue_manager(vid, auth.uid());
$$;
revoke all on function public.venue_kudos_total(uuid, int) from public;
grant execute on function public.venue_kudos_total(uuid, int) to authenticated;
