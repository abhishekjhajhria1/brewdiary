-- ============================================================================
-- brewdiary — STAFF ROLES: who at a venue may do what, decided by the database.
--
-- Until now a venue had three roles (owner / manager / bartender) and every server
-- function asked one question — "is this person on the team?" (is_venue_staff). That
-- was fine while "staff" meant the people behind the bar. The venue app adds servers,
-- hosts, a kitchen and shift supervisors, and "on the team" can no longer mean "may
-- record a guest's tab" or "may read a guest's card". So:
--
--   1. ROLES grow to owner · manager · supervisor · bartender · server · host · kitchen.
--   2. CAPABILITIES are DATA (role_capabilities), like jurisdiction_policy: one row per
--      thing a role may do, written only out-of-band with the service key. venue_can()
--      is the single question every function asks. The apps mirror the table
--      (mobile-bar/lib/logic/roles.dart, src/lib/roles.ts) only to decide what to SHOW.
--      046 moves the existing gates onto it; nothing about today's roles changes —
--      owner, manager and bartender keep every power they have now.
--
-- It also closes four holes found while planning the venue app (mobile-bar/PLAN.md §1.4):
--
--   • A MANAGER COULD CROWN AN OWNER, and REMOVE the real one. venue_staff_insert never
--     looked at the role, and venue_staff_delete let any manager delete any row. Now a
--     role can only be handed out by someone senior enough to grant it (can_grant_role):
--     an owner manages everyone; a manager manages the floor, never other managers; and
--     'owner' is never granted from an app at all (the creator is the owner).
--   • THERE WAS NO WAY TO CHANGE A ROLE — no update policy, so "promote" meant remove
--     and re-add. set_staff_role() does it, with the same seniority rule, and never on
--     yourself.
--   • "DON'T THANK ME" NEVER WORKED. 025 promised staff an opt-out that actually works
--     (venue_staff.thankable), and the dashboard flipped it with a plain UPDATE — but
--     venue_staff has no update policy, so RLS matched no row and nothing changed.
--     set_thankable() now does it, for your own row only.
--   • A VERIFIED VENUE COULD MOVE COUNTRY. The admin guard protected verified/created_by
--     but not where the venue is — and the country decides which loyalty perks are
--     LAWFUL (021). An Irish bar could have become "Indian" to hand out alcohol rewards,
--     after we had checked it. Country, region, kind and slug are now fixed once a venue
--     is verified (the slug is printed on every NFC tag and QR on its tables); changing
--     them goes through brewdiary, like verification itself.
--
-- And: staff INVITES — a code a manager shares, so a new server joins with the right
-- role without anyone knowing their @handle.
--
-- Runs on top of 002..044.
-- ============================================================================

-- ── 1. the roles ─────────────────────────────────────────────────────────────
alter table public.venue_staff drop constraint if exists venue_staff_role_check;
alter table public.venue_staff add constraint venue_staff_role_check
  check (role in ('owner', 'manager', 'supervisor', 'bartender', 'server', 'host', 'kitchen'));

-- ── 2. what each role may do (data, not code) ───────────────────────────────
create table if not exists public.role_capabilities (
  role       text not null check (role in ('owner', 'manager', 'supervisor', 'bartender', 'server', 'host', 'kitchen')),
  capability text not null check (capability ~ '^[a-z0-9_]+\.[a-z0-9_]+$'),
  primary key (role, capability)
);
alter table public.role_capabilities enable row level security;

-- World-readable to signed-in people (the app shows the rule), written only with the
-- service key. No write policy at all.
drop policy if exists role_capabilities_read on public.role_capabilities;
create policy role_capabilities_read on public.role_capabilities for select to authenticated using (true);

