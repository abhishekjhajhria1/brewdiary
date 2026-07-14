-- ============================================================================
-- brewdiary — "Insights": counts a bar can act on, without a profile of anyone.
--
-- Bars fly blind ("no data showing who's drifting away until they're already
-- gone"). The naive fix is a customer list. We will never build that. So: counts.
--
-- ── THE PRIVACY MATH (do not skip this if you change the file) ───────────────
-- What a manager ALREADY lawfully sees: the names of guests in their own room —
-- they need it to record a tab or hand out vibe. So aggregate counts over that
-- same population create no new personal data. The three things that WOULD:
--
-- 1. SMALL-GROUP SPLITS. "1 new guest tonight" tells the manager that ONE named
--    person has never been here before — a fact about that individual they did not
--    have. So splits (new vs returning) are SUPPRESSED below K = 5.
--    Why 5 and not 3? With 3 present and a 2/1 split, a manager who recognises two
--    regulars deduces the third by subtraction — a DIFFERENCING ATTACK, which
--    k=3 does not stop. k=5 makes that materially harder. We also never publish a
--    per-NIGHT split (only a period aggregate), so last night's roster can't be
--    differenced against tonight's.
--
-- 2. PROFILING OVER TIME. A guest consented to join a ROOM, not to be analysed
--    (GDPR purpose limitation). So: NO PER-GUEST ROWS. Ever. Counts only.
--
-- 3. CROSS-VENUE LEAKAGE — the worst one. A bar must never learn what a guest does
--    at ANOTHER bar. Every query below is hard-scoped to one venue_id, and there is
--    no function that takes two.
--
-- REFUSED, PERMANENTLY: "show me who has stopped coming". That is a named list of
-- people plus their drinking habits, handed to a business. It is the single most
-- requested feature in the research and it is the one we will not build.
--
-- Runs on top of schema.sql + 002..025. Idempotent-ish (creates no data tables).
-- ============================================================================

drop function if exists public.venue_insights(uuid, int) cascade;

-- The suppression threshold. One place, so it can't drift between metrics.
create or replace function public.k_anon()
returns int language sql immutable as $$ select 5; $$;

-- Everything a manager gets. Manager-only, one venue, counts only. Any split over
-- a group smaller than k_anon() comes back NULL — the UI must render "—", not 0,
-- because 0 and "hidden" are different facts and conflating them leaks.
create or replace function public.venue_insights(vid uuid, days int default 30)
returns table (
  rooms            int,      -- nights you opened
  guests           int,      -- distinct people who came (count only)
  new_guests       int,      -- NULL when guests < k_anon()
  returning_guests int,      -- NULL when guests < k_anon()
  quiet_visits     int,      -- visits that landed on a night you called quiet
  other_visits     int,
  perks_earned     int,      -- guests sitting on an unclaimed reward (NULL if < k)
  perks_claimed    int,      -- rewards you actually handed over
  tabs             int,      -- how many tabs your staff recorded
  takings          numeric,  -- YOUR OWN sales data, that your staff typed in
  kudos            int       -- your team's thanks (already team-level only)
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

  -- distinct guests in the window
  select count(distinct m.user_id) into n_guests
  from public.party_members m
  join public.parties r on r.id = m.party_id
  where r.venue_id = vid and m.status = 'approved' and m.joined_at > win;

  -- of those, who had NEVER been here before the window opened
  select count(*) into n_new
  from (
    select distinct m.user_id
    from public.party_members m
    join public.parties r on r.id = m.party_id
    where r.venue_id = vid and m.status = 'approved' and m.joined_at > win
      and not exists (
        select 1 from public.party_members m2
        join public.parties r2 on r2.id = m2.party_id
        where r2.venue_id = vid and m2.user_id = m.user_id
          and m2.status = 'approved' and m2.joined_at <= win
      )
  ) fresh;
  n_ret := n_guests - n_new;

  -- guests sitting on an unclaimed reward. A COUNT — never who they are.
  select count(*) into n_earned
  from (
    select distinct m.user_id
    from public.party_members m
    join public.parties r on r.id = m.party_id
    where r.venue_id = vid and m.status = 'approved'
  ) everyone
  where (select earned from public.perk_status(vid, everyone.user_id)) is true;

  return query
  select
    (select count(*)::int from public.parties r
      where r.venue_id = vid and r.created_at > win),

    n_guests::int,

    -- THE SUPPRESSION. Below k, a split identifies a person; hand back NULL.
    case when n_guests >= k then n_new::int end,
    case when n_guests >= k then n_ret::int end,

    (select coalesce(sum(case when public.visit_weight(vid, r.date) = 2 then 1 else 0 end), 0)::int
       from public.party_members m join public.parties r on r.id = m.party_id
      where r.venue_id = vid and m.status = 'approved' and m.joined_at > win),
    (select coalesce(sum(case when public.visit_weight(vid, r.date) = 2 then 0 else 1 end), 0)::int
       from public.party_members m join public.parties r on r.id = m.party_id
      where r.venue_id = vid and m.status = 'approved' and m.joined_at > win),

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
