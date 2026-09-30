-- ============================================================================
-- brewdiary — every staff gate asks a CAPABILITY, not just "are you on the team?".
--
-- 045 added the roles (supervisor, server, host, kitchen) and the capability table.
-- Here the nineteen places that asked is_venue_staff() are split in two:
--
--   • Places where ANY team member belongs keep is_venue_staff(): seeing your own venue,
--     its roster, its rooms, its verification request and its menu draft.
--   • Places that touch a GUEST'S standing or history now ask venue_can() for the one
--     capability they need — so a kitchen porter can't record a guest's tab, and a host
--     who seats people can't read their guest-book card:
--
--       record_spend          spend.record     the tab
--       staff_award           guests.vibe      positive vibe
--       redeem_perk           perks.redeem     handing a reward over
--       record_visit          perks.redeem     punching a counter's card
--       perk_status (staff)   perks.redeem     where a guest is up to
--       set_guest_note        guests.notes     writing the guest book
--       venue_guest_card      guests.card      reading it
--       room_guests (staff)   guests.at_tables who's in tonight's room
--       parties_guard_venue   rooms.open       opening a room
--       + the read/delete policies on spend_events, perk_redemptions,
--         venue_checkins and venue_guest_notes, with the matching capability.
--
-- Nothing changes for today's roles: owner, manager and bartender hold every one of
-- these capabilities (045). Each function below is recreated verbatim from its latest
-- migration apart from that one line. Runs on top of 002..045.
-- ============================================================================

-- ── the tab (017) ────────────────────────────────────────────────────────────
create or replace function public.record_spend(pid uuid, uid uuid, amt numeric)
returns boolean
language plpgsql security definer set search_path = public as $$
declare vid uuid;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if amt is null or amt <= 0 then
    raise exception 'amount must be positive';
  end if;

  select room.venue_id into vid from public.parties room where room.id = pid;
  if vid is null then
    raise exception 'not a venue room';
  end if;
  if not public.venue_can(vid, auth.uid(), 'spend.record') then
    raise exception 'only this venue''s staff can record a tab';
  end if;
  if not exists (select 1 from public.venues v where v.id = vid and v.verified) then
    raise exception 'only a verified venue can record spend';
  end if;
  if not public.is_party_member(pid, uid) then
    raise exception 'that guest is not in this room';
  end if;

  insert into public.spend_events (party_id, subject_user_id, recorded_by, amount)
  values (pid, uid, auth.uid(), amt);
  return true;
end; $$;
revoke all on function public.record_spend(uuid, uuid, numeric) from public;
grant execute on function public.record_spend(uuid, uuid, numeric) to authenticated;

