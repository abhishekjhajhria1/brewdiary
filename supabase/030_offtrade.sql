-- ============================================================================
-- brewdiary — "Off-trade": liquor stores / bottle shops / off-licences.
--
-- ── WHY A STORE IS NOT JUST A QUIETER BAR ───────────────────────────────────
-- At a BAR, a visit and a purchase are different events. You can walk into a pub,
-- meet someone, buy nothing. That gap is the whole reason our visits punch-card is
-- lawful in places that ban alcohol loyalty schemes: we reward PRESENCE, and the
-- prize is not a drink.
--
-- At an OFF-LICENCE that gap DOES NOT EXIST. Nobody hangs out in a bottle shop.
-- A "visit" is a purchase, and the purchase is alcohol. So a visits punch-card at
-- a store is functionally "buy ten times, get a reward" — which is precisely the
-- mischief these statutes target:
--
--   IE  Public Health (Alcohol) Act 2018 s.23 + the Sale and Supply of Alcohol
--       Products Regulations 2020 (in force 11 Jan 2021): bans "the award of, or
--       use of, bonus or loyalty card points IN RELATION TO THE SALE of alcohol
--       products". Not just the reward — the AWARD.
--   NI  Licensing and Registration of Clubs (Amendment) Act (NI) 2021, Art. 57ZB:
--       bans awarding OR redeeming loyalty points for the purchase of intoxicating
--       liquor in ALL LICENSED PREMISES — on-trade included. Fine up to £5,000, and
--       the LICENSEE carries it. Northern Ireland is a region of GB and had been
--       silently inheriting England's row: fixed below.
--   SCO Alcohol etc. (Scotland) Act 2010: off-sales promotions may occur only
--       within the alcohol display area, and quantity discounts in off-sales are
--       banned. An app-side punch-card is neither, but it is close enough to the
--       line that we do not cross it without a solicitor.
--
-- So off-trade gets its OWN policy axis, DENY BY DEFAULT — `allow_offtrade_perks`.
-- A country that permits a bar punch-card does NOT thereby permit a store one; it
-- has to be researched and switched on by name.
--
-- ── TWO RULES WE IMPOSE ON OURSELVES, TIGHTER THAN ANY LAW ───────────────────
-- Wherever a store perk IS lawful, it is still:
--   • VISITS ONLY  — never spend. Spend at an off-licence is literally the alcohol
--                    transaction; rewarding it is rewarding volume.
--   • NON-ALCOHOLIC REWARD ONLY — no exceptions, not even in India where the law
--                    would permit it. A bar's alcoholic prize is one poured drink.
--                    A bottle shop's is a BOTTLE. "Buy nine bottles, get the tenth
--                    free" is the exact loop this product refuses to build.
-- These are enforced in the trigger, not in the UI, so no client can talk its way
-- around them.
--
-- ── ALSO IN HERE ────────────────────────────────────────────────────────────
--   • A CRITICAL FIX to venue_insights(): 029 made perk_status() return one row per
--     tier, which broke a scalar subquery there. See below.
--   • venue_checkins: a store has no rooms, so a visit has to be recorded BY STAFF
--     (one per guest per day, server-clamped). Same rule as spend: a guest can
--     never punch their own card.
--
-- Runs on top of schema.sql + 002..029.
-- ============================================================================



-- ────────────────────────────────────────────────────────────────────────────
-- 1. What KIND of venue is this?
-- ────────────────────────────────────────────────────────────────────────────
alter table public.venues
  add column if not exists kind text not null default 'bar'
  check (kind in ('bar', 'store'));

comment on column public.venues.kind is
  'bar = on-trade (drink here). store = off-trade (carry out). A store''s perks are '
  'governed by allow_offtrade_perks, which is a SEPARATE and stricter permission.';


