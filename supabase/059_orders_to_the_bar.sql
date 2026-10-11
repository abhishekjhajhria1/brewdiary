-- ============================================================================
-- brewdiary — ORDERS THAT GO STRAIGHT TO THE BAR AND THE KITCHEN (059).
--
-- In many places nobody on the floor carries a phone: the guest orders from the
-- table's tag or QR (051) and the order should land where it's made — on the bar's
-- and the kitchen's screens and their ticket printers. For every kind of place:
--
--   • STRAIGHT TO THE BAR AND KITCHEN (venues.orders_direct). Off, a staff member
--     confirms each phone order first (051, unchanged). On, it becomes lines on the
--     table's tab at once — priced by the server, split by station.
--   • PICKUP POINTS (venue_tables.kind = 'pickup'): a bar counter, a café counter, a
--     shop's counter. An order placed there gets a PICKUP NUMBER ("42"); the guest's
--     phone and the public ready board (pickup_board) show it when it's ready.
--     Counters (047) may hold pickup points — still never tables.
--   • PAUSE (venues.orders_paused): the kitchen's "hold phone orders" in a rush. Any
--     station or floor role can flip it (pause_phone_orders).
--   • ORDERING WITHOUT AN ACCOUNT (venues.orders_anon, off by default):
--     place_order_guest() takes a secret the phone made instead of a sign-in; only its
--     hash is kept. Rate-limited per phone and per table — the table's code is the
--     proof of being there, and rotating it (051) retires a leaked one.
--   • WHAT THE GUEST SEES: my_orders() / guest_orders() — each line's step (sent →
--     making → ready → served) and the pickup number. Only their own.
--   • A LIQUOR STORE'S BOTTLES ARE NEVER ORDERED BY PHONE. The law puts an ID check and
--     sale hours on every bottle at the counter; a phone can't carry them, so an
--     off-trade alcohol line is refused unless that state's retail row says otherwise
--     (allow_phone_orders — no row does: deny by default). The shelf is public
--     (store_shelf) so a customer can make a list and show it at the till.
--   • STAFF STILL NEVER SEE WHO ASKED. A ticket says the table or the pickup number.
--
-- Runs on top of 002..058.
-- ============================================================================

-- ── 1. the switches ─────────────────────────────────────────────────────────
alter table public.venues add column if not exists orders_direct boolean not null default false;
alter table public.venues add column if not exists orders_paused boolean not null default false;
alter table public.venues add column if not exists orders_anon boolean not null default false;

-- ── 2. pickup points, pickup numbers ────────────────────────────────────────
alter table public.venue_tables add column if not exists kind text not null default 'table';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'venue_tables_kind_check') then
    alter table public.venue_tables add constraint venue_tables_kind_check check (kind in ('table', 'pickup'));
  end if;
end $$;

alter table public.tabs add column if not exists pickup_no int;
alter table public.tabs add column if not exists pickup_point uuid references public.venue_tables(id) on delete set null;
alter table public.tabs add column if not exists collected_at timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tabs_pickup_no_check') then
    alter table public.tabs add constraint tabs_pickup_no_check check (pickup_no is null or pickup_no between 1 and 999);
  end if;
end $$;
create index if not exists tabs_pickup_idx on public.tabs (venue_id, opened_at) where pickup_no is not null;

-- Which request a line came from — so the guest can follow their own lines.
alter table public.order_lines add column if not exists request_id uuid references public.order_requests(id) on delete set null;
create index if not exists order_lines_request_idx on public.order_lines (request_id) where request_id is not null;

-- A phone without an account: the hash of a secret it made, never the secret.
alter table public.order_requests alter column requested_by drop not null;
alter table public.order_requests add column if not exists device_hash text;
alter table public.table_calls alter column requested_by drop not null;
alter table public.table_calls add column if not exists device_hash text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'order_requests_who_check') then
    alter table public.order_requests add constraint order_requests_who_check check (requested_by is not null or device_hash is not null);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'table_calls_who_check') then
    alter table public.table_calls add constraint table_calls_who_check check (requested_by is not null or device_hash is not null);
  end if;
end $$;
create index if not exists order_requests_device_idx on public.order_requests (device_hash, created_at) where device_hash is not null;

