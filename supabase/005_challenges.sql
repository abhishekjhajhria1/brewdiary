-- ============================================================================
-- brewdiary — "Challenges" (opt-in, INSIDE CIRCLES ONLY — the locked rule:
-- loud/competitive things live in Together; the Calendar never shows a score).
-- Incremental migration — runs on top of schema.sql + 002..004. Idempotent-ish.
--
-- Model: a CHALLENGE belongs to a circle, has a kind + a date window.
-- Participation is a separate opt-in row (CHALLENGE_MEMBERS) — being in the
-- circle does NOT enter you. The leaderboard is never stored: challenge_board()
-- aggregates COUNTS ONLY (days logged, total entries, distinct-drink count)
-- over participants' entries in the window. Opting in consents to exposing
-- those counts to the circle; entry CONTENT (drinks, notes, photos) is never
-- exposed by the function.
-- ============================================================================

drop table if exists public.challenge_members cascade;
drop table if exists public.challenges        cascade;
drop function if exists public.challenge_board(uuid)                 cascade;
drop function if exists public.is_challenge_circle_member(uuid, uuid) cascade;

create table public.challenges (
  id         uuid primary key default gen_random_uuid(),
  circle_id  uuid not null references public.circles(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('most_logged', 'most_kinds', 'longest_streak')),
  starts_on  date not null,
  ends_on    date not null,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);
create index challenges_circle_idx on public.challenges (circle_id);

create table public.challenge_members (
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

-- "does uid belong to the circle this challenge lives in?" — definer, so
-- challenge_members policies don't re-enter challenges' RLS.
create or replace function public.is_challenge_circle_member(chid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.challenges c
    join public.circle_members m on m.circle_id = c.circle_id
    where c.id = chid and m.user_id = uid
  );
$$;

-- The leaderboard. SECURITY DEFINER because participants' entries are private
-- rows the caller can't select — opting in consents to COUNT visibility only.
-- Returns, per participant: their distinct logged dates in the window (drives
-- streak math client-side), total entries, and distinct-drink count. Callers
-- outside the circle get an empty set.
create or replace function public.challenge_board(cid uuid)
returns table (user_id uuid, display_name text, dates date[], total int, kinds int)
language sql stable security definer set search_path = public as $$
  select cm.user_id,
         coalesce(p.display_name, 'member'),
         coalesce(array_agg(distinct e.date) filter (where e.id is not null), '{}'::date[]),
         count(e.id)::int,
         count(distinct lower(trim(e.drink)))::int
  from public.challenge_members cm
  join public.challenges c on c.id = cm.challenge_id
  join public.profiles p on p.id = cm.user_id
  left join public.entries e
    on e.user_id = cm.user_id and e.date >= c.starts_on and e.date <= c.ends_on
  where cm.challenge_id = cid
    and public.is_circle_member(c.circle_id, auth.uid())
  group by cm.user_id, p.display_name;
$$;

revoke all on function public.challenge_board(uuid) from public;
grant execute on function public.challenge_board(uuid) to authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.challenges        enable row level security;
alter table public.challenge_members enable row level security;

-- challenges: circle members see them; any circle member may start one;
-- the starter (or the circle's creator) can remove it.
create policy challenges_read on public.challenges for select to authenticated
  using (public.is_circle_member(circle_id, auth.uid()));
create policy challenges_insert on public.challenges for insert to authenticated
  with check (created_by = auth.uid() and public.is_circle_member(circle_id, auth.uid()));
create policy challenges_delete on public.challenges for delete to authenticated
  using (created_by = auth.uid()
      or exists (select 1 from public.circles c where c.id = circle_id and c.created_by = auth.uid()));

-- participation: visible to the circle; strictly self-service opt-in/out.
create policy challenge_members_read on public.challenge_members for select to authenticated
  using (public.is_challenge_circle_member(challenge_id, auth.uid()));
create policy challenge_members_insert on public.challenge_members for insert to authenticated
  with check (user_id = auth.uid() and public.is_challenge_circle_member(challenge_id, auth.uid()));
create policy challenge_members_delete on public.challenge_members for delete to authenticated
  using (user_id = auth.uid());
