-- ============================================================================
-- brewdiary — "Flex + friends-of-friends" (Phase 7, the last two gaps).
--
-- 1. FLEXING A TAB, DOUBLE-GATED. The maintainer's rule: "let the flexers flex
--    their receipts, but not their contact info." So room_tabs() shows a guest's
--    ₹ total on the wall board ONLY when BOTH switches are on:
--       kiosk_visible  → I agree to appear by name on a screen in the bar.
--       flex_receipts  → I agree that my TAB shows next to my name.
--    One without the other shows nothing. Both default OFF. And the number is
--    still one the BAR recorded (spend_events has no insert policy) — you can't
--    flex a tab you invented. Never a contact, never a handle, never an item.
--
-- 2. FRIENDS-OF-FRIENDS READS. 'fof' has been in the visibility enum since 013
--    but nothing honoured it — it silently behaved as friends-only. public_profile
--    now resolves all three tiers for a signed-in caller:
--       'public'  → anyone, including anon (unchanged).
--       'fof'     → my friends, and my friends' friends.
--       'friends' → my accepted friends only.
--    Anon callers still only ever see 'public'. You always see yourself.
-- Runs on top of schema.sql + 002..017. Idempotent-ish.
-- ============================================================================

drop function if exists public.room_tabs(text)      cascade;
drop function if exists public.is_fof(uuid, uuid)   cascade;
drop function if exists public.public_profile(text) cascade;

-- ── 1. the opt-in tab board ──────────────────────────────────────────────────
-- Anon-callable (the kiosk screen has no session), like room_board. Returns a
-- name and a rupee total — nothing else leaves the function.
create or replace function public.room_tabs(code text)
returns table (display_name text, spend numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(p.display_name, 'guest') as display_name,
         sum(se.amount)::numeric as spend
  from public.parties party
  join public.spend_events se on se.party_id = party.id
  join public.profiles p on p.id = se.subject_user_id
  where party.invite_code = lower(trim(code))
    and p.kiosk_visible = true   -- I agree to be on the screen …
    and p.flex_receipts = true   -- … AND I agree my tab shows there.
  group by p.id, p.display_name
  order by 2 desc, 1;
$$;
revoke all on function public.room_tabs(text) from public;
grant execute on function public.room_tabs(text) to anon, authenticated;

-- ── 2. friends-of-friends ────────────────────────────────────────────────────
-- True when `other` is a friend of mine, or a friend of one of my friends.
create or replace function public.is_fof(me uuid, other uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  with my_friends as (
    select case when f.requester_id = me then f.addressee_id else f.requester_id end as id
    from public.friendships f
    where f.status = 'accepted' and (f.requester_id = me or f.addressee_id = me)
  )
  select exists (select 1 from my_friends where id = other)
      or exists (
        select 1
        from my_friends mf
        join public.friendships f2
          on f2.status = 'accepted'
         and (f2.requester_id = mf.id or f2.addressee_id = mf.id)
        where case when f2.requester_id = mf.id then f2.addressee_id else f2.requester_id end = other
      );
$$;
revoke all on function public.is_fof(uuid, uuid) from public;
grant execute on function public.is_fof(uuid, uuid) to authenticated;

-- Same shape as 013 (counts only — a 12-week mosaic + totals + the one social
-- handle; never notes, never spend, never a contact), but the WHERE now honours
-- the tier the owner picked instead of collapsing everything to 'public'.
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
