-- ============================================================================
-- brewdiary — "Team cups" (047): two-sided cup battles.
--
-- The maintainer's ask: let two GROUPS compete, not just individuals. A cup can
-- now be a team battle — the maker names two sides, members pick one, and the
-- board shows side totals (sum of each member's own breadth score). Octalysis
-- read: this is CD5 (Social Influence — my side needs me, so I invite friends)
-- layered onto CD2 (Accomplishment), and recruiting is the ONLY way to grow a
-- side — which is exactly the growth loop we want.
--
-- RULE #6 UNCHANGED AND STRUCTURAL: a team's score is the SUM of member scores
-- from cup_board(), and every cup_board axis is COUNT(distinct …) — drinks,
-- places, kinds, dry days. Logging the same drink again adds nothing to you and
-- therefore nothing to your team. There is still no volume/spend axis to pick.
-- You help your team by exploring wider or by bringing another explorer — never
-- by drinking more.
--
-- Incremental on 044 (idempotent-ish: add column if not exists / drop fn first).
-- ============================================================================

drop function if exists public.cup_team_board(uuid) cascade;
drop function if exists public.pick_team(uuid, text) cascade;

-- The maker's team setup. team_mode off = the classic solo cup (nothing changes).
alter table public.cups
  add column if not exists team_mode boolean not null default false;
alter table public.cups
  add column if not exists team_a text check (team_a is null or char_length(btrim(team_a)) between 1 and 24);
alter table public.cups
  add column if not exists team_b text check (team_b is null or char_length(btrim(team_b)) between 1 and 24);

-- Which side a member stands on. NULL until they pick (undrafted members still
-- score on the solo board; they just don't count for either side yet).
alter table public.cup_members
  add column if not exists team text check (team in ('a', 'b'));

-- Pick (or switch) your side. Definer — cup_members has no client UPDATE policy,
-- so this fn is the only door, and it re-checks everything server-side.
create or replace function public.pick_team(cup uuid, side text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  c  public.cups;
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if side not in ('a', 'b') then raise exception 'no such side'; end if;
  select * into c from public.cups where id = cup;
  if not found then raise exception 'no such cup'; end if;
  if not c.team_mode then raise exception 'not a team cup'; end if;
  if c.ends_on < current_date then raise exception 'this cup has ended'; end if;
  if not public.is_cup_member(cup, me) then raise exception 'not a member'; end if;
  update public.cup_members set team = side where cup_id = cup and user_id = me;
end;
$$;

revoke all on function public.pick_team(uuid, text) from public;
grant execute on function public.pick_team(uuid, text) to authenticated;

-- The two-sided board: per side, how many stand on it and the SUM of their solo
-- scores. Built ON TOP of cup_board(), so the membership gate and the anti-volume
-- axis palette are inherited, not re-implemented (one authority, no drift).
create or replace function public.cup_team_board(cup uuid)
returns table (team text, players int, score int)
language sql stable security definer set search_path = public as $$
  select cm.team,
         count(*)::int            as players,
         coalesce(sum(b.score), 0)::int as score
  from public.cup_board(cup) b
  join public.cup_members cm on cm.cup_id = cup and cm.user_id = b.user_id
  where cm.team is not null
  group by cm.team;
$$;

revoke all on function public.cup_team_board(uuid) from public;
grant execute on function public.cup_team_board(uuid) to authenticated;