delete from public.role_capabilities;
insert into public.role_capabilities (role, capability) values
  ('owner', 'floor.view'),
  ('owner', 'guests.seat'),
  ('owner', 'orders.take'),
  ('owner', 'station.bar'),
  ('owner', 'station.kitchen'),
  ('owner', 'orders.void_own'),
  ('owner', 'orders.approve'),
  ('owner', 'payments.take'),
  ('owner', 'payments.refund'),
  ('owner', 'cash.own'),
  ('owner', 'cash.close_day'),
  ('owner', 'menu.86'),
  ('owner', 'rooms.open'),
  ('owner', 'guests.at_tables'),
  ('owner', 'guests.card'),
  ('owner', 'guests.taste'),
  ('owner', 'guests.vibe'),
  ('owner', 'guests.notes'),
  ('owner', 'perks.redeem'),
  ('owner', 'spend.record'),
  ('owner', 'menu.edit'),
  ('owner', 'perks.edit'),
  ('owner', 'stock.count'),
  ('owner', 'stock.receive'),
  ('owner', 'stock.adjust'),
  ('owner', 'rota.edit'),
  ('owner', 'shift.own'),
  ('owner', 'tips.manage'),
  ('owner', 'board.live'),
  ('owner', 'reports.view'),
  ('owner', 'area.view'),
  ('owner', 'ai.advisor'),
  ('owner', 'ai.guest_tips'),
  ('owner', 'audit.view'),
  ('owner', 'team.manage'),
  ('owner', 'settings.edit'),
  ('owner', 'venue.verify'),
  ('owner', 'venue.delete'),
  ('manager', 'floor.view'),
  ('manager', 'guests.seat'),
  ('manager', 'orders.take'),
  ('manager', 'station.bar'),
  ('manager', 'station.kitchen'),
  ('manager', 'orders.void_own'),
  ('manager', 'orders.approve'),
  ('manager', 'payments.take'),
  ('manager', 'payments.refund'),
  ('manager', 'cash.own'),
  ('manager', 'cash.close_day'),
  ('manager', 'menu.86'),
  ('manager', 'rooms.open'),
  ('manager', 'guests.at_tables'),
  ('manager', 'guests.card'),
  ('manager', 'guests.taste'),
  ('manager', 'guests.vibe'),
  ('manager', 'guests.notes'),
  ('manager', 'perks.redeem'),
  ('manager', 'spend.record'),
  ('manager', 'menu.edit'),
  ('manager', 'perks.edit'),
  ('manager', 'stock.count'),
  ('manager', 'stock.receive'),
  ('manager', 'stock.adjust'),
  ('manager', 'rota.edit'),
  ('manager', 'shift.own'),
  ('manager', 'tips.manage'),
  ('manager', 'board.live'),
  ('manager', 'reports.view'),
  ('manager', 'area.view'),
  ('manager', 'ai.advisor'),
  ('manager', 'ai.guest_tips'),
  ('manager', 'audit.view'),
  ('manager', 'team.manage'),
  ('manager', 'settings.edit'),
  ('manager', 'venue.verify'),
  ('supervisor', 'floor.view'),
  ('supervisor', 'guests.seat'),
  ('supervisor', 'orders.take'),
  ('supervisor', 'station.bar'),
  ('supervisor', 'station.kitchen'),
  ('supervisor', 'orders.void_own'),
  ('supervisor', 'orders.approve'),
  ('supervisor', 'payments.take'),
  ('supervisor', 'cash.own'),
  ('supervisor', 'cash.close_day'),
  ('supervisor', 'menu.86'),
  ('supervisor', 'rooms.open'),
  ('supervisor', 'guests.at_tables'),
  ('supervisor', 'guests.card'),
  ('supervisor', 'guests.taste'),
  ('supervisor', 'guests.vibe'),
  ('supervisor', 'guests.notes'),
  ('supervisor', 'perks.redeem'),
  ('supervisor', 'spend.record'),
  ('supervisor', 'stock.count'),
  ('supervisor', 'stock.receive'),
  ('supervisor', 'shift.own'),
  ('supervisor', 'board.live'),
  ('supervisor', 'ai.guest_tips'),
  ('bartender', 'floor.view'),
  ('bartender', 'orders.take'),
  ('bartender', 'station.bar'),
  ('bartender', 'orders.void_own'),
  ('bartender', 'payments.take'),
  ('bartender', 'cash.own'),
  ('bartender', 'menu.86'),
  ('bartender', 'rooms.open'),
  ('bartender', 'guests.at_tables'),
  ('bartender', 'guests.card'),
  ('bartender', 'guests.taste'),
  ('bartender', 'guests.vibe'),
  ('bartender', 'guests.notes'),
  ('bartender', 'perks.redeem'),
  ('bartender', 'spend.record'),
  ('bartender', 'stock.count'),
  ('bartender', 'stock.receive'),
  ('bartender', 'shift.own'),
  ('bartender', 'ai.guest_tips'),
  ('server', 'floor.view'),
  ('server', 'guests.seat'),
  ('server', 'orders.take'),
  ('server', 'orders.void_own'),
  ('server', 'payments.take'),
  ('server', 'cash.own'),
  ('server', 'guests.at_tables'),
  ('server', 'guests.card'),
  ('server', 'guests.taste'),
  ('server', 'guests.vibe'),
  ('server', 'guests.notes'),
  ('server', 'perks.redeem'),
  ('server', 'spend.record'),
  ('server', 'shift.own'),
  ('server', 'ai.guest_tips'),
  ('host', 'floor.view'),
  ('host', 'guests.seat'),
  ('host', 'rooms.open'),
  ('host', 'guests.at_tables'),
  ('host', 'guests.vibe'),
  ('host', 'shift.own'),
  ('kitchen', 'station.kitchen'),
  ('kitchen', 'menu.86'),
  ('kitchen', 'stock.count'),
  ('kitchen', 'stock.receive'),
  ('kitchen', 'shift.own');

