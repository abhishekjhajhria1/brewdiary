-- ============================================================================
-- brewdiary — pay-in-app dine-out, the VENUE half: menu → order → bill, and the
-- one careful seam where a night's drinks are *offered* to a guest's diary.
--
-- ── WHY THIS EXISTS, AND WHERE IT DELIBERATELY STOPS ─────────────────────────
-- A bar already runs a tab in this app (spend_events, 017) but only as a NUMBER —
-- staff type a figure, the board shows a band. That is enough to flex a room and
-- nothing else. To actually take payment we need the thing under the number: what
-- was ordered, at what price, for which table, and who at that table it was for.
--
-- The interesting part is the last one. Once a venue knows "these two Negronis
-- were Ada's", the app is one INSERT away from writing Ada's diary for her — and
-- that INSERT is the single most damaging thing this codebase could ever grow.
-- The diary is the product. A diary that fills itself from a till is a receipt.
--
-- So this migration draws the seam explicitly:
--
--   • the venue may record what it SERVED                  (orders / order_items)
--   • the venue may take money for it                      (bills)
--   • on close, the venue may OFFER the drink lines to the
--     guest as a pending suggestion                        (order_log_suggestions)
--   • the guest, and only the guest, turns that offer into
--     an entry — through the ordinary log path, in the app
--
--   ⚠ CRITICAL INVARIANT: there is NO policy, trigger, rpc, view or grant in this
--   file — or anywhere reachable from it — by which a venue, its staff, or any
--   definer function owned by this schema can INSERT INTO public.entries. Not for
--   convenience, not "just the drink lines", not behind a consent flag. If a future
--   migration adds one, it has broken the product, and `npm run db:audit` should be
--   taught to fail on it. Search this file for `entries`: the only occurrences are
--   in comments saying no.
--
-- ── the other rules this had to bend around ─────────────────────────────────
-- • Nothing rewards drinking more. There is no per-guest spend total here, no
--   "biggest tab" column, no ranking. `order_items.guest_user_id` exists to route
--   a *suggestion*, not to build a spender profile — and prompt 5's staff-facing
--   insight view has no user_id column at all, by construction.
-- • A guest can never write their own reward. Symmetrically, a guest can never
--   write their own ORDER: order/order_items/bills have no guest write policy,
--   only staff. A guest reads their own lines through my_order_lines() and that
--   is the whole of their access.
-- • No jurisdiction gate. Deliberate: perk_policy() guards PROMOTIONS (014/030/050).
--   Serving a drink someone paid for is not a promotion — gating a till on
--   allow_perks would stop a lawful bar in a no-promo country from taking money.
--   The gate here is `verified`, because an unverified venue is nobody's venue.
-- • Money is integer MINOR units (paise/cents), never a float, and always in the
--   VENUE's currency (022), server-set so a dashboard can't mislabel it.
-- • The repo-wide INSERT gotcha applies to EVERY table here: each one's SELECT
--   policy calls a SECURITY DEFINER helper (is_venue_staff / is_venue_manager),
--   which trips PostgREST on INSERT..RETURNING. src/lib/orders.ts must generate
--   ids client-side and insert WITHOUT .select(), reading back separately — the
--   same discipline parties.ts and expenses.ts already follow.
--
-- Runs on top of schema.sql + 002..050. Idempotent-ish.
-- Reuses: is_venue_staff(uuid,uuid), is_venue_manager(uuid,uuid) [010],
--         currency_for_country(text) [022].
--
-- ── DOWN-MIGRATION NOTES ────────────────────────────────────────────────────
--   drop function if exists public.my_order_lines(uuid) cascade;
--   drop function if exists public.order_items_snapshot() cascade;
--   drop function if exists public.orders_set_currency() cascade;
--   drop function if exists public.menu_items_set_currency() cascade;
--   drop function if exists public.bills_set_currency() cascade;
--   drop function if exists public.orders_guard() cascade;
--   drop function if exists public.order_log_suggestions_guard() cascade;
--   drop table if exists public.order_log_suggestions cascade;
--   drop table if exists public.bills        cascade;
--   drop table if exists public.order_items  cascade;
--   drop table if exists public.orders       cascade;
--   drop table if exists public.menu_items   cascade;
-- `venues.currency` is NOT dropped on the way down — 022 owns that column and
-- other features (perks, room_tabs) depend on it.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 0. venues.currency — 022 already added this. Re-asserted here so a fresh run
--    of 051 alone cannot produce a currency-less venue, and so the backfill is
--    idempotent. Same server-set mapping (currency_for_country), one source of
--    truth, so money.ts and the DB can never drift on what a bar's money is.
-- ────────────────────────────────────────────────────────────────────────────
alter table public.venues add column if not exists currency text not null default 'INR';
alter table public.venues drop constraint if exists venues_currency_check;
alter table public.venues
  add constraint venues_currency_check check (currency ~ '^[A-Z]{3}$');