-- A state's retail row may one day allow bottles to be ordered by phone; none does.
alter table public.retail_alcohol_rules add column if not exists allow_phone_orders boolean not null default false;

-- Counters may now hold pickup points — still never tables.
create or replace function public.venue_tables_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v public.venues;
begin
  select * into v from public.venues where id = new.venue_id;
  if public.venue_is_counter(v.kind) and new.kind <> 'pickup' then
    raise exception 'a % has a counter, not tables — add a pickup point for the counter', replace(v.kind, '_', ' ');
  end if;
  if new.area_id is not null and not exists (select 1 from public.venue_areas a where a.id = new.area_id and a.venue_id = new.venue_id) then
    raise exception 'that area isn''t this venue''s';
  end if;
  if tg_op = 'UPDATE' and new.venue_id <> old.venue_id then raise exception 'a table stays with its venue'; end if;
  if tg_op = 'UPDATE' and new.kind <> old.kind then raise exception 'a table stays a table and a pickup point a pickup point — add a new one'; end if;
  if tg_op = 'UPDATE' and new.code <> old.code and auth.uid() is not null
     and coalesce(current_setting('brewdiary.rotating_code', true), '') <> 'on' then
    raise exception 'rotate a table''s code with rotate_table_code()';
  end if;
  return new;
end; $$;

-- ── 3. what a table's (or a pickup point's) link opens ──────────────────────
drop function if exists public.table_info(text);
create or replace function public.table_info(in_code text)
returns table (venue_slug text, venue_name text, venue_kind text, currency text, table_label text, table_service boolean,
               point_kind text, orders_direct boolean, orders_paused boolean, orders_anon boolean, legal_class text)
language sql stable security definer set search_path = public as $$
  select v.slug, v.name, v.kind, v.currency, t.label, v.table_service,
         t.kind, v.orders_direct, v.orders_paused, v.orders_anon, public.venue_legal_class(v.kind, v.serves_alcohol)
    from public.venue_tables t join public.venues v on v.id = t.venue_id
   where t.code = lower(trim(in_code)) and t.active and v.verified;
$$;

