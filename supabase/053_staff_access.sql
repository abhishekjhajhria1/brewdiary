-- ============================================================================
-- brewdiary — STAFF ACCESS: adding employees, the owner's code, approvals,
-- lock-out, the team's history, and the time clock.
--
-- Until now a person joined a team the moment they typed an invite code, and the only
-- way to stop someone was to remove them. A venue needs more than that:
--
--   1. ADDING AN EMPLOYEE. An owner or manager adds a person with their name, their email
--      and (optionally) a phone number, and picks the role. brewdiary makes a 6-digit code,
--      shown to that manager ONCE. The employee signs in to the venue app with their own
--      email — the first factor: the emailed sign-in code proves the address is theirs —
--      sees "The Amber Room added you as a server", and types the manager's code — the
--      second factor: the owner vouching, in person. Only then are they on the team, with
--      the role the manager chose. This is now the ONLY way on to a team besides an invite a
--      manager approves: nobody can be inserted straight onto a roster by @handle any more.
--        • The code is stored HASHED (salted with the enrolment's id) and can never be
--          read back: the table has no read policy at all. 48 hours to live, 5 tries, one use.
--        • It only works for the email it was made for, so a leaked code is useless.
--        • A wrong try is COUNTED, not raised: the function returns a result instead of an
--          error, because an exception would roll the counter back with it.
--   2. INVITE CODES NOW WAIT FOR A YES. accept_staff_invite() (045) added the person at
--      once. A shared code can travel further than meant, so it now puts them on the
--      roster as PENDING, with no powers at all, until an owner or manager approves them.
--   3. LOCK-OUT. An owner or manager can pause someone's access at any moment, with a
--      reason and the person to report to. It is enforced where every permission is
--      decided — venue_role(), is_venue_staff() and is_venue_manager() now count ACTIVE
--      staff only — so every screen, table and function stops at once, with no list of
--      places to remember. The paused person can still read their OWN roster row and
--      details (to see why, and who to go to) and nothing else. Locking also clocks them
--      out. Who may lock whom follows can_grant_role(): an owner anyone, a manager the
--      floor; nobody locks the owner, and nobody locks themself.
--   4. THE TEAM'S HISTORY. Every change to the roster — joined, asked, approved, declined,
--      role changed, locked, unlocked, removed, left — is written by a TRIGGER on
--      venue_staff, so no path (the venue app, the website, a function) can skip it.
--      Owners and managers read the venue's history; each person reads their own.
--   5. THE TIME CLOCK. Clock in, clock out; a manager sees who's on and the hours, and can
--      clock out someone who forgot. For pay and fairness only: hours are listed by name,
--      never ranked, and nothing records where anyone is or what they did (025's rule for
--      kudos holds here too — never a league table of staff).
--   6. THE VENUE'S OWN DETAILS for a team member (the name they go by, a phone number to
--      reach them) live in staff_details: readable by owners/managers and by the person
--      themself, never by the rest of the team.
--
-- Runs on top of 002..052.
-- ============================================================================

-- ── 1. a team member's state ────────────────────────────────────────────────
-- Everyone already on a team stays exactly as they were: 'active'.
alter table public.venue_staff add column if not exists status text not null default 'active';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'venue_staff_status_check') then
    alter table public.venue_staff add constraint venue_staff_status_check
      check (status in ('pending', 'active', 'locked'));
  end if;
end $$;

-- ── 2. the three questions every permission asks: ACTIVE staff only ──────────
create or replace function public.is_venue_staff(vid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.venue_staff s
                 where s.venue_id = vid and s.user_id = uid and s.status = 'active');
$$;

create or replace function public.is_venue_manager(vid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.venue_staff s
                 where s.venue_id = vid and s.user_id = uid and s.role in ('owner', 'manager') and s.status = 'active')
      or exists (select 1 from public.venues v where v.id = vid and v.created_by = uid);
$$;

-- The creator is the owner whatever their staff row says, and can't be paused.
create or replace function public.venue_role(vid uuid, uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.venues v where v.id = vid and v.created_by = uid) then 'owner'
    else (select s.role from public.venue_staff s
           where s.venue_id = vid and s.user_id = uid and s.status = 'active')
  end;
$$;

-- The roster: the team reads it, and anyone reads their OWN row (a paused or waiting
-- person needs to see where they stand).
drop policy if exists venue_staff_read on public.venue_staff;
create policy venue_staff_read on public.venue_staff for select to authenticated
  using (user_id = auth.uid() or public.is_venue_staff(venue_id, auth.uid()));