-- ── 3. the one question every function asks ─────────────────────────────────
-- A person's role at a venue. The creator is the owner whatever their staff row says.
create or replace function public.venue_role(vid uuid, uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.venues v where v.id = vid and v.created_by = uid) then 'owner'
    else (select s.role from public.venue_staff s where s.venue_id = vid and s.user_id = uid)
  end;
$$;
revoke all on function public.venue_role(uuid, uuid) from public;
grant execute on function public.venue_role(uuid, uuid) to authenticated;

-- May [uid] do [cap] at [vid]? False for anyone not on the team.
create or replace function public.venue_can(vid uuid, uid uuid, cap text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.role_capabilities rc
    where rc.role = public.venue_role(vid, uid) and rc.capability = cap
  );
$$;
revoke all on function public.venue_can(uuid, uuid, text) from public;
grant execute on function public.venue_can(uuid, uuid, text) to authenticated;

-- May [granter] hand out (or take away) [target] at [vid]? Never 'owner'. An owner
-- manages everyone else; a manager manages the floor, never another manager.
create or replace function public.can_grant_role(vid uuid, granter uuid, target text)
returns boolean language sql stable security definer set search_path = public as $$
  select target is not null and target <> 'owner' and case public.venue_role(vid, granter)
    when 'owner'   then true
    when 'manager' then target in ('supervisor', 'bartender', 'server', 'host', 'kitchen')
    else false
  end;
$$;
revoke all on function public.can_grant_role(uuid, uuid, text) from public;
grant execute on function public.can_grant_role(uuid, uuid, text) to authenticated;

-- ── 4. the roster's write rules ──────────────────────────────────────────────
drop policy if exists venue_staff_insert on public.venue_staff;
create policy venue_staff_insert on public.venue_staff for insert to authenticated
  with check (
    -- the creator puts themself on the team as owner (createVenue, straight after the insert)
    (user_id = auth.uid() and role = 'owner'
      and exists (select 1 from public.venues v where v.id = venue_id and v.created_by = auth.uid()))
    -- everyone else is added by someone senior enough to grant that role
    or public.can_grant_role(venue_id, auth.uid(), role)
  );

drop policy if exists venue_staff_delete on public.venue_staff;
create policy venue_staff_delete on public.venue_staff for delete to authenticated
  using (
    role <> 'owner' and (
      user_id = auth.uid()                                  -- you can leave…
      or public.can_grant_role(venue_id, auth.uid(), role)  -- …or be removed by someone senior
    )
  );
-- Deliberately still NO update policy: roles change through set_staff_role(), the opt-out
-- through set_thankable() — so no other column can be edited from a client.