update public.venues set currency = public.currency_for_country(country)
 where currency is distinct from public.currency_for_country(country);


-- ────────────────────────────────────────────────────────────────────────────
-- 1. menu_items — what the place sells.
--
-- `drink_key` is the bridge to src/lib/drinks.ts: the NORMALIZED canonical name
-- (lowercase, unaccented, punctuation-stripped — `normalize(canonical)`), so
-- "Negroni" on a menu and "negroni" in a diary are the same family. NULL means
-- this line is not a drink — food, a cover charge, a hookah — and food never
-- reaches a diary, which is why the column is nullable rather than defaulted.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.menu_items (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  name        text not null check (char_length(trim(name)) between 1 and 80),
  -- free-text section header as the venue thinks of it: "Cocktails", "Small plates".
  category    text check (category is null or char_length(category) <= 40),
  -- MINOR units (₹250.00 → 25000). Integer, never numeric/float: money that can
  -- hold 0.1 is money that can lose a paise in a split.
  price_minor int  not null check (price_minor >= 0),
  currency    text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  -- normalized canonical drink name (drinks.ts) when this item IS a drink; else NULL.
  drink_key   text check (drink_key is null or char_length(drink_key) between 1 and 60),
  active      boolean not null default true,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists menu_items_venue_idx
  on public.menu_items (venue_id, sort_order, name) where active;

-- currency follows the venue's, server-set (the 022 precedent).
create or replace function public.menu_items_set_currency()
returns trigger language plpgsql set search_path = public as $$
begin
  select v.currency into new.currency from public.venues v where v.id = new.venue_id;
  new.updated_at := now();
  return new;
end; $$;

drop trigger if exists menu_items_currency on public.menu_items;
create trigger menu_items_currency before insert or update on public.menu_items
  for each row execute function public.menu_items_set_currency();

alter table public.menu_items enable row level security;

-- READ: anyone who can see the venue. Mirrors venues_read (010) exactly rather
-- than restating it, so a menu can never be more visible than its venue.
drop policy if exists menu_items_read on public.menu_items;
create policy menu_items_read on public.menu_items for select to authenticated
  using (exists (
    select 1 from public.venues v
     where v.id = venue_id
       and (v.verified or v.created_by = auth.uid() or public.is_venue_staff(v.id, auth.uid()))
  ));

-- WRITE: manager/owner only. A bartender takes orders (below); they do not
-- reprice the whiskey mid-shift.
drop policy if exists menu_items_insert on public.menu_items;
create policy menu_items_insert on public.menu_items for insert to authenticated
  with check (public.is_venue_manager(venue_id, auth.uid()));

drop policy if exists menu_items_update on public.menu_items;
create policy menu_items_update on public.menu_items for update to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()))
  with check (public.is_venue_manager(venue_id, auth.uid()));

drop policy if exists menu_items_delete on public.menu_items;
create policy menu_items_delete on public.menu_items for delete to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()));


-- ────────────────────────────────────────────────────────────────────────────
-- 2. orders — a table, open, with things on it.
--
-- `party_id` is nullable on purpose: most orders are just a table. When a room
-- IS open (parties, 004) linking them is what lets the ticket offer the guests
-- actually present as attribution targets — but a walk-in table must work with
-- no social layer at all, or the till is hostage to the app's social features.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.orders (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  -- set null, not cascade: a closed bill outlives the room it was rung up in.
  party_id    uuid references public.parties(id) on delete set null,
  -- whatever the floor calls it: "12", "Bar 3", "Terrace". Not a seating model.
  table_label text check (table_label is null or char_length(trim(table_label)) <= 40),
  opened_by   uuid not null references public.profiles(id) on delete cascade,
  opened_at   timestamptz not null default now(),
  closed_at   timestamptz,
  status      text not null default 'open' check (status in ('open', 'closed', 'void')),
  currency    text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  updated_at  timestamptz not null default now()
);
create index if not exists orders_venue_open_idx
  on public.orders (venue_id, opened_at desc) where status = 'open';
create index if not exists orders_venue_idx  on public.orders (venue_id, opened_at desc);
create index if not exists orders_party_idx  on public.orders (party_id) where party_id is not null;