-- Nobody is put on a team from outside any more. 045 let an owner or manager insert any
-- account straight in, found by @handle: pick the wrong handle and a stranger was on the
-- floor with a bartender's powers, having agreed to nothing. Now the only rows a client
-- may insert are the creator's own owner row (createVenue); everyone else comes in through
-- the owner's code (claim_staff_enrolment) or an invite a manager then approves
-- (accept_staff_invite → approve_staff) — both functions, both logged.
drop policy if exists venue_staff_insert on public.venue_staff;
create policy venue_staff_insert on public.venue_staff for insert to authenticated
  with check (
    user_id = auth.uid() and role = 'owner' and status = 'active'
    and exists (select 1 from public.venues v where v.id = venue_id and v.created_by = auth.uid())
  );

-- ── 3. the venue's own details for a team member ────────────────────────────
create table if not exists public.staff_details (
  venue_id    uuid not null,
  user_id     uuid not null,
  staff_name  text check (staff_name is null or char_length(trim(staff_name)) between 1 and 60),
  phone       text check (phone is null or phone ~ '^\+?[0-9 ()-]{6,20}$'),
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  locked_by   uuid references public.profiles(id) on delete set null,
  locked_at   timestamptz,
  lock_reason text check (lock_reason is null or char_length(lock_reason) <= 200),
  report_to   uuid references public.profiles(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (venue_id, user_id),
  foreign key (venue_id, user_id) references public.venue_staff (venue_id, user_id) on delete cascade
);
alter table public.staff_details enable row level security;
drop policy if exists staff_details_read on public.staff_details;
create policy staff_details_read on public.staff_details for select to authenticated
  using (user_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'team.manage'));
-- No write policy: set_staff_details(), claim_staff_enrolment(), approve_staff() and
-- lock_staff() are the only ways in.

-- ── 4. the team's history ────────────────────────────────────────────────────
-- actor_id / subject_id carry no foreign key on purpose: the history outlives accounts
-- (a person who deleted theirs leaves an id, never a name).
create table if not exists public.staff_events (
  id         bigint generated always as identity primary key,
  venue_id   uuid not null references public.venues(id) on delete cascade,
  actor_id   uuid,
  subject_id uuid,
  kind       text not null check (kind in (
               'enrolled', 'code_reissued', 'enrolment_revoked', 'requested', 'joined', 'approved',
               'declined', 'role_changed', 'locked', 'unlocked', 'removed', 'left', 'details_changed',
               'shift_ended_by_manager')),
  detail     jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists staff_events_venue_idx on public.staff_events (venue_id, created_at desc);
create index if not exists staff_events_subject_idx on public.staff_events (subject_id, created_at desc);
alter table public.staff_events enable row level security;
drop policy if exists staff_events_read on public.staff_events;
create policy staff_events_read on public.staff_events for select to authenticated
  using (subject_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'audit.view'));
-- No write policy: the trigger below and the functions in this file write it.

-- Every roster change, from any path. A function that knows more says so through two
-- transaction-local settings (how they joined; why they were paused) and clears them.
create or replace function public.venue_staff_log()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  via  text := nullif(current_setting('brewdiary.staff_via', true), '');
  note text := nullif(current_setting('brewdiary.staff_note', true), '');
  me   uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
    values (new.venue_id, me, new.user_id,
            case when new.status = 'pending' then 'requested' else 'joined' end,
            jsonb_build_object('role', new.role,
                               'via', coalesce(via, case when new.user_id = me then 'created' else 'added' end)));
  elsif tg_op = 'UPDATE' then
    if new.role is distinct from old.role then
      insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
      values (new.venue_id, me, new.user_id, 'role_changed', jsonb_build_object('from', old.role, 'to', new.role));
    end if;
    if new.status is distinct from old.status then
      insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
      values (new.venue_id, me, new.user_id,
              case
                when new.status = 'locked' then 'locked'
                when old.status = 'locked' then 'unlocked'
                when via = 'code' then 'joined'
                else 'approved'
              end,
              jsonb_strip_nulls(jsonb_build_object('role', new.role, 'via', via,
                                                   'reason', case when new.status = 'locked' then note end)));
    end if;
  else
    -- A venue being deleted takes its history with it: nothing to write.
    if exists (select 1 from public.venues v where v.id = old.venue_id) then
      insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
      values (old.venue_id, me, old.user_id,
              case when via = 'declined' then 'declined' when old.user_id = me then 'left' else 'removed' end,
              jsonb_build_object('role', old.role, 'status', old.status));
    end if;
  end if;
  return null;
