-- ============================================================================
-- brewdiary — "Staff awards" (Phase 7): the bar's people hand out vibe.
--
-- This completes the locked model — "vibe = positive behaviour recognition,
-- BAR STAFF / your group GIVE it". Friends already award vibe to each other in
-- the room; this adds the other half: a waiter/bartender/manager can award a
-- guest in THEIR venue's room, even though staff aren't party members.
-- Positive-only, always: there is no way to dock anyone, anywhere. Staff vibe is
-- quiet recognition, never a public rating and never a blacklist.
--
-- ALSO HARDENS SPARKS. Until now the client could insert its OWN spark with any
-- `reason`; the anti-farm index only blocks a DUPLICATE reason, so a determined
-- user could mint unlimited sparks with invented ones ("a","b",…) straight at the
-- API — and sparks feed a public kiosk board. Fix: the client spark-insert policy
-- is DROPPED and check-in becomes a definer function that decides the reason
-- itself. Vibe stays client-awarded but its reason is pinned by a CHECK.
--
-- Runs on top of schema.sql + 002..015. Idempotent-ish.
-- ============================================================================

-- (removes the abandoned trivia experiment if it was ever applied)
drop function if exists public.trivia_answer(uuid, uuid, int) cascade;
drop function if exists public.trivia_next(uuid)              cascade;
drop table    if exists public.trivia_attempts   cascade;
drop table    if exists public.trivia_questions  cascade;

drop function if exists public.staff_award(uuid, uuid, text) cascade;
drop function if exists public.room_guests(uuid)             cascade;
drop function if exists public.award_checkin(uuid)           cascade;

-- ── check in: server-authoritative (the client can no longer mint sparks) ────
create or replace function public.award_checkin(pid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_party_member(pid, auth.uid()) then
    raise exception 'not in this room';
  end if;
  insert into public.point_events (party_id, subject_user_id, currency, reason, value)
  values (pid, auth.uid(), 'spark', 'checkin', 1)
  on conflict do nothing;
  return found; -- false when they'd already checked in today
end; $$;
revoke all on function public.award_checkin(uuid) from public;
grant execute on function public.award_checkin(uuid) to authenticated;

-- ── who's in the room — readable by fellow guests OR the venue's staff ───────
-- (staff aren't party members, so party_members RLS alone would hide the room
--  from the very people meant to hand out vibe.)
create or replace function public.room_guests(pid uuid)
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.display_name, 'guest')
  from public.party_members m
  join public.profiles p    on p.id = m.user_id
  join public.parties  room on room.id = m.party_id
  where m.party_id = pid
    and m.status = 'approved'
    and (
      public.is_party_member(pid, auth.uid())
      or (room.venue_id is not null and public.is_venue_staff(room.venue_id, auth.uid()))
    )
  order by 2;
$$;
revoke all on function public.room_guests(uuid) from public;
grant execute on function public.room_guests(uuid) to authenticated;

-- ── a waiter/bartender/manager hands a guest vibe ────────────────────────────
-- Positive-only (value 1, no negative path exists). Verified venues only — the
-- locked rule. The existing (party, awarder, subject, reason) unique index means
-- each staff member can give each guest each reason once per room.
create or replace function public.staff_award(pid uuid, uid uuid, reason text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare vid uuid;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if uid = auth.uid() then
    raise exception 'you cannot award yourself';
  end if;
  if reason not in ('great vibe', 'kept it classy', 'a pleasure to serve', 'looked after the table') then
    raise exception 'unknown vibe';
  end if;

  select room.venue_id into vid from public.parties room where room.id = pid;
  if vid is null then
    raise exception 'not a venue room';
  end if;
  if not public.is_venue_staff(vid, auth.uid()) then
    raise exception 'not staff of this venue';
  end if;
  if not exists (select 1 from public.venues v where v.id = vid and v.verified) then
    raise exception 'only a verified venue can hand out vibe';
  end if;
  if not public.is_party_member(pid, uid) then
    raise exception 'that guest is not in this room';
  end if;

  insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
  values (pid, uid, auth.uid(), 'vibe', reason, 1)
  on conflict do nothing;
  return found; -- false when this staff member already gave that guest that vibe
end; $$;
revoke all on function public.staff_award(uuid, uuid, text) from public;
grant execute on function public.staff_award(uuid, uuid, text) to authenticated;

-- ── HARDENING ────────────────────────────────────────────────────────────────
-- 1. The client can no longer mint its own sparks with invented reasons:
--    award_checkin() is now the only source of a spark.
drop policy if exists point_events_insert_spark on public.point_events;

-- 2. Vibe reasons are pinned to the known set (guest-given + staff-given), so an
--    awarder can't farm someone with invented reasons either. With the existing
--    per-(awarder, subject, reason) unique index this caps how much vibe any one
--    person can hand any other person in a room.
alter table public.point_events drop constraint if exists point_events_vibe_reason;
alter table public.point_events add constraint point_events_vibe_reason
  check (
    currency <> 'vibe'
    or reason in (
      -- your table gives these
      'good sport', 'great vibe', 'kept it classy', 'MVP',
      -- the bar's people give these
      'a pleasure to serve', 'looked after the table'
    )
  );