-- the guard: only a verified venue runs a till, and only its own staff open one.
-- No jurisdiction check — see the header. Serving is not promoting.
create or replace function public.orders_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare ver boolean;
begin
  select v.verified into ver from public.venues v where v.id = new.venue_id;
  if not coalesce(ver, false) then
    raise exception 'only a verified venue can take an order'
      using hint = 'Get the venue verified first (scripts/verify-venue.mjs).';
  end if;
  -- an order's room must belong to the same venue, or attribution would offer
  -- the wrong bar's guests.
  if new.party_id is not null and not exists (
       select 1 from public.parties p where p.id = new.party_id and p.venue_id = new.venue_id) then
    raise exception 'that room does not belong to this venue';
  end if;
  return new;
end; $$;

drop trigger if exists orders_check on public.orders;
create trigger orders_check before insert on public.orders
  for each row execute function public.orders_guard();

-- currency follows the venue's, server-set.
create or replace function public.orders_set_currency()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT' then
    select v.currency into new.currency from public.venues v where v.id = new.venue_id;
  else
    -- an open tab never changes what its money means
    new.currency := old.currency;
    -- stamp the moment it closed, once (OLD is only readable on UPDATE — reading
    -- it in the INSERT branch raises "record old is not assigned yet").
    if new.status = 'closed' and old.status <> 'closed' then
      new.closed_at := coalesce(new.closed_at, now());
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists orders_currency on public.orders;
create trigger orders_currency before insert or update on public.orders
  for each row execute function public.orders_set_currency();

alter table public.orders enable row level security;

-- Read+write is STAFF of the venue, any rung. Service is any-staff: a waiter
-- closes a tab in a restaurant, a bartender does at a bar (049).
-- A guest gets NO row-level read here — their door is my_order_lines() below.
drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()));

drop policy if exists orders_insert on public.orders;
create policy orders_insert on public.orders for insert to authenticated
  with check (public.is_venue_staff(venue_id, auth.uid()) and opened_by = auth.uid());

drop policy if exists orders_update on public.orders;
create policy orders_update on public.orders for update to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()))
  with check (public.is_venue_staff(venue_id, auth.uid()));

-- No DELETE policy: an order is voided, not erased. A till you can delete from
-- is a till you can steal from, and 'void' keeps the record.


-- ────────────────────────────────────────────────────────────────────────────
-- 3. order_items — the lines.
--
-- `guest_user_id` is the attribution: who this line is FOR. NULLABLE BY DESIGN
-- and expected to be null most of the time — attribution is a courtesy that
-- makes a later suggestion possible, never a requirement for taking money. The
-- UI must present it that way (prompt 3) and the schema must not fight it.
--
-- name/price/drink_key are SNAPSHOTTED from the menu item at insert time, and
-- menu_item_id is `on delete set null`. A bar reprices its cocktails every
-- season; last month's bill must still say what it said. The snapshot is also
-- what makes drinkLinesFor() a pure function over order_items with no join.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders(id) on delete cascade,
  menu_item_id     uuid references public.menu_items(id) on delete set null,
  qty              int  not null default 1 check (qty > 0 and qty <= 99),
  unit_price_minor int  not null check (unit_price_minor >= 0),
  -- snapshots (server-set from the menu item; see above)
  name_snapshot    text not null,
  drink_key        text,
  -- who this line is for. NULL = unattributed, and that is a perfectly good bill.
  guest_user_id    uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now()
);
create index if not exists order_items_order_idx on public.order_items (order_id);
create index if not exists order_items_guest_idx
  on public.order_items (guest_user_id) where guest_user_id is not null;

create or replace function public.order_items_snapshot()
returns trigger language plpgsql security definer set search_path = public as $$
declare mi record; ord record;
begin
  select * into ord from public.orders o where o.id = new.order_id;
  if ord.id is null then raise exception 'no such order'; end if;
  if tg_op = 'INSERT' and ord.status <> 'open' then
    raise exception 'that order is already %', ord.status;
  end if;

  if new.menu_item_id is not null then
    select * into mi from public.menu_items m where m.id = new.menu_item_id;
    if mi.id is null then raise exception 'no such menu item'; end if;
    if mi.venue_id <> ord.venue_id then
      raise exception 'that item is not on this venue''s menu';
    end if;
    -- price and name come from the MENU, not the browser: a client-supplied
    -- price is a client-supplied discount.
    if tg_op = 'INSERT' then
      new.unit_price_minor := mi.price_minor;
      new.name_snapshot    := mi.name;
      new.drink_key        := mi.drink_key;
    end if;
  elsif tg_op = 'INSERT' and coalesce(trim(new.name_snapshot), '') = '' then
    -- an off-menu line (staff typed it) must at least say what it was.
    raise exception 'an off-menu line needs a name';
  end if;
  return new;