-- Promote or move someone. The caller must be able to grant BOTH the role they hold now
-- and the one they're getting, and nobody changes their own role.
create or replace function public.set_staff_role(vid uuid, uid uuid, new_role text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cur text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if uid = me then raise exception 'you cannot change your own role'; end if;
  select s.role into cur from public.venue_staff s where s.venue_id = vid and s.user_id = uid;
  if cur is null then raise exception 'they are not on this team'; end if;
  if not public.can_grant_role(vid, me, cur) or not public.can_grant_role(vid, me, new_role) then
    raise exception 'you cannot give that role';
  end if;
  update public.venue_staff set role = new_role where venue_id = vid and user_id = uid;
end; $$;
revoke all on function public.set_staff_role(uuid, uuid, text) from public;
grant execute on function public.set_staff_role(uuid, uuid, text) to authenticated;

-- "Don't thank me": your own row, that one column. (The plain UPDATE the dashboard sent
-- never matched a row — there is no update policy — so the opt-out silently did nothing.)
create or replace function public.set_thankable(vid uuid, on_off boolean)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  update public.venue_staff set thankable = coalesce(on_off, true)
   where venue_id = vid and user_id = auth.uid();
  return found;
end; $$;
revoke all on function public.set_thankable(uuid, boolean) from public;
grant execute on function public.set_thankable(uuid, boolean) to authenticated;

-- ── 5. what a verified venue can no longer change by itself ─────────────────
-- verified / created_by as before; and once verified, where the venue is (the law that
-- governs its perks), what kind of place it is, and its slug (printed on its tables).
create or replace function public.venues_guard_admin_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;   -- the service role (brewdiary) may
  if new.verified is distinct from old.verified
     or new.created_by is distinct from old.created_by then
    raise exception 'verified/ownership are set by brewdiary, not the venue';
  end if;
  if old.verified and (
       new.country is distinct from old.country
    or new.region  is distinct from old.region
    or new.kind    is distinct from old.kind
    or new.slug    is distinct from old.slug) then
    raise exception 'a verified venue''s country, region, kind and web address are fixed'
      using hint = 'Ask brewdiary to change them — they decide which perks are lawful, and the address is printed on your tables.';
  end if;
  return new;
end; $$;

-- ── 6. staff invites ─────────────────────────────────────────────────────────
-- A short code a manager shares (a QR, a message). Single use, a week to live, and it
-- carries the role — so it can only be for a role its creator may grant.
create table if not exists public.staff_invites (
  code       text primary key check (code ~ '^[a-z0-9]{10}$'),
  venue_id   uuid not null references public.venues(id) on delete cascade,
  role       text not null check (role in ('manager', 'supervisor', 'bartender', 'server', 'host', 'kitchen')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by    uuid references public.profiles(id) on delete set null,
  used_at    timestamptz
);
create index if not exists staff_invites_venue_idx on public.staff_invites (venue_id, created_at desc);
alter table public.staff_invites enable row level security;

-- The people who could have made an invite see the venue's invites. No write policy:
-- create_staff_invite() and accept_staff_invite() are the only ways in.
drop policy if exists staff_invites_read on public.staff_invites;
create policy staff_invites_read on public.staff_invites for select to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'team.manage'));

create or replace function public.create_staff_invite(vid uuid, invite_role text)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); c text; b bytea; i int;
  alphabet text := 'abcdefghjkmnpqrstuvwxyz23456789';   -- no 0/o, 1/l/i
  -- the bytes of a v4 uuid that are fully random (6 and 8 carry version/variant bits)
  picks int[] := array[0, 1, 2, 3, 4, 5, 7, 9, 10, 11];
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.can_grant_role(vid, me, invite_role) then
    raise exception 'you cannot invite someone as %', invite_role;
  end if;
  loop
    -- gen_random_uuid() is core Postgres (13+): no pgcrypto, which on Supabase lives in
    -- the `extensions` schema and is invisible to a function pinned to search_path=public.
    b := uuid_send(gen_random_uuid());
    c := '';
    for i in 1..10 loop
      c := c || substr(alphabet, 1 + (get_byte(b, picks[i]) % length(alphabet)), 1);
    end loop;
    begin
      insert into public.staff_invites (code, venue_id, role, created_by) values (c, vid, invite_role, me);
      return c;
    exception when unique_violation then
      -- astronomically unlikely; draw again
    end;
  end loop;
end; $$;
revoke all on function public.create_staff_invite(uuid, text) from public;
grant execute on function public.create_staff_invite(uuid, text) to authenticated;

-- Accept an invite: you join the team at the invite's role. Joining a team you're
-- already on changes nothing (an invite is not a way to change roles). Returns the
-- venue's name for the welcome line.
create or replace function public.accept_staff_invite(invite_code text)
returns text language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); inv public.staff_invites; vname text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into inv from public.staff_invites where code = lower(trim(invite_code)) for update;
  if not found or inv.used_at is not null or inv.expires_at < now() then
    raise exception 'that invite code didn''t work — ask for a new one';
  end if;
  insert into public.venue_staff (venue_id, user_id, role) values (inv.venue_id, me, inv.role)
  on conflict (venue_id, user_id) do nothing;
  update public.staff_invites set used_by = me, used_at = now() where code = inv.code;
  select v.name into vname from public.venues v where v.id = inv.venue_id;
  return vname;
end; $$;
revoke all on function public.accept_staff_invite(text) from public;
grant execute on function public.accept_staff_invite(text) to authenticated;
