-- ============================================================================
-- brewdiary — THE ROTA, BREAKS, AND PAYROLL.
--
-- 053 gave a venue a time clock. A venue also plans who works when, needs breaks
-- taken off the hours, fixes the times people forget, and hands hours to payroll:
--
--   1. THE ROTA. Owners and managers plan shifts week by week: who, in what role, when,
--      the planned break, an optional area and note. A shift can be left OPEN for anyone
--      on the team to pick up. A plan is a draft (theirs alone) until they PUBLISH the week;
--      then the whole team sees it. A week can be copied forward. Nobody is booked twice
--      at once, or on days they've been given off.
--   2. GIVING AWAY AND PICKING UP. Someone can offer a published shift; a teammate who can
--      work that role takes it; an owner or manager says yes before it changes hands. An
--      open shift is picked up the same way.
--   3. TIME OFF, AND DAYS SOMEONE CAN'T WORK. Ask for days off; an owner or manager approves
--      or declines. Everyone keeps the weekdays they can't work, which the rota shows to
--      whoever plans it.
--   4. BREAKS. On the clock: start and end a break — unpaid unless marked paid. Unpaid
--      breaks come off the hours. Clocking out (or being clocked out) ends a break.
--   5. CORRECTIONS. Someone forgot to clock out, or never clocked in: an owner or manager
--      corrects the times or adds the missed shift, always with a reason. The old times
--      are kept in an append-only record, so every payroll figure can be traced. Nobody
--      corrects their own times.
--   6. PAY AND PAYROLL. An hourly rate per person (owners and managers set it; each person
--      sees their own; nobody sets their own). A shift keeps the rate it was worked at.
--      payroll_days() gives, per person per day in the venue's time zone: hours worked,
--      breaks, the published plan, corrections, and pay at those rates. Overtime, tax and
--      statutory deductions stay with the payroll provider: brewdiary reports hours and
--      rates, it doesn't compute employment law.
--
-- Rules that hold throughout (025, 053): lists are in NAME order, never ranked by hours;
-- nothing records where anyone was or what they did; ledgers have no client write policy —
-- the functions below are the only way in.
--
-- Runs on top of 002..053.
-- ============================================================================

-- ── 1. what someone is paid, and the weekdays they can't work ────────────────
alter table public.staff_details add column if not exists hourly_rate numeric(10,2);
alter table public.staff_details add column if not exists cannot_work smallint[] not null default '{}';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'staff_details_hourly_rate_check') then
    alter table public.staff_details add constraint staff_details_hourly_rate_check
      check (hourly_rate is null or (hourly_rate >= 0 and hourly_rate <= 100000));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'staff_details_cannot_work_check') then
    alter table public.staff_details add constraint staff_details_cannot_work_check
      check (cannot_work <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[]);
  end if;
end $$;

-- A shift keeps the rate it was worked at: a raise next month doesn't rewrite last month.
alter table public.staff_shifts add column if not exists hourly_rate numeric(10,2);

create or replace function public.staff_shift_rate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.hourly_rate is null then
    select d.hourly_rate into new.hourly_rate from public.staff_details d
     where d.venue_id = new.venue_id and d.user_id = new.user_id;
  end if;
  return new;
end; $$;
drop trigger if exists staff_shift_rate on public.staff_shifts;
create trigger staff_shift_rate before insert on public.staff_shifts
  for each row execute function public.staff_shift_rate();

-- The team's history learns the new kinds of change.
alter table public.staff_events drop constraint if exists staff_events_kind_check;
alter table public.staff_events add constraint staff_events_kind_check check (kind in (
  'enrolled', 'code_reissued', 'enrolment_revoked', 'requested', 'joined', 'approved',
  'declined', 'role_changed', 'locked', 'unlocked', 'removed', 'left', 'details_changed',
  'shift_ended_by_manager',
  'rota_published', 'swap_decided', 'time_off_decided', 'shift_corrected', 'shift_added', 'pay_changed'));

-- ── 2. the rota ──────────────────────────────────────────────────────────────
create table if not exists public.rota_shifts (
  id            uuid primary key default gen_random_uuid(),
  venue_id      uuid not null references public.venues(id) on delete cascade,
  -- null = an OPEN shift, for anyone on the team who can work the role to pick up
  user_id       uuid references public.profiles(id) on delete set null,
  role          text not null check (role in ('owner', 'manager', 'supervisor', 'bartender', 'server', 'host', 'kitchen')),
  area_id       uuid references public.venue_areas(id) on delete set null,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  break_minutes int not null default 0 check (break_minutes between 0 and 240),
  note          text check (note is null or char_length(note) <= 200),
  -- null = a draft only the planners see
  published_at  timestamptz,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (ends_at > starts_at and ends_at - starts_at <= interval '16 hours'),
  check (break_minutes * interval '1 minute' < ends_at - starts_at)
);
create index if not exists rota_shifts_venue_idx on public.rota_shifts (venue_id, starts_at);
create index if not exists rota_shifts_user_idx on public.rota_shifts (user_id, starts_at);
alter table public.rota_shifts enable row level security;
drop policy if exists rota_shifts_read on public.rota_shifts;
create policy rota_shifts_read on public.rota_shifts for select to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'rota.edit')
         or (published_at is not null and public.is_venue_staff(venue_id, auth.uid())));
-- No write policy: rota_save_shift(), rota_delete_shift(), rota_publish(), rota_copy() and
-- the swap functions are the only ways in.

create table if not exists public.rota_swaps (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  shift_id   uuid not null references public.rota_shifts(id) on delete cascade,
  from_user  uuid references public.profiles(id) on delete cascade,   -- null: an open shift
  to_user    uuid references public.profiles(id) on delete cascade,   -- null: still on offer
  status     text not null default 'offered' check (status in ('offered', 'taken', 'approved', 'declined', 'withdrawn')),
  created_at timestamptz not null default now(),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz,
  check (status <> 'taken' or to_user is not null)
);
create unique index if not exists rota_swaps_live_idx on public.rota_swaps (shift_id) where status in ('offered', 'taken');
alter table public.rota_swaps enable row level security;
drop policy if exists rota_swaps_read on public.rota_swaps;
create policy rota_swaps_read on public.rota_swaps for select to authenticated
  using (from_user = auth.uid() or to_user = auth.uid()
         or public.venue_can(venue_id, auth.uid(), 'rota.edit')
         or (status = 'offered' and public.is_venue_staff(venue_id, auth.uid())));

