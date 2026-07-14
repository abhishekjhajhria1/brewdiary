-- ============================================================================
-- brewdiary — CRITICAL FIX: perk_policy() was ignoring its own arguments.
--
-- ── THE BUG ─────────────────────────────────────────────────────────────────
-- 021 declared:
--     create function public.perk_policy(country text, region text) ...
--       select ... from public.jurisdiction_policy p
--        where p.country = upper(coalesce(country, ''))
--          and p.region  in ('', upper(coalesce(region, '')))
--
-- `jurisdiction_policy` HAS COLUMNS NAMED country AND region. In a SQL-language
-- function, when a parameter name collides with a column name, THE COLUMN WINS.
-- So the predicate silently became:
--
--     where p.country = upper(p.country)     -- true for every row
--       and p.region in ('', upper(p.region)) -- true for every row
--     order by (p.region <> '') desc limit 1
--
-- …which matched EVERY row and returned whichever sorted first: **US-MA**.
--
-- Consequences, all of them live:
--   • EVERY VENUE ON EARTH was judged by Massachusetts law. India — our home
--     market, where an alcoholic reward and a spend-based perk are both lawful —
--     was being refused both.
--   • DENY-BY-DEFAULT WAS DEFEATED: an unresearched country (which must return NO
--     ROW) got the US-MA row instead, so perks were permitted there.
--   • venues_guard_jurisdiction read alcohol_legal from that same wrong row (true),
--     so a venue could be created in a PROHIBITION country.
--
-- It was invisible because every caller is a trigger — nothing threw, the wrong
-- answer just quietly propagated. Caught by scripts/db-audit.mjs.
--
-- ── THE FIX ─────────────────────────────────────────────────────────────────
-- Rename the parameters so they cannot collide with a column, ever. The signature
-- (text, text) is unchanged, so every existing caller keeps working.
-- Runs on top of schema.sql + 002..027.
-- ============================================================================

drop function if exists public.perk_policy(text, text) cascade;

create or replace function public.perk_policy(p_country text, p_region text default null)
returns table (allow_perks boolean, allow_alcohol_reward boolean, allow_spend_perk boolean, min_age int, alcohol_legal boolean)
language sql stable set search_path = public as $$
  select jp.allow_perks, jp.allow_alcohol_reward, jp.allow_spend_perk, jp.min_age, jp.alcohol_legal
  from public.jurisdiction_policy jp
  where jp.country = upper(coalesce(p_country, ''))
    and jp.region  in ('', upper(coalesce(p_region, '')))
  order by (jp.region <> '') desc   -- a region-specific row beats the country row
  limit 1;
$$;
revoke all on function public.perk_policy(text, text) from public;
grant execute on function public.perk_policy(text, text) to anon, authenticated;

-- `drop ... cascade` above took the triggers' functions' dependency with it, so
-- both guards are recreated here verbatim. They were correct — they were simply
-- being fed a wrong answer.

create or replace function public.venue_perks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare c text; r text; pol record;
begin
  select v.country, coalesce(v.region, '') into c, r from public.venues v where v.id = new.venue_id;
  select * into pol from public.perk_policy(c, r);

  -- NO ROW = a jurisdiction we have not researched = NO. Silence means no.
  if pol is null or pol.allow_perks is null or not pol.allow_perks then
    raise exception 'loyalty perks are not permitted for a venue in % %', c, r
      using hint = 'Either the law there forbids it, or we have not researched that jurisdiction yet.';
  end if;

  if new.reward_alcoholic and not pol.allow_alcohol_reward then
    raise exception 'a free or discounted alcoholic drink cannot be a loyalty reward in %', c
      using hint = 'Offer something non-alcoholic — a coffee, a dessert, priority entry.';
  end if;

  if new.kind = 'spend' and not pol.allow_spend_perk then
    raise exception 'a spend-based loyalty perk is not permitted in %', c
      using hint = 'Reward visits instead of money spent.';
  end if;

  return new;
end; $$;

drop trigger if exists venue_perks_policy on public.venue_perks;
create trigger venue_perks_policy before insert or update on public.venue_perks
  for each row execute function public.venue_perks_guard();

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
