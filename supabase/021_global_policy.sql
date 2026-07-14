-- ============================================================================
-- brewdiary — "Deny by default": one jurisdiction table for the whole app.
--
-- THE BUG IN 020. Its perk_policy() named the restricted places (IE/GB/MA/UT) and
-- let EVERYTHING ELSE through. So a venue in Bangkok or Oslo would have been handed
-- the permissive default — and Thailand bans alcohol discounts, giveaways and free
-- offers outright, while Norway has banned alcohol advertising entirely since 1975.
-- Silence meant "yes". That is exactly backwards for law.
--
-- 021 INVERTS IT. An unlisted country gets the STRICTEST setting: no perk at all.
-- Opening a market becomes a deliberate act — research it, insert a row, cite it.
-- Nobody can make an app "legal everywhere"; what we can do is make the unlawful
-- thing impossible BY ACCIDENT. That's what this is.
--
-- It's a DATA table on purpose: when a law changes (they do — Thailand's widened in
-- Nov 2025, Turkey's in 2026) you fix it with one UPDATE, not a code deploy.
--
-- Mirrored in src/lib/jurisdiction.ts. Research: internal/legal-and-compliance.md.
-- Runs on top of schema.sql + 002..020. Idempotent-ish.
-- ============================================================================

drop function if exists public.perk_policy(text, text) cascade;
drop table    if exists public.jurisdiction_policy cascade;

create table public.jurisdiction_policy (
  country              text not null check (country ~ '^[A-Z]{2}$'),
  region               text not null default '',   -- '' = the whole country
  min_age              int  not null check (min_age between 16 and 25),
  alcohol_legal        boolean not null default true,
  allow_perks          boolean not null default false,
  allow_alcohol_reward boolean not null default false,
  allow_spend_perk     boolean not null default false,
  note                 text,
  primary key (country, region)
);
alter table public.jurisdiction_policy enable row level security;
-- World-readable (it's public law, and the venue dashboard must show the rule);
-- writable only out-of-band by us, with the service key. No write policy at all.
create policy jurisdiction_policy_read on public.jurisdiction_policy for select to anon, authenticated
  using (true);

insert into public.jurisdiction_policy
  (country, region, min_age, alcohol_legal, allow_perks, allow_alcohol_reward, allow_spend_perk, note) values
  -- home market: the perk is lawful; it's the ADVERTISING that's restricted, which
  -- is why a perk must always stay private (never a public "offers" feed).
  ('IN','',21,true,true,true,true,null),
  -- researched, an alcoholic reward is permitted
  ('US','',21,true,true,true,true,null),
  -- …except where the state still restricts drink deals
  ('US','MA',21,true,true,false,false,'Massachusetts restricts drink deals, so a perk here rewards visits with something non-alcoholic.'),
  ('US','UT',21,true,true,false,false,'Utah restricts drink deals, so a perk here rewards visits with something non-alcoholic.'),
  -- researched: NON-ALCOHOLIC reward only
  ('IE','',18,true,true,false,false,'Ireland bans loyalty rewards on alcohol, so a perk here rewards visits with something non-alcoholic.'),
  ('GB','',18,true,true,false,false,'UK licensing rules treat a free or discounted drink earned by buying drinks as an irresponsible promotion — so a perk here rewards visits with something non-alcoholic.'),
  ('AU','',18,true,true,false,false,'Australian liquor law names loyalty schemes that encourage drinking as an unacceptable promotion — so a perk here rewards visits with something non-alcoholic.'),
  ('CA','',19,true,true,false,false,'Canadian licensees may not offer inducements — so a perk here rewards visits with something non-alcoholic.'),
  ('FR','',18,true,true,false,false,'France''s Loi Évin restricts alcohol marketing — so a perk here rewards visits with something non-alcoholic.'),
  ('DE','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('ES','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('IT','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('NL','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('SG','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('JP','',20,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('KR','',19,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('NZ','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('ZA','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('BR','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('MX','',18,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  ('AE','',21,true,true,false,false,'A perk here rewards visits with something non-alcoholic.'),
  -- researched: NO PERK OF ANY KIND
  ('TH','',20,true,false,false,false,'Thailand bans alcohol discounts, giveaways and free offers — no loyalty perk of any kind here.'),
  ('NO','',18,true,false,false,false,'Norway bans alcohol advertising outright — no loyalty perk here.'),
  ('SE','',18,true,false,false,false,'Sweden''s alcohol marketing rules are too tight for a loyalty perk.'),
  ('FI','',18,true,false,false,false,'Finland''s alcohol marketing rules are too tight for a loyalty perk.'),
  ('TR','',18,true,false,false,false,'Turkey bans alcohol promotion — no loyalty perk here.'),
  ('PL','',18,true,false,false,false,'Poland prohibits alcohol promotion — no loyalty perk here.'),
  -- alcohol prohibited: the venue layer is off entirely (the DIARY still works —
  -- brewdiary is an all-drinks diary, and a coffee is a coffee anywhere)
  ('SA','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('KW','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('LY','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('IR','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('PK','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('BD','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('BN','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('MV','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('SD','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('SO','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('AF','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.'),
  ('YE','',21,false,false,false,false,'Alcohol is prohibited here — the venue features are off.');

-- The lookup. Region row wins over the country row; an UNKNOWN place falls through
-- to the strict default (no perks, nothing) — never to "anything goes".
create or replace function public.perk_policy(country text, region text default null)
returns table (allow_perks boolean, allow_alcohol_reward boolean, allow_spend_perk boolean, min_age int, alcohol_legal boolean)
language sql stable set search_path = public as $$
  select p.allow_perks, p.allow_alcohol_reward, p.allow_spend_perk, p.min_age, p.alcohol_legal
  from public.jurisdiction_policy p
  where p.country = upper(coalesce(country, ''))
    and p.region in ('', upper(coalesce(region, '')))
  order by (p.region <> '') desc   -- the more specific row first
  limit 1;
$$;
revoke all on function public.perk_policy(text, text) from public;
grant execute on function public.perk_policy(text, text) to anon, authenticated;

-- The guard, rewritten for deny-by-default. An unresearched country returns NO ROW
-- from perk_policy() — and that must mean "no", not "sure, go ahead".
create or replace function public.venue_perks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare c text; r text; pol record;
begin
  select v.country, coalesce(v.region, '') into c, r from public.venues v where v.id = new.venue_id;
  select * into pol from public.perk_policy(c, r);

  if pol is null or not pol.allow_perks then
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

-- Where alcohol is prohibited, the bar layer doesn't exist at all — a venue can't
-- even be created. (The DIARY still works: brewdiary is an all-drinks diary.)
create or replace function public.venues_guard_jurisdiction()
returns trigger language plpgsql security definer set search_path = public as $$
declare pol record;
begin
  select * into pol from public.perk_policy(new.country, coalesce(new.region, ''));
  if pol is not null and not pol.alcohol_legal then
    raise exception 'brewdiary does not run venue features in %', new.country
      using hint = 'The diary works everywhere; the bar layer does not.';
  end if;
  return new;
end; $$;

drop trigger if exists venues_jurisdiction on public.venues;
create trigger venues_jurisdiction before insert or update of country, region on public.venues
  for each row execute function public.venues_guard_jurisdiction();