-- ── 3. time off ──────────────────────────────────────────────────────────────
-- Stored as moments: the app sends the start of the first day and the start of the day
-- after the last one, in the venue's time.
create table if not exists public.time_off (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  note       text check (note is null or char_length(note) <= 200),
  status     text not null default 'requested' check (status in ('requested', 'approved', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz,
  check (ends_at > starts_at and ends_at - starts_at <= interval '62 days')
);
create index if not exists time_off_venue_idx on public.time_off (venue_id, starts_at);
alter table public.time_off enable row level security;
drop policy if exists time_off_read on public.time_off;
create policy time_off_read on public.time_off for select to authenticated
  using (user_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'rota.edit'));

-- ── 4. breaks ────────────────────────────────────────────────────────────────
create table if not exists public.shift_breaks (
  id         uuid primary key default gen_random_uuid(),
  shift_id   uuid not null references public.staff_shifts(id) on delete cascade,
  venue_id   uuid not null references public.venues(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at   timestamptz,
  paid       boolean not null default false,
  check (ended_at is null or ended_at >= started_at)
);
create unique index if not exists shift_breaks_open_idx on public.shift_breaks (shift_id) where ended_at is null;
create index if not exists shift_breaks_shift_idx on public.shift_breaks (shift_id);
alter table public.shift_breaks enable row level security;
drop policy if exists shift_breaks_read on public.shift_breaks;
create policy shift_breaks_read on public.shift_breaks for select to authenticated
  using (user_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'rota.edit'));

-- Whatever ends a shift (clocking out, a manager, a pause, a correction) ends its break.
create or replace function public.staff_shift_closed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.shift_breaks b set ended_at = greatest(b.started_at, new.ended_at)
   where b.shift_id = new.id and b.ended_at is null;
  return null;
end; $$;
drop trigger if exists staff_shift_closed on public.staff_shifts;
create trigger staff_shift_closed after update of ended_at on public.staff_shifts
  for each row when (new.ended_at is not null) execute function public.staff_shift_closed();

-- ── 5. corrections: append-only ──────────────────────────────────────────────
create table if not exists public.shift_corrections (
  id          bigint generated always as identity primary key,
  venue_id    uuid not null references public.venues(id) on delete cascade,
  shift_id    uuid not null references public.staff_shifts(id) on delete cascade,
  subject_id  uuid not null,
  actor_id    uuid,
  kind        text not null check (kind in ('corrected', 'added')),
  old_started timestamptz,
  old_ended   timestamptz,
  new_started timestamptz not null,
  new_ended   timestamptz not null,
  reason      text not null check (char_length(trim(reason)) between 3 and 200),
  created_at  timestamptz not null default now()
);
create index if not exists shift_corrections_shift_idx on public.shift_corrections (shift_id);
alter table public.shift_corrections enable row level security;
drop policy if exists shift_corrections_read on public.shift_corrections;
create policy shift_corrections_read on public.shift_corrections for select to authenticated
  using (subject_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'rota.edit'));
-- No write policy of any kind, and no function updates or deletes a row here.

-- ── 6. how long a shift was ──────────────────────────────────────────────────
-- Minutes of a shift inside [lo, hi): worked (less unpaid breaks), unpaid and paid break
-- minutes. SECURITY INVOKER: called directly it sees only what the caller may see; the
-- definer functions below call it with theirs.
create or replace function public.shift_minutes(sid uuid, lo timestamptz, hi timestamptz)
returns table (worked int, unpaid int, paid int)
language sql stable set search_path = public as $$
  with s as (
    select greatest(sh.started_at, lo) a, least(coalesce(sh.ended_at, now()), hi) b
      from public.staff_shifts sh where sh.id = sid
  ), br as (
    select b.paid, greatest(0.0, extract(epoch from (least(coalesce(b.ended_at, now()), s.b) - greatest(b.started_at, s.a))) / 60.0) m
      from public.shift_breaks b, s
     where b.shift_id = sid
  )
  select greatest(0, round(extract(epoch from (s.b - s.a)) / 60.0 - coalesce((select sum(m) from br where not br.paid), 0))::int),
         round(coalesce((select sum(m) from br where not br.paid), 0))::int,
         round(coalesce((select sum(m) from br where br.paid), 0))::int
    from s where s.b > s.a
  union all
  select 0, 0, 0 where not exists (select 1 from s where s.b > s.a);
$$;

-- ── 7. the rota's functions ──────────────────────────────────────────────────
-- Add or change a shift. [sid] is the app's id for it (a new id adds one). [uid] null
-- leaves it open.
create or replace function public.rota_save_shift(
  vid uuid, sid uuid, uid uuid, shift_role text, area uuid, starts timestamptz, ends timestamptz,
  break_min int default 0, shift_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me  uuid := auth.uid();
  id_ uuid := coalesce(sid, gen_random_uuid());
  cur public.rota_shifts;
  nt  text := nullif(trim(coalesce(shift_note, '')), '');
  bm  int := coalesce(break_min, 0);
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'rota.edit') then
    raise exception 'your role doesn''t plan the rota here' using errcode = '42501';
  end if;
  if shift_role is null or shift_role not in ('owner', 'manager', 'supervisor', 'bartender', 'server', 'host', 'kitchen') then
    raise exception 'pick a role for the shift';
  end if;
  if starts is null or ends is null or ends <= starts then raise exception 'the shift has to end after it starts'; end if;
  if ends - starts < interval '15 minutes' then raise exception 'a shift is at least 15 minutes'; end if;
  if ends - starts > interval '16 hours' then raise exception 'a shift is at most 16 hours'; end if;
  if bm < 0 or bm > 240 or bm * interval '1 minute' >= ends - starts then
    raise exception 'the break has to fit inside the shift (up to 4 hours)';
  end if;
  if nt is not null and char_length(nt) > 200 then raise exception 'keep the note under 200 letters'; end if;
  if area is not null and not exists (select 1 from public.venue_areas a where a.id = area and a.venue_id = vid) then
    raise exception 'that area isn''t at this venue';
  end if;
  select * into cur from public.rota_shifts r where r.id = id_ for update;
  if cur.id is not null and cur.venue_id <> vid then raise exception 'that shift belongs to another venue'; end if;
  if uid is not null then
    if not public.is_venue_staff(vid, uid) then raise exception 'they''re not working here right now'; end if;
    if exists (select 1 from public.rota_shifts r
                where r.venue_id = vid and r.user_id = uid and r.id <> id_ and r.starts_at < ends and r.ends_at > starts) then
      raise exception 'they''re already on the rota then';
    end if;
    if exists (select 1 from public.time_off t
                where t.venue_id = vid and t.user_id = uid and t.status = 'approved' and t.starts_at < ends and t.ends_at > starts) then
      raise exception 'they have time off then';
    end if;
  end if;
  if cur.id is not null then
    -- a new person or new times cancel anything that was on offer for the old ones
    if cur.user_id is distinct from uid or cur.starts_at <> starts or cur.ends_at <> ends then
      update public.rota_swaps w set status = 'withdrawn', decided_by = me, decided_at = now()
       where w.shift_id = id_ and w.status in ('offered', 'taken');
    end if;
    update public.rota_shifts r
       set user_id = uid, role = shift_role, area_id = area, starts_at = starts, ends_at = ends,
           break_minutes = bm, note = nt, updated_at = now()
     where r.id = id_;
  else
    insert into public.rota_shifts (id, venue_id, user_id, role, area_id, starts_at, ends_at, break_minutes, note, created_by)
    values (id_, vid, uid, shift_role, area, starts, ends, bm, nt, me);
  end if;
  return id_;
