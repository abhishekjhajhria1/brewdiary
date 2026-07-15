-- ============================================================================
-- brewdiary — "Plans": pre-plan a night, and let people you're connected to join.
--
-- ── THE SHAPE, AND THE SAFETY LINE ──────────────────────────────────────────
-- A plan is future intent: "Friday, negronis at Toit, who's in?". People can ask to
-- join; the host approves. That's it. The load-bearing decision is WHO can see and
-- ask to join a plan, because that's the whole safety surface:
--
--   join_policy = 'friends'  → only the host's accepted friends.
--   join_policy = 'fof'      → friends, and friends-of-friends.
--
-- There is DELIBERATELY NO 'open'/'stranger' option in the enum. Opening plans to
-- strangers is a later, separately-gated decision that needs real trust-&-safety
-- machinery first (verification, a review queue) — and because the value is
-- constrained by a CHECK, no client, however malicious, can set it until we add it.
-- Deny-by-default, enforced in the database, exactly like the venue jurisdiction layer.
--
-- Everything here also respects BLOCKS: a blocked pair never see each other's plans,
-- can't join, and don't surface in each other's signals. Blocks + reports are built
-- now (phase-1) even though strangers aren't enabled yet, because a friend-of-a-friend
-- can still be someone you need to get away from.
--
-- NO RATING OF PEOPLE. There is no score on a human anywhere in here. "Fit" is shown
-- only as SOFT, factual signals — mutual friends, shared taste, how long on brewdiary —
-- never a number that ranks a person or gates who may meet whom.
--
-- Sensitive writes (join / approve / block) go through SECURITY DEFINER rpcs that
-- re-derive eligibility server-side; the tables that must never be client-forged
-- (plan_joins, reports) carry NO write policy at all. Same pattern as spend_events.
--
-- Runs on top of schema.sql + 002..030.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 0. BLOCKS — mutual invisibility. Built first: other policies depend on it.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists blocks_blocked_idx on public.blocks (blocked_id);
alter table public.blocks enable row level security;

-- You manage your OWN block list, and you can only ever see your own side of it —
-- crucially, a person you blocked cannot tell that you blocked them.
drop policy if exists blocks_read on public.blocks;
create policy blocks_read on public.blocks for select to authenticated
  using (blocker_id = auth.uid());
drop policy if exists blocks_insert on public.blocks;
create policy blocks_insert on public.blocks for insert to authenticated
  with check (blocker_id = auth.uid());
drop policy if exists blocks_delete on public.blocks;
create policy blocks_delete on public.blocks for delete to authenticated
  using (blocker_id = auth.uid());

