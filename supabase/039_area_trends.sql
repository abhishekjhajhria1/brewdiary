-- ============================================================================
-- brewdiary — AREA taste trends: what the neighbourhood is drinking, for bars.
--
-- The market layer under "Ninkasi's read": a venue can be told what CONSENTING
-- drinkers in its own area are into — aggregate, counts-only, no names, ever. This
-- is the good half of "insights on users in that area". The forbidden half — a
-- picture of one person, or what a named guest drinks at another bar — is NOT here
-- and never will be. There is no per-user row and no venue_id in this function.
--
-- It mirrors taste_trends() (006) exactly, with two changes:
--   1. It filters to opt-in users whose coarse AREA matches (profiles.trends_area,
--      only ever set alongside share_trends). No area set → you're not counted.
--   2. Higher k: a city slice is a smaller crowd than "everyone", so a trend needs
--      ≥ 5 distinct people (not 3) before it's shown — harder to re-identify.
--
-- The model never touches this table: the manager's client calls the k-anon rpc,
-- and only the aggregate counts are handed to the advisor. Runs on top of 002..038.
-- ============================================================================

-- Opt-in coarse area (a city/town label). Meaningful ONLY when share_trends is on;
-- null means "don't place me on any local map". Length capped so it's a place, not
-- an address.
alter table public.profiles add column if not exists trends_area text;

do $$ begin
  if not exists (
    select 1 from information_schema.constraint_column_usage
    where table_schema = 'public' and table_name = 'profiles' and constraint_name = 'profiles_trends_area_len'
  ) then
    alter table public.profiles
      add constraint profiles_trends_area_len check (trends_area is null or char_length(trends_area) <= 80);
  end if;
end $$;

drop function if exists public.area_taste_trends(text, int) cascade;

-- CONSENTING users in ONE area only, each row backed by ≥5 distinct people. Counts
-- only. SECURITY DEFINER for the same reason as taste_trends — the k-threshold and
-- count-only shape are what make aggregating over private entries safe.
create or replace function public.area_taste_trends(in_area text, days_back int default 30)
returns table (kind text, name text, users int, logs int)
language sql stable security definer set search_path = public as $$
  with window_entries as (
    select e.user_id, e.drink, e.mood
    from public.entries e
    join public.profiles p on p.id = e.user_id
    where p.share_trends
      and p.trends_area is not null
      and trim(coalesce(in_area, '')) <> ''
      and lower(trim(p.trends_area)) = lower(trim(in_area))
      and e.date >= current_date - make_interval(days => greatest(1, least(days_back, 90)))::interval
  ),
  drinks as (
    select 'drink'::text as kind,
           min(drink) as name,
           count(distinct user_id)::int as users,
           count(*)::int as logs
    from window_entries
    group by lower(trim(drink))
    having count(distinct user_id) >= 5
  ),
  moods as (
    select 'mood'::text as kind,
           min(mood) as name,
           count(distinct user_id)::int as users,
           count(*)::int as logs
    from window_entries
    where mood is not null and trim(mood) <> ''
    group by lower(trim(mood))
    having count(distinct user_id) >= 5
  )
  select * from (
    (select * from drinks order by users desc, logs desc limit 6)
    union all
    (select * from moods order by users desc, logs desc limit 6)
  ) t;
$$;

revoke all on function public.area_taste_trends(text, int) from public;
grant execute on function public.area_taste_trends(text, int) to authenticated;