end; $$;
revoke all on function public.venue_staff_log() from public;
drop trigger if exists venue_staff_log on public.venue_staff;
create trigger venue_staff_log after insert or update or delete on public.venue_staff
  for each row execute function public.venue_staff_log();

-- ── 5. the time clock ────────────────────────────────────────────────────────
create table if not exists public.staff_shifts (
  id         uuid primary key default gen_random_uuid(),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at   timestamptz,
  ended_by   uuid references public.profiles(id) on delete set null,
  check (ended_at is null or ended_at >= started_at)
);
create unique index if not exists staff_shifts_open_idx on public.staff_shifts (venue_id, user_id) where ended_at is null;
create index if not exists staff_shifts_venue_idx on public.staff_shifts (venue_id, started_at desc);
alter table public.staff_shifts enable row level security;
drop policy if exists staff_shifts_read on public.staff_shifts;
create policy staff_shifts_read on public.staff_shifts for select to authenticated
  using (user_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'rota.edit'));
-- No write policy: clock_in(), clock_out(), end_staff_shift() and lock_staff() only.

create or replace function public.clock_in(vid uuid)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); since timestamptz;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'shift.own') then
    raise exception 'you can''t clock in here right now' using errcode = '42501';
  end if;
  select sh.started_at into since from public.staff_shifts sh
   where sh.venue_id = vid and sh.user_id = me and sh.ended_at is null;
  if since is not null then return since; end if;   -- already on: a second tap changes nothing
  insert into public.staff_shifts (venue_id, user_id) values (vid, me) returning started_at into since;
  return since;
end; $$;

create or replace function public.clock_out(vid uuid)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); done timestamptz;
begin
  if me is null then raise exception 'not signed in'; end if;
  update public.staff_shifts sh set ended_at = now(), ended_by = me
   where sh.venue_id = vid and sh.user_id = me and sh.ended_at is null
  returning sh.ended_at into done;
  if done is null then raise exception 'you''re not clocked in'; end if;
  return done;
end; $$;

-- A manager clocks out someone who forgot. Written to the history, so it's never silent.
create or replace function public.end_staff_shift(vid uuid, uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'rota.edit') then
    raise exception 'your role doesn''t manage shifts here' using errcode = '42501';
  end if;
  update public.staff_shifts sh set ended_at = now(), ended_by = me
   where sh.venue_id = vid and sh.user_id = uid and sh.ended_at is null;
  if not found then raise exception 'they''re not clocked in'; end if;
  insert into public.staff_events (venue_id, actor_id, subject_id, kind) values (vid, me, uid, 'shift_ended_by_manager');
end; $$;

create or replace function public.my_shift(vid uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  select sh.started_at from public.staff_shifts sh
   where sh.venue_id = vid and sh.user_id = auth.uid() and sh.ended_at is null;
$$;

-- Minutes worked per person since [since] (the app sends the start of the week; at most
-- 93 days back). A manager sees the team, anyone else themself. Listed by NAME — this is
-- for pay, never a ranking.
create or replace function public.shift_hours(vid uuid, since timestamptz)
returns table (user_id uuid, name text, role text, on_since timestamptz, minutes int)
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
         coalesce((select (sum(extract(epoch from (coalesce(sh.ended_at, now()) - greatest(sh.started_at, lo)))) / 60)::int
                     from public.staff_shifts sh
                    where sh.venue_id = vid and sh.user_id = s.user_id and coalesce(sh.ended_at, now()) > lo), 0)
    from public.venue_staff s
    join public.profiles p on p.id = s.user_id
    left join public.staff_details d on d.venue_id = s.venue_id and d.user_id = s.user_id
   where s.venue_id = vid and (everyone or s.user_id = me)
   order by 2;
end; $$;

-- ── 6. adding an employee: the owner's code ─────────────────────────────────
create table if not exists public.staff_enrolments (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  role        text not null check (role in ('manager', 'supervisor', 'bartender', 'server', 'host', 'kitchen')),
  staff_name  text not null check (char_length(trim(staff_name)) between 1 and 60),
  email       text not null check (email = lower(email) and char_length(email) <= 254
                                   and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  phone       text check (phone is null or phone ~ '^\+?[0-9 ()-]{6,20}$'),
  code_hash   text not null,
  attempts    int not null default 0 check (attempts between 0 and 5),
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  used_by     uuid references public.profiles(id) on delete set null,
  used_at     timestamptz,
  revoked_at  timestamptz
);
create index if not exists staff_enrolments_venue_idx on public.staff_enrolments (venue_id, created_at desc);
create index if not exists staff_enrolments_open_idx on public.staff_enrolments (email)
  where used_at is null and revoked_at is null;
alter table public.staff_enrolments enable row level security;
-- NO policies at all: nobody reads or writes this table directly, so a code's hash never
-- leaves the database. The functions below are the only way in.

-- sha256 is core Postgres (11+); salting with the enrolment's id makes every hash unique.
create or replace function public.staff_code_hash(eid uuid, code text)
returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(eid::text || ':' || code, 'UTF8')), 'hex');
$$;
revoke all on function public.staff_code_hash(uuid, text) from public;