-- True if EITHER of the pair has blocked the other. Symmetric on purpose: a block
-- cuts visibility both ways, so the blocker never appears to the blocked either.
create or replace function public.blocked_between(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;
revoke all on function public.blocked_between(uuid, uuid) from public;
grant execute on function public.blocked_between(uuid, uuid) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 1. PLANS.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.plans (
  id          uuid primary key default gen_random_uuid(),
  host_id     uuid not null references public.profiles(id) on delete cascade,
  title       text not null check (char_length(trim(title)) between 1 and 100),
  plan_date   date not null,
  city        text check (char_length(city) <= 80),
  venue_id    uuid references public.venues(id) on delete set null,
  note        text check (char_length(note) <= 500),
  drinks      text[] not null default '{}',   -- what they want to drink (soft tags)
  vibe_tags   text[] not null default '{}',   -- soft "type" tags, never a rating
  join_policy text not null default 'friends' check (join_policy in ('friends', 'fof')),
  capacity    int check (capacity is null or capacity between 1 and 50),
  status      text not null default 'open' check (status in ('open', 'closed', 'cancelled')),
  created_at  timestamptz not null default now()
);
create index if not exists plans_host_idx on public.plans (host_id);
create index if not exists plans_date_idx on public.plans (plan_date) where status = 'open';
alter table public.plans enable row level security;

-- A plan can't be for the past. current_date isn't immutable so it can't live in a
-- CHECK; a trigger enforces it on insert (an existing plan naturally ages past today,
-- which is fine — it just stops showing in upcoming feeds).
create or replace function public.plans_future_only()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.plan_date < current_date then
    raise exception 'a plan can''t be in the past';
  end if;
  return new;
end; $$;
drop trigger if exists plans_future on public.plans;
create trigger plans_future before insert on public.plans
  for each row execute function public.plans_future_only();

-- THE visibility rule, in one place so the RLS policy and the feed rpc can never
-- drift apart. Host always sees their own (even cancelled). Everyone else must clear
-- the join policy AND not be blocked, and never sees a cancelled plan.
create or replace function public.plan_visible_to(pid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.plans p
    where p.id = pid
      and (
        p.host_id = uid
        or (
          p.status <> 'cancelled'
          and not public.blocked_between(uid, p.host_id)
          and (
            (p.join_policy = 'friends' and public.are_friends(uid, p.host_id))
            or (p.join_policy = 'fof' and public.is_fof(uid, p.host_id))
          )
        )
      )
  );
$$;
revoke all on function public.plan_visible_to(uuid, uuid) from public;
grant execute on function public.plan_visible_to(uuid, uuid) to authenticated;

drop policy if exists plans_read on public.plans;
create policy plans_read on public.plans for select to authenticated
  using (public.plan_visible_to(id, auth.uid()));

drop policy if exists plans_insert on public.plans;
create policy plans_insert on public.plans for insert to authenticated
  with check (host_id = auth.uid());

drop policy if exists plans_update on public.plans;
create policy plans_update on public.plans for update to authenticated
  using (host_id = auth.uid());

drop policy if exists plans_delete on public.plans;
create policy plans_delete on public.plans for delete to authenticated
  using (host_id = auth.uid());


-- ────────────────────────────────────────────────────────────────────────────
-- 2. PLAN_JOINS — who asked to come, and where the host landed on it.
--
-- NO write policy: every write goes through a definer rpc that re-derives who's
-- allowed to do what. A guest can't self-approve, and can't insert an 'approved'
-- row. Same posture as spend_events / perk_redemptions.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.plan_joins (
  id         uuid primary key default gen_random_uuid(),
  plan_id    uuid not null references public.plans(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  status     text not null default 'requested'
             check (status in ('requested', 'approved', 'declined', 'withdrawn')),
  message    text check (char_length(message) <= 300),
  created_at timestamptz not null default now(),
  unique (plan_id, user_id)
);
create index if not exists plan_joins_plan_idx on public.plan_joins (plan_id, status);
create index if not exists plan_joins_user_idx on public.plan_joins (user_id);
alter table public.plan_joins enable row level security;

-- Readable by the joiner, and by the plan's host. Nobody else — not other joiners.
drop policy if exists plan_joins_read on public.plan_joins;
create policy plan_joins_read on public.plan_joins for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.plans p where p.id = plan_id and p.host_id = auth.uid())
  );
-- (No insert/update/delete policy — server-written only, via the rpcs below.)

-- How many are going: approved joiners + the host. A plain count, callable by anyone
-- who can see the plan (so the feed can show "4 going" without leaking who).
create or replace function public.plan_going_count(pid uuid)
returns int
language sql stable security definer set search_path = public as $$
  select 1 + (   -- the host counts
    select count(*)::int from public.plan_joins j
    where j.plan_id = pid and j.status = 'approved'
  );
$$;
revoke all on function public.plan_going_count(uuid) from public;
grant execute on function public.plan_going_count(uuid) to authenticated;