-- ────────────────────────────────────────────────────────────────────────────
-- 2. The off-trade permission — deny by default.
-- ────────────────────────────────────────────────────────────────────────────
alter table public.jurisdiction_policy
  add column if not exists allow_offtrade_perks boolean not null default false;

-- Switched on ONLY where an off-licence loyalty scheme (visits, non-alcoholic
-- prize) is positively lawful. Every other country stays false until researched —
-- including ones where the BAR perk is fine. Silence still means no.
--
--   IN — no loyalty restriction; it's alcohol ADVERTISING that's restricted, and a
--        private punch-card between one guest and one shop isn't an advert.
--   US — federal "tied house" law reaches suppliers, not a retailer's own card.
--        MA and UT keep their region rows (both already false by default).
--   GB — England & Wales: off-trade alcohol loyalty is plainly lawful (a Clubcard
--        earns points on wine). Scotland and NI get their own rows below.
--   AU — off-trade loyalty schemes are established and lawful.
update public.jurisdiction_policy
   set allow_offtrade_perks = true
 where region = '' and country in ('IN', 'US', 'GB', 'AU');

-- NORTHERN IRELAND. Art. 57ZB catches ALL licensed premises, not just off-licences,
-- so we switch the WHOLE venue layer off here rather than try to thread a needle in
-- a jurisdiction that fines the licensee £5,000 for getting it wrong. Belfast bars
-- keep every non-perk feature; they simply get no punch-card.
insert into public.jurisdiction_policy
  (country, region, allow_perks, allow_alcohol_reward, allow_spend_perk,
   allow_offtrade_perks, alcohol_legal, min_age, note)
values
  ('GB', 'NIR', false, false, false, false, true, 18,
   'Northern Ireland bans loyalty and membership rewards on alcohol in all licensed premises (Art. 57ZB).'),
-- SCOTLAND. The bar punch-card stands (it is not a "drinks promotion": no alcohol
-- is given away or discounted). Off-sales promotion rules are tight enough that we
-- do not run a store card here without advice.
  ('GB', 'SCT', true, false, false, false, true, 18,
   'Scotland restricts off-sales promotions to the alcohol display area — no store card here.')
on conflict (country, region) do update
  set allow_perks          = excluded.allow_perks,
      allow_alcohol_reward = excluded.allow_alcohol_reward,
      allow_spend_perk     = excluded.allow_spend_perk,
      allow_offtrade_perks = excluded.allow_offtrade_perks,
      alcohol_legal        = excluded.alcohol_legal,
      min_age              = excluded.min_age,
      note                 = excluded.note;

-- IRELAND: the bar card survives (points accrue for turning up, and the prize is
-- never alcohol, so nothing is awarded "in relation to the sale of alcohol"). The
-- store card does not — at an off-licence, turning up IS the sale. Already false by
-- default; recorded here so the reasoning isn't lost.
--   → IE.allow_offtrade_perks stays FALSE. Deliberately. Do not "fix" this.


-- ────────────────────────────────────────────────────────────────────────────
-- 3. perk_policy() gains the new axis.
--
-- Return type changes → drop + recreate. Parameters stay p_-prefixed: 028 exists
-- because a parameter named `country` was silently shadowed by the COLUMN named
-- `country`, and every venue on earth got judged by Massachusetts law. Never again.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.perk_policy(text, text) cascade;

create or replace function public.perk_policy(p_country text, p_region text default null)
returns table (
  allow_perks boolean, allow_alcohol_reward boolean, allow_spend_perk boolean,
  allow_offtrade_perks boolean, min_age int, alcohol_legal boolean
)
language sql stable set search_path = public as $$
  select jp.allow_perks, jp.allow_alcohol_reward, jp.allow_spend_perk,
         jp.allow_offtrade_perks, jp.min_age, jp.alcohol_legal
  from public.jurisdiction_policy jp
  where jp.country = upper(coalesce(p_country, ''))
    and jp.region  in ('', upper(coalesce(p_region, '')))
  order by (jp.region <> '') desc   -- a region-specific row beats the country row
  limit 1;
