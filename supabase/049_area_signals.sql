-- ============================================================================
-- brewdiary — OUTSIDE SIGNALS: public facts about places, for the people who run them.
--
-- Staff asked to know "what they need to know" about their area: a festival on
-- Saturday, a new bar two streets away, a dry day, a cricket final, what a pint costs
-- down the road. Other tools (scrapers, feeds, a person with a spreadsheet) gather
-- that; this is where it lands, and the rules for what may land.
--
--   • PLACES AND HAPPENINGS, NEVER PEOPLE. A signal is an event, an opening or
--     closing, a holiday, opening hours, a price, a venue fact, a trend, the weather
--     or a news item. Reviews arrive only as numbers on a venue (a rating, a count),
--     never as someone's words. There is no column that could hold a person.
--   • CLEANED TWICE. The importer (src/lib/signals.ts, used by the web route and the
--     CLI) drops personal fields and redacts contact details; this table's guard
--     refuses anything that still looks like an email, a phone number or an @handle.
--   • SERVER-ONLY WRITES. RLS on, no client policy at all: only the service role (the
--     import route or scripts/import-signals.mjs) writes. Staff READ through
--     venue_area_signals(), for their own verified venue's area only.
--   • IT EXPIRES. Every signal carries expires_at; a stale festival stops showing.
--
-- Runs on top of 002..048.
-- ============================================================================

create table if not exists public.area_signals (
  id          uuid primary key default gen_random_uuid(),
  area        text not null check (area ~ '^[0-9b-hjkmnp-z]{4}$'),                 -- the ~40 km cell
  cell        text check (cell is null or cell ~ '^[0-9b-hjkmnp-z]{5,7}$'),         -- where, if known (≥ ~150 m)
  kind        text not null check (kind in ('event', 'opening', 'closing', 'holiday', 'hours', 'price', 'venue', 'trend', 'weather', 'news')),
  title       text not null check (char_length(trim(title)) between 3 and 140),
  detail      text check (detail is null or char_length(detail) <= 600),
  starts_on   date,
  ends_on     date,
  facts       jsonb not null default '{}'::jsonb,
  source      text not null check (char_length(trim(source)) between 2 and 80),
  source_url  text check (source_url is null or (source_url ~ '^https://' and char_length(source_url) <= 500)),
  dedupe_key  text not null unique check (char_length(dedupe_key) between 3 and 300),
  observed_at timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '30 days',
  check (cell is null or left(cell, 4) = area),
  check (ends_on is null or starts_on is null or ends_on >= starts_on),
  check (jsonb_typeof(facts) = 'object' and pg_column_size(facts) <= 2048)
);
create index if not exists area_signals_area_idx on public.area_signals (area, expires_at);

alter table public.area_signals enable row level security;
-- No policies on purpose: nothing a client sends can read or write this table directly.

-- ── the second clean: anything that still looks like a person is refused ────
create or replace function public.area_signals_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  txt   text := coalesce(new.title, '') || ' ' || coalesce(new.detail, '') || ' ' || coalesce(new.facts::text, '');
  nodt  text := regexp_replace(txt, '[0-9]{4}-[0-9]{2}-[0-9]{2}', ' ', 'g');   -- a date is not a phone
begin
  if txt ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
    raise exception 'a signal can''t carry an email address';
  end if;
  if nodt ~ '\+?[0-9][0-9 ().-]{8,}[0-9]' then
    raise exception 'a signal can''t carry a phone number';
  end if;
  if txt ~ '(^|[^a-zA-Z0-9])@[A-Za-z0-9_.]{2,}' then
    raise exception 'a signal can''t carry an @handle — it''s about a place, not a person';
  end if;
  if exists (select 1 from jsonb_object_keys(new.facts) k
             where k ~* '(^|_)(name|email|phone|mobile|user|author|handle|profile|reviewer|contact|owner|person|age|gender)s?(_|$)') then
    raise exception 'a signal''s facts can''t describe a person';
  end if;
  return new;
end; $$;

drop trigger if exists area_signals_guard on public.area_signals;
create trigger area_signals_guard before insert or update on public.area_signals
  for each row execute function public.area_signals_guard();

-- ── staff read their own area ───────────────────────────────────────────────
-- Any staff member of a VERIFIED venue with a location: these are public facts about
-- places, useful to the whole team, and nothing here is about a guest.
create or replace function public.venue_area_signals(vid uuid, days_ahead int default 14)
returns table (id uuid, kind text, title text, detail text, starts_on date, ends_on date,
               cell text, facts jsonb, source text, source_url text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v public.venues;
begin
  if not public.is_venue_staff(vid, auth.uid()) then
    raise exception 'only this venue''s team can read its area' using errcode = '42501';
  end if;
  select * into v from public.venues where public.venues.id = vid;
  if not v.verified or v.geohash is null or char_length(v.geohash) < 4 then
    return;   -- nothing to say until the venue is verified and placed
  end if;
  return query
  select s.id, s.kind, s.title, s.detail, s.starts_on, s.ends_on, s.cell, s.facts, s.source, s.source_url
  from public.area_signals s
  where s.area = left(v.geohash, 4)
    and s.expires_at > now()
    and (s.starts_on is null or s.starts_on <= current_date + greatest(0, least(days_ahead, 60)))
    and (s.ends_on is null or s.ends_on >= current_date)
  order by coalesce(s.starts_on, current_date), s.kind, s.title
  limit 40;
end; $$;

revoke all on function public.venue_area_signals(uuid, int) from public;
grant execute on function public.venue_area_signals(uuid, int) to authenticated;