end; $$;

drop trigger if exists order_items_snap on public.order_items;
create trigger order_items_snap before insert or update on public.order_items
  for each row execute function public.order_items_snapshot();

alter table public.order_items enable row level security;

-- Staff of the order's venue. Same any-rung service rule as orders.
drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o
                  where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid())));

drop policy if exists order_items_insert on public.order_items;
create policy order_items_insert on public.order_items for insert to authenticated
  with check (exists (select 1 from public.orders o
                       where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid())));

drop policy if exists order_items_update on public.order_items;
create policy order_items_update on public.order_items for update to authenticated
  using (exists (select 1 from public.orders o
                  where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid())))
  with check (exists (select 1 from public.orders o
                       where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid())));

-- A line CAN be removed while the order is open (someone changed their mind).
drop policy if exists order_items_delete on public.order_items;
create policy order_items_delete on public.order_items for delete to authenticated
  using (exists (select 1 from public.orders o
                  where o.id = order_id and o.status = 'open'
                    and public.is_venue_staff(o.venue_id, auth.uid())));


-- ────────────────────────────────────────────────────────────────────────────
-- 4. bills — the money.
--
-- One bill per order (unique), because a split is a payment concern, not a
-- second bill; splitEvenly() lives in src/lib/orders.ts and divides THIS total.
--
-- `status` is flipped to 'paid' ONLY by the payment webhook, through a definer
-- function that will land with the payments migration. There is deliberately no
-- client path that sets 'paid': a browser-trusted paid flag is a free-drinks bug.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.bills (
  id             uuid primary key default gen_random_uuid(),
  order_id       uuid not null unique references public.orders(id) on delete cascade,
  subtotal_minor int  not null default 0 check (subtotal_minor >= 0),
  tax_minor      int  not null default 0 check (tax_minor      >= 0),
  tip_minor      int  not null default 0 check (tip_minor      >= 0),
  total_minor    int  not null default 0 check (total_minor    >= 0),
  currency       text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  status         text not null default 'unpaid'
                   check (status in ('unpaid', 'paid', 'refunded')),
  paid_at        timestamptz,
  payment_ref    text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- the arithmetic is an invariant, not a hope. A tampered client total that
  -- doesn't add up cannot even be stored.
  constraint bills_totals_add_up
    check (total_minor = subtotal_minor + tax_minor + tip_minor)
);
create index if not exists bills_unpaid_idx on public.bills (created_at desc) where status = 'unpaid';

create or replace function public.bills_set_currency()
returns trigger language plpgsql set search_path = public as $$
begin
  select o.currency into new.currency from public.orders o where o.id = new.order_id;
  new.updated_at := now();
  return new;
end; $$;

drop trigger if exists bills_currency on public.bills;
create trigger bills_currency before insert or update on public.bills
  for each row execute function public.bills_set_currency();

alter table public.bills enable row level security;

drop policy if exists bills_read on public.bills;
create policy bills_read on public.bills for select to authenticated
  using (exists (select 1 from public.orders o
                  where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid())));

drop policy if exists bills_insert on public.bills;
create policy bills_insert on public.bills for insert to authenticated
  with check (
    status = 'unpaid'                       -- staff raise a bill; they never mark it paid
    and exists (select 1 from public.orders o
                 where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid()))
  );

-- Staff may amend an UNPAID bill (a tip was added, a line was struck) but may
-- never move it to paid/refunded from the client: `with check (status='unpaid')`
-- means every settlement path is the webhook's definer fn, and only that.
drop policy if exists bills_update on public.bills;
create policy bills_update on public.bills for update to authenticated
  using (
    status = 'unpaid'
    and exists (select 1 from public.orders o
                 where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid()))
  )
  with check (
    status = 'unpaid'
    and exists (select 1 from public.orders o
                 where o.id = order_id and public.is_venue_staff(o.venue_id, auth.uid()))
  );

-- No DELETE policy. A settled bill is a record.


