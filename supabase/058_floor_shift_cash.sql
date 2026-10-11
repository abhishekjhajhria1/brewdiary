-- ============================================================================
-- brewdiary — THE FLOOR IN MOTION, THE STATIONS' TOOLS, THE SHIFT'S NOTES, THE
-- CASH DRAWER, BOOKINGS, AND SPEC CARDS.
--
-- 051 gave a venue tables, tabs, tickets and a bill. A real night moves around, and
-- every bar, restaurant and café POS handles these:
--
--   1. MOVING THINGS ON THE FLOOR. A party moves to another table (or to the bar); two
--      tabs become one; some lines move to another tab — which is also how a bill is
--      split BY ITEM: open a second check, move the lines, settle each; a table is handed
--      to another server at shift change. Nothing is deleted: a merged tab is kept,
--      marked 'merged', pointing at the tab that took its lines.
--   2. THE STATIONS. A line marked ready by mistake goes back to making (recall). A
--      bartender or the kitchen can 86 an item the moment it runs out (menu.86), and
--      bring it back.
--   3. SPEC CARDS. A menu item can carry its spec — the recipe, glass, garnish, method —
--      for the team. Staff-only: venue_menu() (what guests read) never returns it.
--   4. THE SHIFT'S NOTES. A pre-shift note from a supervisor or manager ("the walk-in is
--      off, push the paneer", "big party at 9") that everyone on the team marks seen; and
--      a manager's log book for the next manager (what broke, who called, what's owed).
--      Who has seen a pre-shift note is shown to supervisors and managers, never as a
--      ranking.
--   5. THE CASH DRAWER. Open it with a float; pay-ins, pay-outs and drops with a reason;
--      close it with a BLIND count: the person counting types what is in the drawer
--      before the app shows what should be there. The close keeps a report that can't be
--      changed afterwards (expected, counted, the difference, takings by how they were
--      paid). brewdiary still takes and checks no payment: "cash" is whatever the staff
--      wrote as cash when they settled a bill or rang a sale.
--   6. BOOKINGS. A booking by name for a time, a party size, optionally a table and a
--      phone number. The phone number is forgotten the day after; the name a month after
--      (the booking then reads "Party of 4"), so the venue keeps its no-show numbers and
--      not a contact list.
--
-- Rules that hold throughout: functions are the only way into anything that touches
-- money (no client write policy on tabs, lines, payments, drawers or cash moves); every
-- action checks the caller's capability (045) at THIS venue; nothing here records a
-- guest or ranks a member of staff.
--
-- Runs on top of 002..057.
-- ============================================================================

-- ── 1. moving things on the floor ───────────────────────────────────────────
alter table public.tabs add column if not exists server_id uuid references public.profiles(id) on delete set null;
alter table public.tabs add column if not exists merged_into uuid references public.tabs(id) on delete set null;
alter table public.tabs drop constraint if exists tabs_status_check;
alter table public.tabs add constraint tabs_status_check check (status in ('open', 'closed', 'void', 'merged'));
update public.tabs set server_id = opened_by where server_id is null and status = 'open';

-- Whoever opens a tab is its server until it's handed on.
create or replace function public.tabs_server_default()
returns trigger language plpgsql set search_path = public as $$
begin
  new.server_id := coalesce(new.server_id, new.opened_by);
  return new;
end; $$;
drop trigger if exists tabs_server_default on public.tabs;
create trigger tabs_server_default before insert on public.tabs for each row execute function public.tabs_server_default();