-- Six digits from the random bytes of a v4 uuid (bytes 0..3 carry no version bits).
-- In Postgres every bitwise operator shares one precedence, so each shift is bracketed.
create or replace function public.staff_new_code()
returns text language plpgsql volatile set search_path = public as $$
declare b bytea := uuid_send(gen_random_uuid());
begin
  return lpad((((get_byte(b, 0)::bigint << 24) | (get_byte(b, 1)::bigint << 16)
               | (get_byte(b, 2)::bigint << 8) | get_byte(b, 3)::bigint) % 1000000)::text, 6, '0');
end; $$;
revoke all on function public.staff_new_code() from public;

-- Add an employee. Returns the code ONCE — it's never stored in the clear.
create or replace function public.enrol_staff(vid uuid, full_name text, email_addr text, phone_no text, staff_role text)
returns table (enrolment_id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  me  uuid := auth.uid();
  eid uuid := gen_random_uuid();
  c   text := public.staff_new_code();
  em  text := lower(trim(coalesce(email_addr, '')));
  nm  text := trim(coalesce(full_name, ''));
  ph  text := nullif(trim(coalesce(phone_no, '')), '');
  ttl timestamptz := now() + interval '48 hours';
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'team.manage') or not public.can_grant_role(vid, me, staff_role) then
    raise exception 'your role can''t add someone as %', coalesce(staff_role, 'that') using errcode = '42501';
  end if;
  if char_length(nm) not between 1 and 60 then raise exception 'add their name (up to 60 letters)'; end if;
  if char_length(em) > 254 or em !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'that email doesn''t look right';
  end if;
  if ph is not null and ph !~ '^\+?[0-9 ()-]{6,20}$' then raise exception 'that phone number doesn''t look right'; end if;
  if exists (select 1 from public.venue_staff s join auth.users u on u.id = s.user_id
              where s.venue_id = vid and lower(u.email) = em) then
    raise exception 'someone with that email is already on this team';
  end if;
  -- One open code per person per venue: a new one retires the last.
  update public.staff_enrolments e set revoked_at = now()
   where e.venue_id = vid and e.email = em and e.used_at is null and e.revoked_at is null;
  insert into public.staff_enrolments (id, venue_id, role, staff_name, email, phone, code_hash, created_by, expires_at)
  values (eid, vid, staff_role, nm, em, ph, public.staff_code_hash(eid, c), me, ttl);
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (vid, me, null, 'enrolled', jsonb_build_object('enrolment', eid, 'role', staff_role));
  return query select eid, c, ttl;
end; $$;

-- A new code for someone who lost theirs, or let it run out. The old one stops working.
create or replace function public.reissue_staff_code(eid uuid)
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); e public.staff_enrolments; c text := public.staff_new_code(); ttl timestamptz := now() + interval '48 hours';
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into e from public.staff_enrolments x where x.id = eid for update;
  if not found or e.used_at is not null or e.revoked_at is not null then
    raise exception 'that code is closed — add them again';
  end if;
  if not public.venue_can(e.venue_id, me, 'team.manage') or not public.can_grant_role(e.venue_id, me, e.role) then
    raise exception 'your role can''t do that' using errcode = '42501';
  end if;
  update public.staff_enrolments x set code_hash = public.staff_code_hash(eid, c), attempts = 0, expires_at = ttl
   where x.id = eid;
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (e.venue_id, me, null, 'code_reissued', jsonb_build_object('enrolment', eid, 'role', e.role));
  return query select c, ttl;
end; $$;

create or replace function public.revoke_staff_enrolment(eid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); e public.staff_enrolments;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into e from public.staff_enrolments x where x.id = eid for update;
  if not found then raise exception 'no such code'; end if;
  if not public.venue_can(e.venue_id, me, 'team.manage') or not public.can_grant_role(e.venue_id, me, e.role) then
    raise exception 'your role can''t do that' using errcode = '42501';
  end if;
  if e.used_at is not null or e.revoked_at is not null then return; end if;
  update public.staff_enrolments x set revoked_at = now() where x.id = eid;
  insert into public.staff_events (venue_id, actor_id, subject_id, kind, detail)
  values (e.venue_id, me, null, 'enrolment_revoked', jsonb_build_object('enrolment', eid, 'role', e.role));
