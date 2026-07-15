-- ============================================================================
-- brewdiary — Plans: invite by username (with consent), a direct RSVP, a start time.
--
-- ── WHAT CHANGES ────────────────────────────────────────────────────────────
-- 036 gated 'invite' to friends/fof. The user wants to invite specific people by
-- USERNAME — anyone they name — while keeping it safe. So:
--   • invite_to_plan no longer requires the target be a friend/fof. It still refuses a
--     blocked or sanctioned pairing, and the host must own an 'invite' plan. Safety holds
--     because you reach someone by their exact handle (there is still NO public/stranger
--     discovery feed), NOTHING happens to them without their own RSVP, and blocks /
--     reports / moderation all still apply.
--   • respond_invite lets an invited guest say yes/no DIRECTLY — no host approval, since
--     the host already chose them. (Friends/fof plans keep request → host approves.)
--   • plans gain an optional start time.
--
-- Feed rpcs that change SHAPE are dropped + recreated (pre-launch, no data to keep).
-- Runs on top of schema.sql + 002..036. One implicit transaction — lands whole or not.
-- ============================================================================

-- ── 1. optional start time ──────────────────────────────────────────────────
alter table public.plans add column if not exists plan_time time;

-- ── 2. invite by username — drop the friends/fof requirement (keep block + sanction) ──
create or replace function public.invite_to_plan(pid uuid, target uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p public.plans;
begin
  if me is null then raise exception 'not signed in'; end if;
  if public.is_sanctioned(me) then raise exception 'your account is limited right now'; end if;
  select * into p from public.plans where id = pid;
  if p.id is null then raise exception 'no such plan'; end if;
  if p.host_id <> me then raise exception 'only the host can invite'; end if;
  if p.join_policy <> 'invite' then raise exception 'this plan is not an invite plan'; end if;
  if target = me then raise exception 'you are the host'; end if;
  if not exists (select 1 from public.profiles where id = target) then raise exception 'no such person'; end if;
  if public.blocked_between(me, target) then raise exception 'you can''t invite this person'; end if;
  -- No friends/fof gate: you invite whoever you name. It stays safe because the invitee
  -- must accept, and there is no public feed that surfaces the plan to strangers.
  insert into public.plan_invites (plan_id, user_id) values (pid, target)
    on conflict do nothing;
  return true;
end; $$;
revoke all on function public.invite_to_plan(uuid, uuid) from public;
grant execute on function public.invite_to_plan(uuid, uuid) to authenticated;

-- ── 3. respond_invite — an invited guest RSVPs directly (yes = going, no = declined) ──
create or replace function public.respond_invite(pid uuid, going boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p public.plans; cnt int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if public.is_sanctioned(me) then raise exception 'your account is limited right now'; end if;
  select * into p from public.plans where id = pid;
  if p.id is null then raise exception 'no such plan'; end if;
  if p.join_policy <> 'invite' then raise exception 'this plan is not an invite plan'; end if;
  if not public.is_plan_invited(pid, me) then raise exception 'you are not invited to this plan'; end if;
  if public.blocked_between(me, p.host_id) then raise exception 'you can''t join this plan'; end if;
  if going then
    if p.status <> 'open' then raise exception 'this plan isn''t taking people'; end if;
    if p.capacity is not null then
      cnt := public.plan_going_count(pid);
      if cnt >= p.capacity
         and not exists (select 1 from public.plan_joins j where j.plan_id = pid and j.user_id = me and j.status = 'approved')
      then raise exception 'this plan is full'; end if;
    end if;
  end if;
  insert into public.plan_joins (plan_id, user_id, status)
    values (pid, me, case when going then 'approved' else 'declined' end)
    on conflict (plan_id, user_id) do update set status = excluded.status, created_at = now();
  return true;
end; $$;
revoke all on function public.respond_invite(uuid, boolean) from public;
grant execute on function public.respond_invite(uuid, boolean) to authenticated;

-- ── 4. feeds carry the start time (shape changed → drop + recreate) ─────────────
drop function if exists public.upcoming_plans();
create function public.upcoming_plans()
returns table (
  id uuid, host_id uuid, host_name text, host_handle text,
  title text, plan_date date, plan_time time, city text, venue_id uuid,
  note text, drinks text[], vibe_tags text[], join_policy text,
  capacity int, going int, my_status text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.host_id, ph.display_name, ph.handle,
         p.title, p.plan_date, p.plan_time, p.city, p.venue_id,
         p.note, p.drinks, p.vibe_tags, p.join_policy,
         p.capacity, public.plan_going_count(p.id),
         (select j.status from public.plan_joins j where j.plan_id = p.id and j.user_id = auth.uid())
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
  capacity int, status text, going int, pending int
)
language sql stable security definer set search_path = public as $$
  select p.id, p.title, p.plan_date, p.plan_time, p.city, p.venue_id,
         p.note, p.drinks, p.vibe_tags, p.join_policy,
         p.capacity, p.status, public.plan_going_count(p.id),
         (select count(*)::int from public.plan_joins j where j.plan_id = p.id and j.status = 'requested')
  from public.plans p
  where p.host_id = auth.uid()
  order by (p.status = 'open') desc, p.plan_date;
$$;
revoke all on function public.my_plans() from public;
grant execute on function public.my_plans() to authenticated;

drop function if exists public.my_plan_days();
create function public.my_plan_days()
returns table (plan_date date, plan_time time, title text, host boolean)
language sql stable security definer set search_path = public as $$
  select p.plan_date, p.plan_time, p.title, true
  from public.plans p
  where p.host_id = auth.uid()
    and p.status <> 'cancelled'
    and p.plan_date >= current_date
  union all
  select p.plan_date, p.plan_time, p.title, false
  from public.plans p
  join public.plan_joins j on j.plan_id = p.id
  where j.user_id = auth.uid()
    and j.status = 'approved'
    and p.status = 'open'
    and p.plan_date >= current_date;
$$;
revoke all on function public.my_plan_days() from public;
grant execute on function public.my_plan_days() to authenticated;
