-- ============================================================================
-- brewdiary — "Spend + the Together board" (Phase 7 gap-closing).
--
-- TWO things the maintainer asked for that were never built:
--
-- 1. SPEND, RECORDED ONLY BY THE BAR. "points for spends will only be shared by
--    bar / liquor store owner" — so spend_events has **NO insert policy at all**.
--    A guest literally cannot write their own spend from the client, by any path.
--    The only writer is record_spend(), a definer fn that demands the caller be
--    STAFF of that room's VERIFIED venue. This unlocks the perk you originally
--    described: "order above ₹X → a free drink next visit".
--
-- 2. THE TOGETHER LEADERBOARD, OPT-IN. profiles.compete_visible (default OFF).
--    friends_board() only ever returns people who switched it on — so you can't
--    be ranked in front of your friends without having asked to be.
--
-- Also adds profiles.flex_receipts (default OFF) — the consent flag for showing
-- your spend publicly. Nothing reads it yet; the display comes next.
-- Runs on top of schema.sql + 002..016. Idempotent-ish.
-- ============================================================================

drop function if exists public.friends_board()                cascade;
drop function if exists public.venue_spend(uuid)              cascade;
drop function if exists public.record_spend(uuid, uuid, numeric) cascade;
drop table    if exists public.spend_events cascade;

-- ── profiles: two new consent flags, both OFF by default ─────────────────────
alter table public.profiles add column if not exists compete_visible boolean not null default false;
alter table public.profiles add column if not exists flex_receipts   boolean not null default false;

-- ── spend: an append-only ledger the GUEST can never write ───────────────────
create table public.spend_events (
  id              uuid primary key default gen_random_uuid(),
  party_id        uuid not null references public.parties(id)  on delete cascade,
  subject_user_id uuid not null references public.profiles(id) on delete cascade, -- whose tab
  recorded_by     uuid          references public.profiles(id) on delete set null, -- which staff member
  amount          numeric(10, 2) not null check (amount > 0),                      -- ₹
  created_at      timestamptz not null default now()
);
create index spend_events_party_idx   on public.spend_events (party_id);
create index spend_events_subject_idx on public.spend_events (subject_user_id);

alter table public.spend_events enable row level security;

-- You can see YOUR OWN tab; the venue's staff can see tabs in their own rooms.
create policy spend_events_read on public.spend_events for select to authenticated
  using (
    subject_user_id = auth.uid()
    or exists (
      select 1 from public.parties room
      where room.id = party_id
        and room.venue_id is not null
        and public.is_venue_staff(room.venue_id, auth.uid())
    )
  );

-- DELIBERATELY NO INSERT/UPDATE POLICY. Spend is not self-reportable — the only
-- way a row is ever created is record_spend() below (SECURITY DEFINER, staff-only).

-- ── the bar records a guest's tab ────────────────────────────────────────────
create or replace function public.record_spend(pid uuid, uid uuid, amt numeric)
returns boolean
language plpgsql security definer set search_path = public as $$
declare vid uuid;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if amt is null or amt <= 0 then
    raise exception 'amount must be positive';
  end if;

  select room.venue_id into vid from public.parties room where room.id = pid;
  if vid is null then
    raise exception 'not a venue room';
  end if;
  if not public.is_venue_staff(vid, auth.uid()) then
    raise exception 'only this venue''s staff can record a tab';
  end if;
  if not exists (select 1 from public.venues v where v.id = vid and v.verified) then
    raise exception 'only a verified venue can record spend';
  end if;
  if not public.is_party_member(pid, uid) then
    raise exception 'that guest is not in this room';
  end if;

  insert into public.spend_events (party_id, subject_user_id, recorded_by, amount)
  values (pid, uid, auth.uid(), amt);
  return true;
end; $$;
revoke all on function public.record_spend(uuid, uuid, numeric) from public;
grant execute on function public.record_spend(uuid, uuid, numeric) to authenticated;

-- ── the CALLER's own total spend at a venue (self-only, like venue_visits) ───
create or replace function public.venue_spend(vid uuid)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(se.amount), 0)::numeric
  from public.spend_events se
  join public.parties room on room.id = se.party_id
  where room.venue_id = vid
    and se.subject_user_id = auth.uid();
$$;
revoke all on function public.venue_spend(uuid) from public;
grant execute on function public.venue_spend(uuid) to authenticated;

-- ── perks can now be spend-based, not just visit-based ───────────────────────
-- 'visits' → threshold is a number of check-ins. 'spend' → threshold is ₹.
alter table public.venue_perks
  add column if not exists kind text not null default 'visits';
alter table public.venue_perks drop constraint if exists venue_perks_kind_check;
alter table public.venue_perks add constraint venue_perks_kind_check check (kind in ('visits', 'spend'));

-- Widen `threshold` (was int, 1..100 — no good for a ₹ target). The old CHECK is
-- found by lookup rather than by name, so this can't silently leave a 100 ceiling.
do $$
declare c text;
begin
  for c in
    select con.conname from pg_constraint con
    where con.conrelid = 'public.venue_perks'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%threshold%'
  loop
    execute format('alter table public.venue_perks drop constraint %I', c);
  end loop;
end $$;

alter table public.venue_perks alter column threshold type numeric(10, 2) using threshold::numeric;
alter table public.venue_perks add constraint venue_perks_threshold_check
  check (threshold > 0 and threshold <= 1000000);

-- ── the Together leaderboard — opt-in on BOTH sides ──────────────────────────
-- Returns my accepted friends (and me) who switched compete_visible ON. Anyone
-- who hasn't opted in simply isn't on it — you can't be ranked without asking.
create or replace function public.friends_board()
returns table (user_id uuid, display_name text, sparks int, vibe int)
language sql stable security definer set search_path = public as $$
  with peers as (
    select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end as id
    from public.friendships f
    where f.status = 'accepted'
      and (f.requester_id = auth.uid() or f.addressee_id = auth.uid())
    union
    select auth.uid()
  )
  select p.id,
         coalesce(p.display_name, 'friend'),
         coalesce(sum(pe.value) filter (where pe.currency = 'spark'), 0)::int,
         coalesce(sum(pe.value) filter (where pe.currency = 'vibe'),  0)::int
  from peers
  join public.profiles p on p.id = peers.id
  left join public.point_events pe on pe.subject_user_id = p.id
  where auth.uid() is not null
    and p.compete_visible = true
  group by p.id, p.display_name;
$$;
revoke all on function public.friends_board() from public;
grant execute on function public.friends_board() to authenticated;