end; $$;

create or replace function public.rota_delete_shift(sid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select r.venue_id into v from public.rota_shifts r where r.id = sid;
  if v is null then return; end if;
  if not public.venue_can(v, me, 'rota.edit') then
    raise exception 'your role doesn''t plan the rota here' using errcode = '42501';
  end if;
  delete from public.rota_shifts r where r.id = sid;
end; $$;

-- Publish every draft that starts in [from_ts, to_ts): the team sees them from now on.
create or replace function public.rota_publish(vid uuid, from_ts timestamptz, to_ts timestamptz)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'rota.edit') then
    raise exception 'your role doesn''t plan the rota here' using errcode = '42501';
  end if;
  if from_ts is null or to_ts is null or to_ts <= from_ts or to_ts - from_ts > interval '35 days' then
    raise exception 'pick up to five weeks';
  end if;
  update public.rota_shifts r set published_at = now(), updated_at = now()
   where r.venue_id = vid and r.published_at is null and r.starts_at >= from_ts and r.starts_at < to_ts;
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
    values (vid, me, null, 'rota_published', jsonb_build_object('from', from_ts, 'to', to_ts, 'shifts', n));
  end if;
  return n;
end; $$;

-- Copy the shifts that start in [from_ts, to_ts) forward (or back) by [by_days] days, at
-- the same wall-clock times in the venue's time zone [tz]. Copies are drafts. Someone
-- who's no longer here, already booked, or off then leaves an OPEN shift instead; a
-- shift that's already there isn't copied twice.
create or replace function public.rota_copy(vid uuid, from_ts timestamptz, to_ts timestamptz, by_days int, tz text default 'UTC')
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); z text := tz; n int := 0; r record; ns timestamptz; ne timestamptz; who uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'rota.edit') then
    raise exception 'your role doesn''t plan the rota here' using errcode = '42501';
  end if;
  if by_days is null or by_days = 0 or abs(by_days) > 35 then raise exception 'copy by up to five weeks'; end if;
  if from_ts is null or to_ts is null or to_ts <= from_ts or to_ts - from_ts > interval '35 days' then
    raise exception 'pick up to five weeks';
  end if;
  if z is null or not exists (select 1 from pg_timezone_names t where t.name = z) then z := 'UTC'; end if;
  for r in select * from public.rota_shifts s
            where s.venue_id = vid and s.starts_at >= from_ts and s.starts_at < to_ts
            order by s.starts_at loop
    ns := ((r.starts_at at time zone z) + make_interval(days => by_days)) at time zone z;
    ne := ns + (r.ends_at - r.starts_at);
    who := r.user_id;
    if who is not null and (
         not public.is_venue_staff(vid, who)
      or exists (select 1 from public.rota_shifts x where x.venue_id = vid and x.user_id = who and x.starts_at < ne and x.ends_at > ns)
      or exists (select 1 from public.time_off t where t.venue_id = vid and t.user_id = who and t.status = 'approved'
                  and t.starts_at < ne and t.ends_at > ns)) then
      who := null;
    end if;
    if exists (select 1 from public.rota_shifts x
                where x.venue_id = vid and x.starts_at = ns and x.ends_at = ne and x.role = r.role
                  and (x.user_id is not distinct from who or x.user_id is not distinct from r.user_id)) then
      continue;
    end if;
    insert into public.rota_shifts (venue_id, user_id, role, area_id, starts_at, ends_at, break_minutes, note, created_by)
    values (vid, who, r.role, r.area_id, ns, ne, r.break_minutes, r.note, me);
    n := n + 1;
  end loop;
  return n;
end; $$;

