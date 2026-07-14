-- ============================================================================
-- brewdiary — "Venues" (Phase 7: the bar/venue side, served on bar.bwdy.site;
-- the middleware rewrites the `bar.` subdomain onto /venue).
--
-- A VENUE is owned by a profile (created_by) and staffed by profiles via
-- VENUE_STAFF (owner / manager / bartender). `verified` is OUR gate: a venue
-- must be verified before it can issue real-world perks or vibe (enforced when
-- those land). It is admin-only — a trigger blocks any signed-in user from
-- flipping `verified` (or transferring ownership); only the service role (no
-- auth.uid()) can, which is how WE verify a venue.
--
-- RLS gotchas honored (same as circles):
--  * venue_staff policies must not reference venue_staff directly (recursion) →
--    is_venue_staff()/is_venue_manager() are SECURITY DEFINER.
--  * venues_read calls a definer fn → app inserts avoid INSERT..RETURNING
--    (client-gen id, no .select(); read back separately).
-- Runs on top of schema.sql + 002..009. Idempotent-ish.
-- ============================================================================

-- (no standalone `drop trigger` — DROP TRIGGER IF EXISTS still needs the table to
-- exist, which breaks a fresh run; `drop table … cascade` removes the trigger.)
drop table     if exists public.venue_staff cascade;
drop table     if exists public.venues      cascade;
drop function  if exists public.is_venue_staff(uuid, uuid)       cascade;
drop function  if exists public.is_venue_manager(uuid, uuid)     cascade;
drop function  if exists public.venues_guard_admin_fields()      cascade;

create table public.venues (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(trim(name)) between 1 and 80),
  -- web-safe handle → bar.bwdy.site uses it; 2..40 chars, starts/ends alnum.
  slug       text unique not null check (slug ~ '^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])$'),
  created_by uuid not null references public.profiles(id) on delete cascade,
  city       text,
  verified   boolean not null default false,
  created_at timestamptz not null default now()
);
create index venues_creator_idx on public.venues (created_by);

create table public.venue_staff (
  venue_id uuid not null references public.venues(id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  role     text not null default 'bartender' check (role in ('owner', 'manager', 'bartender')),
  added_at timestamptz not null default now(),
  primary key (venue_id, user_id)
);
create index venue_staff_user_idx on public.venue_staff (user_id);

-- definer helpers so venue_staff policies don't recurse on themselves
create or replace function public.is_venue_staff(vid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.venue_staff s where s.venue_id = vid and s.user_id = uid);
$$;

create or replace function public.is_venue_manager(vid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.venue_staff s
                 where s.venue_id = vid and s.user_id = uid and s.role in ('owner', 'manager'))
      or exists (select 1 from public.venues v where v.id = vid and v.created_by = uid);
$$;

-- `verified` and ownership are managed by brewdiary, never self-served. A change
-- to either from a signed-in session (auth.uid() present) is refused; the service
-- role (auth.uid() null) may set them.
create or replace function public.venues_guard_admin_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.verified is distinct from old.verified
      or new.created_by is distinct from old.created_by)
     and auth.uid() is not null then
    raise exception 'verified/ownership are set by brewdiary, not the venue';
  end if;
  return new;
end; $$;
create trigger venues_protect_admin_fields before update on public.venues
  for each row execute function public.venues_guard_admin_fields();

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.venues      enable row level security;
alter table public.venue_staff enable row level security;

-- venues: your team sees theirs; a VERIFIED venue is readable by any signed-in
-- user (public pages / room join / kiosk later). You create your OWN, never
-- pre-verified. Owner or a manager edits; only the creator deletes.
create policy venues_read on public.venues for select to authenticated
  using (verified or created_by = auth.uid() or public.is_venue_staff(id, auth.uid()));
create policy venues_insert on public.venues for insert to authenticated
  with check (created_by = auth.uid() and verified = false);
create policy venues_update on public.venues for update to authenticated
  using (created_by = auth.uid() or public.is_venue_manager(id, auth.uid()));
create policy venues_delete on public.venues for delete to authenticated
  using (created_by = auth.uid());

-- staff: the team sees the roster. You add YOURSELF as owner to a venue you
-- created; a manager adds anyone else. You can leave; a manager can remove staff.
create policy venue_staff_read on public.venue_staff for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()));
create policy venue_staff_insert on public.venue_staff for insert to authenticated
  with check (
    (user_id = auth.uid()
      and exists (select 1 from public.venues v where v.id = venue_id and v.created_by = auth.uid()))
    or public.is_venue_manager(venue_id, auth.uid())
  );
create policy venue_staff_delete on public.venue_staff for delete to authenticated
  using (user_id = auth.uid() or public.is_venue_manager(venue_id, auth.uid()));
