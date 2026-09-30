-- ============================================================================
-- brewdiary — THE COUNTER: products, stock, sales, and the liquor-store rules.
--
-- Every counter (a liquor store, a sweet shop, a bakery, any shop — 047) can now run
-- its till here: a product list with prices, stock that follows every sale, delivery
-- and adjustment, suppliers, and — for a liquor store — the rules the law puts on a
-- bottle leaving the shop, plus the excise register the state asks for.
--
--   • DERIVED, NEVER STORED. Stock on hand is the sum of stock_moves; the register is
--     read from the same ledger. Nothing caches a count.
--   • THE SERVER PRICES THE SALE. A line's price is the product's price at the moment
--     of sale, read by ring_sale(); the till only says what and how many. A price above
--     the printed maximum retail price (MRP) can't even be saved.
--   • LEDGERS HAVE NO CLIENT WRITE. Sales and stock moves are written only by the
--     functions below, each checking the person's capability (045).
--   • ALCOHOL IS DENY-BY-DEFAULT, AGAIN. A bottle may be rung up only where brewdiary
--     has researched that state's RETAIL rules (sale hours, per-sale limits) and added
--     a row with its source — no row, no alcohol sale. A dry day listed for the state
--     stops alcohol sales all day. Every alcohol sale records that ID was checked
--     (never the ID itself) against the drinking age of the venue's jurisdiction.
--   • A SHOP THAT SELLS NO ALCOHOL CAN'T LIST ANY. A sweet shop's shelf can't hold
--     whisky; a liquor store is its own kind (047).
--   • NOTHING HERE IS ABOUT A GUEST. A sale has no guest column: the till sells to
--     "a customer". Loyalty punches stay record_visit() (030), separately.
--
-- Runs on top of 002..049.
-- ============================================================================

-- ── 1. the shelf ────────────────────────────────────────────────────────────
create table if not exists public.shop_products (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 120),
  brand      text check (brand is null or char_length(brand) <= 80),
  category   text not null check (category in ('spirit', 'beer', 'wine', 'other_alcohol', 'soft', 'food', 'sweet', 'other')),
  is_alcohol boolean generated always as (category in ('spirit', 'beer', 'wine', 'other_alcohol')) stored,
  -- What one unit is: a 750 ml bottle, a 500 g box. Sold by WEIGHT means the price is
  -- per kg and the sale quantity is in grams (mithai by the gram).
  size       numeric(10, 2) check (size is null or size > 0),
  unit       text not null default 'piece' check (unit in ('ml', 'g', 'piece')),
  sold_by    text not null default 'unit' check (sold_by in ('unit', 'weight')),
  price      numeric(10, 2) not null check (price >= 0),
  mrp        numeric(10, 2) check (mrp is null or mrp >= 0),
  barcode    text check (barcode is null or barcode ~ '^[0-9A-Za-z-]{4,32}$'),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  check (mrp is null or price <= mrp),                                  -- never above the printed MRP
  check (not (sold_by = 'weight' and category in ('spirit', 'beer', 'wine', 'other_alcohol'))),
  check (not (category in ('spirit', 'beer', 'wine', 'other_alcohol') and unit <> 'ml'))
);
create index if not exists shop_products_venue_idx on public.shop_products (venue_id, active);
create unique index if not exists shop_products_barcode_idx on public.shop_products (venue_id, barcode) where barcode is not null;

alter table public.shop_products enable row level security;
drop policy if exists shop_products_read on public.shop_products;
create policy shop_products_read on public.shop_products for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()));
drop policy if exists shop_products_write on public.shop_products;
create policy shop_products_write on public.shop_products for insert to authenticated
  with check (public.venue_can(venue_id, auth.uid(), 'menu.edit'));
drop policy if exists shop_products_update on public.shop_products;
create policy shop_products_update on public.shop_products for update to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'menu.edit'))
  with check (public.venue_can(venue_id, auth.uid(), 'menu.edit'));
-- No delete: a product that sold stays in the ledger's history. Set active = false.