-- ── staff vibe (016) ─────────────────────────────────────────────────────────
create or replace function public.staff_award(pid uuid, uid uuid, reason text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare vid uuid;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if uid = auth.uid() then
    raise exception 'you cannot award yourself';
  end if;
  if reason not in ('great vibe', 'kept it classy', 'a pleasure to serve', 'looked after the table') then
    raise exception 'unknown vibe';
  end if;

  select room.venue_id into vid from public.parties room where room.id = pid;
  if vid is null then
    raise exception 'not a venue room';
  end if;
  if not public.venue_can(vid, auth.uid(), 'guests.vibe') then
    raise exception 'not staff of this venue';
  end if;
  if not exists (select 1 from public.venues v where v.id = vid and v.verified) then
    raise exception 'only a verified venue can hand out vibe';
  end if;
  if not public.is_party_member(pid, uid) then
    raise exception 'that guest is not in this room';
  end if;

  insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
  values (pid, uid, auth.uid(), 'vibe', reason, 1)
  on conflict do nothing;
  return found; -- false when this staff member already gave that guest that vibe
end; $$;
revoke all on function public.staff_award(uuid, uuid, text) from public;
grant execute on function public.staff_award(uuid, uuid, text) to authenticated;

-- ── handing a reward over (029) ──────────────────────────────────────────────
create or replace function public.redeem_perk(pk uuid, uid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p record; st record;
begin
  if me is null then raise exception 'not signed in'; end if;

  select vp.* into p from public.venue_perks vp where vp.id = pk;
  if not found then raise exception 'no such perk'; end if;

  if not public.venue_can(p.venue_id, me, 'perks.redeem') then
    raise exception 'only this venue''s staff can hand a perk over';
  end if;
  if not exists (select 1 from public.venues v where v.id = p.venue_id and v.verified) then
    raise exception 'only a verified venue can hand out a perk';
  end if;

  select * into st from public.perk_status(p.venue_id, uid) where perk_id = pk;
  if st is null or not st.earned then
    raise exception 'not earned yet';
  end if;

  insert into public.perk_redemptions
    (venue_id, user_id, redeemed_by, perk_id, kind, threshold, reward, currency)
  values (p.venue_id, uid, me, pk, p.kind, p.threshold, p.reward, p.currency);
  return true;
end; $$;
revoke all on function public.redeem_perk(uuid, uuid) from public;
grant execute on function public.redeem_perk(uuid, uuid) to authenticated;

-- ── punching a counter's card (030) ──────────────────────────────────────────
create or replace function public.record_visit(vid uuid, uid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if me = uid then raise exception 'you cannot punch your own card'; end if;
  if not public.venue_can(vid, me, 'perks.redeem') then
    raise exception 'only this venue''s staff can record a visit';
  end if;
  if not exists (select 1 from public.venues v where v.id = vid and v.verified) then
    raise exception 'only a verified venue can record a visit';
  end if;

  insert into public.venue_checkins (venue_id, user_id, recorded_by)
  values (vid, uid, me)
  on conflict (venue_id, user_id, on_date) do nothing;   -- twice in a day is once

  return true;
end; $$;
revoke all on function public.record_visit(uuid, uuid) from public;
grant execute on function public.record_visit(uuid, uuid) to authenticated;

-- ── where a guest is up to (030) ─────────────────────────────────────────────
create or replace function public.perk_status(vid uuid, uid uuid)
returns table (
  perk_id uuid, kind text, threshold numeric, reward text, currency text,
  progress numeric, earned boolean, claims int
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); t record; since timestamptz; prog numeric; vkind text;
begin
  if me is null then raise exception 'not signed in'; end if;
  if me <> uid and not public.venue_can(vid, me, 'perks.redeem') then
    raise exception 'not allowed to read that';
  end if;

  select v.kind into vkind from public.venues v where v.id = vid;

  for t in
    select vp.id, vp.kind, vp.threshold, vp.reward, vp.currency
    from public.venue_perks vp
    where vp.venue_id = vid
    order by vp.threshold
  loop
    since := public.last_redeemed(t.id, uid);

    if t.kind = 'spend' then
      -- (Unreachable for a store — the guard forbids a spend perk there.)
      select coalesce(sum(se.amount), 0)::numeric into prog
      from public.spend_events se
      join public.parties room on room.id = se.party_id
      where room.venue_id = vid and se.subject_user_id = uid and se.created_at > since;

    elsif vkind = 'store' then
      -- A store has no rooms. Its visits are the punches staff recorded — one a day,
      -- weighted by quiet nights exactly as a bar's are.
      select coalesce(sum(public.visit_weight(vid, c.on_date)), 0)::numeric into prog
      from public.venue_checkins c
      where c.venue_id = vid and c.user_id = uid and c.created_at > since;

    else
      -- a visit is worth 1, or 2 if the bar called that night quiet (024)
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

    perk_id   := t.id;
    kind      := t.kind;
    threshold := t.threshold;
    reward    := t.reward;
    currency  := t.currency;
    progress  := prog;
    earned    := prog >= t.threshold;
    claims    := (select count(*)::int from public.perk_redemptions r
                   where r.perk_id = t.id and r.user_id = uid);
    return next;
  end loop;
end; $$;
revoke all on function public.perk_status(uuid, uuid) from public;
grant execute on function public.perk_status(uuid, uuid) to authenticated;

-- ── the guest book (040, 044) ────────────────────────────────────────────────
create or replace function public.set_guest_note(vid uuid, uid uuid, in_body text, in_tags text[])
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'guests.notes') then
    raise exception 'only this venue''s staff can keep a guest book';
  end if;
  if not public.has_venue_interaction(vid, uid) then
    raise exception 'you can only note a guest who has been to your venue';
  end if;
  if public.blocked_between(me, uid) then
    raise exception 'cannot note this guest';
  end if;

  insert into public.venue_guest_notes (venue_id, subject_id, body, tags, updated_by, updated_at)
  values (vid, uid, left(coalesce(in_body, ''), 2000), (coalesce(in_tags, array[]::text[]))[1:12], me, now())
  on conflict (venue_id, subject_id) do update
    set body = excluded.body, tags = excluded.tags, updated_by = excluded.updated_by, updated_at = now();
end; $$;
revoke all on function public.set_guest_note(uuid, uuid, text, text[]) from public;
grant execute on function public.set_guest_note(uuid, uuid, text, text[]) to authenticated;

create or replace function public.venue_guest_card(vid uuid, uid uuid)
returns table (
  visits int,
  first_seen timestamptz,
  last_seen timestamptz,
  tabs int,
  total_spend numeric,   -- this venue's own till data for this guest (owner-side, exact)
  perks_claimed int,
  has_earned boolean,
  been_here boolean,      -- false ⇒ no book may be kept (never interacted)
  note text,
  tags text[],
  note_updated_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.venue_can(vid, me, 'guests.card') then
    raise exception 'only this venue''s staff can read its guest book';
  end if;

  return query
  with seen as (
    select m.joined_at as at
      from public.party_members m join public.parties r on r.id = m.party_id
     where r.venue_id = vid and m.user_id = uid and m.status = 'approved'
    union all
    select c.created_at from public.venue_checkins c
     where c.venue_id = vid and c.user_id = uid
  )
  select
    (select count(*)::int from seen),
    (select min(s.at) from seen s),
    (select max(s.at) from seen s),
    (select count(*)::int from public.spend_events se join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.subject_user_id = uid),
    (select coalesce(sum(se.amount), 0)::numeric from public.spend_events se join public.parties r on r.id = se.party_id
       where r.venue_id = vid and se.subject_user_id = uid),
    (select count(*)::int from public.perk_redemptions pr where pr.venue_id = vid and pr.user_id = uid),
    (exists (select 1 from public.perk_status(vid, uid) ps where ps.earned)),
    public.has_venue_interaction(vid, uid),
    (select n.body       from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select n.tags       from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid),
    (select n.updated_at from public.venue_guest_notes n where n.venue_id = vid and n.subject_id = uid);
end; $$;
revoke all on function public.venue_guest_card(uuid, uuid) from public;
grant execute on function public.venue_guest_card(uuid, uuid) to authenticated;

-- ── who's in tonight's room (016) ────────────────────────────────────────────
create or replace function public.room_guests(pid uuid)
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.display_name, 'guest')
  from public.party_members m
  join public.profiles p    on p.id = m.user_id
  join public.parties  room on room.id = m.party_id
  where m.party_id = pid
    and m.status = 'approved'
    and (
      public.is_party_member(pid, auth.uid())
      or (room.venue_id is not null and public.venue_can(room.venue_id, auth.uid(), 'guests.at_tables'))
    )
  order by 2;
$$;
revoke all on function public.room_guests(uuid) from public;
grant execute on function public.room_guests(uuid) to authenticated;

-- ── opening a room (011) ─────────────────────────────────────────────────────
create or replace function public.parties_guard_venue()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.venue_id is not null
     and (tg_op = 'INSERT' or new.venue_id is distinct from old.venue_id)
     and auth.uid() is not null
     and not public.venue_can(new.venue_id, auth.uid(), 'rooms.open') then
    raise exception 'only this venue''s staff can open a room for it';
  end if;
  return new;
end; $$;

-- ── the read policies over a guest's standing and history ────────────────────
drop policy if exists spend_events_read on public.spend_events;
create policy spend_events_read on public.spend_events for select to authenticated
  using (
    subject_user_id = auth.uid()
    or exists (
      select 1 from public.parties room
      where room.id = party_id
        and room.venue_id is not null
        and public.venue_can(room.venue_id, auth.uid(), 'spend.record')
    )
  );

drop policy if exists perk_redemptions_read on public.perk_redemptions;
create policy perk_redemptions_read on public.perk_redemptions for select to authenticated
  using (user_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'perks.redeem'));

drop policy if exists venue_checkins_read on public.venue_checkins;
create policy venue_checkins_read on public.venue_checkins for select to authenticated
  using (user_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'perks.redeem'));

drop policy if exists venue_guest_notes_read on public.venue_guest_notes;
create policy venue_guest_notes_read on public.venue_guest_notes for select to authenticated
  using (public.venue_can(venue_id, auth.uid(), 'guests.card') or subject_id = auth.uid());

drop policy if exists venue_guest_notes_forget on public.venue_guest_notes;
create policy venue_guest_notes_forget on public.venue_guest_notes for delete to authenticated
  using (subject_id = auth.uid() or public.venue_can(venue_id, auth.uid(), 'guests.notes'));
