-- ============================================================================
-- brewdiary — SERVICE: the floor, tabs, orders, the bar and kitchen, the bill.
--
-- The point-of-sale core for any place with tables (a bar, a club, a restaurant, a
-- café — 047), and the guest's side of it: the table's own menu link, ordering from
-- it, and "call staff / bill please / water".
--
--   • STAFF DECIDE HOW IT'S PAID. The bill records whatever the staff enter — a method
--     ("cash", "card", "UPI", "voucher"…) and an amount, as many as they like, plus an
--     optional tip. brewdiary never takes a payment and never second-guesses one.
--   • THE SERVER PRICES EVERY LINE. A line's name and price are copied from the menu at
--     the moment it's ordered; a later menu edit never rewrites an open tab, and a
--     closed tab's subtotal is a snapshot (a bill can't change after it's settled).
--   • A GUEST ONLY ASKS. Ordering from the table is a REQUEST staff accept or decline;
--     only an accepted request becomes lines on a tab. The venue switches it on
--     (table_service, default off). Staff never see who asked — "a guest at table 4" —
--     and the guest sees only their own requests.
--   • EVERY WRITE IS A FUNCTION, gated by the person's capability (045). No client write
--     policy on tabs, lines, payments, requests or calls.
--   • THE WAITLIST FORGETS. A name on the host's list is gone within a day.
--   • NOTHING REWARDS DRINKING MORE. No happy hours, no discounts, no "another round"
--     prompt, no per-guest drink count. A void needs a reason; approving someone else's
--     void is a supervisor's job.
--
-- Runs on top of 002..050.
-- ============================================================================

-- ── 1. the menu, grown up ───────────────────────────────────────────────────
alter table public.venue_menu_items add column if not exists station text not null default 'bar';
alter table public.venue_menu_items add column if not exists diet text;
alter table public.venue_menu_items add column if not exists allergens text[] not null default '{}';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'venue_menu_items_station_check') then
    alter table public.venue_menu_items add constraint venue_menu_items_station_check check (station in ('bar', 'kitchen', 'none'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'venue_menu_items_diet_check') then
    -- India prints the green / brown dot on every menu; 'egg' is its own mark there.
    alter table public.venue_menu_items add constraint venue_menu_items_diet_check check (diet is null or diet in ('veg', 'non_veg', 'egg', 'vegan'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'venue_menu_items_allergens_check') then
    -- The EU's 14 allergens: the widest list any market asks for.
    alter table public.venue_menu_items add constraint venue_menu_items_allergens_check check (allergens <@ array[
      'gluten', 'crustaceans', 'eggs', 'fish', 'peanuts', 'soy', 'milk', 'nuts',
      'celery', 'mustard', 'sesame', 'sulphites', 'lupin', 'molluscs']::text[]);
  end if;
end $$;
update public.venue_menu_items set station = 'kitchen' where kind = 'food' and station = 'bar';

-- Food goes to the kitchen unless someone says otherwise.
create or replace function public.venue_menu_items_station()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.kind = 'food' and new.station = 'bar' then new.station := 'kitchen'; end if;
  return new;
end; $$;
drop trigger if exists venue_menu_items_station on public.venue_menu_items;
create trigger venue_menu_items_station before insert on public.venue_menu_items
  for each row execute function public.venue_menu_items_station();

-- The public menu now carries the diet mark and allergens (added columns; readers that
-- don't know them ignore them).
drop function if exists public.venue_menu(text);
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
  no_alcohol  boolean,
  diet        text,
  allergens   text[]
)
language sql stable security definer set search_path = public as $$
  select v.name, v.city, v.kind, v.currency,
         i.id, i.section, i.name, i.description, i.price, i.kind, i.no_alcohol, i.diet, i.allergens
    from public.venues v
    left join public.venue_menu_items i on i.venue_id = v.id and i.available
   where v.slug = lower(in_slug) and v.verified
   order by i.position, i.section, i.name;
$$;
revoke all on function public.venue_menu(text) from public;
grant execute on function public.venue_menu(text) to anon, authenticated;

-- The venue's switch for the guest side of service (ordering + calls). Off by default.
alter table public.venues add column if not exists table_service boolean not null default false;

-- ── 2. the floor ────────────────────────────────────────────────────────────
create table if not exists public.venue_areas (
  id       uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  name     text not null check (char_length(trim(name)) between 1 and 40),
  position int not null default 0
);
create table if not exists public.venue_tables (
  id       uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues(id) on delete cascade,
  area_id  uuid references public.venue_areas(id) on delete set null,
  label    text not null check (char_length(trim(label)) between 1 and 20),
  seats    int not null default 4 check (seats between 1 and 40),
  -- What the table's QR / NFC tag carries: bwdy.site/t/<code>. Rotating it retires
  -- every printed tag for that table (a tag someone took home stops working).
  code     text not null unique default lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
           check (code ~ '^[0-9a-z]{8}$'),
  active   boolean not null default true,
  position int not null default 0,
  unique (venue_id, label)
);
create index if not exists venue_tables_venue_idx on public.venue_tables (venue_id, position);

alter table public.venue_areas enable row level security;
alter table public.venue_tables enable row level security;
drop policy if exists venue_areas_read on public.venue_areas;
create policy venue_areas_read on public.venue_areas for select to authenticated using (public.is_venue_staff(venue_id, auth.uid()));
drop policy if exists venue_areas_write on public.venue_areas;
create policy venue_areas_write on public.venue_areas for insert to authenticated with check (public.venue_can(venue_id, auth.uid(), 'settings.edit'));
drop policy if exists venue_areas_update on public.venue_areas;
create policy venue_areas_update on public.venue_areas for update to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'settings.edit')) with check (public.venue_can(venue_id, auth.uid(), 'settings.edit'));
drop policy if exists venue_areas_delete on public.venue_areas;
create policy venue_areas_delete on public.venue_areas for delete to authenticated using (public.venue_can(venue_id, auth.uid(), 'settings.edit'));
drop policy if exists venue_tables_read on public.venue_tables;
create policy venue_tables_read on public.venue_tables for select to authenticated using (public.is_venue_staff(venue_id, auth.uid()));
drop policy if exists venue_tables_write on public.venue_tables;
create policy venue_tables_write on public.venue_tables for insert to authenticated with check (public.venue_can(venue_id, auth.uid(), 'settings.edit'));
drop policy if exists venue_tables_update on public.venue_tables;
create policy venue_tables_update on public.venue_tables for update to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'settings.edit')) with check (public.venue_can(venue_id, auth.uid(), 'settings.edit'));
-- No delete: a table with history is retired (active = false), so old tabs keep their label.