end; $$;

-- The manager's list of people added but not in yet (expired ones too, to re-issue).
create or replace function public.staff_enrolments_open(vid uuid)
returns table (id uuid, staff_name text, email text, phone text, role text, created_at timestamptz,
               expires_at timestamptz, attempts int, added_by text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.venue_can(vid, auth.uid(), 'team.manage') then
    raise exception 'your role doesn''t manage the team here' using errcode = '42501';
  end if;
  return query
  select e.id, e.staff_name, e.email, e.phone, e.role, e.created_at, e.expires_at, e.attempts,
         coalesce(p.display_name, p.handle)
    from public.staff_enrolments e
    left join public.profiles p on p.id = e.created_by
   where e.venue_id = vid and e.used_at is null and e.revoked_at is null
   order by e.created_at desc;
end; $$;

-- The employee's side: every venue that added the email they signed in with, still
-- open. No code in here, ever — only who, where and as what.
create or replace function public.my_staff_enrolments()
returns table (id uuid, venue_id uuid, venue_name text, venue_kind text, role text, staff_name text,
               added_by text, expires_at timestamptz, tries_left int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); em text;
begin
  if me is null then return; end if;
  select lower(u.email) into em from auth.users u where u.id = me;
  if em is null then return; end if;
  return query
  select e.id, e.venue_id, v.name, v.kind, e.role, e.staff_name, coalesce(p.display_name, p.handle),
         e.expires_at, 5 - e.attempts
    from public.staff_enrolments e
    join public.venues v on v.id = e.venue_id
    left join public.profiles p on p.id = e.created_by
   where e.email = em and e.used_at is null and e.revoked_at is null
     and e.expires_at > now() and e.attempts < 5
     and not exists (select 1 from public.venue_staff s
                      where s.venue_id = e.venue_id and s.user_id = me and s.status = 'active')
   order by e.created_at desc;
end; $$;

-- The employee types the manager's code. Returns a result, never raises on a wrong code
-- (an exception would roll back the count of tries with it):
--   {ok: true, venue_id, venue, role}  or  {ok: false, error: not_found | closed | expired |
--   too_many | wrong_code | locked, left?}
create or replace function public.claim_staff_enrolment(eid uuid, code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me    uuid := auth.uid();
  em    text;
  e     public.staff_enrolments;
  cur   public.venue_staff;
  had   boolean;
  final text;
  vname text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select lower(u.email) into em from auth.users u where u.id = me;
  select * into e from public.staff_enrolments x where x.id = eid for update;
  if not found or em is null or e.email <> em then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if e.used_at is not null or e.revoked_at is not null then return jsonb_build_object('ok', false, 'error', 'closed'); end if;
  if e.expires_at <= now() then return jsonb_build_object('ok', false, 'error', 'expired'); end if;
  if e.attempts >= 5 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  if public.staff_code_hash(e.id, trim(coalesce(code, ''))) <> e.code_hash then
    update public.staff_enrolments x set attempts = x.attempts + 1 where x.id = e.id;
    return jsonb_build_object('ok', false,
                              'error', case when e.attempts + 1 >= 5 then 'too_many' else 'wrong_code' end,
                              'left', greatest(0, 4 - e.attempts));
  end if;

  select * into cur from public.venue_staff s where s.venue_id = e.venue_id and s.user_id = me for update;
  had := found;
  if had and cur.status = 'locked' then
    -- a paused person doesn't un-pause themself with a new code
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;
  final := case when had and cur.status = 'active' then cur.role else e.role end;
  perform set_config('brewdiary.staff_via', 'code', true);
  if had then
    -- already on the roster, waiting on an invite: the manager's code is their yes
    update public.venue_staff s set status = 'active', role = final
     where s.venue_id = e.venue_id and s.user_id = me;
  else
    insert into public.venue_staff (venue_id, user_id, role, status) values (e.venue_id, me, final, 'active');
  end if;
  perform set_config('brewdiary.staff_via', '', true);
  insert into public.staff_details (venue_id, user_id, staff_name, phone, approved_by, approved_at)
  values (e.venue_id, me, e.staff_name, e.phone, e.created_by, now())
  on conflict (venue_id, user_id) do update
     set staff_name = excluded.staff_name, phone = coalesce(excluded.phone, staff_details.phone),
         approved_by = excluded.approved_by, approved_at = excluded.approved_at, updated_at = now();
  update public.staff_enrolments x set used_by = me, used_at = now() where x.id = e.id;
  select v.name into vname from public.venues v where v.id = e.venue_id;
  return jsonb_build_object('ok', true, 'venue_id', e.venue_id, 'venue', vname, 'role', final);
end; $$;

-- ── 7. invite codes wait for a yes ───────────────────────────────────────────
-- Same as 045, but the person joins as PENDING — no powers until approved.
create or replace function public.accept_staff_invite(invite_code text)
returns text language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); inv public.staff_invites; vname text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into inv from public.staff_invites i where i.code = lower(trim(invite_code)) for update;
  if not found or inv.used_at is not null or inv.expires_at < now() then
    raise exception 'that invite code didn''t work — ask for a new one';
  end if;
  perform set_config('brewdiary.staff_via', 'invite', true);
  insert into public.venue_staff (venue_id, user_id, role, status) values (inv.venue_id, me, inv.role, 'pending')
  on conflict (venue_id, user_id) do nothing;
  perform set_config('brewdiary.staff_via', '', true);
  update public.staff_invites i set used_by = me, used_at = now() where i.code = inv.code;
  select v.name into vname from public.venues v where v.id = inv.venue_id;
  return vname;
end; $$;

create or replace function public.approve_staff(vid uuid, uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cur public.venue_staff;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into cur from public.venue_staff s where s.venue_id = vid and s.user_id = uid for update;
  if not found then raise exception 'they''re not on this team'; end if;
  if cur.status <> 'pending' then raise exception 'they''re not waiting for a yes'; end if;
  if not public.venue_can(vid, me, 'team.manage') or not public.can_grant_role(vid, me, cur.role) then
    raise exception 'your role can''t approve a %', cur.role using errcode = '42501';
  end if;
  perform set_config('brewdiary.staff_via', 'approved', true);
  update public.venue_staff s set status = 'active' where s.venue_id = vid and s.user_id = uid;
  perform set_config('brewdiary.staff_via', '', true);
  insert into public.staff_details (venue_id, user_id, approved_by, approved_at) values (vid, uid, me, now())
  on conflict (venue_id, user_id) do update
     set approved_by = excluded.approved_by, approved_at = excluded.approved_at, updated_at = now();
end; $$;

create or replace function public.decline_staff(vid uuid, uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cur public.venue_staff;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into cur from public.venue_staff s where s.venue_id = vid and s.user_id = uid for update;
  if not found then raise exception 'they''re not on this team'; end if;
  if cur.status <> 'pending' then raise exception 'they''re not waiting for a yes'; end if;
  if not public.venue_can(vid, me, 'team.manage') or not public.can_grant_role(vid, me, cur.role) then
    raise exception 'your role can''t decline a %', cur.role using errcode = '42501';
  end if;
  perform set_config('brewdiary.staff_via', 'declined', true);
  delete from public.venue_staff s where s.venue_id = vid and s.user_id = uid;
  perform set_config('brewdiary.staff_via', '', true);
end; $$;

-- ── 8. lock-out ──────────────────────────────────────────────────────────────
-- Pause someone's access at once, with a reason and who to report to (an owner or
-- manager here; the person locking, if not said). Locking again updates the message.
create or replace function public.lock_staff(vid uuid, uid uuid, reason text default null, report_to_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  me  uuid := auth.uid();
  cur public.venue_staff;
  rt  uuid := coalesce(report_to_id, auth.uid());
  why text := nullif(trim(coalesce(reason, '')), '');
begin
  if me is null then raise exception 'not signed in'; end if;
  if uid = me then raise exception 'you can''t lock yourself out'; end if;
  if exists (select 1 from public.venues v where v.id = vid and v.created_by = uid) then
    raise exception 'the owner can''t be locked out';
  end if;
  select * into cur from public.venue_staff s where s.venue_id = vid and s.user_id = uid for update;
  if not found then raise exception 'they''re not on this team'; end if;
  if not public.venue_can(vid, me, 'team.manage') or not public.can_grant_role(vid, me, cur.role) then
    raise exception 'your role can''t lock out a %', cur.role using errcode = '42501';
  end if;
  if cur.status = 'pending' then raise exception 'they''re still waiting — decline them instead'; end if;
  if why is not null and char_length(why) > 200 then raise exception 'keep the reason under 200 letters'; end if;
  if coalesce(public.venue_role(vid, rt), '') not in ('owner', 'manager') then
    raise exception 'they can only be asked to report to an owner or a manager here';
  end if;
  if cur.status <> 'locked' then
    perform set_config('brewdiary.staff_note', coalesce(why, ''), true);
    update public.venue_staff s set status = 'locked' where s.venue_id = vid and s.user_id = uid;
    perform set_config('brewdiary.staff_note', '', true);
  end if;
  insert into public.staff_details (venue_id, user_id, locked_by, locked_at, lock_reason, report_to)
  values (vid, uid, me, now(), why, rt)
  on conflict (venue_id, user_id) do update
     set locked_by = excluded.locked_by, locked_at = excluded.locked_at, lock_reason = excluded.lock_reason,
         report_to = excluded.report_to, updated_at = now();
  -- a paused person is off the clock
  update public.staff_shifts sh set ended_at = now(), ended_by = me
   where sh.venue_id = vid and sh.user_id = uid and sh.ended_at is null;
end; $$;

create or replace function public.unlock_staff(vid uuid, uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cur public.venue_staff;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into cur from public.venue_staff s where s.venue_id = vid and s.user_id = uid for update;
  if not found then raise exception 'they''re not on this team'; end if;
  if not public.venue_can(vid, me, 'team.manage') or not public.can_grant_role(vid, me, cur.role) then
    raise exception 'your role can''t unlock a %', cur.role using errcode = '42501';
  end if;
  if cur.status <> 'locked' then return; end if;
  update public.venue_staff s set status = 'active' where s.venue_id = vid and s.user_id = uid;
  update public.staff_details d set locked_by = null, locked_at = null, lock_reason = null, report_to = null, updated_at = now()
   where d.venue_id = vid and d.user_id = uid;
end; $$;

-- ── 9. the venue's details for someone, and the roster that shows them ──────
-- Yourself, or someone you could grant the role of.
create or replace function public.set_staff_details(vid uuid, uid uuid, full_name text, phone_no text)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  cur public.venue_staff;
  nm text := nullif(trim(coalesce(full_name, '')), '');
  ph text := nullif(trim(coalesce(phone_no, '')), '');
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into cur from public.venue_staff s where s.venue_id = vid and s.user_id = uid;
  if not found then raise exception 'they''re not on this team'; end if;
  if uid <> me and not (public.venue_can(vid, me, 'team.manage') and public.can_grant_role(vid, me, cur.role)) then
    raise exception 'your role can''t change their details' using errcode = '42501';
  end if;
  if nm is not null and char_length(nm) > 60 then raise exception 'keep the name under 60 letters'; end if;
  if ph is not null and ph !~ '^\+?[0-9 ()-]{6,20}$' then raise exception 'that phone number doesn''t look right'; end if;
  insert into public.staff_details (venue_id, user_id, staff_name, phone) values (vid, uid, nm, ph)
  on conflict (venue_id, user_id) do update
     set staff_name = excluded.staff_name, phone = excluded.phone, updated_at = now();
  insert into public.staff_events (venue_id, actor_id, subject_id, kind) values (vid, me, uid, 'details_changed');
end; $$;

-- The team as the app shows it. Everyone on the team sees the active roster and who's on
-- shift; owners and managers also see who's waiting or paused, phone numbers, why someone
-- was paused and who approved whom. You always see your own row in full.
create or replace function public.team_roster(vid uuid)
returns table (user_id uuid, handle text, display_name text, staff_name text, phone text, role text,
               status text, thankable boolean, joined_at timestamptz, approved_by text, locked_at timestamptz,
               lock_reason text, report_to text, on_shift_since timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid(); manage boolean;
begin
  if me is null or not public.is_venue_staff(vid, me) then
    raise exception 'you''re not on this team' using errcode = '42501';
  end if;
  manage := public.venue_can(vid, me, 'team.manage');
  return query
  select s.user_id, p.handle, p.display_name, d.staff_name,
         case when manage or s.user_id = me then d.phone end,
         case when v.created_by = s.user_id then 'owner' else s.role end,
         s.status, s.thankable, s.added_at,
         case when manage then coalesce(ap.display_name, ap.handle) end,
         case when manage or s.user_id = me then d.locked_at end,
         case when manage or s.user_id = me then d.lock_reason end,
         case when manage or s.user_id = me then coalesce(rp.display_name, rp.handle) end,
         (select sh.started_at from public.staff_shifts sh
           where sh.venue_id = vid and sh.user_id = s.user_id and sh.ended_at is null)
    from public.venue_staff s
    join public.venues v on v.id = s.venue_id
    join public.profiles p on p.id = s.user_id
    left join public.staff_details d on d.venue_id = s.venue_id and d.user_id = s.user_id
    left join public.profiles ap on ap.id = d.approved_by
    left join public.profiles rp on rp.id = d.report_to
   where s.venue_id = vid and (manage or s.status = 'active')
   order by case s.status when 'pending' then 0 when 'active' then 1 else 2 end, s.added_at;
end; $$;

-- Where I'm waiting or paused: the venue's name even when I can no longer read the
-- venue, why, and who to go and see.
create or replace function public.my_staff_status()
returns table (venue_id uuid, venue_name text, venue_kind text, role text, status text, lock_reason text,
               locked_at timestamptz, report_to text, report_to_role text)
language sql stable security definer set search_path = public as $$
  select s.venue_id, v.name, v.kind, s.role, s.status, d.lock_reason, d.locked_at,
         coalesce(rp.display_name, rp.handle), public.venue_role(s.venue_id, d.report_to)
    from public.venue_staff s
    join public.venues v on v.id = s.venue_id
    left join public.staff_details d on d.venue_id = s.venue_id and d.user_id = s.user_id
    left join public.profiles rp on rp.id = d.report_to
   where s.user_id = auth.uid() and s.status <> 'active'
   order by v.name;
$$;

-- The venue's history (owners/managers), or one person's (theirs, or anyone's for a
-- manager). Names are resolved here; a deleted account shows as nobody.
create or replace function public.staff_history(vid uuid, uid uuid default null, lim int default 100)
returns table (id bigint, kind text, actor text, subject text, detail jsonb, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'audit.view') and coalesce(uid, '00000000-0000-0000-0000-000000000000'::uuid) <> me then
    raise exception 'your role doesn''t see the team''s history' using errcode = '42501';
  end if;
  return query
  select ev.id, ev.kind,
         coalesce(ad.staff_name, ap.display_name, ap.handle),
         coalesce(sd.staff_name, sp.display_name, sp.handle),
         ev.detail, ev.created_at
    from public.staff_events ev
    left join public.profiles ap on ap.id = ev.actor_id
    left join public.staff_details ad on ad.venue_id = ev.venue_id and ad.user_id = ev.actor_id
    left join public.profiles sp on sp.id = ev.subject_id
    left join public.staff_details sd on sd.venue_id = ev.venue_id and sd.user_id = ev.subject_id
   where ev.venue_id = vid and (uid is null or ev.subject_id = uid)
   order by ev.created_at desc, ev.id desc
   limit greatest(1, least(coalesce(lim, 100), 500));
end; $$;

-- ── 10. thanks go to active staff only (025) ─────────────────────────────────
create or replace function public.room_staff(pid uuid)
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.display_name, 'the bar')
  from public.parties room
  join public.venue_staff vs on vs.venue_id = room.venue_id and vs.thankable and vs.status = 'active'
  join public.profiles p on p.id = vs.user_id
  where room.id = pid
    and room.venue_id is not null
    and public.is_party_member(pid, auth.uid())   -- you must be IN the room
  order by 2;
$$;

create or replace function public.thank_staff(pid uuid, sid uuid, why text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); vid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_party_member(pid, me) then raise exception 'not in this room'; end if;

  select room.venue_id into vid from public.parties room where room.id = pid;
  if vid is null then raise exception 'not a venue room'; end if;

  if not exists (
    select 1 from public.venue_staff vs
    where vs.venue_id = vid and vs.user_id = sid and vs.thankable and vs.status = 'active'
  ) then
    raise exception 'that person is not taking thanks';
  end if;

  begin
    insert into public.staff_kudos (venue_id, staff_id, from_user, party_id, reason)
    values (vid, sid, me, pid, why);
  exception when unique_violation then
    return false;   -- already said it; a harmless no-op
  end;
  return true;
end; $$;

-- ── 11. who may call what ────────────────────────────────────────────────────
do $$
declare f text;
begin
  foreach f in array array[
    'public.clock_in(uuid)', 'public.clock_out(uuid)', 'public.end_staff_shift(uuid, uuid)', 'public.my_shift(uuid)',
    'public.shift_hours(uuid, timestamptz)', 'public.enrol_staff(uuid, text, text, text, text)',
    'public.reissue_staff_code(uuid)', 'public.revoke_staff_enrolment(uuid)', 'public.staff_enrolments_open(uuid)',
    'public.my_staff_enrolments()', 'public.claim_staff_enrolment(uuid, text)', 'public.accept_staff_invite(text)',
    'public.approve_staff(uuid, uuid)', 'public.decline_staff(uuid, uuid)', 'public.lock_staff(uuid, uuid, text, uuid)',
    'public.unlock_staff(uuid, uuid)', 'public.set_staff_details(uuid, uuid, text, text)', 'public.team_roster(uuid)',
    'public.my_staff_status()', 'public.staff_history(uuid, uuid, int)', 'public.room_staff(uuid)',
    'public.thank_staff(uuid, uuid, text)'
  ] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
