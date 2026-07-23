-- ============================================================================
-- brewdiary — "Dineout": public dining offers + table reservations.
--
-- ── WHAT THIS ADDS, AND WHY IT'S THE ONE PLACE WE SHOW AN OFFER ──────────────
-- Until now, rule #6 was absolute: Discover lists a bar's NAME and CITY (a
-- directory entry, like Google Maps) but NEVER its offer, because a venue's
-- ALCOHOL offer ("free pour at Toit tonight!") is surrogate alcohol advertising —
-- specifically illegal in India (surrogate-ad rules, CCPA, ₹50 lakh), and banned
-- outright in Thailand, Norway, Lithuania, Türkiye and Poland. See 027 / 030.
--
-- Zomato Dineout, EazyDiner and the like operate lawfully in India while showing
-- deals, because what they advertise is a DINING offer — "Flat 20% off the total
-- bill", a set menu, an experience — never the alcohol itself. That distinction is
-- the whole feature. So we carve a NARROW, DELIBERATE exception to rule #6:
--
--   • A DINING offer (percent off the bill / a flat deal / a set menu / an
--     experience) MAY be shown publicly in Discover and booked against. It is not
--     an alcohol promotion, so it is not surrogate advertising.
--   • An ALCOHOL offer (a free or discounted drink) is UNCHANGED: it stays the
--     private venue_perks loyalty card — earned after you're there, staff-recorded,
--     NEVER advertised. There is deliberately no alcohol field on dining_offers.
--   • An OFF-LICENCE (kind='store') gets NO dining offer at all. At a bottle shop a
--     discount off "the bill" IS a discount on alcohol — the exact thing we refuse.
--   • Only VERIFIED bars, and only where the bar layer is lawful at all
--     (jurisdiction_policy.allow_perks). Deny by default, like everything else.
--
-- A reservation is a table booking — plainly not advertising — so it has no such
-- constraint beyond "a real, verified place you can sit down in" (bars, not shops).
--
-- Runs on top of schema.sql + 002..049. Idempotent-ish.
-- Reuses: is_venue_manager(uuid,uuid), is_venue_staff(uuid,uuid),
--         perk_policy(text,text) — all from 014 / 015 / 030.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 1. dining_offers — the public, advertisable, NON-alcohol deal.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.dining_offers (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  -- what the guest reads, e.g. "Flat 20% off the total bill" / "Chef's tasting menu".
  title       text not null check (char_length(trim(title)) between 1 and 120),
  -- optional fine print, e.g. "Mon–Thu, dine-in, table of 2+".
  detail      text check (detail is null or char_length(detail) <= 240),
  -- the SHAPE of the deal. All four are non-alcohol by construction; there is NO
  -- "free drink" kind, on purpose — that lives in venue_perks and is never public.
  kind        text not null default 'percent_off'
                check (kind in ('percent_off', 'flat_deal', 'set_menu', 'experience')),
  -- only meaningful for percent_off; 1..100.
  percent_off int check (percent_off is null or percent_off between 1 and 100),
  active      boolean not null default true,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists dining_offers_venue_idx
  on public.dining_offers (venue_id) where active;

-- ── the guard: the legal line, in the DB, not the UI ─────────────────────────
-- Mirrors venue_perks_guard (030). No row / not allowed = the offer cannot exist.
create or replace function public.dining_offer_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare c text; r text; k text; ver boolean; pol record;
begin
  select v.country, coalesce(v.region, ''), v.kind, v.verified
    into c, r, k, ver
    from public.venues v where v.id = new.venue_id;

  -- An off-licence never gets a "dining" offer: a discount off a shop's bill is a
  -- discount on alcohol, which is exactly the promotion we refuse everywhere.
  if k = 'store' then
    raise exception 'a dining offer is not available for an off-licence'
      using hint = 'At a bottle shop a bill discount is an alcohol discount. Bars can run one.';
  end if;

  -- Only a verified venue is anybody's recommendation — and only it can be booked.
  if not coalesce(ver, false) then
    raise exception 'only a verified venue can publish a dining offer';
  end if;

  select * into pol from public.perk_policy(c, r);
  -- Silence means no: an unresearched or offer-banning jurisdiction returns no row.
  if pol is null or pol.allow_perks is null or not pol.allow_perks then
    raise exception 'dining offers are not permitted for a venue in % %', c, r
      using hint = 'Either the law there restricts it, or we have not researched that jurisdiction yet.';
  end if;

  return new;
end; $$;

drop trigger if exists dining_offer_policy on public.dining_offers;
create trigger dining_offer_policy before insert or update on public.dining_offers
  for each row execute function public.dining_offer_guard();

-- If a venue flips to a store, loses verification or moves country, its offers must
-- be re-validated — the same self-defence venues_recheck_perks (030) gives perks.
create or replace function public.venues_recheck_offers()
returns trigger language plpgsql security definer set search_path = public as $$
declare o record;
begin
  -- A store / unverified venue can hold no offer at all: drop them rather than
  -- re-fire the guard (which would raise and abort the venue update).
  if new.kind = 'store' or not coalesce(new.verified, false) then
    delete from public.dining_offers where venue_id = new.id;
  else
    for o in select id from public.dining_offers where venue_id = new.id loop
      update public.dining_offers set updated_at = now() where id = o.id;  -- re-fires the guard
    end loop;
  end if;
  return new;
end; $$;

drop trigger if exists venues_recheck_offers on public.venues;
create trigger venues_recheck_offers after update of kind, country, region, verified on public.venues
  for each row execute function public.venues_recheck_offers();

-- ── RLS: managers of a verified venue write; the public reads via discover_offers ──
alter table public.dining_offers enable row level security;

-- Direct table read is the venue's own staff (the dashboard editor + the bookings
-- view, which shows which offer a table booked against). Guests never read this
-- table — they see offers through discover_offers(), which is the one gate that
-- decides what's lawful to show. An offer is public anyway, so staff-wide read of
-- their OWN venue's offers leaks nothing; managers alone may WRITE (below).
drop policy if exists dining_offers_read on public.dining_offers;
create policy dining_offers_read on public.dining_offers for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()));

