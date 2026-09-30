-- ============================================================================
-- brewdiary — THE DOOR: how many are inside, against the licensed capacity.
--
-- Clubs and busy bars count people in and out at the door; the law (and the fire
-- officer) sets how many may be inside. This is that clicker, shared by everyone on
-- the door, derived from a ledger of taps.
--
--   • COUNTS, NEVER PEOPLE. A tap is +1 or −1 (a group up to ±12). No name, no face,
--     no ID, no guest link — nothing here can say who came in.
--   • DERIVED, NEVER STORED. "Inside now" is the sum of tonight's taps (never below 0);
--     "came in" is the sum of the ins. Nothing caches a count.
--   • THE CAPACITY IS THE VENUE'S. A manager sets it; the door screen turns red at it.
--     The count records what happened even past it — a clicker that refuses to count
--     someone who is already inside is a wrong clicker — and the screen says to hold
--     the door.
--
-- Runs on top of 002..051.
-- ============================================================================

alter table public.venues add column if not exists capacity int;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'venues_capacity_check') then
    alter table public.venues add constraint venues_capacity_check check (capacity is null or capacity between 1 and 20000);
  end if;
end $$;

create table if not exists public.door_events (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  delta      int not null check (delta between -12 and 12 and delta <> 0),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists door_events_venue_idx on public.door_events (venue_id, created_at);
alter table public.door_events enable row level security;
drop policy if exists door_events_read on public.door_events;
create policy door_events_read on public.door_events for select to authenticated using (public.venue_can(venue_id, auth.uid(), 'floor.view'));
-- No write policy: door_tick() only.

create or replace function public.door_tick(vid uuid, n int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.venue_can(vid, auth.uid(), 'guests.seat') then
    raise exception 'your role doesn''t work the door here' using errcode = '42501';
  end if;
  if n is null or n = 0 or n < -12 or n > 12 then raise exception 'count 1 to 12 at a time'; end if;
  insert into public.door_events (venue_id, delta, created_by) values (vid, n, auth.uid());
end; $$;

-- Tonight at the door, since the venue's day started (the app sends local midnight;
-- a night that runs past midnight is counted from the evening before, up to 30 hours).
create or replace function public.door_count(vid uuid, day_start timestamptz default null)
returns table (inside int, came_in int, capacity int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  since timestamptz := coalesce(day_start, date_trunc('day', now()));
begin
  if not public.venue_can(vid, auth.uid(), 'floor.view') then
    raise exception 'your role doesn''t see the door' using errcode = '42501';
  end if;
  if since < now() - interval '30 hours' then since := now() - interval '30 hours'; end if;
  return query
  select greatest(0, coalesce(sum(e.delta), 0))::int,
         coalesce(sum(e.delta) filter (where e.delta > 0), 0)::int,
         (select v.capacity from public.venues v where v.id = vid)
    from public.door_events e
   where e.venue_id = vid and e.created_at >= since;
end; $$;

revoke all on function public.door_tick(uuid, int) from public;
revoke all on function public.door_count(uuid, timestamptz) from public;
grant execute on function public.door_tick(uuid, int) to authenticated;
grant execute on function public.door_count(uuid, timestamptz) to authenticated;
