-- ============================================================================
-- brewdiary — the AREA HEAT MAP: what the neighbourhoods around a venue are like.
--
-- A manager asked to see "the kind of people outside": where people go out near
-- them, what they like, when they come out, and what a night costs there. This is
-- that map, built the only way the house rules allow:
--
--   • ONLY PEOPLE WHO SAID YES. A guest is counted only with share_trends (039/041)
--     AND the new share_nights_out ("count me in neighbourhood maps"), both default
--     OFF. Spend also needs the VENUE's yes (area_share): a venue's ledger is its
--     own business, and a venue that shares is the only kind that can see the spend
--     layer (give to get).
--   • GROUPS, NEVER PEOPLE. The map is a grid of geohash-5 cells (~5 km) inside the
--     venue's geohash-4 area (~40 km). A cell appears only with 5+ consenting people
--     AND 3+ venues in it, so no cell is one person or one competitor's till. Counts
--     are rounded DOWN to a multiple of 5 and the window is whole days of fixed
--     length (7/30/90), so subtracting two answers can't isolate someone.
--   • TASTE, NEVER DEMOGRAPHICS. "Kinds of people" are taste personas derived from
--     what each person logged (coffee & tea, beer, wine, cocktails & spirits,
--     zero-proof, explorer). There is no age, gender, religion or origin anywhere
--     in the schema, and nothing here would add one.
--   • BANDS, NEVER FIGURES. Spend is the cell's typical tab as a band floor
--     (spend_band_floor, the SQL twin of money.ts spendBand()).
--   • NO NAME, NO VENUE, NO ROW PER PERSON in the output: (cell, layer, label, people).
--
-- Also here:
--   • area_taste_trends matches on the ~40 km city cell whatever precision a venue
--     stores, so a venue can keep a finer (geohash-6, ~1 km) location for the map.
--   • a verified venue may refine its location, never move it to another area — the
--     map is only ever of the place the venue actually is.
--
-- Runs on top of 002..047.
-- ============================================================================

-- ── 1. the two opt-ins (default OFF) ────────────────────────────────────────
alter table public.profiles add column if not exists share_nights_out boolean not null default false;
alter table public.venues   add column if not exists area_share      boolean not null default false;

-- A geohash is base32 without a, i, l, o. Existing rows are left alone (not valid);
-- new writes must be a real cell, not free text smuggled into a location column.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'venues_geohash_chars') then
    alter table public.venues add constraint venues_geohash_chars
      check (geohash is null or geohash ~ '^[0-9b-hjkmnp-z]{1,12}$') not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_trends_geo_chars') then
    alter table public.profiles add constraint profiles_trends_geo_chars
      check (trends_geo is null or trends_geo ~ '^[0-9b-hjkmnp-z]{1,12}$') not valid;
  end if;
end $$;

-- ── 2. a verified venue stays in its area ───────────────────────────────────
create or replace function public.venues_guard_geohash()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;   -- the service role (brewdiary) may
  if old.verified and old.geohash is not null and new.geohash is not null
     and left(new.geohash, 4) <> left(old.geohash, 4) then
    raise exception 'a verified venue can''t move to another area'
      using hint = 'You can refine your location within your area. To move, ask brewdiary.';
  end if;
  return new;
end; $$;

drop trigger if exists venues_guard_geohash on public.venues;
create trigger venues_guard_geohash before update of geohash on public.venues
  for each row execute function public.venues_guard_geohash();

-- ── 3. area_taste_trends on the city cell, whatever precision was stored ────
create or replace function public.area_taste_trends(in_geo text, days_back int default 30)
returns table (kind text, name text, users int, logs int)
language sql stable security definer set search_path = public as $$
  with window_entries as (
    select e.user_id, e.drink, e.mood
    from public.entries e
    join public.profiles p on p.id = e.user_id
    where p.share_trends
      and p.trends_geo is not null
      and char_length(trim(coalesce(in_geo, ''))) >= 4
      and left(p.trends_geo, 4) = left(trim(in_geo), 4)
      and e.date >= current_date - make_interval(days => greatest(1, least(days_back, 90)))::interval
  ),
  drinks as (
    select 'drink'::text as kind,
           min(drink) as name,
           count(distinct user_id)::int as users,
           count(*)::int as logs
    from window_entries
    group by lower(trim(drink))
    having count(distinct user_id) >= 5
  ),
  moods as (
    select 'mood'::text as kind,
           min(mood) as name,
           count(distinct user_id)::int as users,
           count(*)::int as logs
    from window_entries
    where mood is not null and trim(mood) <> ''
    group by lower(trim(mood))
    having count(distinct user_id) >= 5
  )
  select * from (
    (select * from drinks order by users desc, logs desc limit 6)
    union all
    (select * from moods order by users desc, logs desc limit 6)
  ) t;
