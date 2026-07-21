-- ============================================================================
-- brewdiary — PALATE NEIGHBOURS: "people whose maps look like yours wandered
-- here next." The aggregate half of phase-A §3.4 (the local half — adjacency,
-- friends, novelty — shipped long ago inside the Tonight hand).
--
-- What it is: ONE k-anon rpc. It finds users whose diaries overlap yours
-- (≥ 2 shared distinct drinks), then returns the drinks THOSE people log that
-- YOU never have — as (name, users) counts, each row backed by ≥ 5 distinct
-- neighbours. The client folds the names into dictionary families (drinks.ts —
-- canonicalization is a TS concern, the DB aggregates raw normalized names).
--
-- Privacy posture (mirrors area_taste_trends, 039):
--   • OPT-IN BOTH WAYS via profiles.share_trends: you are only counted in other
--     people's neighbourhoods if it's on — and you can only ASK when it's on
--     (fair trade: no reading the crowd while hiding from it). Off → no rows.
--   • Counts only, k ≥ 5 distinct users per row — no name, no id, no venue,
--     no date ever leaves. There is no per-user row in the result shape.
--   • You need ≥ 3 distinct drinks of your own before it answers — below that
--     "similar to you" is noise, and tiny overlaps are easier to re-identify.
--   • Alcohol is never a ranking signal (rule #6): ordering is by neighbour
--     count alone, so chamomile outranks whisky whenever more of your
--     neighbours wandered there. Nothing here counts volume.
-- Runs on top of 002..047.
-- ============================================================================

drop function if exists public.palate_neighbours(int) cascade;

-- SECURITY DEFINER for the same reason as taste_trends: the k-threshold and
-- counts-only shape are what make aggregating over private entries safe, and
-- they must live HERE, not in a client that could be modified.
create or replace function public.palate_neighbours(lim int default 6)
returns table (name text, users int)
language sql stable security definer set search_path = public as $$
  with me as (
    -- the caller, only if opted in (deny-by-default: not opted in → empty result)
    select p.id from public.profiles p
    where p.id = auth.uid() and p.share_trends
  ),
  mine as (
    select distinct lower(trim(e.drink)) as d
    from public.entries e join me on me.id = e.user_id
  ),
  eligible as (
    -- only proceed when the caller has a real map of their own
    select 1 from mine having count(*) >= 3
  ),
  neighbours as (
    -- opted-in users who share ≥ 2 distinct drinks with the caller
    select e.user_id
    from public.entries e
    join public.profiles p on p.id = e.user_id and p.share_trends
    join mine on lower(trim(e.drink)) = mine.d
    where exists (select 1 from eligible)
      and e.user_id <> auth.uid()
    group by e.user_id
    having count(distinct lower(trim(e.drink))) >= 2
  )
  -- what the neighbourhood pours that the caller never has — counts only, k ≥ 5
  select min(e.drink) as name,
         count(distinct e.user_id)::int as users
  from public.entries e
  join neighbours n on n.user_id = e.user_id
  where lower(trim(e.drink)) not in (select d from mine)
  group by lower(trim(e.drink))
  having count(distinct e.user_id) >= 5
  order by users desc, name
  limit greatest(1, least(lim, 12));
$$;

revoke all on function public.palate_neighbours(int) from public;
grant execute on function public.palate_neighbours(int) to authenticated;
