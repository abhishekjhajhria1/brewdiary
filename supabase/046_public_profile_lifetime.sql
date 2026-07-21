-- ============================================================================
-- brewdiary — "Public profile, lifetime stats" (046).
--
-- The public profile (/u/<handle>) grew a Palate Score + lifetime stats, and the
-- score/consistency figures need a few more COUNTS out of public_profile(). This
-- extends the function (same visibility tiers as 018 — 'public'/'fof'/'friends',
-- always yourself) with:
--     active_days    — distinct days you logged ANYTHING (a dry day counts), all-time
--     longest_streak — longest run of consecutive logged days (no grace; a public approx)
--     months_active  — distinct calendar months with a log
--     first_date     — the day the diary started ("since …")
--
-- Still COUNTS ONLY. Nothing here is a note, a venue, a ₹ figure, or a location — the
-- same promise the page has always made, just with a richer headline. The client computes
-- the score itself (lib/score.ts); the DB only hands over the four breadth/consistency
-- numbers. Rule #6 holds: none of these can be moved by drinking more (distinct days,
-- distinct drinks, a streak — logging the same thing again advances none of them).
--
-- Runs on top of schema.sql + 002..045. Idempotent-ish (drop + recreate the function).
-- ============================================================================

drop function if exists public.public_profile(text) cascade;

create or replace function public.public_profile(h text)
returns table (
  display_name   text,
  handle         text,
  social_handle  text,
  dates          date[],
  total          int,
  kinds          int,
  active_days    int,
  longest_streak int,
  months_active  int,
  first_date     date
)
language sql stable security definer set search_path = public as $$
  select p.display_name,
         p.handle,
         p.social_handle,
         coalesce(array_agg(e.date) filter (where e.date >= current_date - 84), '{}'::date[]) as dates,
         count(e.id)::int                                   as total,
         count(distinct lower(trim(e.drink)))::int          as kinds,
         count(distinct e.date)::int                        as active_days,
         -- longest run of consecutive logged days: a classic gaps-and-islands count.
         -- Grouping distinct days by (day - row_number) collapses each consecutive run to
         -- one bucket; the largest bucket is the longest streak. No grace (the owner's own
         -- view uses a 1-day grace — this public figure is a close, slightly stricter read).
         coalesce((
           select max(rl) from (
             select count(*) as rl
             from (
               select d.day, (d.day - (row_number() over (order by d.day))::int) as grp
               from (select distinct e2.date as day from public.entries e2 where e2.user_id = p.id) d
             ) g
             group by g.grp
           ) runs
         ), 0)::int                                         as longest_streak,
         count(distinct to_char(e.date, 'YYYY-MM'))::int    as months_active,
         min(e.date)                                        as first_date
  from public.profiles p
  left join public.entries e on e.user_id = p.id
  where p.handle = lower(trim(h))
    and (
      p.profile_visibility = 'public'
      or p.id = auth.uid()                                                   -- always yourself
      or (auth.uid() is not null and p.profile_visibility = 'fof'
          and public.is_fof(auth.uid(), p.id))                               -- friends + their friends
      or (auth.uid() is not null and p.profile_visibility = 'friends'
          and exists (
            select 1 from public.friendships f
            where f.status = 'accepted'
              and ((f.requester_id = auth.uid() and f.addressee_id = p.id)
                or (f.addressee_id = auth.uid() and f.requester_id = p.id))
          ))                                                                 -- accepted friends only
    )
  group by p.id, p.display_name, p.handle, p.social_handle;
$$;
revoke all on function public.public_profile(text) from public;
grant execute on function public.public_profile(text) to anon, authenticated;