-- Move a tab to another table — or to the bar, which needs a name for it.
create or replace function public.move_tab(tab uuid, to_table uuid default null, new_name text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.tabs;
begin
  select * into t from public.tabs where id = tab;
  if t.id is null or not public.venue_can(t.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t move a tab here' using errcode = '42501';
  end if;
  if t.status <> 'open' then raise exception 'that tab is %', t.status; end if;
  if to_table is not null then
    if not exists (select 1 from public.venue_tables x where x.id = to_table and x.venue_id = t.venue_id and x.active) then
      raise exception 'that table isn''t this venue''s';
    end if;
    if to_table = t.table_id then return; end if;
    update public.tabs set table_id = to_table where id = tab;
  else
    if char_length(trim(coalesce(new_name, ''))) = 0 then
      raise exception 'a tab at the bar needs a name (Bar 3, the birthday…)';
    end if;
    update public.tabs set table_id = null, name = left(trim(new_name), 40) where id = tab;
  end if;
end; $$;

-- Two tabs become one: every line moves to [into_tab]; [from_tab] is kept, marked merged.
create or replace function public.merge_tabs(from_tab uuid, into_tab uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  a public.tabs;
  b public.tabs;
begin
  select * into a from public.tabs where id = from_tab;
  select * into b from public.tabs where id = into_tab;
  if a.id is null or b.id is null or not public.venue_can(b.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t merge tabs here' using errcode = '42501';
  end if;
  if a.venue_id <> b.venue_id then raise exception 'those tabs are at different venues'; end if;
  if a.id = b.id then raise exception 'pick a different tab to merge with'; end if;
  if a.status <> 'open' or b.status <> 'open' then raise exception 'both tabs need to be open'; end if;
  update public.order_lines set tab_id = b.id where tab_id = a.id;
  update public.tabs set covers = case when a.covers is null and b.covers is null then null
                                        else least(coalesce(a.covers, 0) + coalesce(b.covers, 0), 99) end
   where id = b.id;
  update public.tabs set status = 'merged', merged_into = b.id, closed_by = auth.uid(), closed_at = now(), subtotal = 0
   where id = a.id;
end; $$;

-- Move some lines to another open tab at the same venue (a seat moving over, or a bill
-- split by item). Void lines stay where they were.
create or replace function public.move_lines(line_ids uuid[], to_tab uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  b public.tabs;
  n int;
begin
  select * into b from public.tabs where id = to_tab;
  if b.id is null or not public.venue_can(b.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t move lines here' using errcode = '42501';
  end if;
  if b.status <> 'open' then raise exception 'that tab is %', b.status; end if;
  if line_ids is null or cardinality(line_ids) = 0 or cardinality(line_ids) > 40 then
    raise exception 'move 1 to 40 lines at a time';
  end if;
  if exists (
    select 1 from public.order_lines o join public.tabs t on t.id = o.tab_id
     where o.id = any(line_ids) and (o.venue_id <> b.venue_id or t.status <> 'open' or o.status = 'void')
  ) then
    raise exception 'only lines on an open tab here can move (not voided ones)';
  end if;
  update public.order_lines set tab_id = b.id where id = any(line_ids) and tab_id <> b.id;
  get diagnostics n = row_count;
  return n;
end; $$;

-- Hand a tab to another server (shift change, a section swap).
create or replace function public.assign_tab(tab uuid, to_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.tabs;
begin
  select * into t from public.tabs where id = tab;
  if t.id is null or not public.venue_can(t.venue_id, auth.uid(), 'orders.take') then
    raise exception 'your role can''t hand over a tab here' using errcode = '42501';
  end if;
  if t.status <> 'open' then raise exception 'that tab is %', t.status; end if;
  if not public.venue_can(t.venue_id, to_user, 'orders.take') then
    raise exception 'they can''t take orders here';
  end if;
  update public.tabs set server_id = to_user where id = tab;
end; $$;

-- ── 2. the stations: recall, 86 ─────────────────────────────────────────────
-- A line marked ready by mistake goes back to making.
create or replace function public.recall_line(line uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  o public.order_lines;
  ok boolean;
begin
  select * into o from public.order_lines where id = line;
  if o.id is null then raise exception 'no such line'; end if;
  ok := case
    when o.station = 'bar' then public.venue_can(o.venue_id, auth.uid(), 'station.bar')
    when o.station = 'kitchen' then public.venue_can(o.venue_id, auth.uid(), 'station.kitchen')
    else public.venue_can(o.venue_id, auth.uid(), 'orders.take') end;
  if not ok then raise exception 'your role can''t recall this line' using errcode = '42501'; end if;
  if o.status <> 'ready' then raise exception 'only a ready line can go back to making'; end if;
  if exists (select 1 from public.tabs t where t.id = o.tab_id and t.status <> 'open') then raise exception 'that tab is closed'; end if;
  update public.order_lines set status = 'preparing', ready_at = null where id = line;
end; $$;

-- 86 an item (it ran out) or bring it back. The bar and the kitchen can, not just managers.
create or replace function public.set_item_off(item uuid, is_off boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.venue_menu_items;
begin
  select * into m from public.venue_menu_items where id = item;
  if m.id is null or not (public.venue_can(m.venue_id, auth.uid(), 'menu.86') or public.venue_can(m.venue_id, auth.uid(), 'menu.edit')
                          or public.venue_can(m.venue_id, auth.uid(), 'station.bar') or public.venue_can(m.venue_id, auth.uid(), 'station.kitchen')) then
    raise exception 'your role can''t 86 items here' using errcode = '42501';
  end if;
  update public.venue_menu_items set available = not is_off where id = item;
end; $$;

-- ── 3. spec cards (staff-only) ──────────────────────────────────────────────
alter table public.venue_menu_items add column if not exists spec text check (spec is null or char_length(spec) <= 1500);

-- ── 4. the shift's notes ────────────────────────────────────────────────────
create table if not exists public.venue_notes (
  id         uuid primary key,                                 -- client-made: a retry can't post twice
  venue_id   uuid not null references public.venues(id) on delete cascade,
  kind       text not null check (kind in ('preshift', 'log')),
  body       text not null check (char_length(trim(body)) between 1 and 1000),
  author_id  uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  shown_until timestamptz                                      -- a pre-shift note's end; null for the log
);
create index if not exists venue_notes_venue_idx on public.venue_notes (venue_id, kind, created_at desc);

create table if not exists public.venue_note_reads (
  note_id uuid not null references public.venue_notes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (note_id, user_id)
);

alter table public.venue_notes enable row level security;
alter table public.venue_note_reads enable row level security;
drop policy if exists venue_notes_read on public.venue_notes;
create policy venue_notes_read on public.venue_notes for select to authenticated using (
  (kind = 'preshift' and public.is_venue_staff(venue_id, auth.uid()))
  or (kind = 'log' and public.venue_can(venue_id, auth.uid(), 'orders.approve'))
);
drop policy if exists venue_note_reads_read on public.venue_note_reads;
create policy venue_note_reads_read on public.venue_note_reads for select to authenticated using (
  user_id = auth.uid()
  or exists (select 1 from public.venue_notes n where n.id = note_id and public.venue_can(n.venue_id, auth.uid(), 'orders.approve'))
);
-- No write policies: the functions below only.

-- Post a note. Pre-shift notes show for [for_hours] (default: the rest of the night).
create or replace function public.post_note(vid uuid, note uuid, note_kind text, note_body text, for_hours int default 18)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.venue_can(vid, auth.uid(), 'orders.approve') then
    raise exception 'a supervisor or manager posts the shift''s notes' using errcode = '42501';
  end if;
  if note_kind not in ('preshift', 'log') then raise exception 'a note is a pre-shift note or a log entry'; end if;
  if char_length(trim(coalesce(note_body, ''))) = 0 then raise exception 'write something first'; end if;
  if exists (select 1 from public.venue_notes n where n.id = note) then return; end if;   -- a retry
  insert into public.venue_notes (id, venue_id, kind, body, author_id, shown_until)
  values (note, vid, note_kind, left(trim(note_body), 1000), auth.uid(),
          case when note_kind = 'preshift' then now() + make_interval(hours => greatest(1, least(coalesce(for_hours, 18), 72))) end);
  if note_kind = 'preshift' then
    insert into public.venue_note_reads (note_id, user_id) values (note, auth.uid()) on conflict do nothing;   -- you've seen your own
  end if;
end; $$;

-- Take a pre-shift note down early (it stays in the record).
create or replace function public.end_note(note uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  n public.venue_notes;
begin
  select * into n from public.venue_notes where id = note;
  if n.id is null or not public.venue_can(n.venue_id, auth.uid(), 'orders.approve') then
    raise exception 'a supervisor or manager takes a note down' using errcode = '42501';
  end if;
  if n.kind <> 'preshift' then raise exception 'the log book keeps every entry'; end if;
  update public.venue_notes set shown_until = least(coalesce(shown_until, now()), now()) where id = note;
end; $$;

-- "Got it" on a pre-shift note.
create or replace function public.mark_note_seen(note uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  n public.venue_notes;
begin
  select * into n from public.venue_notes where id = note;
  if n.id is null or n.kind <> 'preshift' or not public.is_venue_staff(n.venue_id, auth.uid()) then
    raise exception 'no such note here';
  end if;
  insert into public.venue_note_reads (note_id, user_id) values (note, auth.uid()) on conflict do nothing;
end; $$;

-- What's on the board: live pre-shift notes (with who's seen them, for supervisors and
-- managers — by name, in name order, never ranked) and, for them, the last 30 log entries.
create or replace function public.shift_notes(vid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  lead boolean := public.venue_can(vid, auth.uid(), 'orders.approve');
begin
  if not public.is_venue_staff(vid, auth.uid()) then
    raise exception 'not your venue' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'preshift', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', n.id, 'body', n.body, 'created_at', n.created_at, 'shown_until', n.shown_until,
        'author', coalesce(p.display_name, 'someone'),
        'seen_by_me', exists (select 1 from public.venue_note_reads r where r.note_id = n.id and r.user_id = auth.uid()),
        'seen_by', case when lead then coalesce((
            select jsonb_agg(coalesce(pp.display_name, 'someone') order by lower(coalesce(pp.display_name, '')))
              from public.venue_note_reads r join public.profiles pp on pp.id = r.user_id
             where r.note_id = n.id and r.user_id is distinct from n.author_id), '[]'::jsonb) end
      ) order by n.created_at desc)
        from public.venue_notes n left join public.profiles p on p.id = n.author_id
       where n.venue_id = vid and n.kind = 'preshift' and n.shown_until > now()), '[]'::jsonb),
    'log', case when lead then coalesce((
      select jsonb_agg(x.j order by x.created_at desc) from (
        select n.created_at, jsonb_build_object('id', n.id, 'body', n.body, 'created_at', n.created_at,
                                                'author', coalesce(p.display_name, 'someone')) j
          from public.venue_notes n left join public.profiles p on p.id = n.author_id
         where n.venue_id = vid and n.kind = 'log'
         order by n.created_at desc limit 30) x), '[]'::jsonb) else '[]'::jsonb end
  );
end; $$;

-- ── 5. the cash drawer ──────────────────────────────────────────────────────
create table if not exists public.cash_sessions (
  id         uuid primary key,                                 -- client-made
  venue_id   uuid not null references public.venues(id) on delete cascade,
  label      text not null default 'Drawer' check (char_length(trim(label)) between 1 and 40),
  status     text not null default 'open' check (status in ('open', 'closed')),
  opening_float numeric(12, 2) not null check (opening_float >= 0),
  opened_by  uuid references public.profiles(id) on delete set null,
  opened_at  timestamptz not null default now(),
  closed_by  uuid references public.profiles(id) on delete set null,
  closed_at  timestamptz,
  counted    numeric(12, 2) check (counted is null or counted >= 0),
  expected   numeric(12, 2),
  report     jsonb,                                            -- the close, kept as it was
  note       text check (note is null or char_length(note) <= 200)
);
-- One drawer open at a time per venue (cash takings are counted against it).
create unique index if not exists cash_sessions_one_open on public.cash_sessions (venue_id) where status = 'open';
create index if not exists cash_sessions_venue_idx on public.cash_sessions (venue_id, opened_at desc);

create table if not exists public.cash_moves (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.cash_sessions(id) on delete cascade,
  venue_id   uuid not null references public.venues(id) on delete cascade,
  kind       text not null check (kind in ('pay_in', 'pay_out', 'drop')),
  amount     numeric(12, 2) not null check (amount > 0),
  reason     text not null check (char_length(trim(reason)) between 3 and 120),
  made_by    uuid references public.profiles(id) on delete set null,
  made_at    timestamptz not null default now()
);
create index if not exists cash_moves_session_idx on public.cash_moves (session_id, made_at);

alter table public.cash_sessions enable row level security;
alter table public.cash_moves enable row level security;
-- Reading the drawers is for whoever closes a day; everyone else goes through
-- drawer_state(), which hides the expected figure until they've counted.
drop policy if exists cash_sessions_read on public.cash_sessions;
create policy cash_sessions_read on public.cash_sessions for select to authenticated using (public.venue_can(venue_id, auth.uid(), 'cash.close_day'));
drop policy if exists cash_moves_read on public.cash_moves;
create policy cash_moves_read on public.cash_moves for select to authenticated using (public.venue_can(venue_id, auth.uid(), 'cash.close_day'));
-- No write policies: the functions below only.

-- What the drawer should hold right now (helper; not callable from an app).
create or replace function public.cash_expected(sid uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select s.opening_float
       + coalesce((select sum(m.amount) from public.cash_moves m where m.session_id = s.id and m.kind = 'pay_in'), 0)
       - coalesce((select sum(m.amount) from public.cash_moves m where m.session_id = s.id and m.kind in ('pay_out', 'drop')), 0)
       + coalesce((select sum(p.amount) from public.tab_payments p
                    where p.venue_id = s.venue_id and lower(trim(p.method)) = 'cash'
                      and p.created_at >= s.opened_at and p.created_at <= coalesce(s.closed_at, now())), 0)
       + coalesce((select sum(x.total) from public.shop_sales x
                    where x.venue_id = s.venue_id and x.paid_by = 'cash'
                      and x.created_at >= s.opened_at and x.created_at <= coalesce(s.closed_at, now())), 0)
    from public.cash_sessions s where s.id = sid;
$$;

create or replace function public.open_drawer(vid uuid, sid uuid, float_amount numeric, drawer_label text default 'Drawer')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.venue_can(vid, auth.uid(), 'cash.own') then
    raise exception 'your role doesn''t handle the cash here' using errcode = '42501';
  end if;
  if exists (select 1 from public.cash_sessions s where s.id = sid) then return; end if;   -- a retry
  if float_amount is null or float_amount < 0 or float_amount > 10000000 then raise exception 'check the float'; end if;
  if exists (select 1 from public.cash_sessions s where s.venue_id = vid and s.status = 'open') then
    raise exception 'a drawer is already open — close it first';
  end if;
  insert into public.cash_sessions (id, venue_id, label, opening_float, opened_by)
  values (sid, vid, left(coalesce(nullif(trim(drawer_label), ''), 'Drawer'), 40), float_amount, auth.uid());
end; $$;

-- Money in or out of the drawer that isn't a sale. A pay-out (paying the ice man from
-- the till) is for whoever can close a day; a pay-in or a drop, anyone on the cash.
create or replace function public.cash_move(sid uuid, move_kind text, amt numeric, why text)
returns void language plpgsql security definer set search_path = public as $$
declare
  s public.cash_sessions;
begin
  select * into s from public.cash_sessions where id = sid;
  if s.id is null or not public.venue_can(s.venue_id, auth.uid(), 'cash.own') then
    raise exception 'your role doesn''t handle the cash here' using errcode = '42501';
  end if;
  if s.status <> 'open' then raise exception 'that drawer is closed'; end if;
  if move_kind not in ('pay_in', 'pay_out', 'drop') then raise exception 'a pay-in, a pay-out or a drop'; end if;
  if move_kind = 'pay_out' and not public.venue_can(s.venue_id, auth.uid(), 'cash.close_day') then
    raise exception 'a supervisor or manager pays out from the drawer' using errcode = '42501';
  end if;
  if amt is null or amt <= 0 or amt > 10000000 then raise exception 'check the amount'; end if;
  if char_length(trim(coalesce(why, ''))) < 3 then raise exception 'say what it was for'; end if;
  insert into public.cash_moves (session_id, venue_id, kind, amount, reason, made_by)
  values (sid, s.venue_id, move_kind, amt, left(trim(why), 120), auth.uid());
end; $$;

-- The open drawer and the last closes. The expected figure only for whoever closes a
-- day: the person counting their own drawer sees it after they've counted.
create or replace function public.drawer_state(vid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  lead boolean := public.venue_can(vid, auth.uid(), 'cash.close_day');
  s public.cash_sessions;
begin
  if not public.venue_can(vid, auth.uid(), 'cash.own') then
    raise exception 'your role doesn''t handle the cash here' using errcode = '42501';
  end if;
  select * into s from public.cash_sessions x where x.venue_id = vid and x.status = 'open';
  return jsonb_build_object(
    'open', case when s.id is null then null else jsonb_build_object(
      'id', s.id, 'label', s.label, 'float', s.opening_float, 'opened_at', s.opened_at,
      'opened_by', (select coalesce(p.display_name, 'someone') from public.profiles p where p.id = s.opened_by),
      'mine', s.opened_by = auth.uid(),
      'expected', case when lead then public.cash_expected(s.id) end,
      'moves', coalesce((select jsonb_agg(jsonb_build_object('kind', m.kind, 'amount', m.amount, 'reason', m.reason, 'made_at', m.made_at,
                                                             'by', (select coalesce(p.display_name, 'someone') from public.profiles p where p.id = m.made_by))
                                          order by m.made_at)
                           from public.cash_moves m where m.session_id = s.id), '[]'::jsonb)
    ) end,
    'closed', case when lead then coalesce((
      select jsonb_agg(x.j order by x.closed_at desc) from (
        select c.closed_at, jsonb_build_object('id', c.id, 'label', c.label, 'opened_at', c.opened_at, 'closed_at', c.closed_at,
                 'closed_by', (select coalesce(p.display_name, 'someone') from public.profiles p where p.id = c.closed_by),
                 'report', c.report, 'note', c.note) j
          from public.cash_sessions c where c.venue_id = vid and c.status = 'closed'
         order by c.closed_at desc limit 14) x), '[]'::jsonb) else '[]'::jsonb end
  );
end; $$;

-- Close the drawer with a blind count. Returns the report it keeps (expected, counted,
-- the difference, and the takings since it opened). Your own drawer, or any drawer if
-- you close the day.
create or replace function public.close_drawer(sid uuid, counted_amount numeric, close_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s public.cash_sessions;
  expected_cash numeric(12, 2);
  rep jsonb;
  t_end timestamptz := now();
begin
  select * into s from public.cash_sessions where id = sid for update;
  if s.id is null or not (
       public.venue_can(s.venue_id, auth.uid(), 'cash.close_day')
       or (s.opened_by = auth.uid() and public.venue_can(s.venue_id, auth.uid(), 'cash.own'))) then
    raise exception 'a supervisor or manager closes this drawer' using errcode = '42501';
  end if;
  if s.status <> 'open' then raise exception 'that drawer is already closed'; end if;
  if counted_amount is null or counted_amount < 0 or counted_amount > 10000000 then raise exception 'check the count'; end if;
  expected_cash := public.cash_expected(sid);
  rep := jsonb_build_object(
    'float', s.opening_float,
    'expected', expected_cash,
    'counted', counted_amount,
    'difference', counted_amount - expected_cash,
    'pay_ins', coalesce((select sum(m.amount) from public.cash_moves m where m.session_id = sid and m.kind = 'pay_in'), 0),
    'pay_outs', coalesce((select sum(m.amount) from public.cash_moves m where m.session_id = sid and m.kind = 'pay_out'), 0),
    'drops', coalesce((select sum(m.amount) from public.cash_moves m where m.session_id = sid and m.kind = 'drop'), 0),
    'bills', (select count(*) from public.tabs t where t.venue_id = s.venue_id and t.status = 'closed' and t.closed_at >= s.opened_at and t.closed_at <= t_end),
    'sales', coalesce((select sum(t.subtotal) from public.tabs t where t.venue_id = s.venue_id and t.status = 'closed' and t.closed_at >= s.opened_at and t.closed_at <= t_end), 0)
           + coalesce((select sum(x.total) from public.shop_sales x where x.venue_id = s.venue_id and x.created_at >= s.opened_at and x.created_at <= t_end), 0),
    'tips', coalesce((select sum(t.tip) from public.tabs t where t.venue_id = s.venue_id and t.status = 'closed' and t.closed_at >= s.opened_at and t.closed_at <= t_end), 0),
    'voids', (select count(*) from public.order_lines o where o.venue_id = s.venue_id and o.status = 'void' and o.created_at >= s.opened_at and o.created_at <= t_end),
    'by_method', coalesce((select jsonb_object_agg(m.method, m.total) from (
                   select lower(trim(p.method)) method, sum(p.amount) total from public.tab_payments p
                    where p.venue_id = s.venue_id and p.created_at >= s.opened_at and p.created_at <= t_end group by 1
                   union all
                   select 'till · ' || x.paid_by, sum(x.total) from public.shop_sales x
                    where x.venue_id = s.venue_id and x.created_at >= s.opened_at and x.created_at <= t_end group by x.paid_by) m), '{}'::jsonb)
  );
  update public.cash_sessions set status = 'closed', closed_by = auth.uid(), closed_at = t_end, counted = counted_amount,
         expected = expected_cash, report = rep, note = nullif(left(trim(coalesce(close_note, '')), 200), '')
   where id = sid;
  return rep;
end; $$;

-- ── 6. bookings ─────────────────────────────────────────────────────────────
create table if not exists public.reservations (
  id         uuid primary key,                                 -- client-made
  venue_id   uuid not null references public.venues(id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 40),
  party      int not null check (party between 1 and 99),
  starts_at  timestamptz not null,
  minutes    int not null default 90 check (minutes between 15 and 480),
  table_id   uuid references public.venue_tables(id) on delete set null,
  phone      text check (phone is null or phone ~ '^[0-9+() -]{6,20}$'),
  note       text check (note is null or char_length(note) <= 160),
  status     text not null default 'booked' check (status in ('booked', 'arrived', 'seated', 'no_show', 'cancelled')),
  tab_id     uuid references public.tabs(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists reservations_venue_idx on public.reservations (venue_id, starts_at);

alter table public.reservations enable row level security;
drop policy if exists reservations_read on public.reservations;
create policy reservations_read on public.reservations for select to authenticated using (public.venue_can(venue_id, auth.uid(), 'floor.view'));
drop policy if exists reservations_write on public.reservations;
create policy reservations_write on public.reservations for insert to authenticated with check (public.venue_can(venue_id, auth.uid(), 'guests.seat'));
drop policy if exists reservations_update on public.reservations;
create policy reservations_update on public.reservations for update to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'guests.seat')) with check (public.venue_can(venue_id, auth.uid(), 'guests.seat'));
-- No delete: a booking is cancelled, so the no-show numbers stay true.

-- Keep it sane, keep the table this venue's, and forget contact details on schedule.
create or replace function public.reservations_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' and (new.starts_at < now() - interval '1 day' or new.starts_at > now() + interval '366 days') then
    raise exception 'a booking is for today or a day within the year';
  end if;
  if new.table_id is not null and not exists (select 1 from public.venue_tables t where t.id = new.table_id and t.venue_id = new.venue_id) then
    raise exception 'that table isn''t this venue''s';
  end if;
  if new.tab_id is not null and not exists (select 1 from public.tabs t where t.id = new.tab_id and t.venue_id = new.venue_id) then
    raise exception 'that tab isn''t this venue''s';
  end if;
  new.name := trim(new.name);
  new.phone := nullif(trim(coalesce(new.phone, '')), '');
  return new;
end; $$;
drop trigger if exists reservations_guard on public.reservations;
create trigger reservations_guard before insert or update on public.reservations for each row execute function public.reservations_guard();

create or replace function public.reservations_forget()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.reservations set phone = null
   where venue_id = new.venue_id and phone is not null and starts_at < now() - interval '1 day';
  update public.reservations set name = 'Party of ' || party, note = null
   where venue_id = new.venue_id and starts_at < now() - interval '30 days' and name not like 'Party of %';
  return null;
end; $$;
drop trigger if exists reservations_forget on public.reservations;
create trigger reservations_forget after insert on public.reservations for each row execute function public.reservations_forget();

-- ── grants ──────────────────────────────────────────────────────────────────
do $$
declare f text;
begin
  foreach f in array array[
    'public.move_tab(uuid, uuid, text)', 'public.merge_tabs(uuid, uuid)', 'public.move_lines(uuid[], uuid)',
    'public.assign_tab(uuid, uuid)', 'public.recall_line(uuid)', 'public.set_item_off(uuid, boolean)',
    'public.post_note(uuid, uuid, text, text, int)', 'public.end_note(uuid)', 'public.mark_note_seen(uuid)',
    'public.shift_notes(uuid)', 'public.open_drawer(uuid, uuid, numeric, text)', 'public.cash_move(uuid, text, numeric, text)',
    'public.drawer_state(uuid)', 'public.close_drawer(uuid, numeric, text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- Helpers and triggers: never called from an app.
  foreach f in array array[
    'public.cash_expected(uuid)', 'public.tabs_server_default()', 'public.reservations_guard()', 'public.reservations_forget()'
  ] loop
    execute format('revoke all on function %s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then execute format('revoke all on function %s from anon', f); end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then execute format('revoke all on function %s from authenticated', f); end if;
  end loop;
end $$;