$$;
revoke all on function public.perk_policy(text, text) from public;
grant execute on function public.perk_policy(text, text) to anon, authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 4. The perk guard — now kind-aware.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.venue_perks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare c text; r text; k text; pol record;
begin
  select v.country, coalesce(v.region, ''), v.kind
    into c, r, k
    from public.venues v where v.id = new.venue_id;

  select * into pol from public.perk_policy(c, r);

  -- NO ROW = a jurisdiction we have not researched = NO. Silence means no.
  if pol is null or pol.allow_perks is null or not pol.allow_perks then
    raise exception 'loyalty perks are not permitted for a venue in % %', c, r
      using hint = 'Either the law there forbids it, or we have not researched that jurisdiction yet.';
  end if;

  if k = 'store' then
    -- An off-licence needs its own permission. A country allowing a BAR card does
    -- not thereby allow a STORE card — at a bottle shop the visit IS the sale.
    if not pol.allow_offtrade_perks then
      raise exception 'a loyalty card is not permitted for an off-licence in % %', c, r
        using hint = 'At an off-licence a visit is a purchase, so the card would be an alcohol loyalty scheme.';
    end if;
    -- OUR rule, stricter than any law: a bar's alcoholic prize is one poured drink;
    -- a bottle shop's is a bottle. Not a loop we will build, anywhere.
    if new.reward_alcoholic then
      raise exception 'an off-licence reward can never be alcohol'
        using hint = 'Offer something else — a glass, a coffee, a tasting, a discount on a non-alcoholic line.';
    end if;
    -- Spend at an off-licence IS the alcohol transaction. Visits only.
    if new.kind = 'spend' then
      raise exception 'an off-licence perk must count visits, not money spent'
        using hint = 'Spend at an off-licence is the alcohol purchase itself.';
    end if;
  else
    if new.reward_alcoholic and not pol.allow_alcohol_reward then
      raise exception 'a free or discounted alcoholic drink cannot be a loyalty reward in %', c
        using hint = 'Offer something non-alcoholic — a coffee, a dessert, priority entry.';
    end if;
    if new.kind = 'spend' and not pol.allow_spend_perk then
      raise exception 'a spend-based loyalty perk is not permitted in %', c
        using hint = 'Reward visits instead of money spent.';
    end if;
  end if;

  return new;
end; $$;

drop trigger if exists venue_perks_policy on public.venue_perks;
create trigger venue_perks_policy before insert or update on public.venue_perks
  for each row execute function public.venue_perks_guard();

-- Recreated verbatim (the cascade above takes it with perk_policy). Unchanged.
create or replace function public.venues_guard_jurisdiction()
returns trigger language plpgsql security definer set search_path = public as $$
declare pol record;
begin
  select * into pol from public.perk_policy(new.country, coalesce(new.region, ''));
  -- An unknown country is NOT a licence to operate: no row → we don't run venues there.
  if pol is null or pol.alcohol_legal is null or not pol.alcohol_legal then
    raise exception 'brewdiary does not run venue features in %', new.country
      using hint = 'The diary works everywhere; the bar layer does not.';
  end if;
  return new;
end; $$;

drop trigger if exists venues_jurisdiction on public.venues;
create trigger venues_jurisdiction before insert or update of country, region on public.venues
  for each row execute function public.venues_guard_jurisdiction();

-- A venue that switches kind ('bar' → 'store') must not carry an unlawful perk over
-- with it. Re-run every perk through the guard when the kind or the country moves.
create or replace function public.venues_recheck_perks()
returns trigger language plpgsql security definer set search_path = public as $$
declare p record;
begin
  for p in select * from public.venue_perks where venue_id = new.id loop
    -- touching the row re-fires venue_perks_policy, which will raise if it's now unlawful
    update public.venue_perks set updated_at = now() where id = p.id;
  end loop;
  return new;
