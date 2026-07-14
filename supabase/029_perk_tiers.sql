-- ============================================================================
-- brewdiary — "Tiers": more than one reward per venue.
--
-- Industry data: tiered programmes beat single-tier by ~22% on engagement, and a
-- bar already thinks this way — "3 visits: a coffee. 10 visits: a free pour."
--
-- ── THE MODEL: independent punch-cards, not a ladder ────────────────────────
-- Each tier is its OWN card with its OWN clock. Reaching 10 doesn't consume the
-- coffee you earned at 3; claiming the coffee doesn't wipe your progress toward
-- the pour. That's what a guest expects, it's easy for a bartender to explain at
-- the bar, and it keeps the one rule that matters intact: progress toward a reward
-- counts SINCE YOU LAST CLAIMED THAT REWARD, so nothing can be claimed twice for
-- the same earn.
--
-- (A cumulative ladder — climb, claim the top, reset everything — was the other
-- option. It's harder to explain while someone is holding a drink, and it makes
-- the small reward worthless the moment you pass it. Not worth it.)
--
-- Jurisdiction rules are UNCHANGED and apply per-tier: the guard trigger fires on
-- every row, so a Dublin bar can't sneak an alcoholic reward in as "tier 2".
--
-- Runs on top of schema.sql + 002..028. venue_perks is currently EMPTY in prod
-- (checked), so re-keying it is safe.
-- ============================================================================

drop function if exists public.perk_status(uuid, uuid)   cascade;
drop function if exists public.redeem_perk(uuid, uuid)   cascade;
drop function if exists public.last_redeemed(uuid, uuid)  cascade;

-- ── venue_perks: one row per TIER, not one row per venue ────────────────────
alter table public.venue_perks add column if not exists id uuid default gen_random_uuid();
update public.venue_perks set id = gen_random_uuid() where id is null;
alter table public.venue_perks alter column id set not null;

alter table public.venue_perks drop constraint if exists venue_perks_pkey;
alter table public.venue_perks add primary key (id);

-- A venue can't offer the same reward twice at the same bar. Three tiers is plenty
-- (more is a loyalty scheme nobody can remember, and the research is blunt that
-- unattractive/confusing rewards are why people abandon these programmes).
create unique index if not exists venue_perks_tier_uniq
  on public.venue_perks (venue_id, kind, threshold);
create index if not exists venue_perks_venue_idx on public.venue_perks (venue_id);

-- ── redemptions now point at the TIER that was claimed ──────────────────────
alter table public.perk_redemptions
  add column if not exists perk_id uuid references public.venue_perks(id) on delete set null;
create index if not exists perk_redemptions_perk_idx
  on public.perk_redemptions (perk_id, user_id, redeemed_at desc);

-- ── the clock, now per TIER ─────────────────────────────────────────────────
create or replace function public.last_redeemed(pk uuid, uid uuid)
returns timestamptz
language sql stable security definer set search_path = public as $$
  select coalesce(max(r.redeemed_at), 'epoch'::timestamptz)
  from public.perk_redemptions r
  where r.perk_id = pk and r.user_id = uid;
$$;
revoke all on function public.last_redeemed(uuid, uuid) from public;
grant execute on function public.last_redeemed(uuid, uuid) to authenticated;

-- ── the guest's standing on EVERY tier at this venue ────────────────────────
-- One row per tier. Readable by the guest themselves, or by that venue's staff —
-- nobody else, and never anyone at another venue.
create or replace function public.perk_status(vid uuid, uid uuid)
returns table (
  perk_id uuid, kind text, threshold numeric, reward text, currency text,
  progress numeric, earned boolean, claims int
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); t record; since timestamptz; prog numeric;
begin
  if me is null then raise exception 'not signed in'; end if;
  if me <> uid and not public.is_venue_staff(vid, me) then
    raise exception 'not allowed to read that';
  end if;

  for t in
    select vp.id, vp.kind, vp.threshold, vp.reward, vp.currency
    from public.venue_perks vp
    where vp.venue_id = vid
    order by vp.threshold
  loop
    since := public.last_redeemed(t.id, uid);

    if t.kind = 'spend' then
      select coalesce(sum(se.amount), 0)::numeric into prog
      from public.spend_events se
      join public.parties room on room.id = se.party_id
      where room.venue_id = vid and se.subject_user_id = uid and se.created_at > since;
    else
      -- a visit is worth 1, or 2 if the bar called that night quiet (024)
      select coalesce(sum(public.visit_weight(vid, room.date)), 0)::numeric into prog
      from (
        select distinct m.party_id
        from public.party_members m
        join public.parties pr on pr.id = m.party_id
        where pr.venue_id = vid and m.user_id = uid and m.status = 'approved'
          and m.joined_at > since
      ) visits
      join public.parties room on room.id = visits.party_id;
    end if;

    perk_id   := t.id;
    kind      := t.kind;
    threshold := t.threshold;
    reward    := t.reward;
    currency  := t.currency;
    progress  := prog;
    earned    := prog >= t.threshold;
    claims    := (select count(*)::int from public.perk_redemptions r
                   where r.perk_id = t.id and r.user_id = uid);
    return next;
  end loop;
end; $$;
revoke all on function public.perk_status(uuid, uuid) from public;
grant execute on function public.perk_status(uuid, uuid) to authenticated;

-- ── the claim, now against ONE TIER ─────────────────────────────────────────
-- Staff of a VERIFIED venue. The server re-derives eligibility for THAT tier —
-- it never trusts a client that says "they earned it".
create or replace function public.redeem_perk(pk uuid, uid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p record; st record;
begin
  if me is null then raise exception 'not signed in'; end if;

  select vp.* into p from public.venue_perks vp where vp.id = pk;
  if not found then raise exception 'no such perk'; end if;

  if not public.is_venue_staff(p.venue_id, me) then
    raise exception 'only this venue''s staff can hand a perk over';
  end if;
  if not exists (select 1 from public.venues v where v.id = p.venue_id and v.verified) then
    raise exception 'only a verified venue can hand out a perk';
  end if;

  select * into st from public.perk_status(p.venue_id, uid) where perk_id = pk;
  if st is null or not st.earned then
    raise exception 'not earned yet';
  end if;

  insert into public.perk_redemptions
    (venue_id, user_id, redeemed_by, perk_id, kind, threshold, reward, currency)
  values (p.venue_id, uid, me, pk, p.kind, p.threshold, p.reward, p.currency);
  return true;
end; $$;
revoke all on function public.redeem_perk(uuid, uuid) from public;
grant execute on function public.redeem_perk(uuid, uuid) to authenticated;
