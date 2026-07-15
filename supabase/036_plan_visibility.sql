-- ============================================================================
-- brewdiary — Plans: two quieter visibilities + the calendar overlay.
--
-- ── WHY ─────────────────────────────────────────────────────────────────────
-- 031 gave plans two audiences: 'friends' and 'fof'. This adds the two the user asked
-- for — keep a night to YOURSELF, or open it only to SPECIFIC people you invite — and a
-- read the home calendar uses to mark the days you've got something planned.
--
-- Still deny-by-default and still NO stranger tier: 'private' is visible to nobody but
-- the host, and 'invite' is visible only to people the host explicitly named (who must
-- not be blocked). Everything reuses plan_visible_to, the one visibility authority, so
-- the RLS policy and every feed rpc move together and can't drift.
--
-- Runs on top of schema.sql + 002..035. One implicit transaction — lands whole or not.
-- ============================================================================

-- ── 1. widen the join policy (deny-by-default preserved — the set is explicit) ──
alter table public.plans drop constraint if exists plans_join_policy_check;
alter table public.plans add constraint plans_join_policy_check
  check (join_policy in ('friends', 'fof', 'private', 'invite'));

-- ── 2. plan_invites — the named guests for an 'invite' plan. Server-written only:
--       no client write policy; the host manages it through the rpcs below, which
--       re-check host-ownership and blocks. Readable by the host and by the invitee. ──
create table if not exists public.plan_invites (
  plan_id    uuid not null references public.plans(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (plan_id, user_id)
);
create index if not exists plan_invites_user_idx on public.plan_invites (user_id);
alter table public.plan_invites enable row level security;

drop policy if exists plan_invites_read on public.plan_invites;
create policy plan_invites_read on public.plan_invites for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.plans p where p.id = plan_id and p.host_id = auth.uid())
  );
-- (No insert/update/delete policy — written only by invite_to_plan / uninvite_from_plan.)

-- Am I invited to this plan? Definer so plan_visible_to can call it under RLS.
create or replace function public.is_plan_invited(pid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.plan_invites where plan_id = pid and user_id = uid);
$$;
revoke all on function public.is_plan_invited(uuid, uuid) from public;
grant execute on function public.is_plan_invited(uuid, uuid) to authenticated;

-- ── 3. plan_visible_to — add the two new branches. Host always sees their own (incl.
--       'private', which stops there). 'invite' opens only to a named, non-blocked
--       guest. 'friends'/'fof' are unchanged. Rewrites 031's function. ──
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
            or (p.join_policy = 'invite' and public.is_plan_invited(pid, uid))
            -- 'private' has no branch here: nobody but the host, on purpose.
          )
        )
      )
  );
$$;
revoke all on function public.plan_visible_to(uuid, uuid) from public;
grant execute on function public.plan_visible_to(uuid, uuid) to authenticated;

-- ── 4. invite / uninvite — host-only, block-aware, and only for an 'invite' plan. ──
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
  if public.blocked_between(me, target) then raise exception 'you can''t invite this person'; end if;
  -- Invites stay INSIDE the graph — a friend or a friend-of-a-friend, never a stranger.
  -- 'invite' narrows who sees a plan (these specific people), it doesn't widen it to the
  -- public. This keeps the whole no-stranger-tier safety property intact.
  if not (public.are_friends(me, target) or public.is_fof(me, target)) then
    raise exception 'you can only invite people in your circle';
  end if;

  insert into public.plan_invites (plan_id, user_id) values (pid, target)
    on conflict do nothing;
  return true;
end; $$;
revoke all on function public.invite_to_plan(uuid, uuid) from public;
grant execute on function public.invite_to_plan(uuid, uuid) to authenticated;

create or replace function public.uninvite_from_plan(pid uuid, target uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from public.plans p where p.id = pid and p.host_id = me) then
    raise exception 'only the host can manage invites';
  end if;
  delete from public.plan_invites where plan_id = pid and user_id = target;
  -- pulling an invite also withdraws any join they'd started off it
  update public.plan_joins set status = 'withdrawn'
   where plan_id = pid and user_id = target and status in ('requested', 'approved');
  return true;
end; $$;
revoke all on function public.uninvite_from_plan(uuid, uuid) from public;
grant execute on function public.uninvite_from_plan(uuid, uuid) to authenticated;

-- The named guests on one of MY plans (host-only), with display names for the UI.
create or replace function public.plan_invitees(pid uuid)
returns table (user_id uuid, handle text, display_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from public.plans p where p.id = pid and p.host_id = auth.uid()) then
    raise exception 'only the host can see the guest list';
  end if;
  return query
    select i.user_id, pr.handle, pr.display_name
    from public.plan_invites i
    join public.profiles pr on pr.id = i.user_id
    where i.plan_id = pid
    order by pr.display_name nulls last, pr.handle;
end; $$;
revoke all on function public.plan_invitees(uuid) from public;
grant execute on function public.plan_invitees(uuid) to authenticated;

-- ── 5. my_plan_days — the days the home calendar marks: plans I host, plus plans I've
--       been approved to join. Upcoming only, and only ever the caller's own. ──
create or replace function public.my_plan_days()
returns table (plan_date date, title text, host boolean)
language sql stable security definer set search_path = public as $$
  select p.plan_date, p.title, true
  from public.plans p
  where p.host_id = auth.uid()
    and p.status <> 'cancelled'
    and p.plan_date >= current_date
  union all
  select p.plan_date, p.title, false
  from public.plans p
  join public.plan_joins j on j.plan_id = p.id
  where j.user_id = auth.uid()
    and j.status = 'approved'
    and p.status = 'open'
    and p.plan_date >= current_date;
$$;
revoke all on function public.my_plan_days() from public;
grant execute on function public.my_plan_days() to authenticated;