$$;

revoke all on function public.area_taste_trends(text, int) from public;
grant execute on function public.area_taste_trends(text, int) to authenticated;

-- ── 4. spend bands in SQL (the twin of money.ts spendBand) ──────────────────
-- Bands are ×1, ×2, ×5, ×10, ×20 of a per-currency step. Returns the band's FLOOR,
-- or 0 for "under the first band". tests/areaMap.test.ts pins the steps to money.ts.
create or replace function public.spend_band_floor(amount numeric, currency text)
returns numeric language sql immutable set search_path = public as $$
  with s as (
    select coalesce((
      select v.step from (values
        ('INR', 500), ('JPY', 3000), ('KRW', 30000), ('THB', 500), ('ZAR', 250), ('MXN', 250),
        ('BRL', 100), ('TRY', 500), ('NOK', 250), ('SEK', 250), ('PLN', 100), ('AED', 100)
      ) v(code, step) where v.code = upper(coalesce(currency, 'INR'))
    ), 25)::numeric as step
  )
  select coalesce(max(m * s.step), 0)
  from s, unnest(array[1, 2, 5, 10, 20]) m
  where amount >= m * s.step;
$$;

revoke all on function public.spend_band_floor(numeric, text) from public;
grant execute on function public.spend_band_floor(numeric, text) to authenticated;

