-- ============================================================================
-- brewdiary — "Vouches": a friend stakes their word that you're a real person.
--
-- ── WHAT THIS IS, AND THE LINE IT DOES NOT CROSS ────────────────────────────
-- A vouch is the last of the FREE trust signals (alongside tenure, diary use, and
-- the on-device liveness check — see src/lib/verify.ts). It answers the same narrow
-- question as the rest of the trust layer: "is this a real, settled human, or a
-- throwaway account?" — never "is this a good person". It is:
--
--   • Directional and OTHER-only. You vouch FOR someone else. You can never vouch
--     for yourself (the CHECK forbids voucher = vouchee), so no one can inflate their
--     own standing — the same "a guest can never write their own reward" line we hold
--     for spend/perks, applied to trust.
--   • Friend-gated. You can only vouch for someone you're actually accepted friends
--     with. Your word only means something about people you actually know. Enforced in
--     the DB (are_friends in the insert policy), not just the UI.
--   • A COUNT, never a ranking. vouch_count(uid) returns a number of vouchers; there is
--     no "who ranks whom", no leaderboard, no rating of a person. NO RATING OF PEOPLE —
--     the same line held in 031.
--   • Capped and additive in the score (verify.ts: min(vouches,5)*3), so a ring of
--     friends can nudge each other up but can't manufacture "trusted" out of nothing —
--     and we are always honest that this is anti-BOT, not identity proof.
--
-- Blocks are respected: you can't vouch across a block, and a blocked pair never see
-- each other's counts through plan_signals.
--
-- Runs on top of schema.sql + 002..032.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. VOUCHES — voucher stakes their word for vouchee. One row per (voucher, vouchee).
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.vouches (
  voucher_id uuid not null references public.profiles(id) on delete cascade,
  vouchee_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (voucher_id, vouchee_id),
  check (voucher_id <> vouchee_id)
);
-- Counts are looked up by vouchee, so index that side.
create index if not exists vouches_vouchee_idx on public.vouches (vouchee_id);
alter table public.vouches enable row level security;

-- You can read the vouches you GAVE and the vouches you RECEIVED — nothing else. The
-- full "who vouched for whom" graph is never exposed; a third party only ever gets a
-- COUNT, via vouch_count() below.
drop policy if exists vouches_read on public.vouches;
create policy vouches_read on public.vouches for select to authenticated
  using (voucher_id = auth.uid() or vouchee_id = auth.uid());

-- You may only ADD a vouch as yourself, for a real accepted friend, across no block.
-- The friend-gate lives in the CHECK (are_friends is a SECURITY DEFINER helper safe to
-- call in RLS), so a forged client insert for a non-friend is rejected by the database,
-- not merely hidden by the UI. voucher <> vouchee is already guaranteed by the table
-- CHECK, so self-vouching is impossible here too.
drop policy if exists vouches_insert on public.vouches;
create policy vouches_insert on public.vouches for insert to authenticated
  with check (
    voucher_id = auth.uid()
    and public.are_friends(auth.uid(), vouchee_id)
    and not public.blocked_between(auth.uid(), vouchee_id)
  );

-- You can withdraw a vouch you gave.
drop policy if exists vouches_delete on public.vouches;
create policy vouches_delete on public.vouches for delete to authenticated
  using (voucher_id = auth.uid());

-- ────────────────────────────────────────────────────────────────────────────
-- 2. COUNT — how many people vouch for this person. A plain number, callable by any
--    signed-in user (so a plan's soft signals can show it) — never the list of who.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.vouch_count(uid uuid)
returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.vouches where vouchee_id = uid;
$$;
revoke all on function public.vouch_count(uuid) from public;
grant execute on function public.vouch_count(uuid) to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. PLAN SIGNALS — fold "how many vouch for the host" into the existing soft signals.
--
-- plan_signals (from 031) already returns mutual_friends / shared_drinks / verified /
-- since. Adding a column changes the function's return type, which create-or-replace
-- can't do, so we drop and recreate. The body is unchanged except for the new
-- host_vouches column — still counts-only, still nothing for a blocked pair, still
-- never a rating.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.plan_signals(uuid);
create or replace function public.plan_signals(pid uuid)
returns table (mutual_friends int, shared_drinks int, host_verified boolean, host_vouches int, host_since timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); host uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select host_id into host from public.plans where id = pid;
  if host is null then return; end if;
  if host = me or public.blocked_between(me, host) then return; end if;
  if not public.plan_visible_to(pid, me) then return; end if;

  return query
  select
    -- mutual accepted friends (a count, never names)
    (
      with mine as (
        select case when f.requester_id = me then f.addressee_id else f.requester_id end id
        from public.friendships f
        where f.status = 'accepted' and (f.requester_id = me or f.addressee_id = me)
      ),
      theirs as (
        select case when f.requester_id = host then f.addressee_id else f.requester_id end id
        from public.friendships f
        where f.status = 'accepted' and (f.requester_id = host or f.addressee_id = host)
      )
      select count(*)::int from mine join theirs using (id)
    ),
    -- distinct drink types you BOTH log (taste overlap, as a number)
    (
      select count(*)::int from (
        select distinct lower(trim(type)) t from public.entries where user_id = me   and type is not null
        intersect
        select distinct lower(trim(type)) t from public.entries where user_id = host and type is not null
      ) shared
    ),
    (select verified from public.profiles where id = host),
    -- how many people vouch for the host (a count, never who)
    public.vouch_count(host),
    (select created_at from public.profiles where id = host);
end; $$;
revoke all on function public.plan_signals(uuid) from public;
grant execute on function public.plan_signals(uuid) to authenticated;
