-- ============================================================================
-- brewdiary — "Discover": list the BAR, never the OFFER.
--
-- ── THE WALL THIS FEATURE MUST NOT CROSS ────────────────────────────────────
-- A venue LISTING is a directory entry — Google Maps lists bars, and nobody
-- considers that alcohol advertising. A venue OFFER ("free pour at Toit tonight!")
-- is alcohol advertising, and in India that is specifically illegal (surrogate-ad
-- rules, CCPA, penalties to ₹50 lakh). It is also banned outright in Thailand,
-- Norway, Lithuania, Türkiye and Poland.
--
-- So this function returns a bar's NAME, CITY, and whether a room is open tonight.
-- It does NOT return — and must never return — the perk, the reward, a price, a
-- drink, or a discount. That is rule #6 in docs/11, and THIS is the feature most
-- likely to erode it, so the separation lives in the query rather than in our good
-- intentions: `venue_perks` is not joined here, and it never should be.
--
-- Jurisdiction: a venue only appears where the bar layer is lawful at all (Class
-- A/B — allow_perks). Deny by default, like everything else: an unresearched
-- country lists nothing.
--
-- Runs on top of schema.sql + 002..026. Idempotent-ish (creates no data tables).
-- ============================================================================

drop function if exists public.discover_venues(text, int) cascade;

create or replace function public.discover_venues(in_country text default null, lim int default 30)
returns table (
  name         text,
  slug         text,
  city         text,
  country      text,
  open_tonight boolean   -- a room is running right now. NOT an offer — just "we're on".
)
language sql stable security definer set search_path = public as $$
  select v.name,
         v.slug,
         v.city,
         v.country,
         exists (
           select 1 from public.parties r
           where r.venue_id = v.id
             and r.date >= current_date - 1
             and public.board_live(r)
         ) as open_tonight
  from public.venues v
  join public.jurisdiction_policy jp
    on jp.country = v.country
   and jp.region  = ''          -- country-level rule is enough to decide "may we list"
  where v.verified                        -- an unverified bar is nobody's recommendation
    and jp.allow_perks                    -- the bar layer is lawful here at all
    and (in_country is null or v.country = upper(in_country))
  -- NOTE: public.venue_perks is deliberately NOT joined. Listing a bar is a
  -- directory entry; listing its offer is alcohol advertising. Don't.
  order by open_tonight desc, v.name
  limit greatest(least(coalesce(lim, 30), 100), 1);
$$;
revoke all on function public.discover_venues(text, int) from public;
grant execute on function public.discover_venues(text, int) to anon, authenticated;