-- The rota for [from_ts, to_ts) as the caller may see it, in one call: the shifts (drafts
-- too, for whoever plans), what's on offer, time off, and the team. Up to five weeks.
create or replace function public.rota_week(vid uuid, from_ts timestamptz, to_ts timestamptz)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); plan boolean;
begin
  if me is null or not public.is_venue_staff(vid, me) then
    raise exception 'you''re not on this team' using errcode = '42501';
  end if;
  if from_ts is null or to_ts is null or to_ts <= from_ts or to_ts - from_ts > interval '35 days' then
    raise exception 'pick up to five weeks';
  end if;
  plan := public.venue_can(vid, me, 'rota.edit');
  return jsonb_build_object(
    'can_plan', plan,
    'shifts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'user_id', r.user_id,
               'name', coalesce(d.staff_name, p.display_name, p.handle),
               'active', r.user_id is null or public.is_venue_staff(vid, r.user_id),
               'role', r.role, 'area_id', r.area_id, 'area', a.name,
               'starts_at', r.starts_at, 'ends_at', r.ends_at, 'break_minutes', r.break_minutes,
               'note', r.note, 'published', r.published_at is not null,
               'swap', (select jsonb_build_object('id', w.id, 'status', w.status, 'from_user', w.from_user,
                                                  'to_user', w.to_user,
                                                  'to_name', coalesce(td.staff_name, tp.display_name, tp.handle))
                          from public.rota_swaps w
                          left join public.profiles tp on tp.id = w.to_user
                          left join public.staff_details td on td.venue_id = w.venue_id and td.user_id = w.to_user
                         where w.shift_id = r.id and w.status in ('offered', 'taken')
                         limit 1))
             order by r.starts_at, coalesce(d.staff_name, p.display_name, p.handle))
        from public.rota_shifts r
        left join public.profiles p on p.id = r.user_id
        left join public.staff_details d on d.venue_id = r.venue_id and d.user_id = r.user_id
        left join public.venue_areas a on a.id = r.area_id
       where r.venue_id = vid and r.starts_at >= from_ts and r.starts_at < to_ts
         and (plan or r.published_at is not null)), '[]'::jsonb),
    'time_off', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'user_id', t.user_id, 'name', coalesce(d.staff_name, p.display_name, p.handle),
               'starts_at', t.starts_at, 'ends_at', t.ends_at, 'status', t.status,
               'note', case when plan or t.user_id = me then t.note end)
             order by t.starts_at)
        from public.time_off t
        left join public.profiles p on p.id = t.user_id
        left join public.staff_details d on d.venue_id = t.venue_id and d.user_id = t.user_id
       where t.venue_id = vid and t.starts_at < to_ts and t.ends_at > from_ts
         and (t.status = 'approved' or (t.status = 'requested' and (plan or t.user_id = me)))), '[]'::jsonb),
    'team', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', s.user_id, 'name', coalesce(d.staff_name, p.display_name, p.handle),
               'role', case when v.created_by = s.user_id then 'owner' else s.role end,
               'cannot_work', case when plan or s.user_id = me then to_jsonb(coalesce(d.cannot_work, '{}'::smallint[])) end)
             order by coalesce(d.staff_name, p.display_name, p.handle))
        from public.venue_staff s
        join public.venues v on v.id = s.venue_id
        join public.profiles p on p.id = s.user_id
        left join public.staff_details d on d.venue_id = s.venue_id and d.user_id = s.user_id
       where s.venue_id = vid and s.status = 'active'), '[]'::jsonb)
  );
end; $$;