-- A shop that sells no alcohol can't list any (047's legal class decides).
create or replace function public.shop_products_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v public.venues;
begin
  select * into v from public.venues where id = new.venue_id;
  if new.category in ('spirit', 'beer', 'wine', 'other_alcohol')
     and public.venue_legal_class(v.kind, v.serves_alcohol) = 'no_alcohol' then
    raise exception 'a % sells no alcohol — it can''t list %', replace(v.kind, '_', ' '), new.name
      using hint = 'A shop that sells alcohol is a liquor store (its own kind).';
  end if;
  if tg_op = 'UPDATE' and new.venue_id <> old.venue_id then
    raise exception 'a product stays with its venue';
  end if;
  return new;
end; $$;

drop trigger if exists shop_products_guard on public.shop_products;
create trigger shop_products_guard before insert or update on public.shop_products
  for each row execute function public.shop_products_guard();

-- ── 2. suppliers ────────────────────────────────────────────────────────────
-- Businesses, not people: a name and a trade licence number (an excise wholesale
-- licence, for a liquor store).
create table if not exists public.shop_suppliers (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 120),
  licence_no text check (licence_no is null or char_length(licence_no) <= 60),
  created_at timestamptz not null default now()
);
alter table public.shop_suppliers enable row level security;
drop policy if exists shop_suppliers_read on public.shop_suppliers;
create policy shop_suppliers_read on public.shop_suppliers for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()));
drop policy if exists shop_suppliers_write on public.shop_suppliers;
create policy shop_suppliers_write on public.shop_suppliers for insert to authenticated
  with check (public.venue_can(venue_id, auth.uid(), 'stock.receive'));

-- ── 3. the stock ledger ─────────────────────────────────────────────────────
create table if not exists public.stock_moves (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  product_id  uuid not null references public.shop_products(id) on delete cascade,
  qty         integer not null check (qty <> 0),           -- + in, − out (units, or grams by weight)
  reason      text not null check (reason in ('receive', 'sale', 'adjust', 'waste', 'return')),
  note        text check (note is null or char_length(note) <= 200),
  supplier_id uuid references public.shop_suppliers(id) on delete set null,
  invoice     text check (invoice is null or char_length(invoice) <= 60),
  sale_id     uuid,
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists stock_moves_product_idx on public.stock_moves (product_id, created_at);
create index if not exists stock_moves_venue_idx on public.stock_moves (venue_id, created_at);
alter table public.stock_moves enable row level security;
drop policy if exists stock_moves_read on public.stock_moves;
create policy stock_moves_read on public.stock_moves for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()));
-- No write policy: receive_stock(), adjust_stock() and ring_sale() only.