-- ────────────────────────────────────────────────────────────────────────────
-- 5. order_log_suggestions — THE SEAM.
--
-- This row is an OFFER, and that is the whole of its power. It says: "the bar
-- believes you had these drinks; would you like them in your diary?" It cannot
-- write the diary. It cannot nag. It cannot report back.
--
-- `items` is drinks ONLY — [{drink_key, name, qty}] — assembled by
-- drinkLinesFor() in src/lib/orders.ts. Food is dropped at the source. Price is
-- NOT carried: a diary entry has never had a price field and is not getting one.
--
-- ⚠ WHO MAY READ THE STATUS: the subject. Only the subject. There is no staff
-- SELECT policy on this table and there must never be one. A bar that can see
-- "Ada was offered her Negronis and said no" has been handed exactly the
-- surveillance this product refuses. The venue's view of this data is an
-- aggregate count with no user_id column at all (prompt 5 / the insights view) —
-- and the protection is that SQL shape, not the UI's restraint.
--
-- ⚠ WHO MAY WRITE ONE: nobody, from the client. There is no INSERT policy. Rows
-- arrive only via the SECURITY DEFINER rpc suggest_order_log(order_id), which
-- lands with the emit migration. Until then this table is inert by design.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.order_log_suggestions (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references public.orders(id) on delete cascade,
  subject_user_id uuid not null references public.profiles(id) on delete cascade,
  venue_id        uuid not null references public.venues(id) on delete cascade,
  -- the calendar day the entry would be FOR (the venue's night, not UTC's).
  date            date not null,
  -- [{drink_key, name, qty}], drinks only. jsonb array, enforced.
  items           jsonb not null default '[]'::jsonb
                    check (jsonb_typeof(items) = 'array'),
  status          text not null default 'pending'
                    check (status in ('pending', 'accepted', 'dismissed')),
  created_at      timestamptz not null default now(),
  responded_at    timestamptz,
  -- a re-fire (bill reopened, webhook replayed) is a harmless no-op.
  unique (order_id, subject_user_id)
);
create index if not exists order_log_suggestions_subject_idx
  on public.order_log_suggestions (subject_user_id, created_at desc) where status = 'pending';
-- supports the 7-day expiry sweep that lands with the emit migration.
create index if not exists order_log_suggestions_stale_idx
  on public.order_log_suggestions (created_at) where status = 'pending';

-- The subject may answer, and answering is ALL they may do. RLS's USING clause
-- pins the old row to 'pending' and WITH CHECK pins the new one to an answer;
-- this trigger pins everything else, so a hand-rolled PATCH can't rewrite the
-- items into something the bar never served (or move the row to another user).
create or replace function public.order_log_suggestions_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.order_id        is distinct from old.order_id
  or new.subject_user_id is distinct from old.subject_user_id
  or new.venue_id        is distinct from old.venue_id
  or new.date            is distinct from old.date
  or new.items           is distinct from old.items
  or new.created_at      is distinct from old.created_at then
    raise exception 'only the status of a suggestion can change';
  end if;
  new.responded_at := now();
  return new;
end; $$;

drop trigger if exists order_log_suggestions_immutable on public.order_log_suggestions;
create trigger order_log_suggestions_immutable before update on public.order_log_suggestions
  for each row execute function public.order_log_suggestions_guard();

alter table public.order_log_suggestions enable row level security;

-- READ: the subject alone. (No staff policy — see the warning above.)
drop policy if exists order_log_suggestions_read on public.order_log_suggestions;
create policy order_log_suggestions_read on public.order_log_suggestions for select to authenticated
  using (subject_user_id = auth.uid());

-- UPDATE: the subject, pending → accepted | dismissed, once.
drop policy if exists order_log_suggestions_answer on public.order_log_suggestions;
create policy order_log_suggestions_answer on public.order_log_suggestions for update to authenticated
  using  (subject_user_id = auth.uid() and status = 'pending')
  with check (subject_user_id = auth.uid() and status in ('accepted', 'dismissed'));

-- No INSERT policy (definer rpc only). No DELETE policy: dismissing is the
-- answer, and a dismissed row is what stops the same order asking twice.


-- ────────────────────────────────────────────────────────────────────────────
-- 6. my_order_lines() — a guest's one window onto a bill.
--
-- The guest gets no row-level read on orders/order_items, because a table read
-- scoped to "my lines" still leaks the shape of everyone else's. This definer
-- function returns ONLY the lines attributed to the caller, and no totals for
-- the table — you can see what was rung up as yours, not what the party spent.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.my_order_lines(uuid) cascade;

create or replace function public.my_order_lines(oid uuid)
returns table (
  id               uuid,
  name             text,
  drink_key        text,
  qty              int,
  unit_price_minor int,
  currency         text
)
language sql stable security definer set search_path = public as $$
  select oi.id, oi.name_snapshot, oi.drink_key, oi.qty, oi.unit_price_minor, o.currency
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.id = oid
    and auth.uid() is not null
    and oi.guest_user_id = auth.uid()
  order by oi.created_at;
$$;
revoke all on function public.my_order_lines(uuid) from public;
grant execute on function public.my_order_lines(uuid) to authenticated;
