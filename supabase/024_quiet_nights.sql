-- ============================================================================
-- brewdiary — "Quiet nights": the dead Tuesday, solved without rewarding drinking.
--
-- A bar's #1 complaint is the empty Tuesday. The obvious fix is the illegal one:
-- discount the drinks. The second-most obvious fix is the one that breaks OUR own
-- rule: hand out a spark for turning up on a Tuesday — which is a reward for
-- FREQUENCY, exactly what 019 tore out ("sparks pay for variety, never frequency";
-- a public score that climbs the more often you go out drinking is the thing we
-- most need not to build).
--
-- So the boost lands somewhere else entirely: a visit on a quiet night counts
-- DOUBLE toward that venue's HOUSE PERK.
--   • It's PRIVATE — between one guest and one bar. Never on the leaderboard,
--     never on the wall screen, never in a share card.
--   • It rewards ARRIVING, not drinking. No discount, no price, no quantity —
--     so it isn't an "irresponsible promotion" in the markets that ban those
--     (Scotland bans time-limited price promotions outright; Alberta caps happy
--     hours). Same benefit to the bar; a completely different legal object.
--   • It inherits the perk's jurisdiction rules for free: no perk here → no boost
--     here. Nothing new to gate.
--
-- Runs on top of schema.sql + 002..023. Idempotent-ish.
-- ============================================================================

-- Which weekdays are quiet for this venue. Postgres dow: 0 = Sunday … 6 = Saturday.
alter table public.venues add column if not exists quiet_nights int[] not null default '{}';
alter table public.venues drop constraint if exists venues_quiet_nights_check;
alter table public.venues add constraint venues_quiet_nights_check
  check (quiet_nights <@ array[0,1,2,3,4,5,6]);

-- How much a visit is worth toward the perk. 2 on a quiet night, else 1.
create or replace function public.visit_weight(vid uuid, on_date date)
returns int
language sql stable set search_path = public as $$
  select case
    when extract(dow from on_date)::int = any (
      select unnest(v.quiet_nights) from public.venues v where v.id = vid
    ) then 2
    else 1
  end;
$$;
grant execute on function public.visit_weight(uuid, date) to authenticated;

-- perk_status(), rewritten: a VISITS perk now SUMS the weight of each visit rather
-- than counting rows. A spend perk is untouched — money is never doubled, because
-- doubling money would be rewarding the spend, which is the thing we don't do.
create or replace function public.perk_status(vid uuid, uid uuid)
returns table (
  kind text, threshold numeric, reward text, currency text,
  progress numeric, earned boolean, claims int, last_claim timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); since timestamptz; p record; prog numeric;
begin
  if me is null then raise exception 'not signed in'; end if;
  if me <> uid and not public.is_venue_staff(vid, me) then
    raise exception 'not allowed to read that';
  end if;

  select vp.kind, vp.threshold, vp.reward, vp.currency into p
  from public.venue_perks vp where vp.venue_id = vid;
  if not found then return; end if;   -- no perk here (or not lawful here)

  since := public.last_redeemed(vid, uid);

  if p.kind = 'spend' then
    select coalesce(sum(se.amount), 0)::numeric into prog
    from public.spend_events se
    join public.parties room on room.id = se.party_id
    where room.venue_id = vid and se.subject_user_id = uid and se.created_at > since;
  else
    -- one row per distinct room attended, each worth 1 — or 2 if the bar called
    -- that night quiet.
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

  return query
    select p.kind, p.threshold, p.reward, p.currency,
           prog,
           prog >= p.threshold,
           (select count(*)::int from public.perk_redemptions r
             where r.venue_id = vid and r.user_id = uid),
           nullif(since, 'epoch'::timestamptz);
end; $$;
revoke all on function public.perk_status(uuid, uuid) from public;
grant execute on function public.perk_status(uuid, uuid) to authenticated;