end; $$;

drop trigger if exists venues_recheck_perks on public.venues;
create trigger venues_recheck_perks after update of kind, country, region on public.venues
  for each row execute function public.venues_recheck_perks();


-- ────────────────────────────────────────────────────────────────────────────
-- 5. venue_checkins — how a store records a visit.
--
-- A bar records a visit implicitly: you joined the room. A store has no room, so a
-- member of staff has to punch the card. That means it is STAFF-WRITTEN, exactly
-- like spend — a guest can NEVER punch their own card, or the whole thing is a
-- self-service free-drinks machine.
--
-- No insert policy. No update policy. No delete policy. The only way a row lands
-- here is record_visit() below.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.venue_checkins (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  -- NULLABLE on purpose: a bartender leaving the venue must not delete the visits
  -- they recorded, and `not null` + `on delete set null` is a contradiction that
  -- only detonates later, at the moment someone quits.
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  on_date     date not null default current_date
);
alter table public.venue_checkins enable row level security;

-- ONE punch per guest per store per day. A shop cannot punch your card ten times
-- because you bought ten bottles — that would turn a visits card back into a
-- volume card, which is the thing we refused to build.
create unique index if not exists venue_checkins_one_a_day
  on public.venue_checkins (venue_id, user_id, on_date);
create index if not exists venue_checkins_user_idx
  on public.venue_checkins (venue_id, user_id, created_at desc);

drop policy if exists venue_checkins_read on public.venue_checkins;
create policy venue_checkins_read on public.venue_checkins for select
  using (user_id = auth.uid() or public.is_venue_staff(venue_id, auth.uid()));

