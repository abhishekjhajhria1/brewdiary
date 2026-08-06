-- ============================================================================
-- brewdiary — 053: NIGHTS. One object for "a night out", replacing the split
-- between Plans (the before) and Parties (the during/after).
--
-- ── WHY ─────────────────────────────────────────────────────────────────────
-- `plans` (031/036/037) and `parties` (004/007) grew up separately and ended up
-- modelling the same thing: a date, a place, people, who may come, who's approved.
-- The user had to choose between two near-identical forms BEFORE they knew what
-- they wanted, and there was no way to convert one into the other — a plan that
-- actually happened had no room to log into, and a party had no pre-night
-- invite tier or private mode.
--
-- ── THE SHAPE ───────────────────────────────────────────────────────────────
-- `plans` is the spine: it has the richer fields, the private/invite/friends/fof
-- policy ladder, and the whole approval + block + sanction machinery that has
-- already been audited. A `parties` row is now the plan's ROOM — created LAZILY,
-- only when a night needs one (a shareable link for people off the app, or the
-- live log on the night itself). That keeps /p/<code> previews and code-join
-- working exactly as they do, and means most plans never allocate a party at all.
--
-- Lifecycle is TIME, not a mode the user picks:
--   upcoming → the invitation   today → the live room   past → the recap
--
-- ── SAFETY (unchanged, and this file must not weaken it) ────────────────────
--   • Still NO stranger tier. join_policy stays private|invite|friends|fof.
--     "Anyone with the link" is the party invite CODE — a link you hand out
--     yourself — not public discovery. Whoever clicks it still lands PENDING.
--   • open_night_room is HOST-ONLY and idempotent. A guest cannot conjure a room,
--     and cannot use it to get themselves approved.
--   • together_inbox is scoped to auth.uid() in every branch — it returns only
--     items the caller is already entitled to see (it is a convenience union over
--     rows their existing RLS policies already permit, not a new read surface).
--
-- Feed rpcs that change SHAPE are dropped + recreated (pre-launch, no data to keep).
-- Runs on top of schema.sql + 002..052. One implicit transaction.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. THE LINK — a plan's room, once it has one.
-- ────────────────────────────────────────────────────────────────────────────
alter table public.plans
  add column if not exists party_id uuid references public.parties(id) on delete set null;
create index if not exists plans_party_idx on public.plans (party_id);


