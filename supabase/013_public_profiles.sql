-- ============================================================================
-- brewdiary — "Public profiles" (Phase 7): let people be as public as they
-- CHOOSE, but our side never exposes them. Adds a per-user visibility setting +
-- one optional social link. public_profile() is ANON-callable and returns only
-- profiles set to 'public', COUNTS ONLY (a 12-week mosaic + all-time totals) +
-- the one social handle — NEVER notes, spend, contacts, or location.
--
-- Visibility tiers: 'friends' (default — today's friend-mosaic peek), 'fof'
-- (friends-of-friends — read support lands later; behaves as friends until then),
-- 'public' (anyone). Nobody is public unless they opt in.
-- Runs on top of schema.sql + 002..012. Idempotent-ish.
-- ============================================================================

drop function if exists public.public_profile(text) cascade;

alter table public.profiles
  add column if not exists profile_visibility text not null default 'friends'
    check (profile_visibility in ('friends', 'fof', 'public'));
alter table public.profiles
  add column if not exists social_handle text;

-- Anon-callable public summary for a 'public' profile. DEFINER so it can count a
-- user's private entries WITHOUT exposing content — only per-day counts (the
-- mosaic) + all-time totals leave the function.
create or replace function public.public_profile(h text)
returns table (display_name text, handle text, social_handle text, dates date[], total int, kinds int)
language sql stable security definer set search_path = public as $$
  select p.display_name,
         p.handle,
         p.social_handle,
         coalesce(array_agg(e.date) filter (where e.date >= current_date - 84), '{}'::date[]),
         count(e.id)::int,
         count(distinct lower(trim(e.drink)))::int
  from public.profiles p
  left join public.entries e on e.user_id = p.id
  where p.handle = lower(trim(h))
    and p.profile_visibility = 'public'
  group by p.id, p.display_name, p.handle, p.social_handle;
$$;
revoke all on function public.public_profile(text) from public;
grant execute on function public.public_profile(text) to anon, authenticated;
