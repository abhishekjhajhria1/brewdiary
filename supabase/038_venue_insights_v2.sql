-- ============================================================================
-- brewdiary — Insights v2: the metrics a bar owner actually acts on.
--
-- The research is blunt about which numbers change a decision: the busiest and
-- DEADEST night of the week, whether you're growing vs last month, and how many
-- guests come back. This migration adds exactly those to venue_insights(), and
-- nothing that would break the privacy math in 026/030.
--
-- ── STILL WITHIN THE PRIVACY LINE (re-read 026 before touching this) ─────────
--   • visits_by_dow is VISIT VOLUME bucketed by weekday over the whole window — a
--     period aggregate, exactly like quiet_visits/other_visits, which 030 already
--     returns raw. It is not a per-night roster and not a per-guest split, so it
--     creates no new fact about any individual. (Busiest/deadest is chosen by the
--     UI from this array — feeding the quiet-night lever we already have.)
--   • prev_guests / prev_takings are the SAME counts as guests/takings, just for
--     the previous equal-length window, so the owner can see a trend. Same standard.
--   • The new/returning SPLIT stays k-anon suppressed (unchanged). Return-rate is
--     derived by the client from those already-suppressed numbers, so it inherits
--     the suppression for free (null below k = no rate shown).
--   • Average tab is NOT computed here — the client shows it only when tabs >= k,
--     because an average over 1–4 tabs would leak an individual's spend.
--
-- Signature change (new return columns) → drop + recreate. Pre-launch, no data.
-- Runs on top of 002..037.
-- ============================================================================

drop function if exists public.venue_insights(uuid, int) cascade;

create or replace function public.venue_insights(vid uuid, days int default 30)
returns table (
  rooms int, guests int, new_guests int, returning_guests int,
  quiet_visits int, other_visits int,
  perks_earned int, perks_claimed int,
  tabs int, takings numeric, kudos int,
  -- v2 (appended, so name-based readers stay stable):
  visits_by_dow int[],  -- 7 slots, index 1 = Sunday … 7 = Saturday (visit volume)
  prev_guests int,      -- distinct guests in the PREVIOUS equal-length window
  prev_takings numeric  -- takings in the previous equal-length window
)
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  d  int := greatest(coalesce(days, 30), 1);
  win  timestamptz := now() - make_interval(days => d);
  win2 timestamptz := now() - make_interval(days => 2 * d);  -- start of the prior window
  k int := public.k_anon();
  n_guests int; n_new int; n_ret int; n_earned int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_venue_manager(vid, me) then
    raise exception 'only this venue''s managers can see this';
  end if;

  -- Everyone who was here in the window: a room they joined (bar) or a card staff
  -- punched (store). A store has no rooms, so the union is load-bearing.
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
    (select coalesce(count(*) filter (where public.visit_weight(vid, d2.day) = 2), 0)::int from (
        select r.date as day from public.party_members m join public.parties r on r.id = m.party_id
         where r.venue_id = vid and m.status = 'approved' and m.joined_at > win
        union all
        select c.on_date from public.venue_checkins c where c.venue_id = vid and c.created_at > win
      ) d2),
    (select coalesce(count(*) filter (where public.visit_weight(vid, d2.day) <> 2), 0)::int from (
        select r.date as day from public.party_members m join public.parties r on r.id = m.party_id
         where r.venue_id = vid and m.status = 'approved' and m.joined_at > win
        union all
        select c.on_date from public.venue_checkins c where c.venue_id = vid and c.created_at > win
      ) d2),

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
      where sk.venue_id = vid and sk.created_at > win),

    -- v2 · visits by weekday (Sun=slot 1 … Sat=slot 7). Every slot present, 0 where
    -- nothing landed, so the UI can render all seven bars. Same visit population as
    -- quiet/other above, bucketed by the DATE of the visit.
    (select array_agg(coalesce(c.cnt, 0) order by g.dow)
       from generate_series(0, 6) g(dow)
       left join (
         select extract(dow from d2.day)::int as dow, count(*)::int as cnt
         from (
           select r.date as day from public.party_members m join public.parties r on r.id = m.party_id
            where r.venue_id = vid and m.status = 'approved' and m.joined_at > win
           union all
           select c2.on_date from public.venue_checkins c2 where c2.venue_id = vid and c2.created_at > win
         ) d2
         group by 1
       ) c on c.dow = g.dow),

    -- v2 · the previous equal-length window, for a growth trend
    (select count(distinct s.user_id)::int from (
        select m.user_id, m.joined_at as seen_at
          from public.party_members m join public.parties r on r.id = m.party_id
         where r.venue_id = vid and m.status = 'approved'
        union all
        select c.user_id, c.created_at from public.venue_checkins c where c.venue_id = vid
      ) s where s.seen_at > win2 and s.seen_at <= win),

    (select coalesce(sum(se.amount), 0)::numeric from public.spend_events se
      join public.parties r on r.id = se.party_id
     where r.venue_id = vid and se.created_at > win2 and se.created_at <= win);
end; $$;

revoke all on function public.venue_insights(uuid, int) from public;
grant execute on function public.venue_insights(uuid, int) to authenticated;