-- ── ask to join ──────────────────────────────────────────────────────────────
-- Re-derives eligibility on the server: the plan must be visible to you (which folds
-- in the join policy AND the block check), open, not yours, and not already full.
create or replace function public.request_join(pid uuid, msg text default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p public.plans; going int;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into p from public.plans where id = pid;
  if p.id is null then raise exception 'no such plan'; end if;
  if p.host_id = me then raise exception 'it''s already your plan'; end if;
  if p.status <> 'open' then raise exception 'this plan isn''t taking people'; end if;
  if not public.plan_visible_to(pid, me) then
    raise exception 'you can''t join this plan';   -- covers policy + blocks
  end if;
  if p.capacity is not null then
    going := public.plan_going_count(pid);
    if going >= p.capacity then raise exception 'this plan is full'; end if;
  end if;

  insert into public.plan_joins (plan_id, user_id, status, message)
  values (pid, me, 'requested', nullif(trim(coalesce(msg, '')), ''))
  on conflict (plan_id, user_id) do update
    set status = 'requested', message = excluded.message, created_at = now()
    where public.plan_joins.status in ('declined', 'withdrawn');  -- let a prior no re-ask
  return true;
end; $$;
revoke all on function public.request_join(uuid, text) from public;
grant execute on function public.request_join(uuid, text) to authenticated;

-- ── host approves or declines ─────────────────────────────────────────────────
create or replace function public.respond_join(jid uuid, approve boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); j public.plan_joins; p public.plans; going int;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into j from public.plan_joins where id = jid;
  if j.id is null then raise exception 'no such request'; end if;
  select * into p from public.plans where id = j.plan_id;
  if p.host_id <> me then raise exception 'only the host decides'; end if;

  if approve then
    if p.capacity is not null then
      going := public.plan_going_count(p.id);
      if going >= p.capacity then raise exception 'the plan is full'; end if;
    end if;
    update public.plan_joins set status = 'approved' where id = jid;
  else
    update public.plan_joins set status = 'declined' where id = jid;
  end if;
  return true;
end; $$;
revoke all on function public.respond_join(uuid, boolean) from public;
grant execute on function public.respond_join(uuid, boolean) to authenticated;

-- ── joiner backs out ──────────────────────────────────────────────────────────
create or replace function public.withdraw_join(pid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  update public.plan_joins set status = 'withdrawn'
  where plan_id = pid and user_id = me;
  return true;
end; $$;
revoke all on function public.withdraw_join(uuid) from public;
grant execute on function public.withdraw_join(uuid) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 3. BLOCK — as an action that also cleans up. Blocking someone should pull apart
--    any pending arrangement between you, both directions, in one go.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.block_user(other uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if me = other then raise exception 'you can''t block yourself'; end if;

  insert into public.blocks (blocker_id, blocked_id) values (me, other)
    on conflict do nothing;

  -- withdraw/decline anything live between the two, both directions
  update public.plan_joins j set status = 'withdrawn'
   from public.plans p
   where j.plan_id = p.id and j.status in ('requested', 'approved')
     and ((j.user_id = me and p.host_id = other) or (j.user_id = other and p.host_id = me));
  return true;
end; $$;
revoke all on function public.block_user(uuid) from public;
grant execute on function public.block_user(uuid) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 4. REPORTS — write-only for users; a human on our side reviews them.
--    No select policy: a reporter can't read reports back, and a subject can never
--    see they were reported. Service role reads them out of band.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.reports (
  id              uuid primary key default gen_random_uuid(),
  reporter_id     uuid not null references public.profiles(id) on delete set null,
  subject_user_id uuid references public.profiles(id) on delete set null,
  plan_id         uuid references public.plans(id) on delete set null,
  reason          text not null check (reason in ('harassment', 'spam', 'fake', 'unsafe', 'other')),
  note            text check (char_length(note) <= 1000),
  created_at      timestamptz not null default now()
);
create index if not exists reports_created_idx on public.reports (created_at desc);
alter table public.reports enable row level security;

drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports for insert to authenticated
  with check (reporter_id = auth.uid());
-- (No select/update/delete policy — a report is a one-way message to the safety team.)


-- ────────────────────────────────────────────────────────────────────────────
-- 5. SOFT SIGNALS — facts that help you feel comfortable, never a score.
--
-- Returns COUNTS and plain facts about the viewer's relationship to a host: mutual
-- friends, how many drink types you both log, whether they're verified, and how long
-- they've been here. Never a list of who, never spend, never a rating. If the pair is
-- blocked it returns nothing.
-- ────────────────────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists verified boolean not null default false;

create or replace function public.plan_signals(pid uuid)
returns table (mutual_friends int, shared_drinks int, host_verified boolean, host_since timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); host uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select host_id into host from public.plans where id = pid;
  if host is null then return; end if;
  if host = me or public.blocked_between(me, host) then return; end if;
  if not public.plan_visible_to(pid, me) then return; end if;

  return query
  select
    -- mutual accepted friends (a count, never names)
    (
      with mine as (
        select case when f.requester_id = me then f.addressee_id else f.requester_id end id
        from public.friendships f
        where f.status = 'accepted' and (f.requester_id = me or f.addressee_id = me)
      ),
      theirs as (
        select case when f.requester_id = host then f.addressee_id else f.requester_id end id
        from public.friendships f
        where f.status = 'accepted' and (f.requester_id = host or f.addressee_id = host)
      )
      select count(*)::int from mine join theirs using (id)
    ),
    -- distinct drink types you BOTH log (taste overlap, as a number)
    (
      select count(*)::int from (
        select distinct lower(trim(type)) t from public.entries where user_id = me   and type is not null
        intersect
        select distinct lower(trim(type)) t from public.entries where user_id = host and type is not null
      ) shared
    ),
    (select verified from public.profiles where id = host),
    (select created_at from public.profiles where id = host);
end; $$;
revoke all on function public.plan_signals(uuid) from public;
grant execute on function public.plan_signals(uuid) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 6. FEEDS.
-- ────────────────────────────────────────────────────────────────────────────

-- Upcoming plans I'm allowed to see (host or friends/fof, not blocked), enriched with
-- who's going and whether I'm already in. plan_visible_to is the one authority, reused.
create or replace function public.upcoming_plans()
returns table (
  id uuid, host_id uuid, host_name text, host_handle text,
  title text, plan_date date, city text, venue_id uuid,
  note text, drinks text[], vibe_tags text[], join_policy text,
  capacity int, going int, my_status text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.host_id, ph.display_name, ph.handle,
         p.title, p.plan_date, p.city, p.venue_id,
         p.note, p.drinks, p.vibe_tags, p.join_policy,
         p.capacity, public.plan_going_count(p.id),
         (select j.status from public.plan_joins j where j.plan_id = p.id and j.user_id = auth.uid())
  from public.plans p
  join public.profiles ph on ph.id = p.host_id
  where p.status = 'open'
    and p.plan_date >= current_date
    and public.plan_visible_to(p.id, auth.uid())
    and p.host_id <> auth.uid()          -- my own plans live in "mine", not the feed
  order by p.plan_date, p.created_at;
$$;
revoke all on function public.upcoming_plans() from public;
grant execute on function public.upcoming_plans() to authenticated;

-- My own plans (as host), with the going count.
create or replace function public.my_plans()
returns table (
  id uuid, title text, plan_date date, city text, venue_id uuid,
  note text, drinks text[], vibe_tags text[], join_policy text,
  capacity int, status text, going int, pending int
)
language sql stable security definer set search_path = public as $$
  select p.id, p.title, p.plan_date, p.city, p.venue_id,
         p.note, p.drinks, p.vibe_tags, p.join_policy,
         p.capacity, p.status, public.plan_going_count(p.id),
         (select count(*)::int from public.plan_joins j where j.plan_id = p.id and j.status = 'requested')
  from public.plans p
  where p.host_id = auth.uid()
  order by (p.status = 'open') desc, p.plan_date;
$$;
revoke all on function public.my_plans() from public;
grant execute on function public.my_plans() to authenticated;

-- Block-aware people search. The old client query (profiles ilike) showed everyone,
-- including someone you blocked or who blocked you. This is the same search, but it
-- drops anyone on either side of a block — so a blocked pair can't find each other to
-- send a friend request in the first place.
create or replace function public.search_users(q text)
returns table (id uuid, handle text, display_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.handle, p.display_name
  from public.profiles p
  where p.id <> auth.uid()
    and not public.blocked_between(auth.uid(), p.id)
    and (p.handle ilike '%' || q || '%' or p.display_name ilike '%' || q || '%')
  order by p.handle
  limit 10;
$$;
revoke all on function public.search_users(text) from public;
grant execute on function public.search_users(text) to authenticated;

-- The people who asked to join one of MY plans (host-only; the rpc enforces it).
create or replace function public.plan_requests(pid uuid)
returns table (join_id uuid, user_id uuid, name text, handle text, message text, status text, asked_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from public.plans where id = pid and host_id = auth.uid()) then
    raise exception 'only the host can see who asked';
  end if;
  return query
    select j.id, j.user_id, pr.display_name, pr.handle, j.message, j.status, j.created_at
    from public.plan_joins j
    join public.profiles pr on pr.id = j.user_id
    where j.plan_id = pid
    order by (j.status = 'requested') desc, j.created_at;
end; $$;
revoke all on function public.plan_requests(uuid) from public;
grant execute on function public.plan_requests(uuid) to authenticated;