-- ── 4. placing an order (shared by the signed-in and the no-account paths) ──
-- The next pickup number: one after the highest of the last 12 hours, 1..999. A quiet
-- morning starts again at 1. One venue at a time (an advisory lock), so two orders
-- never share a number.
create or replace function public.next_pickup_no(vid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  last int;
begin
  perform pg_advisory_xact_lock(hashtext('pickup:' || vid::text));
  select t.pickup_no into last from public.tabs t
   where t.venue_id = vid and t.pickup_no is not null and t.opened_at > now() - interval '12 hours'
   order by t.opened_at desc, t.pickup_no desc limit 1;
  return coalesce(last, 0) % 999 + 1;
end; $$;

-- Check a guest's lines against the menu: available, sensible quantities, and — at a
-- liquor store — no bottles unless the state's row allows phone orders (none does).
create or replace function public.check_guest_lines(v public.venues, lines jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  l  jsonb;
  m  public.venue_menu_items;
  q  int;
  out_lines jsonb := '[]'::jsonb;
  bottles_ok boolean;
  is_alc boolean;
begin
  if jsonb_typeof(lines) <> 'array' or jsonb_array_length(lines) = 0 or jsonb_array_length(lines) > 20 then
    raise exception 'an order has 1 to 20 lines';
  end if;
  select coalesce(r.allow_phone_orders, false) into bottles_ok from public.retail_alcohol_rules r
   where r.country = v.country and r.region in (coalesce(upper(v.region), ''), '')
   order by (r.region = '') limit 1;
  for l in select * from jsonb_array_elements(lines) loop
    select * into m from public.venue_menu_items where id = (l->>'item')::uuid;
    if m.id is null or m.venue_id <> v.id or not m.available then raise exception 'something in your order isn''t available'; end if;
    q := coalesce((l->>'qty')::int, 1);
    if q < 1 or q > 20 then raise exception 'check the quantity of %', m.name; end if;
    is_alc := not m.no_alcohol and m.kind in ('beer', 'wine', 'cocktail', 'spirit');
    if is_alc and public.venue_legal_class(v.kind, v.serves_alcohol) = 'off_trade' and not coalesce(bottles_ok, false) then
      raise exception 'bottles are sold at the counter, with an ID check — add them to your list and show it there';
    end if;
    out_lines := out_lines || jsonb_build_object('item', m.id, 'name', m.name, 'qty', q,
      'note', nullif(left(trim(coalesce(l->>'note', '')), 120), ''), 'alcohol', is_alc);
  end loop;
  return out_lines;
end; $$;

-- Turn a request into lines: on the table's open tab (opened if there is none), or —
-- at a pickup point — on a tab of its own with the next pickup number. Re-checks each
-- item (it may have been 86'd since).
create or replace function public.land_order(req uuid, decider uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  r   public.order_requests;
  pt  public.venue_tables;
  tab uuid;
  pno int;
  x   jsonb;
  m   public.venue_menu_items;
begin
  select * into r from public.order_requests where id = req for update;
  if r.status <> 'pending' then raise exception 'that order is already %', r.status; end if;
  select * into pt from public.venue_tables where id = r.table_id;
  if pt.kind = 'pickup' then
    pno := public.next_pickup_no(r.venue_id);
    tab := gen_random_uuid();
    insert into public.tabs (id, venue_id, table_id, name, pickup_no, pickup_point, opened_by)
    values (tab, r.venue_id, null, 'Pickup ' || pno, pno, pt.id, decider);
  else
    select t.id into tab from public.tabs t
     where t.venue_id = r.venue_id and t.table_id = pt.id and t.status = 'open'
     order by t.opened_at desc limit 1;
    if tab is null then
      tab := gen_random_uuid();
      insert into public.tabs (id, venue_id, table_id, opened_by) values (tab, r.venue_id, pt.id, decider);
    end if;
  end if;
  for x in select * from jsonb_array_elements(r.lines) loop
    select * into m from public.venue_menu_items where id = (x->>'item')::uuid;
    if m.id is null or not m.available then raise exception '% is off tonight', coalesce(m.name, 'an item'); end if;
    insert into public.order_lines (tab_id, venue_id, menu_item_id, name, unit_price, qty, note, station, source, created_by, request_id)
    values (tab, r.venue_id, m.id, m.name, coalesce(m.price, 0), (x->>'qty')::int,
            nullif(left(trim(coalesce(x->>'note', '')), 120), ''), m.station, 'guest', r.requested_by, r.id);
  end loop;
  update public.order_requests set status = 'accepted', decided_by = decider, decided_at = now(), tab_id = tab where id = req;
  return tab;
end; $$;

-- One order's state as the guest sees it.
create or replace function public.order_status_json(req uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', r.id,
    'status', case
       when r.status <> 'accepted' then r.status
       when not exists (select 1 from public.order_lines o where o.request_id = r.id and o.status <> 'void') then 'declined'
       when not exists (select 1 from public.order_lines o where o.request_id = r.id and o.status not in ('served', 'void')) then 'served'
       when not exists (select 1 from public.order_lines o where o.request_id = r.id and o.status not in ('ready', 'served', 'void')) then 'ready'
       when exists (select 1 from public.order_lines o where o.request_id = r.id and o.status in ('preparing', 'ready')) then 'making'
       else 'sent' end,
    'created_at', r.created_at,
    'venue_name', v.name,
    'point', t.label,
    'point_kind', t.kind,
    'pickup_no', tb.pickup_no,
    'decline_reason', r.decline_reason,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('name', o.name, 'qty', o.qty, 'status', o.status) order by o.created_at)
                         from public.order_lines o where o.request_id = r.id),
                      (select jsonb_agg(jsonb_build_object('name', x->>'name', 'qty', (x->>'qty')::int, 'status', 'waiting'))
                         from jsonb_array_elements(r.lines) x)))
    from public.order_requests r
    join public.venues v on v.id = r.venue_id
    join public.venue_tables t on t.id = r.table_id
    left join public.tabs tb on tb.id = r.tab_id
   where r.id = req;
$$;

create or replace function public.place_order_inner(in_code text, req uuid, lines jsonb, req_note text, who uuid, dev text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  t   public.venue_tables;
  v   public.venues;
  r   public.order_requests;
  out_lines jsonb;
begin
  select * into t from public.venue_tables where code = lower(trim(in_code)) and active;
  select * into v from public.venues where id = t.venue_id;
  if t.id is null or not v.verified or not v.table_service then
    raise exception 'this place doesn''t take orders from phones — ask at the bar';
  end if;
  if who is null and not v.orders_anon then raise exception 'sign in to order here'; end if;
  select * into r from public.order_requests where id = req;
  if r.id is not null then   -- a retry: the same order, never a second one
    if (who is not null and r.requested_by = who) or (dev is not null and r.device_hash = dev) then return public.order_status_json(req); end if;
    raise exception 'that order belongs to someone else';
  end if;
  if v.orders_paused then raise exception 'the kitchen has paused phone orders for a few minutes — ask at the bar'; end if;
  if exists (select 1 from public.order_requests x
              where ((who is not null and x.requested_by = who) or (dev is not null and x.device_hash = dev))
                and x.created_at > now() - interval '20 seconds') then
    raise exception 'one moment — your last order is on its way';
  end if;
  if (select count(*) from public.order_requests x
       where ((who is not null and x.requested_by = who) or (dev is not null and x.device_hash = dev))
         and x.created_at > now() - interval '10 minutes') >= 6 then
    raise exception 'that''s a lot of orders — give the bar a moment';
  end if;
  if not v.orders_direct and (select count(*) from public.order_requests x
       where ((who is not null and x.requested_by = who) or (dev is not null and x.device_hash = dev))
         and x.table_id = t.id and x.status = 'pending') >= 3 then
    raise exception 'you have 3 orders waiting — give the staff a moment';
  end if;
  if who is null and (select count(*) from public.order_requests x
       where x.table_id = t.id and x.requested_by is null and x.created_at > now() - interval '10 minutes') >= 12 then
    raise exception 'lots of orders from this table just now — ask at the bar';
  end if;
  out_lines := public.check_guest_lines(v, lines);
  insert into public.order_requests (id, venue_id, table_id, requested_by, device_hash, lines, note)
  values (req, v.id, t.id, who, dev, out_lines, nullif(left(trim(coalesce(req_note, '')), 200), ''));
  if v.orders_direct then perform public.land_order(req, null); end if;
  return public.order_status_json(req);
end; $$;

-- Signed in.
create or replace function public.place_order(in_code text, req uuid, lines jsonb, req_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in to order from the table'; end if;
  return public.place_order_inner(in_code, req, lines, req_note, auth.uid(), null);
end; $$;

-- No account: the phone's own secret (32–64 hex characters), hashed before it's kept.
create or replace function public.device_hash_of(device text)
returns text language plpgsql immutable set search_path = public as $$
begin
  if device is null or device !~ '^[0-9a-f]{32,64}$' then raise exception 'this phone needs to start again — reload the page'; end if;
  return encode(sha256(convert_to('brewdiary-order:' || device, 'UTF8')), 'hex');
end; $$;

create or replace function public.place_order_guest(in_code text, req uuid, device text, lines jsonb, req_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return public.place_order_inner(in_code, req, lines, req_note, null, public.device_hash_of(device));
end; $$;

-- 051's request_order now takes the same road (older apps keep working, and get the
-- direct path, the pause and pickup points too).
create or replace function public.request_order(in_code text, req uuid, lines jsonb, req_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in to order from the table'; end if;
  perform public.place_order_inner(in_code, req, lines, req_note, auth.uid(), null);
end; $$;

-- Staff accept a request (confirm mode): a pickup point's gets its own numbered tab;
-- a table's goes on the given tab (or a new one with that id).
create or replace function public.accept_request(req uuid, tab uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  r  public.order_requests;
  pt public.venue_tables;
  t  public.tabs;
  x  jsonb;
  m  public.venue_menu_items;
begin
  select * into r from public.order_requests where id = req;
  if r.id is null or not public.venue_can(r.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t take orders here' using errcode = '42501';
  end if;
  if r.status <> 'pending' then raise exception 'that request is already %', r.status; end if;
  select * into pt from public.venue_tables where id = r.table_id;
  if pt.kind = 'pickup' then
    return public.land_order(req, auth.uid());
  end if;
  select * into t from public.tabs where id = tab;
  if t.id is null then
    perform public.open_tab(r.venue_id, tab, r.table_id, null, null);
  elsif t.venue_id <> r.venue_id or t.status <> 'open' then
    raise exception 'pick an open tab at this venue';
  end if;
  for x in select * from jsonb_array_elements(r.lines) loop
    select * into m from public.venue_menu_items where id = (x->>'item')::uuid;
    if m.id is null or m.venue_id <> r.venue_id then raise exception 'an item isn''t on this venue''s menu'; end if;
    if not m.available then raise exception '% is off tonight (86''d)', m.name; end if;
    insert into public.order_lines (tab_id, venue_id, menu_item_id, name, unit_price, qty, note, station, source, created_by, request_id)
    values (tab, r.venue_id, m.id, m.name, coalesce(m.price, 0), (x->>'qty')::int,
            nullif(left(trim(coalesce(x->>'note', '')), 120), ''), m.station, 'guest', auth.uid(), r.id);
  end loop;
  update public.order_requests set status = 'accepted', decided_by = auth.uid(), decided_at = now(), tab_id = tab where id = req;
  return tab;
end; $$;

-- ── 5. what the guest follows ───────────────────────────────────────────────
create or replace function public.my_orders()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.order_status_json(r.id) order by r.created_at desc), '[]'::jsonb)
    from (select x.id, x.created_at from public.order_requests x
           where x.requested_by = auth.uid() and x.created_at > now() - interval '12 hours'
           order by x.created_at desc limit 10) r;
$$;

create or replace function public.guest_orders(device text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public.order_status_json(r.id) order by r.created_at desc), '[]'::jsonb)
    from (select x.id, x.created_at from public.order_requests x
           where x.device_hash = public.device_hash_of(device) and x.created_at > now() - interval '12 hours'
           order by x.created_at desc limit 10) r;
$$;

-- A guest without an account withdraws a pending order (confirm mode only).
create or replace function public.withdraw_guest_order(req uuid, device text)
returns void language sql security definer set search_path = public as $$
  update public.order_requests set status = 'withdrawn'
   where id = req and device_hash = public.device_hash_of(device) and status = 'pending';
$$;

-- "Call staff / bill please / water" without an account (same rules as 051's).
create or replace function public.call_table_staff_guest(in_code text, device text, call_kind text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.venue_tables;
  v public.venues;
  dev text := public.device_hash_of(device);
begin
  if call_kind not in ('staff', 'bill', 'water') then raise exception 'call for staff, the bill or water'; end if;
  select * into t from public.venue_tables where code = lower(trim(in_code)) and active;
  select * into v from public.venues where id = t.venue_id;
  if t.id is null or not v.verified or not v.table_service or not v.orders_anon then
    raise exception 'this table doesn''t take calls from phones — wave, they''ll see you';
  end if;
  if exists (select 1 from public.table_calls c where c.table_id = t.id and c.device_hash = dev and c.kind = call_kind and c.status = 'open') then
    return;
  end if;
  if (select count(*) from public.table_calls c where c.table_id = t.id and c.requested_by is null and c.created_at > now() - interval '10 minutes') >= 10 then
    raise exception 'lots of calls from this table just now — wave, they''ll see you';
  end if;
  insert into public.table_calls (venue_id, table_id, device_hash, kind) values (v.id, t.id, dev, call_kind);
end; $$;

-- ── 6. the counter's side: collected, paused ────────────────────────────────
-- Handed over: every live line on a pickup tab is served. (Paying is still close_tab.)
create or replace function public.collect_pickup(tab uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.tabs;
begin
  select * into t from public.tabs where id = tab;
  if t.id is null or t.pickup_no is null then raise exception 'that isn''t a pickup order'; end if;
  if not (public.venue_can(t.venue_id, auth.uid(), 'orders.take')
          or public.venue_can(t.venue_id, auth.uid(), 'station.bar')
          or public.venue_can(t.venue_id, auth.uid(), 'station.kitchen')) then
    raise exception 'your role can''t hand orders over here' using errcode = '42501';
  end if;
  update public.order_lines set status = 'served',
         started_at = coalesce(started_at, now()), ready_at = coalesce(ready_at, now()), served_at = now()
   where tab_id = tab and status in ('sent', 'preparing', 'ready');
  update public.tabs set collected_at = now() where id = tab;
end; $$;

create or replace function public.pause_phone_orders(vid uuid, paused boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.venue_can(vid, auth.uid(), 'orders.take')
          or public.venue_can(vid, auth.uid(), 'station.bar')
          or public.venue_can(vid, auth.uid(), 'station.kitchen')) then
    raise exception 'your role can''t pause phone orders here' using errcode = '42501';
  end if;
  update public.venues set orders_paused = coalesce(paused, false) where id = vid;
end; $$;

-- ── 7. the ready board (public, on a screen by the counter) ─────────────────
-- Numbers only: what's being made and what's ready, from the last six hours. Opened by
-- any of the venue's pickup-point codes (bwdy.site/ready/<code>).
create or replace function public.pickup_board(in_code text)
returns table (venue_name text, pickup_no int, state text, since timestamptz)
language sql stable security definer set search_path = public as $$
  select v.name, tb.pickup_no,
         case when not exists (select 1 from public.order_lines o where o.tab_id = tb.id and o.status not in ('ready', 'served', 'void'))
              then 'ready' else 'making' end,
         coalesce((select max(o.ready_at) from public.order_lines o where o.tab_id = tb.id), tb.opened_at)
    from public.venue_tables p
    join public.venues v on v.id = p.venue_id and v.verified
    join public.tabs tb on tb.venue_id = v.id
   where p.code = lower(trim(in_code)) and p.active and p.kind = 'pickup'
     and tb.pickup_no is not null and tb.collected_at is null and tb.status = 'open'
     and tb.opened_at > now() - interval '6 hours'
     and exists (select 1 from public.order_lines o where o.tab_id = tb.id and o.status <> 'void')
   order by tb.opened_at;
$$;

-- ── 8. a counter's shelf, public (so a customer can make a list) ────────────
-- What's in stock at a verified counter, at its price (never above MRP — 050). On
-- hand is derived from the ledger, as everywhere; only "in stock" is shown, not the count.
create or replace function public.store_shelf(in_slug text)
returns table (venue_name text, currency text, product_id uuid, name text, brand text, category text,
               size numeric, unit text, sold_by text, price numeric, mrp numeric, is_alcohol boolean)
language sql stable security definer set search_path = public as $$
  select v.name, v.currency, p.id, p.name, p.brand, p.category, p.size, p.unit, p.sold_by, p.price, p.mrp, p.is_alcohol
    from public.venues v
    join public.shop_products p on p.venue_id = v.id and p.active
   where v.slug = lower(trim(in_slug)) and v.verified and public.venue_is_counter(v.kind)
     and coalesce((select sum(m.qty) from public.stock_moves m where m.product_id = p.id), 0) > 0
   order by p.category, p.name;
$$;

-- ── 9. who may call what ────────────────────────────────────────────────────
do $$
declare f text;
begin
  -- Signed in only.
  foreach f in array array[
    'public.place_order(text, uuid, jsonb, text)', 'public.request_order(text, uuid, jsonb, text)', 'public.accept_request(uuid, uuid)',
    'public.my_orders()', 'public.collect_pickup(uuid)', 'public.pause_phone_orders(uuid, boolean)'
  ] loop
    execute format('revoke all on function %s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then execute format('revoke all on function %s from anon', f); end if;
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- Open to a phone without an account (each checks the venue allows it).
  foreach f in array array[
    'public.table_info(text)', 'public.place_order_guest(text, uuid, text, jsonb, text)', 'public.guest_orders(text)',
    'public.withdraw_guest_order(uuid, text)', 'public.call_table_staff_guest(text, text, text)',
    'public.pickup_board(text)', 'public.store_shelf(text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
  -- Helpers: never called from an app.
  foreach f in array array[
    'public.next_pickup_no(uuid)', 'public.check_guest_lines(public.venues, jsonb)', 'public.land_order(uuid, uuid)',
    'public.order_status_json(uuid)', 'public.place_order_inner(text, uuid, jsonb, text, uuid, text)', 'public.device_hash_of(text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then execute format('revoke all on function %s from anon', f); end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then execute format('revoke all on function %s from authenticated', f); end if;
  end loop;
end $$;
