-- ============================================================================
-- brewdiary — Moderation: make reports actionable, and give the safety layer teeth.
--
-- ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 031 built blocks + reports, but a report landed in a table nothing read, and there
-- was no way to act on one. This adds the missing half: a moderator can read the queue
-- and suspend or ban an account, and a suspended/banned account loses the ability to
-- create or join a plan, or to be found in search. Built now (not just for a future
-- stranger tier) because a friend-of-a-friend can already be someone to get away from.
--
-- ── THE TRUST ROOT ──────────────────────────────────────────────────────────
-- Who is a moderator is decided by the `moderators` table, which has NO client write
-- policy at all — the maintainer seeds it via SQL, and no request from the app can ever
-- add a moderator. Everything else (reading reports, suspending, banning) is gated by
-- is_moderator() re-derived server-side, exactly like is_venue_staff / is_venue_manager.
-- A guest can never grant themselves the power, and can never sanction anyone.
--
-- ── SANCTIONS ARE SERVER-WRITTEN ────────────────────────────────────────────
-- Sanction state lives in its OWN table (user_sanctions), NOT on the user-editable
-- profiles row, and has NO client write policy — the only writers are the moderator-only
-- definer rpcs below. A user can READ their own sanction (so the app can tell them
-- honestly, never fail silently), but can never clear it. Same posture as spend_events.
--
-- NO RATING OF PEOPLE. A sanction is a safety action with a reason and an audit row,
-- not a score; there is still no ranking of anyone anywhere.
--
-- Runs on top of schema.sql + 002..033.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. MODERATORS — the trust root. Seeded by SQL only; no client can ever write it.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.moderators (
  user_id  uuid primary key references public.profiles(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table public.moderators enable row level security;

-- You can read exactly one row: your own, so the app can tell whether to show the
-- moderation screen. The full team list is not exposed to the client (a moderator can
-- read it via SQL). No insert/update/delete policy — seeded server-side only.
drop policy if exists moderators_read on public.moderators;
create policy moderators_read on public.moderators for select to authenticated
  using (user_id = auth.uid());

-- Am I (or anyone) a moderator? SECURITY DEFINER so it can be called inside RLS and
-- rpcs without exposing the table. Bypasses RLS as owner, so no recursion.
create or replace function public.is_moderator(uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.moderators where user_id = uid);
$$;
revoke all on function public.is_moderator(uuid) from public;
grant execute on function public.is_moderator(uuid) to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. SANCTIONS — suspend (temporary) or ban (indefinite). Server-written only.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.user_sanctions (
  user_id         uuid primary key references public.profiles(id) on delete cascade,
  suspended_until timestamptz,                 -- a temporary freeze; null once lifted
  banned          boolean not null default false,
  reason          text check (char_length(reason) <= 1000),
  updated_by      uuid references public.profiles(id) on delete set null,
  updated_at      timestamptz not null default now()
);
alter table public.user_sanctions enable row level security;

-- You can see your OWN sanction (so we can tell you plainly), and a moderator can see
-- anyone's. Nobody else. No client write policy — only the definer rpcs below write it.
drop policy if exists user_sanctions_read on public.user_sanctions;
create policy user_sanctions_read on public.user_sanctions for select to authenticated
  using (user_id = auth.uid() or public.is_moderator(auth.uid()));

-- Is this account currently frozen? Banned outright, or suspended and the clock hasn't
-- run out. Used in RLS/rpcs to stop a sanctioned user acting. Definer so it reads the
-- table regardless of the caller.
create or replace function public.is_sanctioned(uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_sanctions
    where user_id = uid
      and (banned or (suspended_until is not null and suspended_until > now()))
  );
$$;
revoke all on function public.is_sanctioned(uuid) from public;
grant execute on function public.is_sanctioned(uuid) to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. MODERATION ACTIONS — an append-only audit trail. Who did what, to whom, why.
--    A moderator can read it; nobody writes it except the rpcs (accountability).
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.moderation_actions (
  id         uuid primary key default gen_random_uuid(),
  actor_id   uuid references public.profiles(id) on delete set null,
  subject_id uuid references public.profiles(id) on delete set null,
  action     text not null check (action in ('suspend', 'ban', 'lift')),
  reason     text check (char_length(reason) <= 1000),
  until      timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists moderation_actions_subject_idx on public.moderation_actions (subject_id, created_at desc);
alter table public.moderation_actions enable row level security;

drop policy if exists moderation_actions_read on public.moderation_actions;
create policy moderation_actions_read on public.moderation_actions for select to authenticated
  using (public.is_moderator(auth.uid()));
-- (No client write policy — written only by the suspend/ban/lift rpcs.)

-- ── suspend ───────────────────────────────────────────────────────────────────
create or replace function public.suspend_user(target uuid, until timestamptz, reason text default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_moderator(me) then raise exception 'moderators only'; end if;
  if target = me then raise exception 'you can''t sanction yourself'; end if;
  if until is null or until <= now() then raise exception 'a suspension must end in the future'; end if;

  insert into public.user_sanctions (user_id, suspended_until, banned, reason, updated_by, updated_at)
    values (target, until, false, reason, me, now())
    on conflict (user_id) do update
      set suspended_until = excluded.suspended_until, banned = false,
          reason = excluded.reason, updated_by = me, updated_at = now();
  insert into public.moderation_actions (actor_id, subject_id, action, reason, until)
    values (me, target, 'suspend', reason, until);
  return true;
end; $$;
revoke all on function public.suspend_user(uuid, timestamptz, text) from public;
grant execute on function public.suspend_user(uuid, timestamptz, text) to authenticated;

-- ── ban ───────────────────────────────────────────────────────────────────────
create or replace function public.ban_user(target uuid, reason text default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_moderator(me) then raise exception 'moderators only'; end if;
  if target = me then raise exception 'you can''t sanction yourself'; end if;

  insert into public.user_sanctions (user_id, suspended_until, banned, reason, updated_by, updated_at)
    values (target, null, true, reason, me, now())
    on conflict (user_id) do update
      set banned = true, suspended_until = null, reason = excluded.reason, updated_by = me, updated_at = now();
  insert into public.moderation_actions (actor_id, subject_id, action, reason, until)
    values (me, target, 'ban', reason, null);
  return true;
end; $$;
revoke all on function public.ban_user(uuid, text) from public;
grant execute on function public.ban_user(uuid, text) to authenticated;

-- ── lift (un-suspend / un-ban) ─────────────────────────────────────────────────
create or replace function public.lift_sanction(target uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_moderator(me) then raise exception 'moderators only'; end if;
  delete from public.user_sanctions where user_id = target;
  insert into public.moderation_actions (actor_id, subject_id, action, reason, until)
    values (me, target, 'lift', null, null);
  return true;
end; $$;
revoke all on function public.lift_sanction(uuid) from public;
grant execute on function public.lift_sanction(uuid) to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. THE QUEUE — a moderator reads reports here (the reports table itself still has
--    NO select policy; only this definer rpc exposes them, and only to moderators).
--    Includes how many times each subject has been reported (repeat-offender signal)
--    and whether they're already sanctioned.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.open_reports()
returns table (
  id uuid, reporter_name text, subject_id uuid, subject_name text, subject_handle text,
  reason text, note text, created_at timestamptz,
  subject_report_count int, subject_sanctioned boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_moderator(auth.uid()) then raise exception 'moderators only'; end if;
  return query
    select r.id, rp.display_name, r.subject_user_id, sp.display_name, sp.handle,
           r.reason, r.note, r.created_at,
           (select count(*)::int from public.reports r2 where r2.subject_user_id = r.subject_user_id),
           public.is_sanctioned(r.subject_user_id)
    from public.reports r
    left join public.profiles rp on rp.id = r.reporter_id
    left join public.profiles sp on sp.id = r.subject_user_id
    order by r.created_at desc
    limit 200;
end; $$;
revoke all on function public.open_reports() from public;
grant execute on function public.open_reports() to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. ENFORCEMENT — a sanctioned account can't create or join a plan, or use/appear in
--    search. We re-derive is_sanctioned at each action; the CHECK/rpc is the wall.
-- ────────────────────────────────────────────────────────────────────────────

-- Can't create a plan while frozen. (Rewrites 031's plans_insert to add the gate.)
drop policy if exists plans_insert on public.plans;
create policy plans_insert on public.plans for insert to authenticated
  with check (host_id = auth.uid() and not public.is_sanctioned(auth.uid()));

-- Can't ask to join while frozen. (Rewrites 031's request_join to add the gate up top.)
create or replace function public.request_join(pid uuid, msg text default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p public.plans; going int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if public.is_sanctioned(me) then raise exception 'your account is limited right now'; end if;
  select * into p from public.plans where id = pid;
  if p.id is null then raise exception 'no such plan'; end if;
  if p.host_id = me then raise exception 'it''s already your plan'; end if;
  if p.status <> 'open' then raise exception 'this plan isn''t taking people'; end if;
  if not public.plan_visible_to(pid, me) then
    raise exception 'you can''t join this plan';
  end if;
  if p.capacity is not null then
    going := public.plan_going_count(pid);
    if going >= p.capacity then raise exception 'this plan is full'; end if;
  end if;

  insert into public.plan_joins (plan_id, user_id, status, message)
  values (pid, me, 'requested', nullif(trim(coalesce(msg, '')), ''))
  on conflict (plan_id, user_id) do update
    set status = 'requested', message = excluded.message, created_at = now()
    where public.plan_joins.status in ('declined', 'withdrawn');
  return true;
end; $$;
revoke all on function public.request_join(uuid, text) from public;
grant execute on function public.request_join(uuid, text) to authenticated;

-- A banned/suspended person neither searches nor surfaces in search. (Rewrites 031's
-- search_users: a sanctioned caller gets nothing, and sanctioned users are dropped from
-- everyone's results.)
create or replace function public.search_users(q text)
returns table (id uuid, handle text, display_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.handle, p.display_name
  from public.profiles p
  where p.id <> auth.uid()
    and not public.blocked_between(auth.uid(), p.id)
    and not public.is_sanctioned(auth.uid())
    and not public.is_sanctioned(p.id)
    and (p.handle ilike '%' || q || '%' or p.display_name ilike '%' || q || '%')
  order by p.handle
  limit 10;
$$;
revoke all on function public.search_users(text) from public;
grant execute on function public.search_users(text) to authenticated;
