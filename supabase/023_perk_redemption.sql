-- ============================================================================
-- brewdiary — "Claim it, once": perk redemption.
--
-- THE BUG THIS FIXES IS LIVE. The guest's perk card already says "Show this to
-- the bar to claim it" — and NOTHING ANYWHERE RECORDS A CLAIM. venue_visits() and
-- venue_spend() count ALL TIME, so once you cross the threshold you stay above it
-- forever: the same free drink can be claimed every visit, and two bartenders can
-- each honour it without knowing. The loyalty feature — the thing we ask bars to
-- trust us with — is currently decorative.
--
-- The fix is a ledger, like everything else here:
--   • perk_redemptions   — append-only; one row per claim.
--   • progress is counted SINCE YOUR LAST CLAIM, not since the dawn of time.
--   • redeem_perk()      — SERVER decides eligibility. Staff of a VERIFIED venue
--                          only. It re-checks the threshold itself, so a stale or
--                          hostile client cannot claim a perk that isn't earned.
--   • perk_status()      — what the guest sees, and what the bartender sees when
--                          they look a guest up. Same numbers, one source.
--
-- Jurisdiction still rules: a perk that can't lawfully exist here can't be claimed
-- here either, because there IS no perk row (021 blocks it at write time).
-- Runs on top of schema.sql + 002..022. Idempotent-ish.
-- ============================================================================

drop function if exists public.redeem_perk(uuid, uuid) cascade;
drop function if exists public.perk_status(uuid, uuid) cascade;
drop table    if exists public.perk_redemptions cascade;

create table public.perk_redemptions (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id)   on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade, -- who claimed
  redeemed_by uuid          references public.profiles(id) on delete set null, -- which staff member
  -- A snapshot of what was actually promised, so a later edit to the perk can't
  -- rewrite history. "You gave me a free pour" must stay true even if the bar
  -- switches to offering a coffee tomorrow.
  kind        text not null,
  threshold   numeric(10, 2) not null,
  reward      text not null,
  currency    text not null default 'INR',
  redeemed_at timestamptz not null default now()
);
create index perk_redemptions_venue_user_idx on public.perk_redemptions (venue_id, user_id, redeemed_at desc);

alter table public.perk_redemptions enable row level security;

-- You can see your own claims; a venue's staff can see claims at their venue.
create policy perk_redemptions_read on public.perk_redemptions for select to authenticated
  using (user_id = auth.uid() or public.is_venue_staff(venue_id, auth.uid()));

-- DELIBERATELY NO INSERT/UPDATE/DELETE POLICY. A claim is not something a guest
-- can write — only redeem_perk() (definer, staff-only) creates one, and nothing
-- ever deletes one. Same discipline as spend_events.

-- ── when did this guest last claim here? (the clock everything counts from) ──
create or replace function public.last_redeemed(vid uuid, uid uuid)
returns timestamptz
language sql stable security definer set search_path = public as $$
  select coalesce(max(r.redeemed_at), 'epoch'::timestamptz)
  from public.perk_redemptions r
  where r.venue_id = vid and r.user_id = uid;
$$;
revoke all on function public.last_redeemed(uuid, uuid) from public;
grant execute on function public.last_redeemed(uuid, uuid) to authenticated;

-- ── the one source of truth for "where is this guest up to?" ────────────────
-- Readable by the GUEST (themselves) or by that venue's STAFF — nobody else, and
-- never a third party. Progress counts only what happened AFTER the last claim.
create or replace function public.perk_status(vid uuid, uid uuid)
returns table (
  kind text, threshold numeric, reward text, currency text,
  progress numeric, earned boolean, claims int, last_claim timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); since timestamptz; p record; prog numeric;
begin
  if me is null then raise exception 'not signed in'; end if;
  if me <> uid and not public.is_venue_staff(vid, me) then
    raise exception 'not allowed to read that';
  end if;

  select vp.kind, vp.threshold, vp.reward, vp.currency into p
  from public.venue_perks vp where vp.venue_id = vid;
  if not found then return; end if;   -- no perk here (or not lawful here)

  since := public.last_redeemed(vid, uid);

  if p.kind = 'spend' then
    select coalesce(sum(se.amount), 0)::numeric into prog
    from public.spend_events se
    join public.parties room on room.id = se.party_id
    where room.venue_id = vid and se.subject_user_id = uid and se.created_at > since;
  else
    select count(distinct m.party_id)::numeric into prog
    from public.party_members m
    join public.parties room on room.id = m.party_id
    where room.venue_id = vid and m.user_id = uid and m.status = 'approved'
      and m.joined_at > since;
  end if;

  return query
    select p.kind, p.threshold, p.reward, p.currency,
           prog,
           prog >= p.threshold,
           (select count(*)::int from public.perk_redemptions r
             where r.venue_id = vid and r.user_id = uid),
           nullif(since, 'epoch'::timestamptz);
end; $$;
revoke all on function public.perk_status(uuid, uuid) from public;
grant execute on function public.perk_status(uuid, uuid) to authenticated;

-- ── the claim. Staff of a VERIFIED venue, and the server re-checks earning. ──
create or replace function public.redeem_perk(vid uuid, uid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); st record;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_venue_staff(vid, me) then
    raise exception 'only this venue''s staff can hand a perk over';
  end if;
  if not exists (select 1 from public.venues v where v.id = vid and v.verified) then
    raise exception 'only a verified venue can hand out a perk';
  end if;

  -- Re-derive eligibility HERE. Never trust a client that says "they earned it".
  select * into st from public.perk_status(vid, uid);
  if st is null or st.kind is null then
    raise exception 'this venue has no perk';
  end if;
  if not st.earned then
    raise exception 'not earned yet';
  end if;

  insert into public.perk_redemptions (venue_id, user_id, redeemed_by, kind, threshold, reward, currency)
  values (vid, uid, me, st.kind, st.threshold, st.reward, st.currency);
  return true;
end; $$;
revoke all on function public.redeem_perk(uuid, uuid) from public;
grant execute on function public.redeem_perk(uuid, uuid) to authenticated;
