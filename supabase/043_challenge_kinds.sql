-- ============================================================================
-- brewdiary — 043: MORE CHALLENGES, all of them for variety or consistency.
--
-- Five new auto-scored kinds for circle challenges, none of which can be won by
-- drinking more (CLAUDE.md: nothing rewards drinking more):
--   days_kept   — nights you wrote in the diary (dry nights count)
--   dry_nights  — nights you logged as dry
--   new_drinks  — drinks you'd never logged before the challenge began
--   new_places  — places you'd never logged before the challenge began
--   hydration   — nights you logged a water
--
-- Same privacy shape as challenge_board() (005): opt-in participants only,
-- COUNTS ONLY, callers outside the circle get nothing, and entry content never
-- leaves the function. challenge_board() is left as it is for older clients;
-- the new kinds read challenge_board_v2().
-- Runs on top of 005 + 008. Idempotent-ish.
-- ============================================================================

alter table public.challenges drop constraint if exists challenges_kind_check;
alter table public.challenges add constraint challenges_kind_check
  check (kind in ('most_logged', 'most_kinds', 'longest_streak', 'freeform',
                  'days_kept', 'dry_nights', 'new_drinks', 'new_places', 'hydration'));

drop function if exists public.challenge_board_v2(uuid) cascade;
create or replace function public.challenge_board_v2(cid uuid)
returns table (
  user_id      uuid,
  display_name text,
  days_kept    int,
  dry_nights   int,
  new_drinks   int,
  new_places   int,
  water_days   int
)
language sql stable security definer set search_path = public as $$
  with ch as (
    select c.* from public.challenges c
     where c.id = cid and public.is_circle_member(c.circle_id, auth.uid())
  ),
  win as (
    select cm.user_id, e.date, lower(trim(e.drink)) as drink, e.type, lower(trim(e.venue)) as venue
      from ch
      join public.challenge_members cm on cm.challenge_id = ch.id
      join public.entries e on e.user_id = cm.user_id and e.date between ch.starts_on and ch.ends_on
  ),
  before as (
    select cm.user_id, lower(trim(e.drink)) as drink, lower(trim(e.venue)) as venue
      from ch
      join public.challenge_members cm on cm.challenge_id = ch.id
      join public.entries e on e.user_id = cm.user_id and e.date < ch.starts_on
  )
  select cm.user_id,
         coalesce(p.display_name, 'member'),
         (select count(distinct w.date) from win w where w.user_id = cm.user_id)::int,
         (select count(distinct w.date) from win w where w.user_id = cm.user_id and w.type = 'none')::int,
         (select count(distinct w.drink) from win w
           where w.user_id = cm.user_id and coalesce(w.type, '') <> 'none'
             and not exists (select 1 from before b where b.user_id = cm.user_id and b.drink = w.drink))::int,
         (select count(distinct w.venue) from win w
           where w.user_id = cm.user_id and coalesce(w.venue, '') <> ''
             and not exists (select 1 from before b where b.user_id = cm.user_id and b.venue = w.venue))::int,
         (select count(distinct w.date) from win w where w.user_id = cm.user_id and w.drink = 'water')::int
    from ch
    join public.challenge_members cm on cm.challenge_id = ch.id
    join public.profiles p on p.id = cm.user_id;
$$;
revoke all on function public.challenge_board_v2(uuid) from public;
grant execute on function public.challenge_board_v2(uuid) to authenticated;
