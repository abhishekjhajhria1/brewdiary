-- ============================================================================
-- brewdiary — area trends by LOCATION, the privacy-preserving way (Path A).
--
-- 039 matched drinkers to a bar by a TYPED city string — messy and rarely filled.
-- This replaces the match key with a COARSE GEOHASH computed ON THE DEVICE from a
-- one-time location permission. The raw coordinates never leave the phone and are
-- never stored — only a short, low-precision geohash (precision 4 ≈ a ~40 km,
-- city-scale cell). So we know "roughly which city", never "where you are".
--
--   • profiles.trends_geo — the drinker's coarse cell (opt-in, alongside share_trends)
--   • venues.geohash       — the venue's coarse cell (owner sets it from the dashboard)
--   • area_taste_trends(in_geo) matches trends_geo = in_geo, still k-anon ≥5.
--
-- The old typed-city column (profiles.trends_area) is left in place but unused — no
-- destructive drop needed, and nothing reads it anymore.
--
-- Runs on top of 002..040 (039 must be applied — this supersedes its function).
-- ============================================================================

-- The drinker's coarse cell. Short by construction (a geohash), capped hard so it
-- can never smuggle in precise coordinates.
alter table public.profiles add column if not exists trends_geo text;

do $$ begin
  if not exists (
    select 1 from information_schema.constraint_column_usage
    where table_schema = 'public' and table_name = 'profiles' and constraint_name = 'profiles_trends_geo_len'
  ) then
    alter table public.profiles
      add constraint profiles_trends_geo_len check (trends_geo is null or char_length(trends_geo) <= 12);
  end if;
end $$;

-- The venue's coarse cell, set by the owner from the dashboard ("use my location").
alter table public.venues add column if not exists geohash text;

do $$ begin
  if not exists (
    select 1 from information_schema.constraint_column_usage
    where table_schema = 'public' and table_name = 'venues' and constraint_name = 'venues_geohash_len'
  ) then
    alter table public.venues
      add constraint venues_geohash_len check (geohash is null or char_length(geohash) <= 12);
  end if;
end $$;

-- Signature keeps (text, int) but the parameter is now a geohash, so recreate.
drop function if exists public.area_taste_trends(text, int) cascade;

-- CONSENTING drinkers in ONE coarse cell only, each row backed by ≥5 distinct people.
-- Counts only. SECURITY DEFINER for the same reason as taste_trends — the k-threshold
-- and count-only shape are what make aggregating over private entries safe.
create or replace function public.area_taste_trends(in_geo text, days_back int default 30)
returns table (kind text, name text, users int, logs int)
language sql stable security definer set search_path = public as $$
  with window_entries as (
    select e.user_id, e.drink, e.mood
    from public.entries e
    join public.profiles p on p.id = e.user_id
    where p.share_trends
      and p.trends_geo is not null
      and trim(coalesce(in_geo, '')) <> ''
      and p.trends_geo = trim(in_geo)
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
