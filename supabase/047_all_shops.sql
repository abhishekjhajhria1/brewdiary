-- ============================================================================
-- brewdiary — EVERY KIND OF SHOP: cafés, restaurants, clubs, sweet shops, bakeries,
-- any shop — not only bars and liquor stores.
--
-- The venue layer was built around alcohol: a bar ('bar') and an off-licence ('store'),
-- with the loyalty card shaped by alcohol-promotion law (020–030). The venue app is for
-- every place that serves or sells to the public, and a mithai shop is not a bar.
--
-- ── THE ONE IDEA: what the law sees is what a place SELLS ────────────────────
--   on-trade alcohol   bar · club · a restaurant or café that serves alcohol
--                      → the BAR rules, unchanged (perk_policy's allow_* columns).
--   off-trade alcohol  store (a liquor store / off-licence)
--                      → the STORE rules, unchanged (030: its own permission,
--                        visits only, never an alcoholic reward).
--   no alcohol         sweet shop · bakery · shop · an unlicensed café or restaurant
--                      → alcohol-promotion law has nothing to say. A loyalty card for
--                        kaju katli is just a loyalty card: visits OR spend, any reward
--                        that isn't alcohol (it doesn't sell any).
--
-- Deny-by-default still holds for every class: a venue can only exist in a country we
-- have researched (a jurisdiction_policy row), because consumer and data-protection law
-- still differ. What changes is that a PROHIBITION country (alcohol_legal = false) is
-- closed only to places that sell alcohol — a sweet shop in one is a sweet shop.
--
-- ── ALSO ─────────────────────────────────────────────────────────────────────
--   • A COUNTER (store, sweet shop, bakery, shop) runs no rooms: nobody hangs out at a
--     till, and a board of who's-in-the-shop is surveillance (030's reasoning, widened).
--     Its visits are staff-punched (record_visit), once a day.
--   • serves_alcohol is server-normalised for the fixed kinds (a bar always serves, a
--     bakery never does), the owner's choice only for a restaurant or café — and, like
--     country and kind, fixed once the venue is verified (045's guard, widened): flipping
--     a licensed bar to "no alcohol" would otherwise dodge the alcohol rules.
--   • Discover may list a no-alcohol venue anywhere we operate; an alcohol venue still
--     only where the bar layer is lawful (027).
--
-- Runs on top of 002..046.
-- ============================================================================

-- ── 1. the kinds, and whether the place serves alcohol ──────────────────────
alter table public.venues drop constraint if exists venues_kind_check;
alter table public.venues add constraint venues_kind_check
  check (kind in ('bar', 'club', 'restaurant', 'cafe', 'store', 'sweet_shop', 'bakery', 'shop'));

alter table public.venues add column if not exists serves_alcohol boolean not null default true;
comment on column public.venues.serves_alcohol is
  'Server-normalised: always true for bar/club/store, always false for sweet_shop/bakery/shop; '
  'the owner''s choice only for restaurant/cafe. Fixed once the venue is verified.';

-- Fixed kinds are set by the server, whatever the client sends (like currency, 022).
create or replace function public.venues_set_alcohol()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.kind in ('bar', 'club', 'store') then
    new.serves_alcohol := true;
  elsif new.kind in ('sweet_shop', 'bakery', 'shop') then
    new.serves_alcohol := false;
  end if;
  return new;
end; $$;
drop trigger if exists venues_alcohol on public.venues;
create trigger venues_alcohol before insert or update of kind, serves_alcohol on public.venues
  for each row execute function public.venues_set_alcohol();

-- Belt and braces: the table can't hold a contradiction even if the trigger were dropped.
alter table public.venues drop constraint if exists venues_serves_alcohol_check;
alter table public.venues add constraint venues_serves_alcohol_check check (
  (kind in ('bar', 'club', 'store') and serves_alcohol)
  or (kind in ('sweet_shop', 'bakery', 'shop') and not serves_alcohol)
  or kind in ('restaurant', 'cafe')
);

-- ── 2. what the law sees ─────────────────────────────────────────────────────
create or replace function public.venue_legal_class(p_kind text, p_serves_alcohol boolean)
returns text language sql immutable set search_path = public as $$
  select case
    when p_kind = 'store' then 'off_trade'
    when p_kind in ('bar', 'club') then 'on_trade'
    when p_kind in ('restaurant', 'cafe') and coalesce(p_serves_alcohol, false) then 'on_trade'
    else 'no_alcohol'
  end;
$$;
grant execute on function public.venue_legal_class(text, boolean) to anon, authenticated;

-- A counter: you buy and leave. No rooms; visits are punched at the till.
create or replace function public.venue_is_counter(p_kind text)
returns boolean language sql immutable set search_path = public as $$
  select p_kind in ('store', 'sweet_shop', 'bakery', 'shop');
$$;
grant execute on function public.venue_is_counter(text) to anon, authenticated;

-- ── 3. where a venue may exist ───────────────────────────────────────────────
-- Researched countries only (deny by default), and a place that sells alcohol only
-- where alcohol is legal.
create or replace function public.venues_guard_jurisdiction()
returns trigger language plpgsql security definer set search_path = public as $$
declare pol record;
begin
  select * into pol from public.perk_policy(new.country, coalesce(new.region, ''));
  if pol is null or pol.alcohol_legal is null then
    raise exception 'brewdiary does not run venue features in % yet', new.country
      using hint = 'We open a country only once we have researched its rules.';
  end if;
  if not pol.alcohol_legal and public.venue_legal_class(new.kind, new.serves_alcohol) <> 'no_alcohol' then
    raise exception 'a place that sells alcohol can''t run on brewdiary in %', new.country
      using hint = 'The diary works everywhere; a venue that sells no alcohol can join too.';
  end if;
  return new;
end; $$;
drop trigger if exists venues_jurisdiction on public.venues;
create trigger venues_jurisdiction before insert or update of country, region, kind, serves_alcohol on public.venues
  for each row execute function public.venues_guard_jurisdiction();

-- ── 4. the loyalty card, by what the place sells ─────────────────────────────
create or replace function public.venue_perks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare c text; r text; k text; alc boolean; cls text; pol record;
begin
  select v.country, coalesce(v.region, ''), v.kind, v.serves_alcohol
    into c, r, k, alc
    from public.venues v where v.id = new.venue_id;
  cls := public.venue_legal_class(k, alc);

  select * into pol from public.perk_policy(c, r);

  -- NO ROW = a jurisdiction we have not researched = NO. Silence means no — for every class.
  if pol is null then
    raise exception 'loyalty perks are not permitted for a venue in % %', c, r
      using hint = 'We have not researched that jurisdiction yet.';
  end if;

  if cls = 'no_alcohol' then
    -- Alcohol-promotion law has nothing to say about a card at a place that sells no
    -- alcohol. The one rule: its reward can't be alcohol — it doesn't sell any.
    if new.reward_alcoholic then
      raise exception 'this venue sells no alcohol, so its reward can''t be alcohol';
    end if;
    return new;
  end if;

  if pol.allow_perks is null or not pol.allow_perks then
    raise exception 'loyalty perks are not permitted for a venue in % %', c, r
      using hint = 'Either the law there forbids it, or we have not researched that jurisdiction yet.';
  end if;

  if cls = 'off_trade' then
    -- An off-licence needs its own permission (030). At a bottle shop the visit IS the sale.
    if not pol.allow_offtrade_perks then
      raise exception 'a loyalty card is not permitted for an off-licence in % %', c, r
        using hint = 'At an off-licence a visit is a purchase, so the card would be an alcohol loyalty scheme.';
    end if;
    if new.reward_alcoholic then
      raise exception 'an off-licence reward can never be alcohol'
        using hint = 'Offer something else — a glass, a coffee, a tasting, a discount on a non-alcoholic line.';
    end if;
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

-- Re-test every perk when what decides the law changes — now including serves_alcohol.
drop trigger if exists venues_recheck_perks on public.venues;
create trigger venues_recheck_perks after update of kind, country, region, serves_alcohol on public.venues
  for each row execute function public.venues_recheck_perks();

-- ── 5. a counter runs no rooms ───────────────────────────────────────────────
create or replace function public.parties_guard_venue_kind()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.venue_id is not null
     and public.venue_is_counter((select v.kind from public.venues v where v.id = new.venue_id)) then
    raise exception 'a counter does not run rooms'
      using hint = 'Rooms are for spending an evening somewhere. A shop punches a card at the till instead.';
  end if;
  return new;
end; $$;

-- ── 6. a counter's visits are the punches (perk_status, venue_visits) ───────
create or replace function public.perk_status(vid uuid, uid uuid)
returns table (
  perk_id uuid, kind text, threshold numeric, reward text, currency text,
  progress numeric, earned boolean, claims int
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); t record; since timestamptz; prog numeric; vkind text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if me <> uid and not public.venue_can(vid, me, 'perks.redeem') then
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
      -- Spend is recorded against a room (017); a counter has no rooms, so a counter's
      -- spend perk accrues nothing until the till records spend of its own.
      select coalesce(sum(se.amount), 0)::numeric into prog
      from public.spend_events se
      join public.parties room on room.id = se.party_id
      where room.venue_id = vid and se.subject_user_id = uid and se.created_at > since;

    elsif public.venue_is_counter(vkind) then
      -- A counter has no rooms. Its visits are the punches staff recorded — one a day,
      -- weighted by quiet nights exactly as a bar's are.
      select coalesce(sum(public.visit_weight(vid, c.on_date)), 0)::numeric into prog
      from public.venue_checkins c
      where c.venue_id = vid and c.user_id = uid and c.created_at > since;

    else
      -- a visit is worth 1, or 2 if the venue called that night quiet (024)
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

create or replace function public.venue_visits(vid uuid)
returns int
language sql stable security definer set search_path = public as $$
  select case
    when public.venue_is_counter((select v.kind from public.venues v where v.id = vid)) then
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

-- ── 7. fixed once verified: serves_alcohol joins country/region/kind/slug ────
create or replace function public.venues_guard_admin_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;   -- the service role (brewdiary) may
  if new.verified is distinct from old.verified
     or new.created_by is distinct from old.created_by then
    raise exception 'verified/ownership are set by brewdiary, not the venue';
  end if;
  if old.verified and (
       new.country        is distinct from old.country
    or new.region         is distinct from old.region
    or new.kind           is distinct from old.kind
    or new.slug           is distinct from old.slug
    or new.serves_alcohol is distinct from old.serves_alcohol) then
    raise exception 'a verified venue''s country, region, kind, alcohol licence and web address are fixed'
      using hint = 'Ask brewdiary to change them — they decide which perks are lawful, and the address is printed on your tables.';
  end if;
  return new;
end; $$;

-- ── 8. Discover: list the place, never the offer ─────────────────────────────
-- An alcohol venue only where the bar layer is lawful (027's conservative gate, kept);
-- a no-alcohol venue anywhere we operate. Still NO join to venue_perks or menus.
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
  where v.verified
    and (jp.allow_perks or public.venue_legal_class(v.kind, v.serves_alcohol) = 'no_alcohol')
    and (in_country is null or v.country = upper(in_country))
  -- NOTE: public.venue_perks is deliberately NOT joined. Listing a place is a directory
  -- entry; listing its offer is advertising. Don't.
  order by open_tonight desc, v.name
  limit greatest(least(coalesce(lim, 30), 100), 1);
$$;
revoke all on function public.discover_venues(text, int) from public;
grant execute on function public.discover_venues(text, int) to anon, authenticated;
