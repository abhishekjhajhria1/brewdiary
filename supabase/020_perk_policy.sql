-- ============================================================================
-- brewdiary — "The perk, done legally" + a regression fix.
--
-- WHY. Desk research (internal/legal-and-compliance.md) found that our house perk
-- — "spend ₹X → a free DRINK next visit" — is already unlawful in several markets
-- we want to enter:
--   • Ireland  — awarding loyalty points on alcohol purchases is banned outright
--                (Public Health (Alcohol) Act 2018 regs, in force 2021-01-11).
--   • Scotland — "supply of an alcoholic drink free of charge or at a reduced
--                price on the purchase of one or more drinks" is the statutory
--                definition of an IRRESPONSIBLE PROMOTION (Licensing (S) Act 2005).
--   • Eng/Wal  — mandatory licensing conditions ban "prizes and rewards for
--                drinking large amounts". The LICENSEE carries the liability, so a
--                bad promotion of ours could cost a partner bar its licence.
--   • US       — MA/UT (and parts of AK, IN) still restrict drink deals.
--
-- THE INSIGHT: a loyalty scheme whose prize is NOT alcohol is not an alcohol
-- loyalty scheme. So we don't delete the feature — we make it jurisdiction-aware
-- and default the reward to something you can't get drunk on. The bar still gets
-- its regular back; nobody gets a free drink for spending more on drink.
--
-- Enforced in the DATABASE, not in the dashboard's JavaScript — a venue in Dublin
-- cannot save an unlawful perk even by calling the API directly.
--
-- ALSO FIXES A REGRESSION FROM 019: venue_visits() counted check-in SPARKS, but
-- 019 stopped paying a spark for returning to the same venue (that was the point).
-- So loyalty progress would have frozen at 1 forever and every perk would quietly
-- never pay out. Visits now count ROOMS ATTENDED, which is what they always meant.
-- Runs on top of schema.sql + 002..019. Idempotent-ish.
-- ============================================================================

drop function if exists public.perk_policy(text, text) cascade;
drop function if exists public.venue_visits(uuid)      cascade;

-- ── where the venue is ───────────────────────────────────────────────────────
-- ISO-3166-1 alpha-2 ('IN', 'IE', 'GB', 'US'). `region` is the sub-national code
-- where it matters (US states: 'MA', 'UT'; UK nations: 'SCT', 'ENG').
alter table public.venues add column if not exists country text not null default 'IN';
alter table public.venues add column if not exists region  text;
alter table public.venues drop constraint if exists venues_country_check;
alter table public.venues add constraint venues_country_check check (country ~ '^[A-Z]{2}$');

-- ── is the reward itself alcoholic? ──────────────────────────────────────────
-- Defaults to FALSE — the safe answer, and the one that's legal nearly everywhere.
alter table public.venue_perks add column if not exists reward_alcoholic boolean not null default false;

-- ── the policy, in one place ─────────────────────────────────────────────────
-- allow_alcohol_reward → may the prize be a drink?
-- allow_spend_perk     → may progress accrue from MONEY SPENT (vs. visits)?
-- Mirrored in src/lib/perks.ts (PERK_POLICY) for the UI; THIS is the authority.
create or replace function public.perk_policy(country text, region text default null)
returns table (allow_alcohol_reward boolean, allow_spend_perk boolean)
language sql immutable set search_path = public as $$
  select
    case
      when country = 'IE' then false                      -- alcohol loyalty: banned outright
      when country = 'GB' then false                      -- irresponsible-promotion rules
      when country = 'US' and region in ('MA','UT') then false
      else true
    end,
    case
      -- Where a "reward for spending on drink" reads as a reward for drinking
      -- more, we don't allow spend-based accrual at all — visits only.
      when country = 'IE' then false
      when country = 'GB' then false
      when country = 'US' and region in ('MA','UT') then false
      else true
    end;
$$;
revoke all on function public.perk_policy(text, text) from public;
grant execute on function public.perk_policy(text, text) to anon, authenticated;

-- ── the guard: an unlawful perk cannot be saved. Full stop. ──────────────────
create or replace function public.venue_perks_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare c text; r text; pol record;
begin
  select v.country, v.region into c, r from public.venues v where v.id = new.venue_id;
  select * into pol from public.perk_policy(c, r);

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

-- ── REGRESSION FIX: a "visit" is a room you attended, not a spark you earned ──
-- 019 deliberately stopped paying a spark for returning to the same venue, which
-- silently broke this count (it would sit at 1 forever). Loyalty and the public
-- score are different things and must not share a source: the PUBLIC board pays
-- for variety, the PRIVATE perk counts every time you came back.
create or replace function public.venue_visits(vid uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(distinct m.party_id)::int
  from public.party_members m
  join public.parties party on party.id = m.party_id
  where party.venue_id = vid
    and m.user_id = auth.uid()
    and m.status = 'approved';
$$;
revoke all on function public.venue_visits(uuid) from public;
grant execute on function public.venue_visits(uuid) to authenticated;