-- Tables belong to places with tables; a table's area is its own venue's.
create or replace function public.venue_tables_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v public.venues;
begin
  select * into v from public.venues where id = new.venue_id;
  if public.venue_is_counter(v.kind) then
    raise exception 'a % has a counter, not tables', replace(v.kind, '_', ' ');
  end if;
  if new.area_id is not null and not exists (select 1 from public.venue_areas a where a.id = new.area_id and a.venue_id = new.venue_id) then
    raise exception 'that area isn''t this venue''s';
  end if;
  if tg_op = 'UPDATE' and new.venue_id <> old.venue_id then raise exception 'a table stays with its venue'; end if;
  if tg_op = 'UPDATE' and new.code <> old.code and auth.uid() is not null
     and coalesce(current_setting('brewdiary.rotating_code', true), '') <> 'on' then
    raise exception 'rotate a table''s code with rotate_table_code()';
  end if;
  return new;
end; $$;
drop trigger if exists venue_tables_guard on public.venue_tables;
create trigger venue_tables_guard before insert or update on public.venue_tables
  for each row execute function public.venue_tables_guard();

create or replace function public.rotate_table_code(tid uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  t public.venue_tables;
  c text;
begin
  select * into t from public.venue_tables where id = tid;
  if t.id is null or not public.venue_can(t.venue_id, auth.uid(), 'settings.edit') then
    raise exception 'your role can''t change tables here' using errcode = '42501';
  end if;
  c := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  perform set_config('brewdiary.rotating_code', 'on', true);
  update public.venue_tables set code = c where id = tid;
  perform set_config('brewdiary.rotating_code', '', true);
  return c;
end; $$;

-- ── 3. tabs, lines, payments ────────────────────────────────────────────────
create table if not exists public.tabs (
  id        uuid primary key,                                 -- client-made: a retry can't open two
  venue_id  uuid not null references public.venues(id) on delete cascade,
  table_id  uuid references public.venue_tables(id) on delete set null,
  name      text check (name is null or char_length(name) <= 40),   -- "Bar 3", "the birthday"
  covers    int check (covers is null or covers between 1 and 99),
  status    text not null default 'open' check (status in ('open', 'closed', 'void')),
  opened_by uuid references public.profiles(id) on delete set null,
  opened_at timestamptz not null default now(),
  closed_by uuid references public.profiles(id) on delete set null,
  closed_at timestamptz,
  subtotal  numeric(12, 2),                                   -- snapshot at close
  tip       numeric(12, 2) check (tip is null or tip >= 0),
  void_reason text
);
create index if not exists tabs_venue_idx on public.tabs (venue_id, status, opened_at);

create table if not exists public.order_lines (
  id           uuid primary key default gen_random_uuid(),
  tab_id       uuid not null references public.tabs(id) on delete cascade,
  venue_id     uuid not null references public.venues(id) on delete cascade,
  menu_item_id uuid references public.venue_menu_items(id) on delete set null,
  name         text not null,                                 -- snapshot
  unit_price   numeric(10, 2) not null default 0,             -- snapshot
  qty          int not null check (qty between 1 and 99),
  note         text check (note is null or char_length(note) <= 120),
  seat         int check (seat is null or seat between 1 and 40),
  station      text not null check (station in ('bar', 'kitchen', 'none')),
  status       text not null default 'sent' check (status in ('sent', 'preparing', 'ready', 'served', 'void')),
  source       text not null default 'staff' check (source in ('staff', 'guest')),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  started_at   timestamptz,
  ready_at     timestamptz,
  served_at    timestamptz,
  void_reason  text,
  voided_by    uuid references public.profiles(id) on delete set null
);
create index if not exists order_lines_tab_idx on public.order_lines (tab_id);
create index if not exists order_lines_station_idx on public.order_lines (venue_id, station, status);

create table if not exists public.tab_payments (
  id          uuid primary key default gen_random_uuid(),
  tab_id      uuid not null references public.tabs(id) on delete cascade,
  venue_id    uuid not null references public.venues(id) on delete cascade,
  method      text not null check (char_length(trim(method)) between 2 and 20),   -- the staff's word for it
  amount      numeric(12, 2) not null check (amount >= 0),
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table public.tabs enable row level security;
alter table public.order_lines enable row level security;
alter table public.tab_payments enable row level security;
drop policy if exists tabs_read on public.tabs;
create policy tabs_read on public.tabs for select to authenticated using (public.venue_can(venue_id, auth.uid(), 'floor.view') or public.venue_can(venue_id, auth.uid(), 'station.kitchen'));
drop policy if exists order_lines_read on public.order_lines;
create policy order_lines_read on public.order_lines for select to authenticated using (public.is_venue_staff(venue_id, auth.uid()));
drop policy if exists tab_payments_read on public.tab_payments;
create policy tab_payments_read on public.tab_payments for select to authenticated using (public.venue_can(venue_id, auth.uid(), 'payments.take'));
-- No write policies: the functions below only.

-- Open a tab (at a table, or a named tab at the bar).
create or replace function public.open_tab(vid uuid, tab uuid, tbl uuid default null, tab_name text default null, cov int default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.venue_can(vid, auth.uid(), 'orders.take') then
    raise exception 'your role can''t open a tab here' using errcode = '42501';
  end if;
  if exists (select 1 from public.tabs t where t.id = tab) then return; end if;   -- a retry
  if tbl is not null and not exists (select 1 from public.venue_tables x where x.id = tbl and x.venue_id = vid and x.active) then
    raise exception 'that table isn''t this venue''s';
  end if;
  if tbl is null and char_length(trim(coalesce(tab_name, ''))) = 0 then
    raise exception 'a tab without a table needs a name (Bar 3, the birthday…)';
  end if;
  insert into public.tabs (id, venue_id, table_id, name, covers, opened_by)
  values (tab, vid, tbl, nullif(trim(coalesce(tab_name, '')), ''), cov, auth.uid());
end; $$;

-- Add lines: [{ "item": uuid, "qty": int, "note": text, "seat": int }]. The server
-- copies each item's name, price and station; an 86'd item is refused.
create or replace function public.add_order_lines(tab uuid, lines jsonb, src text default 'staff')
returns int language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  t  public.tabs;
  l  jsonb;
  m  public.venue_menu_items;
  n  int := 0;
  q  int;
begin
  select * into t from public.tabs where id = tab;
  if t.id is null or not public.venue_can(t.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t take orders here' using errcode = '42501';
  end if;
  if t.status <> 'open' then raise exception 'that tab is closed'; end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 or jsonb_array_length(lines) > 40 then
    raise exception 'send 1 to 40 lines at a time';
  end if;
  for l in select * from jsonb_array_elements(lines) loop
    select * into m from public.venue_menu_items where id = (l->>'item')::uuid;
    if m.id is null or m.venue_id <> t.venue_id then raise exception 'an item isn''t on this venue''s menu'; end if;
    if not m.available then raise exception '% is off tonight (86''d)', m.name; end if;
    q := coalesce((l->>'qty')::int, 1);
    if q < 1 or q > 99 then raise exception 'check the quantity of %', m.name; end if;
    insert into public.order_lines (tab_id, venue_id, menu_item_id, name, unit_price, qty, note, seat, station, source, created_by)
    values (t.id, t.venue_id, m.id, m.name, coalesce(m.price, 0), q,
            nullif(left(trim(coalesce(l->>'note', '')), 120), ''),
            nullif((l->>'seat')::int, 0), m.station,
            case when src = 'guest' then 'guest' else 'staff' end, auth.uid());
    n := n + 1;
  end loop;
  return n;
end; $$;

-- Move a line along: sent → preparing → ready → served. The bar and the kitchen move
-- their own lines; serving is the floor's.
create or replace function public.set_line_status(line uuid, to_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.order_lines;
  ok boolean;
  rank_from int;
  rank_to int;
begin
  select * into o from public.order_lines where id = line;
  if o.id is null then raise exception 'no such line'; end if;
  if to_status not in ('preparing', 'ready', 'served') then raise exception 'a line can be preparing, ready or served'; end if;
  ok := case
    when to_status = 'served' then public.venue_can(o.venue_id, auth.uid(), 'orders.take')
    when o.station = 'bar' then public.venue_can(o.venue_id, auth.uid(), 'station.bar')
    when o.station = 'kitchen' then public.venue_can(o.venue_id, auth.uid(), 'station.kitchen')
    else public.venue_can(o.venue_id, auth.uid(), 'orders.take') end;
  if not ok then raise exception 'your role can''t move this line' using errcode = '42501'; end if;
  rank_from := array_position(array['sent', 'preparing', 'ready', 'served'], o.status);
  rank_to := array_position(array['sent', 'preparing', 'ready', 'served'], to_status);
  if o.status = 'void' or rank_to <= rank_from then raise exception 'that line is already %', o.status; end if;
  update public.order_lines set
    status = to_status,
    started_at = coalesce(started_at, case when to_status in ('preparing', 'ready', 'served') then now() end),
    ready_at = coalesce(ready_at, case when to_status in ('ready', 'served') then now() end),
    served_at = case when to_status = 'served' then now() else served_at end
  where id = line;
end; $$;

-- A void needs a reason. Your own line, still unstarted and under 10 minutes old, is
-- yours to void; anything else is a supervisor's.
create or replace function public.void_line(line uuid, reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.order_lines;
  own boolean;
begin
  select * into o from public.order_lines where id = line;
  if o.id is null then raise exception 'no such line'; end if;
  if char_length(trim(coalesce(reason, ''))) < 3 then raise exception 'say why (a mistake, sent back…)'; end if;
  if o.status = 'void' then return; end if;
  if exists (select 1 from public.tabs t where t.id = o.tab_id and t.status <> 'open') then raise exception 'that tab is closed'; end if;
  own := o.created_by = auth.uid() and o.status = 'sent' and o.created_at > now() - interval '10 minutes';
  if not ((own and public.venue_can(o.venue_id, auth.uid(), 'orders.void_own')) or public.venue_can(o.venue_id, auth.uid(), 'orders.approve')) then
    raise exception 'a supervisor needs to void this one' using errcode = '42501';
  end if;
  update public.order_lines set status = 'void', void_reason = left(trim(reason), 120), voided_by = auth.uid() where id = line;
end; $$;

-- Settle the bill: the staff say how it was paid — any method, any split — and the tab
-- closes with its subtotal kept as it was. brewdiary doesn't take or check payments.
create or replace function public.close_tab(tab uuid, payments jsonb default '[]'::jsonb, tip_amount numeric default null)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  t   public.tabs;
  p   jsonb;
  sub numeric(12, 2);
begin
  select * into t from public.tabs where id = tab;
  if t.id is null or not public.venue_can(t.venue_id, auth.uid(), 'payments.take') then
    raise exception 'your role can''t settle a bill here' using errcode = '42501';
  end if;
  if t.status <> 'open' then raise exception 'that tab is already %', t.status; end if;
  if jsonb_typeof(payments) <> 'array' or jsonb_array_length(payments) > 12 then raise exception 'up to 12 payments'; end if;
  if tip_amount is not null and tip_amount < 0 then raise exception 'a tip can''t be negative'; end if;
  select coalesce(sum(o.unit_price * o.qty), 0) into sub from public.order_lines o where o.tab_id = tab and o.status <> 'void';
  for p in select * from jsonb_array_elements(payments) loop
    if char_length(trim(coalesce(p->>'method', ''))) < 2 or (p->>'amount')::numeric < 0 then
      raise exception 'each payment needs a method and an amount';
    end if;
    insert into public.tab_payments (tab_id, venue_id, method, amount, recorded_by)
    values (tab, t.venue_id, left(trim(p->>'method'), 20), (p->>'amount')::numeric, auth.uid());
  end loop;
  update public.tabs set status = 'closed', closed_by = auth.uid(), closed_at = now(), subtotal = sub, tip = tip_amount where id = tab;
  return sub;
end; $$;

-- A tab opened by mistake: void it, with a reason — only while nothing on it was served.
create or replace function public.void_tab(tab uuid, reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.tabs;
begin
  select * into t from public.tabs where id = tab;
  if t.id is null or not public.venue_can(t.venue_id, auth.uid(), 'orders.approve') then
    raise exception 'a supervisor needs to void a tab' using errcode = '42501';
  end if;
  if t.status <> 'open' then raise exception 'that tab is already %', t.status; end if;
  if char_length(trim(coalesce(reason, ''))) < 3 then raise exception 'say why'; end if;
  if exists (select 1 from public.order_lines o where o.tab_id = tab and o.status = 'served') then
    raise exception 'something on this tab was served — settle it instead';
  end if;
  update public.order_lines set status = 'void', void_reason = 'tab voided', voided_by = auth.uid() where tab_id = tab and status <> 'void';
  update public.tabs set status = 'void', void_reason = left(trim(reason), 120), closed_by = auth.uid(), closed_at = now(), subtotal = 0 where id = tab;
end; $$;

-- ── 4. the guest's side: the table link, requests, calls ────────────────────
create table if not exists public.order_requests (
  id           uuid primary key,                              -- client-made
  venue_id     uuid not null references public.venues(id) on delete cascade,
  table_id     uuid not null references public.venue_tables(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  lines        jsonb not null,                                -- [{item, name, qty, note}]
  note         text check (note is null or char_length(note) <= 200),
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'withdrawn')),
  decided_by   uuid references public.profiles(id) on delete set null,
  decided_at   timestamptz,
  decline_reason text,
  tab_id       uuid references public.tabs(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists order_requests_venue_idx on public.order_requests (venue_id, status, created_at);
create table if not exists public.table_calls (
  id           uuid primary key default gen_random_uuid(),
  venue_id     uuid not null references public.venues(id) on delete cascade,
  table_id     uuid not null references public.venue_tables(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  kind         text not null check (kind in ('staff', 'bill', 'water')),
  status       text not null default 'open' check (status in ('open', 'done')),
  created_at   timestamptz not null default now(),
  done_by      uuid references public.profiles(id) on delete set null,
  done_at      timestamptz
);
create index if not exists table_calls_venue_idx on public.table_calls (venue_id, status, created_at);

alter table public.order_requests enable row level security;
alter table public.table_calls enable row level security;
-- The guest sees their own; staff read through service_inbox(), which never says who.
drop policy if exists order_requests_own on public.order_requests;
create policy order_requests_own on public.order_requests for select to authenticated using (requested_by = auth.uid());
drop policy if exists table_calls_own on public.table_calls;
create policy table_calls_own on public.table_calls for select to authenticated using (requested_by = auth.uid());

-- What a table's link opens: which venue, which table, whether ordering is on. Public
-- (the menu itself is public); only a verified venue and an active table answer.
create or replace function public.table_info(in_code text)
returns table (venue_slug text, venue_name text, venue_kind text, currency text, table_label text, table_service boolean)
language sql stable security definer set search_path = public as $$
  select v.slug, v.name, v.kind, v.currency, t.label, v.table_service
    from public.venue_tables t join public.venues v on v.id = t.venue_id
   where t.code = lower(trim(in_code)) and t.active and v.verified;
$$;
revoke all on function public.table_info(text) from public;
grant execute on function public.table_info(text) to anon, authenticated;

create or replace function public.request_order(in_code text, req uuid, lines jsonb, req_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  t  public.venue_tables;
  v  public.venues;
  l  jsonb;
  m  public.venue_menu_items;
  out_lines jsonb := '[]'::jsonb;
  q  int;
begin
  if auth.uid() is null then raise exception 'sign in to order from the table'; end if;
  select * into t from public.venue_tables where code = lower(trim(in_code)) and active;
  select * into v from public.venues where id = t.venue_id;
  if t.id is null or not v.verified or not v.table_service then
    raise exception 'this table doesn''t take orders from phones — ask your server';
  end if;
  if exists (select 1 from public.order_requests r where r.id = req) then return; end if;   -- a retry
  if (select count(*) from public.order_requests r where r.requested_by = auth.uid() and r.table_id = t.id and r.status = 'pending') >= 3 then
    raise exception 'you have 3 orders waiting — give the staff a moment';
  end if;
  if exists (select 1 from public.order_requests r where r.requested_by = auth.uid() and r.created_at > now() - interval '20 seconds') then
    raise exception 'one moment — your last order is on its way';
  end if;
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 or jsonb_array_length(lines) > 20 then
    raise exception 'an order has 1 to 20 lines';
  end if;
  for l in select * from jsonb_array_elements(lines) loop
    select * into m from public.venue_menu_items where id = (l->>'item')::uuid;
    if m.id is null or m.venue_id <> v.id or not m.available then raise exception 'something in your order isn''t available'; end if;
    q := coalesce((l->>'qty')::int, 1);
    if q < 1 or q > 20 then raise exception 'check the quantity of %', m.name; end if;
    out_lines := out_lines || jsonb_build_object('item', m.id, 'name', m.name, 'qty', q,
      'note', nullif(left(trim(coalesce(l->>'note', '')), 120), ''), 'alcohol', not m.no_alcohol and m.kind in ('beer', 'wine', 'cocktail', 'spirit'));
  end loop;
  insert into public.order_requests (id, venue_id, table_id, requested_by, lines, note)
  values (req, v.id, t.id, auth.uid(), out_lines, nullif(left(trim(coalesce(req_note, '')), 200), ''));
end; $$;

create or replace function public.withdraw_request(req uuid)
returns void language sql security definer set search_path = public as $$
  update public.order_requests set status = 'withdrawn'
   where id = req and requested_by = auth.uid() and status = 'pending';
$$;

create or replace function public.call_table_staff(in_code text, call_kind text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.venue_tables;
  v public.venues;
begin
  if auth.uid() is null then raise exception 'sign in to call staff from the table'; end if;
  if call_kind not in ('staff', 'bill', 'water') then raise exception 'call for staff, the bill or water'; end if;
  select * into t from public.venue_tables where code = lower(trim(in_code)) and active;
  select * into v from public.venues where id = t.venue_id;
  if t.id is null or not v.verified or not v.table_service then
    raise exception 'this table doesn''t take calls from phones — wave, they''ll see you';
  end if;
  if exists (select 1 from public.table_calls c where c.table_id = t.id and c.requested_by = auth.uid() and c.kind = call_kind and c.status = 'open') then
    return;   -- already asked; asking twice doesn't make it faster
  end if;
  insert into public.table_calls (venue_id, table_id, requested_by, kind) values (v.id, t.id, auth.uid(), call_kind);
end; $$;

-- The floor's inbox: open requests and calls from the last 12 hours — the table, what,
-- when. Never who asked.
create or replace function public.service_inbox(vid uuid)
returns table (item_kind text, id uuid, table_id uuid, table_label text, created_at timestamptz,
               lines jsonb, note text, call_kind text, has_alcohol boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.venue_can(vid, auth.uid(), 'floor.view') then
    raise exception 'your role doesn''t see the floor' using errcode = '42501';
  end if;
  return query
  select 'order'::text, r.id, r.table_id, t.label, r.created_at, r.lines, r.note, null::text,
         exists (select 1 from jsonb_array_elements(r.lines) x where (x->>'alcohol')::boolean)
    from public.order_requests r join public.venue_tables t on t.id = r.table_id
   where r.venue_id = vid and r.status = 'pending' and r.created_at > now() - interval '12 hours'
  union all
  select 'call'::text, c.id, c.table_id, t.label, c.created_at, null::jsonb, null::text, c.kind, false
    from public.table_calls c join public.venue_tables t on t.id = c.table_id
   where c.venue_id = vid and c.status = 'open' and c.created_at > now() - interval '12 hours'
  order by 5;
end; $$;

-- Accept a guest's request onto a tab (the table's open tab, or a new one). Only now
-- does it become lines — priced by the server, as if staff had keyed them.
create or replace function public.accept_request(req uuid, tab uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  r public.order_requests;
  t public.tabs;
begin
  select * into r from public.order_requests where id = req;
  if r.id is null or not public.venue_can(r.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t take orders here' using errcode = '42501';
  end if;
  if r.status <> 'pending' then raise exception 'that request is already %', r.status; end if;
  select * into t from public.tabs where id = tab;
  if t.id is null then
    perform public.open_tab(r.venue_id, tab, r.table_id, null, null);
  elsif t.venue_id <> r.venue_id or t.status <> 'open' then
    raise exception 'pick an open tab at this venue';
  end if;
  perform public.add_order_lines(tab,
    (select jsonb_agg(jsonb_build_object('item', x->>'item', 'qty', (x->>'qty')::int, 'note', x->>'note')) from jsonb_array_elements(r.lines) x),
    'guest');
  update public.order_requests set status = 'accepted', decided_by = auth.uid(), decided_at = now(), tab_id = tab where id = req;
  return tab;
end; $$;

create or replace function public.decline_request(req uuid, reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  r public.order_requests;
begin
  select * into r from public.order_requests where id = req;
  if r.id is null or not public.venue_can(r.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t take orders here' using errcode = '42501';
  end if;
  if r.status <> 'pending' then return; end if;
  update public.order_requests set status = 'declined', decided_by = auth.uid(), decided_at = now(),
         decline_reason = nullif(left(trim(coalesce(reason, '')), 120), '') where id = req;
end; $$;

create or replace function public.resolve_call(call uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  c public.table_calls;
begin
  select * into c from public.table_calls where id = call;
  if c.id is null or not public.venue_can(c.venue_id, auth.uid(), 'floor.view') then
    raise exception 'your role doesn''t see the floor' using errcode = '42501';
  end if;
  update public.table_calls set status = 'done', done_by = auth.uid(), done_at = now() where id = call and status = 'open';
end; $$;

-- ── 5. the host's waitlist (forgets within a day) ───────────────────────────
create table if not exists public.waitlist (
  id         uuid primary key,
  venue_id   uuid not null references public.venues(id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 40),   -- a first name or "party of 4"
  party      int not null check (party between 1 and 40),
  quoted_min int check (quoted_min is null or quoted_min between 0 and 240),
  note       text check (note is null or char_length(note) <= 120),
  status     text not null default 'waiting' check (status in ('waiting', 'seated', 'left')),
  table_id   uuid references public.venue_tables(id) on delete set null,
  created_at timestamptz not null default now(),
  seated_at  timestamptz
);
alter table public.waitlist enable row level security;
drop policy if exists waitlist_read on public.waitlist;
create policy waitlist_read on public.waitlist for select to authenticated using (public.venue_can(venue_id, auth.uid(), 'floor.view'));
drop policy if exists waitlist_write on public.waitlist;
create policy waitlist_write on public.waitlist for insert to authenticated with check (public.venue_can(venue_id, auth.uid(), 'guests.seat'));
drop policy if exists waitlist_update on public.waitlist;
create policy waitlist_update on public.waitlist for update to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'guests.seat')) with check (public.venue_can(venue_id, auth.uid(), 'guests.seat'));

-- Every new name clears yesterday's: nobody's name outlives the night on a host's list.
create or replace function public.waitlist_forget()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.waitlist w where w.venue_id = new.venue_id and w.created_at < now() - interval '20 hours';
  return new;
end; $$;
drop trigger if exists waitlist_forget on public.waitlist;
create trigger waitlist_forget after insert on public.waitlist for each row execute function public.waitlist_forget();

-- ── 6. the live board (managers) ────────────────────────────────────────────
-- Business numbers only — no guest, no per-staff ranking. "Today" is since the
-- venue's day started (the caller says where that is; the app sends local midnight).
create or replace function public.service_board(vid uuid, day_start timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  since timestamptz := coalesce(day_start, date_trunc('day', now()));
begin
  if not public.venue_can(vid, auth.uid(), 'board.live') then
    raise exception 'your role doesn''t see the live board' using errcode = '42501';
  end if;
  if since < now() - interval '36 hours' then since := now() - interval '36 hours'; end if;
  return jsonb_build_object(
    'open_tabs',   (select count(*) from public.tabs t where t.venue_id = vid and t.status = 'open'),
    'covers',      (select coalesce(sum(t.covers), 0) from public.tabs t where t.venue_id = vid and t.status = 'open'),
    'sales',       (select coalesce(sum(t.subtotal), 0) from public.tabs t where t.venue_id = vid and t.status = 'closed' and t.closed_at >= since),
    'tips',        (select coalesce(sum(t.tip), 0) from public.tabs t where t.venue_id = vid and t.status = 'closed' and t.closed_at >= since),
    'bills',       (select count(*) from public.tabs t where t.venue_id = vid and t.status = 'closed' and t.closed_at >= since),
    'bar_waiting', (select count(*) from public.order_lines o where o.venue_id = vid and o.station = 'bar' and o.status in ('sent', 'preparing')),
    'kitchen_waiting', (select count(*) from public.order_lines o where o.venue_id = vid and o.station = 'kitchen' and o.status in ('sent', 'preparing')),
    'bar_minutes', (select round(avg(extract(epoch from o.ready_at - o.created_at) / 60)::numeric, 1) from public.order_lines o
                     where o.venue_id = vid and o.station = 'bar' and o.ready_at >= since),
    'kitchen_minutes', (select round(avg(extract(epoch from o.ready_at - o.created_at) / 60)::numeric, 1) from public.order_lines o
                     where o.venue_id = vid and o.station = 'kitchen' and o.ready_at >= since),
    'voids',       (select count(*) from public.order_lines o where o.venue_id = vid and o.status = 'void' and o.created_at >= since),
    'requests',    (select count(*) from public.order_requests r where r.venue_id = vid and r.status = 'pending'),
    'calls',       (select count(*) from public.table_calls c where c.venue_id = vid and c.status = 'open'),
    'waiting',     (select count(*) from public.waitlist w where w.venue_id = vid and w.status = 'waiting'),
    'methods',     (select coalesce(jsonb_object_agg(m.method, m.total), '{}'::jsonb) from (
                     select lower(p.method) as method, sum(p.amount) as total from public.tab_payments p
                      where p.venue_id = vid and p.created_at >= since group by lower(p.method)) m)
  );
end; $$;

revoke all on function public.rotate_table_code(uuid) from public;
revoke all on function public.open_tab(uuid, uuid, uuid, text, int) from public;
revoke all on function public.add_order_lines(uuid, jsonb, text) from public;
revoke all on function public.set_line_status(uuid, text) from public;
revoke all on function public.void_line(uuid, text) from public;
revoke all on function public.close_tab(uuid, jsonb, numeric) from public;
revoke all on function public.void_tab(uuid, text) from public;
revoke all on function public.request_order(text, uuid, jsonb, text) from public;
revoke all on function public.withdraw_request(uuid) from public;
revoke all on function public.call_table_staff(text, text) from public;
revoke all on function public.service_inbox(uuid) from public;
revoke all on function public.accept_request(uuid, uuid) from public;
revoke all on function public.decline_request(uuid, text) from public;
revoke all on function public.resolve_call(uuid) from public;
revoke all on function public.service_board(uuid, timestamptz) from public;
grant execute on function public.rotate_table_code(uuid) to authenticated;
grant execute on function public.open_tab(uuid, uuid, uuid, text, int) to authenticated;
grant execute on function public.add_order_lines(uuid, jsonb, text) to authenticated;
grant execute on function public.set_line_status(uuid, text) to authenticated;
grant execute on function public.void_line(uuid, text) to authenticated;
grant execute on function public.close_tab(uuid, jsonb, numeric) to authenticated;
grant execute on function public.void_tab(uuid, text) to authenticated;
grant execute on function public.request_order(text, uuid, jsonb, text) to authenticated;
grant execute on function public.withdraw_request(uuid) to authenticated;
grant execute on function public.call_table_staff(text, text) to authenticated;
grant execute on function public.service_inbox(uuid) to authenticated;
grant execute on function public.accept_request(uuid, uuid) to authenticated;
grant execute on function public.decline_request(uuid, text) to authenticated;
grant execute on function public.resolve_call(uuid) to authenticated;
grant execute on function public.service_board(uuid, timestamptz) to authenticated;