create or replace function public.receive_stock(pid uuid, qty int, supplier uuid default null, invoice_no text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  p public.shop_products;
begin
  select * into p from public.shop_products where id = pid;
  if p.id is null or not public.venue_can(p.venue_id, auth.uid(), 'stock.receive') then
    raise exception 'your role can''t receive stock here' using errcode = '42501';
  end if;
  if qty is null or qty < 1 or qty > 100000 then raise exception 'receive between 1 and 100000'; end if;
  if supplier is not null and not exists (select 1 from public.shop_suppliers s where s.id = supplier and s.venue_id = p.venue_id) then
    raise exception 'that supplier isn''t this venue''s';
  end if;
  insert into public.stock_moves (venue_id, product_id, qty, reason, supplier_id, invoice, recorded_by)
  values (p.venue_id, pid, qty, 'receive', supplier, nullif(trim(coalesce(invoice_no, '')), ''), auth.uid());
end; $$;

create or replace function public.adjust_stock(pid uuid, qty int, why text, note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  p public.shop_products;
begin
  select * into p from public.shop_products where id = pid;
  if p.id is null or not public.venue_can(p.venue_id, auth.uid(), 'stock.adjust') then
    raise exception 'your role can''t adjust stock here' using errcode = '42501';
  end if;
  if why not in ('adjust', 'waste', 'return') then raise exception 'say why: adjust, waste or return'; end if;
  if qty is null or qty = 0 or abs(qty) > 100000 then raise exception 'adjust by a real amount'; end if;
  if why = 'adjust' and char_length(trim(coalesce(note, ''))) < 3 then
    raise exception 'an adjustment needs a note (a count, a breakage…)';
  end if;
  insert into public.stock_moves (venue_id, product_id, qty, reason, note, recorded_by)
  values (p.venue_id, pid, qty, why, nullif(trim(coalesce(note, '')), ''), auth.uid());
end; $$;

-- On hand, per product: the ledger's sum. Staff of the venue only.
create or replace function public.shop_stock(vid uuid)
returns table (product_id uuid, on_hand bigint, last_move timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(sum(m.qty), 0)::bigint, max(m.created_at)
  from public.shop_products p
  left join public.stock_moves m on m.product_id = p.id
  where p.venue_id = vid and public.is_venue_staff(vid, auth.uid())
  group by p.id;
$$;

-- ── 4. retail alcohol rules (deny-by-default) ───────────────────────────────
-- One row per researched jurisdiction (country, or country + state), each with its
-- source. The hours are the rule's own local clock (tz). No row → no alcohol sale.
create table if not exists public.retail_alcohol_rules (
  country         text not null check (country ~ '^[A-Z]{2}$'),
  region          text not null default '' check (region = '' or region ~ '^[A-Z0-9]{1,3}$'),
  tz              text not null,
  sale_start      time not null,
  sale_end        time not null,                    -- may be past midnight (end < start)
  max_ml_per_sale int check (max_ml_per_sale is null or max_ml_per_sale > 0),
  source          text not null check (char_length(trim(source)) >= 5),
  note            text,
  primary key (country, region)
);
alter table public.retail_alcohol_rules enable row level security;
drop policy if exists retail_alcohol_rules_read on public.retail_alcohol_rules;
create policy retail_alcohol_rules_read on public.retail_alcohol_rules for select to authenticated using (true);

-- Dry days: dates on which no alcohol may be sold (national when region = '').
create table if not exists public.dry_days (
  country text not null check (country ~ '^[A-Z]{2}$'),
  region  text not null default '' check (region = '' or region ~ '^[A-Z0-9]{1,3}$'),
  day     date not null,
  reason  text not null check (char_length(trim(reason)) between 3 and 120),
  source  text not null check (char_length(trim(source)) >= 5),
  primary key (country, region, day)
);
alter table public.dry_days enable row level security;
drop policy if exists dry_days_read on public.dry_days;
create policy dry_days_read on public.dry_days for select to authenticated using (true);
-- Both tables are written only out-of-band with the service key, like jurisdiction_policy.

-- Today's alcohol status for a venue: the till shows it before anyone rings anything.
create or replace function public.store_sale_status(vid uuid)
returns table (researched boolean, allowed_now boolean, reason text, min_age int, max_ml int,
               sale_start time, sale_end time, dry_reason text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v    public.venues;
  r    public.retail_alcohol_rules;
  pol  record;
  lt   timestamp;
  dry  text;
  in_hours boolean;
begin
  if not public.is_venue_staff(vid, auth.uid()) then
    raise exception 'only this venue''s team can see its till rules' using errcode = '42501';
  end if;
  select * into v from public.venues where id = vid;
  select * into r from public.retail_alcohol_rules x
   where x.country = v.country and x.region in (coalesce(upper(v.region), ''), '')
   order by (x.region = '') limit 1;                                   -- the state's row beats the country's
  select * into pol from public.perk_policy(v.country, v.region);
  if r.country is null or pol is null or not coalesce(pol.alcohol_legal, false) then
    return query select false, false,
      'We haven''t researched the retail alcohol rules here yet, so alcohol can''t be rung up. Everything else can.'::text,
      pol.min_age, null::int, null::time, null::time, null::text;
    return;
  end if;
  lt := now() at time zone r.tz;
  select d.reason into dry from public.dry_days d
   where d.country = v.country and d.region in (coalesce(upper(v.region), ''), '') and d.day = lt::date
   limit 1;
  in_hours := case when r.sale_start <= r.sale_end then lt::time >= r.sale_start and lt::time < r.sale_end
               else lt::time >= r.sale_start or lt::time < r.sale_end end;
  return query select true,
    dry is null and in_hours,
    case when dry is not null then 'Dry day: ' || dry || ' — no alcohol may be sold today.'
         when not in_hours then 'Outside legal sale hours (' || to_char(r.sale_start, 'HH24:MI') || '–' || to_char(r.sale_end, 'HH24:MI') || ').'
         else null end,
    pol.min_age, r.max_ml_per_sale, r.sale_start, r.sale_end, dry;
end; $$;

-- ── 5. the sale ─────────────────────────────────────────────────────────────
create table if not exists public.shop_sales (
  id         uuid primary key,                              -- client-made: a retry can't double-ring
  venue_id   uuid not null references public.venues(id) on delete cascade,
  rung_by    uuid references public.profiles(id) on delete set null,
  paid_by    text not null check (paid_by in ('cash', 'card', 'upi', 'other')),
  total      numeric(12, 2) not null check (total >= 0),
  has_alcohol boolean not null default false,
  id_checked boolean not null default false,                -- a yes, never the ID itself
  created_at timestamptz not null default now(),
  check (not has_alcohol or id_checked)
);
create index if not exists shop_sales_venue_idx on public.shop_sales (venue_id, created_at);

create table if not exists public.shop_sale_lines (
  sale_id    uuid not null references public.shop_sales(id) on delete cascade,
  line_no    int not null,
  product_id uuid not null references public.shop_products(id) on delete cascade,
  qty        int not null check (qty > 0),                  -- units, or grams when sold by weight
  unit_price numeric(10, 2) not null,
  line_total numeric(12, 2) not null,
  primary key (sale_id, line_no)
);

alter table public.shop_sales enable row level security;
alter table public.shop_sale_lines enable row level security;
drop policy if exists shop_sales_read on public.shop_sales;
create policy shop_sales_read on public.shop_sales for select to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'reports.view') or rung_by = auth.uid());
drop policy if exists shop_sale_lines_read on public.shop_sale_lines;
create policy shop_sale_lines_read on public.shop_sale_lines for select to authenticated
  using (exists (select 1 from public.shop_sales s where s.id = sale_id
                 and (public.venue_can(s.venue_id, auth.uid(), 'reports.view') or s.rung_by = auth.uid())));
-- No write policy: ring_sale() only.

-- lines: [{ "product": uuid, "qty": int }]. Returns the total the server priced.
create or replace function public.ring_sale(vid uuid, sale uuid, lines jsonb, paid text, id_checked boolean default false)
returns numeric language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  st      record;
  l       jsonb;
  p       public.shop_products;
  q       int;
  n       int := 0;
  lt      numeric(12, 2);
  sum_total numeric(12, 2) := 0;
  alcohol boolean := false;
  ml      numeric := 0;
begin
  if not public.venue_can(vid, auth.uid(), 'payments.take') then
    raise exception 'your role can''t ring up a sale here' using errcode = '42501';
  end if;
  if exists (select 1 from public.shop_sales s where s.id = sale) then
    return (select s.total from public.shop_sales s where s.id = sale and s.venue_id = vid);   -- a retry
  end if;
  if paid not in ('cash', 'card', 'upi', 'other') then raise exception 'how was it paid?'; end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 or jsonb_array_length(lines) > 60 then
    raise exception 'a sale has 1 to 60 lines';
  end if;

  insert into public.shop_sales (id, venue_id, rung_by, paid_by, total, has_alcohol, id_checked)
  values (sale, vid, auth.uid(), paid, 0, false, coalesce(id_checked, false));

  for l in select * from jsonb_array_elements(lines) loop
    select * into p from public.shop_products where id = (l->>'product')::uuid;
    if p.id is null or p.venue_id <> vid or not p.active then
      raise exception 'a product isn''t on this venue''s shelf';
    end if;
    q := (l->>'qty')::int;
    if q is null or q < 1 or q > (case when p.sold_by = 'weight' then 100000 else 999 end) then
      raise exception 'check the quantity of %', p.name;
    end if;
    lt := case when p.sold_by = 'weight' then round(p.price * q / 1000.0, 2) else p.price * q end;
    n := n + 1;
    insert into public.shop_sale_lines (sale_id, line_no, product_id, qty, unit_price, line_total)
    values (sale, n, p.id, q, p.price, lt);
    insert into public.stock_moves (venue_id, product_id, qty, reason, sale_id, recorded_by)
    values (vid, p.id, -q, 'sale', sale, auth.uid());
    sum_total := sum_total + lt;
    if p.is_alcohol then
      alcohol := true;
      ml := ml + coalesce(p.size, 0) * q;
    end if;
  end loop;

  if alcohol then
    select * into st from public.store_sale_status(vid);
    if not st.researched or not st.allowed_now then
      raise exception '%', coalesce(st.reason, 'alcohol can''t be sold here right now');
    end if;
    if not coalesce(id_checked, false) then
      raise exception 'check ID first: % or over', coalesce(st.min_age, 21);
    end if;
    if st.max_ml is not null and ml > st.max_ml then
      raise exception 'that''s over the per-sale limit here (% ml)', st.max_ml;
    end if;
  end if;

  update public.shop_sales set total = sum_total, has_alcohol = alcohol where id = sale;
  return sum_total;
end; $$;

-- ── 6. the excise register ──────────────────────────────────────────────────
-- Per alcohol product per day: opening, received, sold, other moves, closing — read
-- from the ledger, with days on the state's own clock (the retail rule's tz; UTC if the
-- state isn't researched). The state's own format is an export of this (the app writes CSV).
create or replace function public.excise_register(vid uuid, from_day date, to_day date)
returns table (day date, product_id uuid, name text, brand text, size numeric, opening bigint,
               received bigint, sold bigint, other bigint, closing bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  zone text;
begin
  if not public.venue_can(vid, auth.uid(), 'reports.view') then
    raise exception 'your role can''t read the register' using errcode = '42501';
  end if;
  select r.tz into zone from public.venues v
    join public.retail_alcohol_rules r on r.country = v.country and r.region in (coalesce(upper(v.region), ''), '')
   where v.id = vid order by (r.region = '') limit 1;
  zone := coalesce(zone, 'UTC');
  if to_day < from_day or to_day - from_day > 92 then raise exception 'pick up to 93 days'; end if;
  return query
  with days as (select generate_series(from_day, to_day, interval '1 day')::date as d),
  prods as (select * from public.shop_products x where x.venue_id = vid and x.is_alcohol),
  moves as (select m.product_id as pid, (m.created_at at time zone zone)::date as d, m.reason, m.qty from public.stock_moves m where m.venue_id = vid)
  select dd.d, p.id, p.name, p.brand, p.size,
    coalesce((select sum(m.qty) from moves m where m.pid = p.id and m.d < dd.d), 0)::bigint,
    coalesce((select sum(m.qty) from moves m where m.pid = p.id and m.d = dd.d and m.reason = 'receive'), 0)::bigint,
    coalesce((select -sum(m.qty) from moves m where m.pid = p.id and m.d = dd.d and m.reason = 'sale'), 0)::bigint,
    coalesce((select sum(m.qty) from moves m where m.pid = p.id and m.d = dd.d and m.reason not in ('receive', 'sale')), 0)::bigint,
    coalesce((select sum(m.qty) from moves m where m.pid = p.id and m.d <= dd.d), 0)::bigint
  from days dd cross join prods p
  order by dd.d, p.brand nulls last, p.name;
end; $$;

revoke all on function public.receive_stock(uuid, int, uuid, text) from public;
revoke all on function public.adjust_stock(uuid, int, text, text) from public;
revoke all on function public.shop_stock(uuid) from public;
revoke all on function public.store_sale_status(uuid) from public;
revoke all on function public.ring_sale(uuid, uuid, jsonb, text, boolean) from public;
revoke all on function public.excise_register(uuid, date, date) from public;
grant execute on function public.receive_stock(uuid, int, uuid, text) to authenticated;
grant execute on function public.adjust_stock(uuid, int, text, text) to authenticated;
grant execute on function public.shop_stock(uuid) to authenticated;
grant execute on function public.store_sale_status(uuid) to authenticated;
grant execute on function public.ring_sale(uuid, uuid, jsonb, text, boolean) to authenticated;
grant execute on function public.excise_register(uuid, date, date) to authenticated;