-- ── 8. giving away and picking up ───────────────────────────────────────────
create or replace function public.rota_offer_shift(sid uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r public.rota_shifts; wid uuid := gen_random_uuid();
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into r from public.rota_shifts s where s.id = sid for update;
  if not found or r.user_id is distinct from me then raise exception 'that isn''t your shift'; end if;
  if not public.venue_can(r.venue_id, me, 'shift.own') then
    raise exception 'you can''t change shifts here right now' using errcode = '42501';
  end if;
  if r.published_at is null then raise exception 'that shift isn''t on the published rota yet'; end if;
  if r.starts_at <= now() then raise exception 'that shift has already started'; end if;
  if exists (select 1 from public.rota_swaps w where w.shift_id = sid and w.status in ('offered', 'taken')) then
    raise exception 'it''s already on offer';
  end if;
  insert into public.rota_swaps (id, venue_id, shift_id, from_user, status) values (wid, r.venue_id, sid, me, 'offered');
  return wid;
end; $$;

-- Ask for a shift: an open one, or one a teammate offered. A manager says yes after.
-- You can take a shift in your own role — a shift lead, manager or owner, any role.
create or replace function public.rota_take_shift(sid uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r public.rota_shifts; w public.rota_swaps; mine text; wid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into r from public.rota_shifts s where s.id = sid for update;
  if not found or r.published_at is null then raise exception 'that shift isn''t on the published rota'; end if;
  if not public.venue_can(r.venue_id, me, 'shift.own') then
    raise exception 'you can''t pick up shifts here right now' using errcode = '42501';
  end if;
  if r.starts_at <= now() then raise exception 'that shift has already started'; end if;
  if r.user_id = me then raise exception 'it''s already yours'; end if;
  mine := public.venue_role(r.venue_id, me);
  if mine is distinct from r.role and coalesce(mine, '') not in ('owner', 'manager', 'supervisor') then
    raise exception 'that''s a % shift', r.role;
  end if;
  if exists (select 1 from public.rota_shifts x
              where x.venue_id = r.venue_id and x.user_id = me and x.id <> r.id and x.starts_at < r.ends_at and x.ends_at > r.starts_at) then
    raise exception 'you''re already on the rota then';
  end if;
  if exists (select 1 from public.time_off t
              where t.venue_id = r.venue_id and t.user_id = me and t.status = 'approved' and t.starts_at < r.ends_at and t.ends_at > r.starts_at) then
    raise exception 'you have time off then';
  end if;
  select * into w from public.rota_swaps x where x.shift_id = sid and x.status in ('offered', 'taken') for update;
  if r.user_id is null then
    if found then raise exception 'someone has already asked for it'; end if;
    wid := gen_random_uuid();
    insert into public.rota_swaps (id, venue_id, shift_id, from_user, to_user, status)
    values (wid, r.venue_id, sid, null, me, 'taken');
    return wid;
  end if;
  if not found or w.status <> 'offered' then raise exception 'that shift isn''t on offer'; end if;
  update public.rota_swaps x set to_user = me, status = 'taken' where x.id = w.id;
  return w.id;
end; $$;

create or replace function public.rota_decide_swap(wid uuid, approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w public.rota_swaps; r public.rota_shifts;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into w from public.rota_swaps x where x.id = wid for update;
  if not found then raise exception 'no such request'; end if;
  if not public.venue_can(w.venue_id, me, 'rota.edit') then
    raise exception 'your role doesn''t plan the rota here' using errcode = '42501';
  end if;
  if w.status <> 'taken' then raise exception 'nobody has asked to take it yet'; end if;
  select * into r from public.rota_shifts s where s.id = w.shift_id for update;
  if coalesce(approve, false) then
    if not public.is_venue_staff(w.venue_id, w.to_user) then raise exception 'they''re not working here right now'; end if;
    if exists (select 1 from public.rota_shifts x
                where x.venue_id = r.venue_id and x.user_id = w.to_user and x.id <> r.id
                  and x.starts_at < r.ends_at and x.ends_at > r.starts_at) then
      raise exception 'they''re already on the rota then';
    end if;
    if exists (select 1 from public.time_off t
                where t.venue_id = r.venue_id and t.user_id = w.to_user and t.status = 'approved'
                  and t.starts_at < r.ends_at and t.ends_at > r.starts_at) then
      raise exception 'they have time off then';
    end if;
    update public.rota_shifts s set user_id = w.to_user, updated_at = now() where s.id = r.id;
    update public.rota_swaps x set status = 'approved', decided_by = me, decided_at = now() where x.id = wid;
  else
    update public.rota_swaps x set status = 'declined', decided_by = me, decided_at = now() where x.id = wid;
  end if;
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (w.venue_id, me, w.to_user, 'swap_decided',
          jsonb_build_object('approved', coalesce(approve, false), 'role', r.role, 'shift_start', r.starts_at,
                             'open', w.from_user is null));
end; $$;

-- The person who offered a shift takes the offer back; the person who asked for one
-- takes their ask back (a teammate's offer goes back on offer).
create or replace function public.rota_withdraw_swap(wid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w public.rota_swaps;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into w from public.rota_swaps x where x.id = wid for update;
  if not found then raise exception 'no such request'; end if;
  if w.status not in ('offered', 'taken') then return; end if;
  if me = w.from_user then
    update public.rota_swaps x set status = 'withdrawn', decided_at = now() where x.id = wid;
  elsif me = w.to_user then
    if w.from_user is null then
      update public.rota_swaps x set status = 'withdrawn', decided_at = now() where x.id = wid;
    else
      update public.rota_swaps x set to_user = null, status = 'offered' where x.id = wid;
    end if;
  else
    raise exception 'that isn''t yours to take back' using errcode = '42501';
  end if;
end; $$;

-- Someone who leaves the team leaves their future shifts OPEN, and their offers and asks go.
create or replace function public.venue_staff_left_rota()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.rota_shifts r set user_id = null, updated_at = now()
   where r.venue_id = old.venue_id and r.user_id = old.user_id and r.starts_at > now();
  update public.rota_swaps w set status = 'withdrawn', decided_at = now()
   where w.venue_id = old.venue_id and w.status in ('offered', 'taken') and (w.from_user = old.user_id or w.to_user = old.user_id);
  return null;
end; $$;
drop trigger if exists venue_staff_left_rota on public.venue_staff;
create trigger venue_staff_left_rota after delete on public.venue_staff
  for each row execute function public.venue_staff_left_rota();

-- ── 9. time off, and the days someone can't work ─────────────────────────────
create or replace function public.request_time_off(vid uuid, from_ts timestamptz, to_ts timestamptz, why text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); tid uuid := gen_random_uuid(); nt text := nullif(trim(coalesce(why, '')), '');
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'shift.own') then
    raise exception 'you can''t ask for time off here right now' using errcode = '42501';
  end if;
  if from_ts is null or to_ts is null or to_ts <= from_ts then raise exception 'pick the first and last day'; end if;
  if to_ts - from_ts > interval '62 days' then raise exception 'ask for up to 62 days at a time'; end if;
  if to_ts <= now() then raise exception 'those days have gone'; end if;
  if nt is not null and char_length(nt) > 200 then raise exception 'keep the note under 200 letters'; end if;
  if exists (select 1 from public.time_off t
              where t.venue_id = vid and t.user_id = me and t.status in ('requested', 'approved')
                and t.starts_at < to_ts and t.ends_at > from_ts) then
    raise exception 'you''ve already asked for some of those days';
  end if;
  insert into public.time_off (id, venue_id, user_id, starts_at, ends_at, note) values (tid, vid, me, from_ts, to_ts, nt);
  return tid;
end; $$;

create or replace function public.decide_time_off(tid uuid, approve boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t public.time_off; their text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into t from public.time_off x where x.id = tid for update;
  if not found then raise exception 'no such request'; end if;
  if t.user_id = me then raise exception 'nobody approves their own time off'; end if;
  their := (select s.role from public.venue_staff s where s.venue_id = t.venue_id and s.user_id = t.user_id);
  if not public.venue_can(t.venue_id, me, 'rota.edit')
     or (their is not null and not public.can_grant_role(t.venue_id, me, their)) then
    raise exception 'your role can''t answer that request' using errcode = '42501';
  end if;
  if t.status <> 'requested' then raise exception 'that request has already been answered'; end if;
  update public.time_off x
     set status = case when coalesce(approve, false) then 'approved' else 'declined' end,
         decided_by = me, decided_at = now()
   where x.id = tid;
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (t.venue_id, me, t.user_id, 'time_off_decided',
          jsonb_build_object('approved', coalesce(approve, false), 'from', t.starts_at, 'to', t.ends_at));
end; $$;

create or replace function public.cancel_time_off(tid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t public.time_off;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into t from public.time_off x where x.id = tid for update;
  if not found or t.user_id <> me then raise exception 'that isn''t your request'; end if;
  if t.status not in ('requested', 'approved') then return; end if;
  if t.ends_at <= now() then raise exception 'those days have gone'; end if;
  update public.time_off x set status = 'cancelled', decided_at = now() where x.id = tid;
end; $$;

-- Your own requests; whoever plans the rota sees the team's (waiting, and the last month).
create or replace function public.time_off_list(vid uuid)
returns table (id uuid, user_id uuid, name text, starts_at timestamptz, ends_at timestamptz, note text,
               status text, decided_by text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); plan boolean;
begin
  if me is null or not public.is_venue_staff(vid, me) then
    raise exception 'you''re not on this team' using errcode = '42501';
  end if;
  plan := public.venue_can(vid, me, 'rota.edit');
  return query
  select t.id, t.user_id, coalesce(d.staff_name, p.display_name, p.handle), t.starts_at, t.ends_at, t.note, t.status,
         coalesce(dd.staff_name, dp.display_name, dp.handle), t.created_at
    from public.time_off t
    left join public.profiles p on p.id = t.user_id
    left join public.staff_details d on d.venue_id = t.venue_id and d.user_id = t.user_id
    left join public.profiles dp on dp.id = t.decided_by
    left join public.staff_details dd on dd.venue_id = t.venue_id and dd.user_id = t.decided_by
   where t.venue_id = vid and (t.user_id = me or plan)
     and (t.status = 'requested' or t.ends_at > now() - interval '30 days')
   order by case t.status when 'requested' then 0 else 1 end, t.starts_at;
end; $$;

-- The weekdays you can't work (0 = Sunday … 6 = Saturday), for whoever plans the rota.
create or replace function public.set_cannot_work(vid uuid, days smallint[])
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); clean smallint[];
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_venue_staff(vid, me) then raise exception 'you''re not on this team' using errcode = '42501'; end if;
  select coalesce(array_agg(distinct x order by x), '{}') into clean from unnest(coalesce(days, '{}')) x;
  if not clean <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[] then raise exception 'days are 0 (Sunday) to 6 (Saturday)'; end if;
  insert into public.staff_details (venue_id, user_id, cannot_work) values (vid, me, clean)
  on conflict (venue_id, user_id) do update set cannot_work = excluded.cannot_work, updated_at = now();
end; $$;

-- ── 10. breaks ───────────────────────────────────────────────────────────────
create or replace function public.start_break(vid uuid, paid boolean default false)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); sid uuid; since timestamptz;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'shift.own') then
    raise exception 'you can''t do that here right now' using errcode = '42501';
  end if;
  select sh.id into sid from public.staff_shifts sh where sh.venue_id = vid and sh.user_id = me and sh.ended_at is null;
  if sid is null then raise exception 'you''re not clocked in'; end if;
  if exists (select 1 from public.shift_breaks b where b.shift_id = sid and b.ended_at is null) then
    raise exception 'you''re already on a break';
  end if;
  insert into public.shift_breaks (shift_id, venue_id, user_id, paid) values (sid, vid, me, coalesce(paid, false))
  returning started_at into since;
  return since;
end; $$;

create or replace function public.end_break(vid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b public.shift_breaks;
begin
  if me is null then raise exception 'not signed in'; end if;
  select x.* into b from public.shift_breaks x
    join public.staff_shifts sh on sh.id = x.shift_id
   where sh.venue_id = vid and sh.user_id = me and sh.ended_at is null and x.ended_at is null
   for update of x;
  if not found then raise exception 'you''re not on a break'; end if;
  update public.shift_breaks x set ended_at = now() where x.id = b.id;
  return greatest(0, round(extract(epoch from (now() - b.started_at)) / 60))::int;
end; $$;

-- Where I stand on the clock here: on since, on a break since (and whether it's paid), and
-- unpaid break minutes so far this shift.
create or replace function public.my_shift_state(vid uuid)
returns table (on_since timestamptz, break_since timestamptz, break_paid boolean, break_minutes int)
language sql stable security definer set search_path = public as $$
  select sh.started_at,
         (select b.started_at from public.shift_breaks b where b.shift_id = sh.id and b.ended_at is null),
         (select b.paid from public.shift_breaks b where b.shift_id = sh.id and b.ended_at is null),
         coalesce((select round(sum(extract(epoch from (coalesce(b.ended_at, now()) - b.started_at))) / 60)::int
                     from public.shift_breaks b where b.shift_id = sh.id and not b.paid), 0)
    from public.staff_shifts sh
   where sh.venue_id = vid and sh.user_id = auth.uid() and sh.ended_at is null;
$$;

-- Hours per person since [since]: worked minutes are after unpaid breaks. Still listed by
-- NAME, never ranked (053's rule).
drop function if exists public.shift_hours(uuid, timestamptz);
create function public.shift_hours(vid uuid, since timestamptz)
returns table (user_id uuid, name text, role text, on_since timestamptz, minutes int, break_minutes int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); everyone boolean; lo timestamptz := greatest(coalesce(since, now() - interval '7 days'), now() - interval '93 days');
begin
  if me is null then raise exception 'not signed in'; end if;
  everyone := public.venue_can(vid, me, 'rota.edit');
  if not everyone and not public.is_venue_staff(vid, me) then
    raise exception 'you''re not on this team' using errcode = '42501';
  end if;
  return query
  select s.user_id,
         coalesce(d.staff_name, p.display_name, p.handle),
         s.role,
         (select sh.started_at from public.staff_shifts sh
           where sh.venue_id = vid and sh.user_id = s.user_id and sh.ended_at is null),
         coalesce((select sum(m.worked)::int from public.staff_shifts sh
                    cross join lateral public.shift_minutes(sh.id, lo, now()) m
                   where sh.venue_id = vid and sh.user_id = s.user_id and coalesce(sh.ended_at, now()) > lo), 0),
         coalesce((select sum(m.unpaid)::int from public.staff_shifts sh
                    cross join lateral public.shift_minutes(sh.id, lo, now()) m
                   where sh.venue_id = vid and sh.user_id = s.user_id and coalesce(sh.ended_at, now()) > lo), 0)
    from public.venue_staff s
    join public.profiles p on p.id = s.user_id
    left join public.staff_details d on d.venue_id = s.venue_id and d.user_id = s.user_id
   where s.venue_id = vid and (everyone or s.user_id = me)
   order by 2;
end; $$;

-- ── 11. the timesheet, and corrections ───────────────────────────────────────
-- One person's shifts that started in [from_ts, to_ts), with breaks and every correction.
-- Whoever plans the rota sees anyone's; everyone sees their own.
create or replace function public.staff_timesheet(vid uuid, uid uuid, from_ts timestamptz, to_ts timestamptz)
returns table (shift_id uuid, started_at timestamptz, ended_at timestamptz, worked_minutes int,
               unpaid_break_minutes int, paid_break_minutes int, corrections jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if uid is distinct from me and not public.venue_can(vid, me, 'rota.edit') then
    raise exception 'your role doesn''t see other people''s timesheets' using errcode = '42501';
  end if;
  if from_ts is null or to_ts is null or to_ts <= from_ts or to_ts - from_ts > interval '93 days' then
    raise exception 'pick up to 93 days';
  end if;
  return query
  select sh.id, sh.started_at, sh.ended_at, m.worked, m.unpaid, m.paid,
         coalesce((select jsonb_agg(jsonb_build_object(
                            'kind', c.kind, 'reason', c.reason, 'at', c.created_at,
                            'by', coalesce(ad.staff_name, ap.display_name, ap.handle),
                            'old_started', c.old_started, 'old_ended', c.old_ended,
                            'new_started', c.new_started, 'new_ended', c.new_ended)
                          order by c.created_at)
                     from public.shift_corrections c
                     left join public.profiles ap on ap.id = c.actor_id
                     left join public.staff_details ad on ad.venue_id = c.venue_id and ad.user_id = c.actor_id
                    where c.shift_id = sh.id), '[]'::jsonb)
    from public.staff_shifts sh
    cross join lateral public.shift_minutes(sh.id, sh.started_at, coalesce(sh.ended_at, now())) m
   where sh.venue_id = vid and sh.user_id = uid and sh.started_at >= from_ts and sh.started_at < to_ts
   order by sh.started_at;
end; $$;

-- Who may correct someone's times: whoever plans the rota and could grant their role —
-- never their own.
create or replace function public.can_correct_times(vid uuid, me uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select me is not null and uid is distinct from me
     and public.venue_can(vid, me, 'rota.edit')
     and coalesce(public.can_grant_role(vid, me,
           (select s.role from public.venue_staff s where s.venue_id = vid and s.user_id = uid)), true);
$$;

create or replace function public.correct_shift(sid uuid, new_start timestamptz, new_end timestamptz, reason text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); sh public.staff_shifts; why text := trim(coalesce(reason, ''));
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into sh from public.staff_shifts x where x.id = sid for update;
  if not found then raise exception 'no such shift'; end if;
  if sh.user_id = me then raise exception 'nobody corrects their own times — ask an owner or manager'; end if;
  if not public.can_correct_times(sh.venue_id, me, sh.user_id) then
    raise exception 'your role can''t correct their times' using errcode = '42501';
  end if;
  if char_length(why) < 3 or char_length(why) > 200 then raise exception 'say why (3 to 200 letters)'; end if;
  if new_start is null or new_end is null or new_end <= new_start then raise exception 'the shift has to end after it starts'; end if;
  if new_end - new_start > interval '24 hours' then raise exception 'a shift is at most 24 hours'; end if;
  if new_end > now() + interval '5 minutes' then raise exception 'a shift can''t end in the future'; end if;
  if exists (select 1 from public.staff_shifts x
              where x.venue_id = sh.venue_id and x.user_id = sh.user_id and x.id <> sid
                and x.started_at < new_end and coalesce(x.ended_at, now()) > new_start) then
    raise exception 'that overlaps another of their shifts';
  end if;
  insert into public.shift_corrections (venue_id, shift_id, subject_id, actor_id, kind, old_started, old_ended,
                                        new_started, new_ended, reason)
  values (sh.venue_id, sid, sh.user_id, me, 'corrected', sh.started_at, sh.ended_at, new_start, new_end, why);
  update public.staff_shifts x set started_at = new_start, ended_at = new_end, ended_by = coalesce(x.ended_by, me)
   where x.id = sid;
  -- breaks stay inside the corrected shift
  delete from public.shift_breaks b
   where b.shift_id = sid and (b.started_at >= new_end or coalesce(b.ended_at, new_end) <= new_start);
  update public.shift_breaks b
     set started_at = greatest(b.started_at, new_start), ended_at = least(coalesce(b.ended_at, new_end), new_end)
   where b.shift_id = sid;
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (sh.venue_id, me, sh.user_id, 'shift_corrected', jsonb_build_object('reason', why, 'shift_start', new_start));
end; $$;

-- A shift someone worked but never clocked: added by an owner or manager, with a reason.
create or replace function public.add_missed_shift(vid uuid, uid uuid, starts timestamptz, ends timestamptz,
                                                   break_min int default 0, reason text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); sid uuid := gen_random_uuid(); why text := trim(coalesce(reason, '')); bm int := coalesce(break_min, 0); bs timestamptz;
begin
  if me is null then raise exception 'not signed in'; end if;
  if uid is null or uid = me then raise exception 'nobody adds hours for themself — ask an owner or manager'; end if;
  if not exists (select 1 from public.venue_staff s where s.venue_id = vid and s.user_id = uid) then
    raise exception 'they''re not on this team';
  end if;
  if not public.can_correct_times(vid, me, uid) then
    raise exception 'your role can''t add their hours' using errcode = '42501';
  end if;
  if char_length(why) < 3 or char_length(why) > 200 then raise exception 'say why (3 to 200 letters)'; end if;
  if starts is null or ends is null or ends <= starts then raise exception 'the shift has to end after it starts'; end if;
  if ends - starts > interval '24 hours' then raise exception 'a shift is at most 24 hours'; end if;
  if ends > now() + interval '5 minutes' then raise exception 'a shift can''t end in the future'; end if;
  if bm < 0 or bm * interval '1 minute' >= ends - starts then raise exception 'the break has to fit inside the shift'; end if;
  if exists (select 1 from public.staff_shifts x
              where x.venue_id = vid and x.user_id = uid and x.started_at < ends and coalesce(x.ended_at, now()) > starts) then
    raise exception 'that overlaps another of their shifts';
  end if;
  insert into public.staff_shifts (id, venue_id, user_id, started_at, ended_at, ended_by) values (sid, vid, uid, starts, ends, me);
  if bm > 0 then
    bs := starts + ((ends - starts) - bm * interval '1 minute') / 2;
    insert into public.shift_breaks (shift_id, venue_id, user_id, started_at, ended_at, paid)
    values (sid, vid, uid, bs, bs + bm * interval '1 minute', false);
  end if;
  insert into public.shift_corrections (venue_id, shift_id, subject_id, actor_id, kind, new_started, new_ended, reason)
  values (vid, sid, uid, me, 'added', starts, ends, why);
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (vid, me, uid, 'shift_added', jsonb_build_object('reason', why, 'shift_start', starts));
  return sid;
end; $$;

-- ── 12. pay ──────────────────────────────────────────────────────────────────
-- An owner sets anyone's rate but their own; a manager, the floor's. Nobody sets their own.
create or replace function public.set_staff_pay(vid uuid, uid uuid, rate numeric)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); their text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if uid = me then raise exception 'nobody sets their own pay'; end if;
  their := (select s.role from public.venue_staff s where s.venue_id = vid and s.user_id = uid);
  if their is null then raise exception 'they''re not on this team'; end if;
  if not public.venue_can(vid, me, 'team.manage') or not public.can_grant_role(vid, me, their) then
    raise exception 'your role can''t set a %''s pay', their using errcode = '42501';
  end if;
  if rate is not null and (rate < 0 or rate > 100000) then raise exception 'the rate is 0 to 1,00,000 an hour'; end if;
  insert into public.staff_details (venue_id, user_id, hourly_rate) values (vid, uid, round(rate, 2))
  on conflict (venue_id, user_id) do update set hourly_rate = excluded.hourly_rate, updated_at = now();
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (vid, me, uid, 'pay_changed', '{}'::jsonb);   -- never the amount
end; $$;

-- Rates: owners and managers see the team's; everyone else, their own.
create or replace function public.pay_rates(vid uuid)
returns table (user_id uuid, hourly_rate numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); all_ boolean;
begin
  if me is null or not public.is_venue_staff(vid, me) then
    raise exception 'you''re not on this team' using errcode = '42501';
  end if;
  all_ := public.venue_can(vid, me, 'team.manage');
  return query
  select s.user_id, d.hourly_rate
    from public.venue_staff s
    left join public.staff_details d on d.venue_id = s.venue_id and d.user_id = s.user_id
   where s.venue_id = vid and (all_ or s.user_id = me);
end; $$;

-- ── 13. payroll ──────────────────────────────────────────────────────────────
-- Per person per day ([from_day, to_day], in the venue's time zone [tz]) — for owners and
-- managers. A shift counts on the day it started (a night past midnight is one night).
-- Pay is each shift's minutes at the rate it was worked at. Includes people who have since
-- left (they still get paid), and days someone was on the published rota but didn't clock
-- in (planned_minutes > 0, worked 0). In NAME order.
create or replace function public.payroll_days(vid uuid, from_day date, to_day date, tz text default 'UTC')
returns table (user_id uuid, name text, role text, day date, shifts int, first_in text, last_out text,
               worked_minutes int, unpaid_break_minutes int, paid_break_minutes int, planned_minutes int,
               still_on boolean, corrected boolean, hourly_rate numeric, pay numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); z text := tz; lo timestamptz; hi timestamptz;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'team.manage') then
    raise exception 'your role doesn''t run payroll here' using errcode = '42501';
  end if;
  if from_day is null or to_day is null or to_day < from_day or to_day - from_day > 62 then
    raise exception 'pick up to 62 days';
  end if;
  if z is null or not exists (select 1 from pg_timezone_names n where n.name = z) then z := 'UTC'; end if;
  lo := from_day::timestamp at time zone z;
  hi := (to_day + 1)::timestamp at time zone z;
  return query
  with w as (
    select sh.user_id uid, (sh.started_at at time zone z)::date d, count(*)::int n,
           to_char(min(sh.started_at) at time zone z, 'HH24:MI') fi,
           to_char(max(sh.ended_at) at time zone z, 'HH24:MI') lo_,
           bool_or(sh.ended_at is null) open_,
           sum(m.worked)::int wm, sum(m.unpaid)::int ub, sum(m.paid)::int pb,
           bool_or(exists (select 1 from public.shift_corrections c where c.shift_id = sh.id)) corr,
           max(coalesce(sh.hourly_rate, d2.hourly_rate)) rate,
           round(sum(m.worked * coalesce(sh.hourly_rate, d2.hourly_rate)) / 60.0, 2) pay_
      from public.staff_shifts sh
      cross join lateral public.shift_minutes(sh.id, sh.started_at, coalesce(sh.ended_at, now())) m
      left join public.staff_details d2 on d2.venue_id = sh.venue_id and d2.user_id = sh.user_id
     where sh.venue_id = vid and sh.started_at >= lo and sh.started_at < hi
     group by 1, 2
  ), p as (
    select r.user_id uid, (r.starts_at at time zone z)::date d,
           sum(round(extract(epoch from (r.ends_at - r.starts_at)) / 60.0)::int - r.break_minutes)::int pm
      from public.rota_shifts r
     where r.venue_id = vid and r.user_id is not null and r.published_at is not null
       and r.starts_at >= lo and r.starts_at < hi
     group by 1, 2
  ), x as (
    select coalesce(w.uid, p.uid) uid, coalesce(w.d, p.d) d, w.n, w.fi, w.lo_, w.wm, w.ub, w.pb, p.pm, w.open_, w.corr,
           w.rate, w.pay_
      from w full join p on p.uid = w.uid and p.d = w.d
  )
  select x.uid,
         coalesce(sd.staff_name, pr.display_name, pr.handle, 'someone'),
         coalesce(case when v.created_by = x.uid then 'owner' end, vs.role, 'left'),
         x.d, coalesce(x.n, 0), x.fi, x.lo_, coalesce(x.wm, 0), coalesce(x.ub, 0), coalesce(x.pb, 0), coalesce(x.pm, 0),
         coalesce(x.open_, false), coalesce(x.corr, false), coalesce(x.rate, sd.hourly_rate), x.pay_
    from x
    join public.venues v on v.id = vid
    left join public.profiles pr on pr.id = x.uid
    left join public.venue_staff vs on vs.venue_id = vid and vs.user_id = x.uid
    left join public.staff_details sd on sd.venue_id = vid and sd.user_id = x.uid
   order by 2, 4;
end; $$;

-- ── 14. who may call what ────────────────────────────────────────────────────
do $$
declare f text;
begin
  foreach f in array array[
    'public.rota_save_shift(uuid, uuid, uuid, text, uuid, timestamptz, timestamptz, int, text)',
    'public.rota_delete_shift(uuid)', 'public.rota_publish(uuid, timestamptz, timestamptz)',
    'public.rota_copy(uuid, timestamptz, timestamptz, int, text)', 'public.rota_week(uuid, timestamptz, timestamptz)',
    'public.rota_offer_shift(uuid)', 'public.rota_take_shift(uuid)', 'public.rota_decide_swap(uuid, boolean)',
    'public.rota_withdraw_swap(uuid)', 'public.request_time_off(uuid, timestamptz, timestamptz, text)',
    'public.decide_time_off(uuid, boolean)', 'public.cancel_time_off(uuid)', 'public.time_off_list(uuid)',
    'public.set_cannot_work(uuid, smallint[])', 'public.start_break(uuid, boolean)', 'public.end_break(uuid)',
    'public.my_shift_state(uuid)', 'public.shift_hours(uuid, timestamptz)',
    'public.staff_timesheet(uuid, uuid, timestamptz, timestamptz)',
    'public.correct_shift(uuid, timestamptz, timestamptz, text)',
    'public.add_missed_shift(uuid, uuid, timestamptz, timestamptz, int, text)',
    'public.set_staff_pay(uuid, uuid, numeric)', 'public.pay_rates(uuid)',
    'public.payroll_days(uuid, date, date, text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- Helpers and triggers: never called from an app. (Supabase's default privileges grant
  -- anon and authenticated every new function, so they're named here too.)
  foreach f in array array[
    'public.shift_minutes(uuid, timestamptz, timestamptz)', 'public.can_correct_times(uuid, uuid, uuid)',
    'public.staff_shift_rate()', 'public.staff_shift_closed()', 'public.venue_staff_left_rota()'
  ] loop
    execute format('revoke all on function %s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then execute format('revoke all on function %s from anon', f); end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then execute format('revoke all on function %s from authenticated', f); end if;
  end loop;
end $$;
