-- ============================================================================
-- brewdiary — "Kiosk" (Phase 2 of Rooms/Points/Venues): the public wall board a
-- venue casts to a screen (bwdy.site/kiosk/<code>).
--
-- Appearing by name on a PHYSICAL screen is its own, stronger consent than
-- appearing in-app: profiles.kiosk_visible (opt-in, default OFF). room_board()
-- is ANON-callable (like party_preview) and returns ONLY opted-in guests, COUNTS
-- ONLY (sparks/vibe) — never a user id, never entry content.
-- Runs on top of schema.sql + 002..011. Idempotent-ish.
-- ============================================================================

drop function if exists public.room_board(text) cascade;

alter table public.profiles add column if not exists kiosk_visible boolean not null default false;

create or replace function public.room_board(code text)
returns table (display_name text, sparks int, vibe int)
language sql stable security definer set search_path = public as $$
  select coalesce(p.display_name, 'guest') as display_name,
         coalesce(sum(pe.value) filter (where pe.currency = 'spark'), 0)::int as sparks,
         coalesce(sum(pe.value) filter (where pe.currency = 'vibe'),  0)::int as vibe
  from public.parties party
  join public.point_events pe on pe.party_id = party.id
  join public.profiles p on p.id = pe.subject_user_id
  where party.invite_code = lower(trim(code))
    and p.kiosk_visible = true
  group by p.id, p.display_name
  -- no HAVING needed: point_events.value has CHECK (value > 0) and this is an
  -- inner join, so every grouped guest already has sparks or vibe > 0.
  order by 2 desc, 3 desc, 1;
$$;
revoke all on function public.room_board(text) from public;
grant execute on function public.room_board(text) to anon, authenticated;
