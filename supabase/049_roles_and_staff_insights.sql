-- ============================================================================
-- brewdiary — trade-portal HIERARCHY roles + Ninkasi for the whole team.
--
-- 1) The real staff ladder (researched: owner → GM → FOH manager → servers/
--    bartenders → kitchen). We add the two missing rungs:
--      'waiter'  — front-of-house service. Same service powers as a bartender
--                  (rooms/tabs/vibe all gate on is_venue_staff, so nothing else
--                  needs touching — a waiter closes tabs in a restaurant).
--      'kitchen' — back-of-house. Also is_venue_staff (can thank/be thanked,
--                  sees the room), but the CLIENT shows kitchen a read-focused
--                  dashboard. Manage-level rights stay owner/manager ONLY
--                  (is_venue_manager is unchanged everywhere).
--
-- 2) venue_insights() opens from manager-only to ALL STAFF — so every rung gets
--    Ninkasi's read — but the MONEY (takings, prev_takings) comes back NULL for
--    anyone below manager, using the same case-null suppression the k-anon
--    fields already use. The DB stays the authority on who sees revenue; the
--    client's null-guards do the explaining. Counts (guests, weekday pattern,
--    perks, kudos) are service-relevant and safe for the team.
--    Body is otherwise IDENTICAL to 038 (privacy notes there still govern).
-- Runs on top of 002..048.
-- ============================================================================

-- ── 1 · the ladder ───────────────────────────────────────────────────────────
alter table public.venue_staff drop constraint if exists venue_staff_role_check;
alter table public.venue_staff
  add constraint venue_staff_role_check
  check (role in ('owner', 'manager', 'bartender', 'waiter', 'kitchen'));

-- ── 2 · insights for every rung, money for managers ─────────────────────────
drop function if exists public.venue_insights(uuid, int) cascade;

create or replace function public.venue_insights(vid uuid, days int default 30)
returns table (
  rooms int, guests int, new_guests int, returning_guests int,
  quiet_visits int, other_visits int,
  perks_earned int, perks_claimed int,
  tabs int, takings numeric, kudos int,
  visits_by_dow int[],
  prev_guests int,
  prev_takings numeric
)
language plpgsql stable security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  d  int := greatest(coalesce(days, 30), 1);
  win  timestamptz := now() - make_interval(days => d);
  win2 timestamptz := now() - make_interval(days => 2 * d);
  k int := public.k_anon();
  is_mgr boolean;
  n_guests int; n_new int; n_ret int; n_earned int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_venue_staff(vid, me) then
    raise exception 'only this venue''s team can see this';
  end if;
  is_mgr := public.is_venue_manager(vid, me);

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

    case when n_guests >= k then n_new::int end,
    case when n_guests >= k then n_ret::int end,

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

    -- MONEY: managers only. Below that rung the team sees the pattern, not the till.
    case when is_mgr then
      (select coalesce(sum(se.amount), 0)::numeric from public.spend_events se
        join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.created_at > win)
    end,

    (select count(*)::int from public.staff_kudos sk
      where sk.venue_id = vid and sk.created_at > win),

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

    (select count(distinct s.user_id)::int from (
        select m.user_id, m.joined_at as seen_at
          from public.party_members m join public.parties r on r.id = m.party_id
         where r.venue_id = vid and m.status = 'approved'
        union all
        select c.user_id, c.created_at from public.venue_checkins c where c.venue_id = vid
      ) s where s.seen_at > win2 and s.seen_at <= win),

    case when is_mgr then
      (select coalesce(sum(se.amount), 0)::numeric from public.spend_events se
        join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.created_at > win2 and se.created_at <= win)
    end;
end; $$;

revoke all on function public.venue_insights(uuid, int) from public;
grant execute on function public.venue_insights(uuid, int) to authenticated;