-- ────────────────────────────────────────────────────────────────────────────
-- 2. open_night_room(pid) — give a night its room. HOST ONLY. Idempotent.
--
-- Creates the parties row from the plan, seeds the host as approved, and carries
-- everyone already approved on the plan straight in (they were vetted once; being
-- asked to queue again on the night would be nonsense). Returns the party id —
-- calling it twice just returns the same one.
--
-- The venue string is the venue's NAME when the plan points at a real venue,
-- else the city — parties.venue is free text and is only ever displayed.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.open_night_room(pid uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p public.plans; new_id uuid; place text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into p from public.plans where id = pid;
  if p.id is null then raise exception 'no such night'; end if;
  if p.host_id <> me then raise exception 'only the host can open the room'; end if;
  if p.status = 'cancelled' then raise exception 'this night was called off'; end if;

  if p.party_id is not null then
    return p.party_id;                       -- already has one
  end if;

  select v.name into place from public.venues v where v.id = p.venue_id;
  place := coalesce(place, p.city);

  insert into public.parties (name, host_id, venue, date)
    values (left(trim(p.title), 80), me, place, p.plan_date)
    returning id into new_id;

  -- the host is in, approved
  insert into public.party_members (party_id, user_id, status, rsvp)
    values (new_id, me, 'approved', 'going')
    on conflict do nothing;

  -- everyone the host already approved on the plan comes with it
  insert into public.party_members (party_id, user_id, status, rsvp)
    select new_id, j.user_id, 'approved', 'going'
    from public.plan_joins j
    where j.plan_id = pid and j.status = 'approved'
    on conflict do nothing;

  update public.plans set party_id = new_id where id = pid;
  return new_id;
end; $$;
revoke all on function public.open_night_room(uuid) from public;
grant execute on function public.open_night_room(uuid) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 3. THE FEEDS — carry party_id so the UI can jump straight into a room.
--    Shape changed → drop + recreate (same bodies as 037 plus the one column).
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.upcoming_plans();
create function public.upcoming_plans()
returns table (
  id uuid, host_id uuid, host_name text, host_handle text,
  title text, plan_date date, plan_time time, city text, venue_id uuid,
  note text, drinks text[], vibe_tags text[], join_policy text,
  capacity int, going int, my_status text, party_id uuid
)
language sql stable security definer set search_path = public as $$
  select p.id, p.host_id, ph.display_name, ph.handle,
         p.title, p.plan_date, p.plan_time, p.city, p.venue_id,
         p.note, p.drinks, p.vibe_tags, p.join_policy,
         p.capacity, public.plan_going_count(p.id),
         (select j.status from public.plan_joins j where j.plan_id = p.id and j.user_id = auth.uid()),
         p.party_id
  from public.plans p
  join public.profiles ph on ph.id = p.host_id
  where p.status = 'open'
    and p.plan_date >= current_date
    and public.plan_visible_to(p.id, auth.uid())
    and p.host_id <> auth.uid()
  order by p.plan_date, p.created_at;
$$;
revoke all on function public.upcoming_plans() from public;
grant execute on function public.upcoming_plans() to authenticated;

drop function if exists public.my_plans();
create function public.my_plans()
returns table (
  id uuid, title text, plan_date date, plan_time time, city text, venue_id uuid,
  note text, drinks text[], vibe_tags text[], join_policy text,
  capacity int, status text, going int, pending int, party_id uuid
)
language sql stable security definer set search_path = public as $$
  select p.id, p.title, p.plan_date, p.plan_time, p.city, p.venue_id,
         p.note, p.drinks, p.vibe_tags, p.join_policy,
         p.capacity, p.status, public.plan_going_count(p.id),
         (select count(*)::int from public.plan_joins j where j.plan_id = p.id and j.status = 'requested'),
         p.party_id
  from public.plans p
  where p.host_id = auth.uid()
  order by (p.status = 'open') desc, p.plan_date;
$$;
revoke all on function public.my_plans() from public;
grant execute on function public.my_plans() to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 4. my_nights() — the Nights list: every night that is MINE, hosted or joined,
--    past included so recaps have somewhere to live.
--
--    my_plans() is hosted-only and my_plan_days() is upcoming-only, so neither
--    could back a list that shows "Ash's thing last Friday" next to "mine on
--    Saturday". This is that one list. `host` tells the UI which powers to show.
--
--    THREE ways a night is yours, and all three must be here:
--      1. you host it
--      2. the host approved your request to come  (plan_joins)
--      3. you followed the SHARE LINK and were let in at the door (party_members) —
--         that path never creates a plan_joins row, so without this branch the whole
--         share-link feature would drop people's nights on the floor.
--    Set UNION (not UNION ALL): open_night_room copies approved joiners into the
--    room, so branches 2 and 3 overlap by design and the duplicate must collapse.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.my_nights()
returns table (
  id uuid, host_id uuid, host_name text, title text,
  plan_date date, plan_time time, city text, venue_id uuid,
  join_policy text, status text, going int, pending int,
  party_id uuid, host boolean
)
language sql stable security definer set search_path = public as $$
  select p.id, p.host_id, ph.display_name, p.title,
         p.plan_date, p.plan_time, p.city, p.venue_id,
         p.join_policy, p.status, public.plan_going_count(p.id),
         (select count(*)::int from public.plan_joins j
           where j.plan_id = p.id and j.status = 'requested'),
         p.party_id, true
  from public.plans p
  join public.profiles ph on ph.id = p.host_id
  where p.host_id = auth.uid()

  union
  -- approved on the night itself
  select p.id, p.host_id, ph.display_name, p.title,
         p.plan_date, p.plan_time, p.city, p.venue_id,
         p.join_policy, p.status, public.plan_going_count(p.id),
         0,                                  -- a guest never sees the request queue
         p.party_id, false
  from public.plans p
  join public.profiles ph on ph.id = p.host_id
  join public.plan_joins j on j.plan_id = p.id
  where j.user_id = auth.uid()
    and j.status = 'approved'
    and p.status <> 'cancelled'
    and not public.blocked_between(auth.uid(), p.host_id)

  union
  -- let in at the door, having followed the share link
  select p.id, p.host_id, ph.display_name, p.title,
         p.plan_date, p.plan_time, p.city, p.venue_id,
         p.join_policy, p.status, public.plan_going_count(p.id),
         0,
         p.party_id, false
  from public.plans p
  join public.profiles ph on ph.id = p.host_id
  join public.party_members m on m.party_id = p.party_id
  where m.user_id = auth.uid()
    and m.status = 'approved'
    and p.host_id <> auth.uid()
    and p.status <> 'cancelled'
    and not public.blocked_between(auth.uid(), p.host_id)

  order by plan_date desc, plan_time desc nulls last;
$$;
revoke all on function public.my_nights() from public;
grant execute on function public.my_nights() to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 5. together_inbox() — everything waiting on YOU, in one round-trip.
--
-- Together's features each kept their own pending queue buried in their own room,
-- so nothing ever told you that you were needed. This unions those queues. It is
-- deliberately NOT a new read surface: every branch is scoped to auth.uid() and
-- returns rows the caller's existing RLS policies already let them select.
--
-- Four kinds, because those are the four that exist:
--   friend_request  — someone wants to be friends
--   night_request   — someone asked to join a night I host
--   night_invite    — I was named on an invite-only night and haven't answered
--   room_request    — someone used my night's share link and is waiting at the door
-- (Circles and Cups join by CODE and have no invite table — nothing to surface.)
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.together_inbox()
returns table (
  kind         text,
  ref_id       uuid,       -- the row to act on (friendship id, join id, else the night)
  subject_id   uuid,       -- the night/room it concerns, when it concerns one
  actor_id     uuid,
  actor_name   text,
  actor_handle text,
  title        text,
  created_at   timestamptz
)
language sql stable security definer set search_path = public as $$
  -- 1. friend requests addressed to me
  select 'friend_request'::text, f.id, null::uuid,
         pr.id, pr.display_name, pr.handle, null::text, f.created_at
  from public.friendships f
  join public.profiles pr on pr.id = f.requester_id
  where f.addressee_id = auth.uid()
    and f.status = 'pending'
    and not public.blocked_between(auth.uid(), f.requester_id)

  union all
  -- 2. people asking to join a night I host
  select 'night_request'::text, j.id, p.id,
         pr.id, pr.display_name, pr.handle, p.title, j.created_at
  from public.plan_joins j
  join public.plans p    on p.id = j.plan_id
  join public.profiles pr on pr.id = j.user_id
  where p.host_id = auth.uid()
    and j.status = 'requested'
    and p.status = 'open'
    and not public.blocked_between(auth.uid(), j.user_id)

  union all
  -- 3. invite-only nights I was named on and haven't answered
  select 'night_invite'::text, p.id, p.id,
         pr.id, pr.display_name, pr.handle, p.title, i.created_at
  from public.plan_invites i
  join public.plans p     on p.id = i.plan_id
  join public.profiles pr on pr.id = p.host_id
  where i.user_id = auth.uid()
    and p.status = 'open'
    and p.plan_date >= current_date
    and not exists (
      select 1 from public.plan_joins j
      where j.plan_id = p.id and j.user_id = auth.uid()
        and j.status in ('approved', 'declined')
    )
    and not public.blocked_between(auth.uid(), p.host_id)

  union all
  -- 4. someone at the door of a room I host (came in by share link)
  select 'room_request'::text, m.party_id, m.party_id,
         pr.id, pr.display_name, pr.handle, pt.name, m.joined_at
  from public.party_members m
  join public.parties pt  on pt.id = m.party_id
  join public.profiles pr on pr.id = m.user_id
  where pt.host_id = auth.uid()
    and m.status = 'pending'
    and not public.blocked_between(auth.uid(), m.user_id)

  order by created_at desc
  limit 60;
$$;
revoke all on function public.together_inbox() from public;
grant execute on function public.together_inbox() to authenticated;
