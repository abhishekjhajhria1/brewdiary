-- ============================================================================
-- brewdiary — MENUS, opened by tapping the table.
--
-- A venue keeps its menu here; a guest opens it by tapping an NFC tag (or
-- scanning the QR) on the table. The tag holds a plain URL, bwdy.site/m/<slug>:
-- with the app installed the phone opens the menu in the app, without it the
-- website shows the same menu. No app-specific tag format, no extra hardware
-- beyond a ₹20 sticker.
--
-- ── THE LINES THIS FEATURE KEEPS ─────────────────────────────────────────────
-- 1. A MENU IS NOT AN OFFER. It is the paper menu on the table, read by someone
--    already sitting there. So it carries a name, a section, a description and
--    a price — and nothing else: no discount, no "happy hour", no "today only".
--    There is no column for one and there must never be (docs/11 rule #6).
-- 2. IT IS REACHED FROM THE TABLE, NEVER FROM DISCOVER. discover_venues() (027)
--    lists the bar, never the offer; a price list in the browse view would turn a
--    directory into alcohol advertising. venue_menu() takes a slug you only get
--    from the tag / QR in the room, and discover_venues() must not join this
--    table (db:audit checks both).
-- 3. NO DIARY EVER REACHES A VENUE. Opening a menu tells the venue nothing: the
--    read is anonymous-capable, logs nothing, and "you'd probably like" is worked
--    out ON THE PHONE from the diary. The venue never learns who looked.
-- 4. VERIFIED VENUES ONLY. An unverified venue can draft its menu, but only a
--    verified one is served — a fake "bar" can't publish a menu in our name.
--
-- Writes: the venue's owner/managers (is_venue_manager). Staff can read the draft.
-- Runs on top of 002..041. Idempotent-ish.
-- ============================================================================

create table if not exists public.venue_menu_items (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  section     text not null default 'Drinks' check (char_length(trim(section)) between 1 and 40),
  name        text not null check (char_length(trim(name)) between 1 and 80),
  description text check (description is null or char_length(description) <= 240),
  price       numeric(10, 2) check (price is null or (price >= 0 and price < 10000000)),
  -- Same vocabulary as the diary's DrinkType (plus 'food'), so "you'd probably
  -- like" can match on the phone. 'none' (a dry day) makes no sense on a menu.
  kind        text check (kind is null or kind in ('coffee','tea','beer','wine','cocktail','spirit','soft','food','other')),
  no_alcohol  boolean not null default false,
  available   boolean not null default true,
  position    int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists venue_menu_items_venue_idx on public.venue_menu_items (venue_id, position);

-- A menu, not a catalogue: 400 items is more than any bar prints.
create or replace function public.venue_menu_items_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.venue_menu_items where venue_id = new.venue_id) >= 400 then
    raise exception 'a menu holds at most 400 items';
  end if;
  return new;
end; $$;
drop trigger if exists venue_menu_items_cap on public.venue_menu_items;
create trigger venue_menu_items_cap before insert on public.venue_menu_items
  for each row execute function public.venue_menu_items_cap();

alter table public.venue_menu_items enable row level security;

-- The team sees the draft; owners/managers edit it. Guests read through venue_menu().
drop policy if exists venue_menu_read on public.venue_menu_items;
create policy venue_menu_read on public.venue_menu_items for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()) or public.is_venue_manager(venue_id, auth.uid()));
drop policy if exists venue_menu_insert on public.venue_menu_items;
create policy venue_menu_insert on public.venue_menu_items for insert to authenticated
  with check (public.is_venue_manager(venue_id, auth.uid()));
drop policy if exists venue_menu_update on public.venue_menu_items;
create policy venue_menu_update on public.venue_menu_items for update to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()))
  with check (public.is_venue_manager(venue_id, auth.uid()));
drop policy if exists venue_menu_delete on public.venue_menu_items;
create policy venue_menu_delete on public.venue_menu_items for delete to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()));

-- The guest's read: one verified venue's available items, by the slug on the tag.
-- Returns one row per item; the venue fields repeat (a menu with no items yet
-- returns a single row with a null item_id, so the page can still say whose it is).
-- Anonymous-capable on purpose (the website serves people without the app), and it
-- records nothing about who asked.
drop function if exists public.venue_menu(text) cascade;
create or replace function public.venue_menu(in_slug text)
returns table (
  venue_name  text,
  venue_city  text,
  venue_kind  text,
  currency    text,
  item_id     uuid,
  section     text,
  name        text,
  description text,
  price       numeric,
  kind        text,
  no_alcohol  boolean
)
language sql stable security definer set search_path = public as $$
  select v.name, v.city, v.kind, v.currency,
         i.id, i.section, i.name, i.description, i.price, i.kind, i.no_alcohol
    from public.venues v
    left join public.venue_menu_items i on i.venue_id = v.id and i.available
   where v.slug = lower(in_slug) and v.verified
   order by i.position, i.section, i.name;
$$;
revoke all on function public.venue_menu(text) from public;
grant execute on function public.venue_menu(text) to anon, authenticated;