drop policy if exists dining_offers_insert on public.dining_offers;
create policy dining_offers_insert on public.dining_offers for insert to authenticated
  with check (
    public.is_venue_manager(venue_id, auth.uid())
    and exists (select 1 from public.venues v where v.id = venue_id and v.verified)
  );

drop policy if exists dining_offers_update on public.dining_offers;
create policy dining_offers_update on public.dining_offers for update to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()))
  with check (public.is_venue_manager(venue_id, auth.uid()));

drop policy if exists dining_offers_delete on public.dining_offers;
create policy dining_offers_delete on public.dining_offers for delete to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()));


-- ────────────────────────────────────────────────────────────────────────────
-- 2. reservations — a guest asks for a table; the venue confirms it.
--
-- Shaped like a plan's join request, not a live floor map: a guest can only ever
-- create a 'requested' row for THEMSELVES, and only staff move it forward. That is
-- the same discipline as spend/perks — a guest can't self-confirm anything.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.reservations (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  -- the dining offer this booking is against, if any. set null (not cascade) so a
  -- booking survives the venue retiring the offer — a record of what was promised.
  offer_id    uuid references public.dining_offers(id) on delete set null,
  -- if the booking came from a Together plan, so the two stay linked.
  plan_id     uuid references public.plans(id) on delete set null,
  res_date    date not null,
  res_time    time,
  party_size  int  not null check (party_size between 1 and 50),
  note        text check (note is null or char_length(note) <= 240),
  status      text not null default 'requested'
                check (status in ('requested','confirmed','declined','cancelled','seated','no_show')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists reservations_user_idx  on public.reservations (user_id, res_date desc);
create index if not exists reservations_venue_idx on public.reservations (venue_id, res_date desc);

-- ── the guard: you can only book a real, sit-down, verified place, in the future ──
create or replace function public.reservations_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare k text; ver boolean;
begin
  select v.kind, v.verified into k, ver from public.venues v where v.id = new.venue_id;
  if k = 'store' then
    raise exception 'you can''t reserve a table at an off-licence'
      using hint = 'A bottle shop has no tables to book.';
  end if;
  if not coalesce(ver, false) then
    raise exception 'you can only book a table at a verified venue';
  end if;
  if new.res_date < current_date then
    raise exception 'a booking can''t be in the past';
  end if;
  return new;
end; $$;

drop trigger if exists reservations_check on public.reservations;
create trigger reservations_check before insert or update on public.reservations
  for each row execute function public.reservations_guard();

-- ── RLS: guest sees/creates their own; staff see their venue's; moves go via rpc ──
alter table public.reservations enable row level security;

drop policy if exists reservations_read on public.reservations;
create policy reservations_read on public.reservations for select to authenticated
  using (user_id = auth.uid() or public.is_venue_staff(venue_id, auth.uid()));

-- A guest may only ever request, and only for themselves. No self-confirm.
drop policy if exists reservations_insert on public.reservations;
create policy reservations_insert on public.reservations for insert to authenticated
  with check (user_id = auth.uid() and status = 'requested');

-- No UPDATE / DELETE policy on purpose. Every status move goes through
-- set_reservation_status() below, which decides who may make which move.

-- The one door for moving a booking forward or calling it off.
--   • the guest may cancel their own,
--   • the venue's staff may confirm / decline / seat / mark no_show.
-- A guest can never confirm their own table, exactly like they can never punch
-- their own card.
create or replace function public.set_reservation_status(rid uuid, new_status text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); row public.reservations;
begin
  if me is null then raise exception 'not signed in'; end if;
  if new_status not in ('confirmed','declined','cancelled','seated','no_show') then
    raise exception 'unknown status %', new_status;
  end if;

  select * into row from public.reservations where id = rid;
  if row.id is null then raise exception 'no such booking'; end if;

  if new_status = 'cancelled' then
    -- a guest cancels their own; staff may also cancel on a guest's behalf.
    if me <> row.user_id and not public.is_venue_staff(row.venue_id, me) then
      raise exception 'not allowed to cancel this booking';
    end if;
  else
    -- confirm / decline / seat / no_show are the venue's calls only.
    if not public.is_venue_staff(row.venue_id, me) then
      raise exception 'only this venue''s staff can update a booking';
    end if;
  end if;

  update public.reservations set status = new_status, updated_at = now() where id = rid;
  return true;
end; $$;
revoke all on function public.set_reservation_status(uuid, text) from public;
grant execute on function public.set_reservation_status(uuid, text) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 3. discover_offers() — the ONE place a bar's offer is shown to a guest.
--
-- This is the join discover_venues() deliberately refuses (venue_perks). It is
-- lawful ONLY because dining_offers carries a DINING deal, never alcohol, and only
-- for verified bars where the bar layer is legal. If you are ever tempted to join
-- venue_perks here to "also show the loyalty reward" — that is the line, and it is
-- illegal in India. Don't.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.discover_offers(text, int) cascade;

create or replace function public.discover_offers(in_country text default null, lim int default 40)
returns table (
  venue_id    uuid,
  name        text,
  slug        text,
  city        text,
  country     text,
  offer_id    uuid,
  title       text,
  detail      text,
  kind        text,
  percent_off int
)
language sql stable security definer set search_path = public as $$
  select v.id, v.name, v.slug, v.city, v.country,
         o.id, o.title, o.detail, o.kind, o.percent_off
  from public.dining_offers o
  join public.venues v on v.id = o.venue_id
  join public.jurisdiction_policy jp
    on jp.country = v.country and jp.region = ''
  where o.active
    and v.verified
    and v.kind = 'bar'                     -- never a bottle shop (see the guard)
    and jp.allow_perks                     -- the bar layer is lawful here at all
    and (in_country is null or v.country = upper(in_country))
  order by v.name, o.title
  limit greatest(least(coalesce(lim, 40), 100), 1);
$$;
revoke all on function public.discover_offers(text, int) from public;
grant execute on function public.discover_offers(text, int) to anon, authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 4. venue_directory() — verified venues a guest can attach to a plan or book.
--
-- Returns the venue's id (needed to create a reservation / attach to a plan) plus
-- its directory facts. NOT an offer — this is the same directory data discover_venues
-- already exposes, just keyed by id and searchable, for the plan venue-picker and to
-- resolve an attached venue's name for display.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.venue_directory(text) cascade;

create or replace function public.venue_directory(q text default null)
returns table (id uuid, name text, slug text, city text, kind text, country text)
language sql stable security definer set search_path = public as $$
  select v.id, v.name, v.slug, v.city, v.kind, v.country
  from public.venues v
  join public.jurisdiction_policy jp
    on jp.country = v.country and jp.region = ''
  where v.verified
    and jp.allow_perks
    and (
      q is null
      or v.name ilike '%' || q || '%'
      or v.slug ilike '%' || q || '%'
      or coalesce(v.city, '') ilike '%' || q || '%'
    )
  order by v.name
  limit 100;
$$;
revoke all on function public.venue_directory(text) from public;
grant execute on function public.venue_directory(text) to authenticated;