-- ── 5. the map ──────────────────────────────────────────────────────────────
-- (cell, layer, label, people):
--   people  · ''                         how many consenting people went out here
--   persona · coffee_tea|beer|wine|cocktails|zero_proof|explorer|other
--   taste   · a drink type they logged (coffee, tea, beer, wine, cocktail, spirit, soft)
--   hours   · morning|afternoon|evening|late   when they came out (the venue's clock)
--   spend   · a band floor, in the caller venue's currency (sharing venues only)
-- Every people figure is ≥ 5 and a multiple of 5. A cell missing from the answer has
-- fewer than 5 consenting people or 3 venues — the app says exactly that.
create or replace function public.area_heat_map(vid uuid, days_back int default 30, tz text default 'UTC')
returns table (cell text, layer text, label text, people int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v     public.venues;
  d     int;
  zone  text;
  since date;
begin
  if not public.venue_can(vid, auth.uid(), 'area.view') then
    raise exception 'your role can''t see the area map' using errcode = '42501';
  end if;
  select * into v from public.venues where id = vid;
  if not v.verified then
    raise exception 'the area map opens once your venue is verified';
  end if;
  if v.geohash is null or char_length(v.geohash) < 5 then
    raise exception 'set your venue''s location first (Setup → Where you are)';
  end if;

  -- Fixed windows of whole days, ending yesterday: answers change once a day, so
  -- two answers a few minutes apart can't be subtracted to find one person.
  d := case when days_back <= 7 then 7 when days_back <= 30 then 30 else 90 end;
  since := current_date - d;
  zone := case when exists (select 1 from pg_timezone_names where name = tz) then tz else 'UTC' end;

  return query
  with vcells as (
    select x.id, left(x.geohash, 5) as cell, x.area_share, x.currency
    from public.venues x
    where x.verified and x.geohash is not null and char_length(x.geohash) >= 5
      and left(x.geohash, 4) = left(v.geohash, 4)
  ),
  -- Where consenting people went out: their own room joins and shop punches.
  outings as (
    select pm.user_id, vc.cell, vc.id as venue_id, pm.joined_at as at_ts
    from public.party_members pm
    join public.parties pa on pa.id = pm.party_id
    join vcells vc on vc.id = pa.venue_id
    where pm.joined_at >= since and pm.joined_at < current_date
    union all
    select ch.user_id, vc.cell, vc.id, ch.created_at
    from public.venue_checkins ch
    join vcells vc on vc.id = ch.venue_id
    where ch.created_at >= since and ch.created_at < current_date
  ),
  consenting as (
    select o.* from outings o
    join public.profiles p on p.id = o.user_id
    where p.share_trends and p.share_nights_out
  ),
  ok_cells as (
    select c.cell from consenting c
    group by c.cell
    having count(distinct c.user_id) >= 5 and count(distinct c.venue_id) >= 3
  ),
  people as (
    select distinct c.user_id, c.cell from consenting c where c.cell in (select oc.cell from ok_cells oc)
  ),
  -- Each person's own taste over the same window (aggregated below, never returned).
  logs as (
    select e.user_id, e.type, count(*) as n
    from public.entries e
    where e.user_id in (select user_id from people)
      and e.date >= since and e.date < current_date
    group by e.user_id, e.type
  ),
  grouped as (
    select l.user_id,
           case
             when l.type in ('coffee', 'tea') then 'coffee_tea'
             when l.type = 'beer' then 'beer'
             when l.type = 'wine' then 'wine'
             when l.type in ('cocktail', 'spirit') then 'cocktails'
             when l.type in ('soft', 'none') then 'zero_proof'
             else 'other'
           end as grp,
           sum(l.n) as n
    from logs l
    group by 1, 2
  ),
  persona as (
    select u.user_id,
           case
             when (select count(distinct l.type) from logs l
                   where l.user_id = u.user_id and l.type in ('coffee', 'tea', 'beer', 'wine', 'cocktail', 'spirit', 'soft')) >= 4
               then 'explorer'
             else (select g.grp from grouped g where g.user_id = u.user_id order by g.n desc, g.grp limit 1)
           end as persona
    from (select distinct user_id from people) u
  ),
  hours as (
    select c.cell, c.user_id,
           case
             when extract(hour from c.at_ts at time zone zone) between 5 and 11 then 'morning'
             when extract(hour from c.at_ts at time zone zone) between 12 and 16 then 'afternoon'
             when extract(hour from c.at_ts at time zone zone) between 17 and 20 then 'evening'
             else 'late'
           end as band
    from consenting c
    where c.cell in (select oc.cell from ok_cells oc)
  ),
  -- A night's tab per guest, at sharing venues in the caller's currency, only if the
  -- caller shares too. The median lands in a band; the figure never leaves.
  tabs as (
    select vc.cell, vc.id as venue_id, se.subject_user_id as user_id, sum(se.amount) as tab
    from public.spend_events se
    join public.parties pa on pa.id = se.party_id
    join vcells vc on vc.id = pa.venue_id
    join public.profiles p on p.id = se.subject_user_id
    where v.area_share
      and vc.area_share and vc.currency = v.currency
      and p.share_trends and p.share_nights_out
      and se.created_at >= since and se.created_at < current_date
    group by vc.cell, vc.id, se.party_id, se.subject_user_id
  ),
  spend as (
    select t.cell,
           public.spend_band_floor(percentile_cont(0.5) within group (order by t.tab)::numeric, v.currency) as floor,
           count(distinct t.user_id) as n
    from tabs t
    group by t.cell
    having count(distinct t.user_id) >= 5 and count(distinct t.venue_id) >= 3
  ),
  answer as (
    select p.cell, 'people'::text as layer, ''::text as label, count(distinct p.user_id) as n
    from people p group by p.cell
    union all
    select p.cell, 'persona', pe.persona, count(distinct p.user_id)
    from people p join persona pe on pe.user_id = p.user_id
    where pe.persona is not null
    group by p.cell, pe.persona
    union all
    select p.cell, 'taste', l.type, count(distinct p.user_id)
    from people p join logs l on l.user_id = p.user_id
    where l.type in ('coffee', 'tea', 'beer', 'wine', 'cocktail', 'spirit', 'soft')
    group by p.cell, l.type
    union all
    select h.cell, 'hours', h.band, count(distinct h.user_id)
    from hours h group by h.cell, h.band
    union all
    select s.cell, 'spend', s.floor::text, s.n from spend s
  )
  select a.cell, a.layer, a.label, ((a.n / 5) * 5)::int
  from answer a
  where a.n >= 5
  order by a.cell, a.layer, a.n desc, a.label;
end; $$;

revoke all on function public.area_heat_map(uuid, int, text) from public;
grant execute on function public.area_heat_map(uuid, int, text) to authenticated;