/** Staff of a VERIFIED store punch a guest's card. Idempotent per day. */
create or replace function public.record_visit(vid uuid, uid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if me = uid then raise exception 'you cannot punch your own card'; end if;
  if not public.is_venue_staff(vid, me) then
    raise exception 'only this venue''s staff can record a visit';
  end if;
  if not exists (select 1 from public.venues v where v.id = vid and v.verified) then
    raise exception 'only a verified venue can record a visit';
  end if;

  insert into public.venue_checkins (venue_id, user_id, recorded_by)
  values (vid, uid, me)
  on conflict (venue_id, user_id, on_date) do nothing;   -- twice in a day is once

  return true;
end; $$;
revoke all on function public.record_visit(uuid, uuid) from public;
grant execute on function public.record_visit(uuid, uuid) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 6. perk_status() counts a store's visits from the check-in book.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.perk_status(vid uuid, uid uuid)
returns table (
  perk_id uuid, kind text, threshold numeric, reward text, currency text,
  progress numeric, earned boolean, claims int
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); t record; since timestamptz; prog numeric; vkind text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if me <> uid and not public.is_venue_staff(vid, me) then
    raise exception 'not allowed to read that';
  end if;

  select v.kind into vkind from public.venues v where v.id = vid;

  for t in
    select vp.id, vp.kind, vp.threshold, vp.reward, vp.currency
    from public.venue_perks vp
    where vp.venue_id = vid
    order by vp.threshold
  loop
    since := public.last_redeemed(t.id, uid);

    if t.kind = 'spend' then
      -- (Unreachable for a store — the guard forbids a spend perk there.)
      select coalesce(sum(se.amount), 0)::numeric into prog
      from public.spend_events se
      join public.parties room on room.id = se.party_id
      where room.venue_id = vid and se.subject_user_id = uid and se.created_at > since;

    elsif vkind = 'store' then
      -- A store has no rooms. Its visits are the punches staff recorded — one a day,
      -- weighted by quiet nights exactly as a bar's are.
      select coalesce(sum(public.visit_weight(vid, c.on_date)), 0)::numeric into prog
      from public.venue_checkins c
      where c.venue_id = vid and c.user_id = uid and c.created_at > since;

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

-- The guest's own count, for their card. Same branch.
create or replace function public.venue_visits(vid uuid)
returns int
language sql stable security definer set search_path = public as $$
  select case
    when (select v.kind from public.venues v where v.id = vid) = 'store' then
      (select count(*)::int from public.venue_checkins c
        where c.venue_id = vid and c.user_id = auth.uid())
    else
      (select count(distinct m.party_id)::int
         from public.party_members m
         join public.parties party on party.id = m.party_id
        where party.venue_id = vid and m.user_id = auth.uid() and m.status = 'approved')
  end;
$$;
revoke all on function public.venue_visits(uuid) from public;
grant execute on function public.venue_visits(uuid) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 7. A store has no rooms.
--
-- A "room" is people drinking together in a place. A bottle shop is not that, and a
-- kiosk board of who's-in-the-shop-tonight is a surveillance feature with no upside.
-- Block it at the source rather than merely hiding the button.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.parties_guard_venue_kind()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.venue_id is not null
     and (select v.kind from public.venues v where v.id = new.venue_id) = 'store' then
    raise exception 'an off-licence does not run rooms'
      using hint = 'Rooms are for drinking together somewhere. A store punches a card instead.';
  end if;
  return new;
end; $$;

drop trigger if exists parties_venue_kind on public.parties;
create trigger parties_venue_kind before insert or update of venue_id on public.parties
  for each row execute function public.parties_guard_venue_kind();


-- ────────────────────────────────────────────────────────────────────────────
-- 8. Discover carries the kind, so a guest knows if it's a bar or a bottle shop.
-- Still NO join to venue_perks: listing a venue is a directory entry; listing its
-- offer is alcohol advertising. That line does not move.
-- ────────────────────────────────────────────────────────────────────────────
drop function if exists public.discover_venues(text, int) cascade;

create or replace function public.discover_venues(in_country text default null, lim int default 30)
returns table (name text, slug text, city text, country text, kind text, open_tonight boolean)
language sql stable security definer set search_path = public as $$
  select v.name,
         v.slug,
         v.city,
         v.country,
         v.kind,
         exists (
           select 1 from public.parties r
           where r.venue_id = v.id
             and r.date >= current_date - 1
             and public.board_live(r)
         ) as open_tonight
  from public.venues v
  join public.jurisdiction_policy jp
    on jp.country = v.country
   and jp.region  = ''
  where v.verified                        -- an unverified venue is nobody's recommendation
    and jp.allow_perks                    -- unchanged gate: the conservative one. Countries that
                                          -- ban loyalty schemes (TH, PL, NO…) also police alcohol
                                          -- ADVERTISING hardest, and a directory listing is the
                                          -- thing most likely to be read as one. Don't widen this
                                          -- in a migration that's about something else.
    and (in_country is null or v.country = upper(in_country))
  order by open_tonight desc, v.name
  limit greatest(least(coalesce(lim, 30), 100), 1);
$$;
revoke all on function public.discover_venues(text, int) from public;
grant execute on function public.discover_venues(text, int) to anon, authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 9. CRITICAL: repair venue_insights() — a 029 regression, plus store visits.
--
-- 029 turned perk_status() into a SET (one row per tier). venue_insights still had
--     where (select earned from public.perk_status(vid, u)) is true
-- A scalar subquery over a multi-row set raises "more than one row returned by a
-- subquery used as an expression". Any venue with 2+ tiers and 1+ guest would have
-- 500'd the manager's Insights panel. It's latent only because no venue has perks
-- yet. "Sitting on an unclaimed reward" now means: ANY tier is earned.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.venue_insights(vid uuid, days int default 30)
returns table (
  rooms int, guests int, new_guests int, returning_guests int,
  quiet_visits int, other_visits int,
  perks_earned int, perks_claimed int,
  tabs int, takings numeric, kudos int
)
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  win timestamptz := now() - make_interval(days => greatest(coalesce(days, 30), 1));
  k int := public.k_anon();
  n_guests int; n_new int; n_ret int; n_earned int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_venue_manager(vid, me) then
    raise exception 'only this venue''s managers can see this';
  end if;

  -- Everyone who was here: a room they joined (bar), or a card staff punched
  -- (store). A store has no rooms, so without the second half of this union its
  -- insights would all read zero. Kept as a CTE, not a temp table — this function is
  -- STABLE and must not write anything, not even scratch.
  with seen as (
    select m.user_id, m.joined_at as seen_at
      from public.party_members m
      join public.parties r on r.id = m.party_id
     where r.venue_id = vid and m.status = 'approved'
    union all
    select c.user_id, c.created_at as seen_at
      from public.venue_checkins c
     where c.venue_id = vid
  ),
  -- One row per guest: when we FIRST saw them, and when we last did. A guest is
  -- "new" iff their first-ever sighting falls inside the window — which is a plain
  -- min() over their own rows, no correlated subquery needed.
  per_guest as (
    select s.user_id, min(s.seen_at) as first_seen, max(s.seen_at) as last_seen
      from seen s group by s.user_id
  )
  select count(*), count(*) filter (where g.first_seen > win)
    into n_guests, n_new
    from per_guest g
   where g.last_seen > win;
  n_ret := n_guests - n_new;

  -- Guests sitting on an unclaimed reward — ANY tier of it. A COUNT, never a name.
  -- (029 made perk_status a SET; the old scalar subquery here would now raise.)
  with seen as (
    select distinct m.user_id
      from public.party_members m
      join public.parties r on r.id = m.party_id
     where r.venue_id = vid and m.status = 'approved'
    union
    select distinct c.user_id from public.venue_checkins c where c.venue_id = vid
  )
  select count(*) into n_earned
  from seen
  where exists (select 1 from public.perk_status(vid, seen.user_id) ps where ps.earned);

  return query
  select
    (select count(*)::int from public.parties r
      where r.venue_id = vid and r.created_at > win),

    n_guests::int,

    -- THE SUPPRESSION. Below k, a split identifies a person; hand back NULL.
    case when n_guests >= k then n_new::int end,
    case when n_guests >= k then n_ret::int end,

    -- quiet vs. ordinary nights: rooms for a bar, punched cards for a store
    (select coalesce(count(*) filter (where public.visit_weight(vid, d.day) = 2), 0)::int from (
        select r.date as day from public.party_members m join public.parties r on r.id = m.party_id
         where r.venue_id = vid and m.status = 'approved' and m.joined_at > win
        union all
        select c.on_date from public.venue_checkins c where c.venue_id = vid and c.created_at > win
      ) d),
    (select coalesce(count(*) filter (where public.visit_weight(vid, d.day) <> 2), 0)::int from (
        select r.date as day from public.party_members m join public.parties r on r.id = m.party_id
         where r.venue_id = vid and m.status = 'approved' and m.joined_at > win
        union all
        select c.on_date from public.venue_checkins c where c.venue_id = vid and c.created_at > win
      ) d),

    case when n_guests >= k then n_earned::int end,

    (select count(*)::int from public.perk_redemptions pr
      where pr.venue_id = vid and pr.redeemed_at > win),

    (select count(*)::int from public.spend_events se
      join public.parties r on r.id = se.party_id
     where r.venue_id = vid and se.created_at > win),
    (select coalesce(sum(se.amount), 0)::numeric from public.spend_events se
      join public.parties r on r.id = se.party_id
     where r.venue_id = vid and se.created_at > win),

    (select count(*)::int from public.staff_kudos sk
      where sk.venue_id = vid and sk.created_at > win);
end; $$;
revoke all on function public.venue_insights(uuid, int) from public;
grant execute on function public.venue_insights(uuid, int) to authenticated;
