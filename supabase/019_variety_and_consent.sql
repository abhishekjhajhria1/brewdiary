-- ============================================================================
-- brewdiary — "Variety, not frequency" + per-night consent (the behaviour fix).
--
-- WHY THIS EXISTS. We wrote the rule "nobody is ranked by what they spent" and
-- kept it — but missed that a SPARK WAS A CHECK-IN, so the public score was a
-- count of how often you went out drinking, shown on a screen in a bar. Same
-- failure wearing a nicer shirt. This migration re-points the incentive:
--
--   1. SPARKS NOW PAY FOR VARIETY, NOT FREQUENCY.
--        • a NEW venue      → +1 spark  (exploration)
--        • a NEW drink      → +1 spark  (curiosity)
--        • a logged DRY DAY → +1 spark  (balance — yes, really)
--        • coming back to your local AGAIN → nothing, publicly.
--      Loyalty is still rewarded — privately, by that bar's own perk. The public
--      board rewards trying things; the private perk rewards coming back. Those
--      are different jobs and they should use different currencies.
--
--   2. CONSENT TO BE ON A BAR'S SCREEN IS NOW PER-ROOM, AND IT EXPIRES.
--      Before, kiosk_visible was a permanent global flag: flip it once for a fun
--      night and your name is on every venue's TV forever. Consent to be on a
--      screen TONIGHT is not consent to be on screens ALWAYS. Now it's granted
--      per room (room_consent) and the bar sets how long its board lives
--      (parties.board_until). When the room's board expires, everyone is off it.
--
-- Runs on top of schema.sql + 002..018. Idempotent-ish.
-- ============================================================================

drop function if exists public.award_checkin(uuid)        cascade;
drop function if exists public.award_diary(text, text)    cascade;
drop function if exists public.room_board(text)           cascade;
drop function if exists public.room_tabs(text)            cascade;
drop table    if exists public.room_consent               cascade;

-- ── 1. sparks can now come from the DIARY, not just a room ───────────────────
-- A diary spark (a new drink, a dry day) has no party — so party_id goes nullable.
alter table public.point_events alter column party_id drop not null;

-- The old dedupe index keys on party_id; a NULL party never collides, so diary
-- sparks need their own: one spark per reason per person, ever.
create unique index if not exists point_events_diary_dedupe
  on public.point_events (subject_user_id, reason)
  where currency = 'spark' and party_id is null;

-- You can always read your own diary sparks (they belong to no party, so the
-- existing party-membership read policy can't see them).
drop policy if exists point_events_read_own on public.point_events;
create policy point_events_read_own on public.point_events for select to authenticated
  using (subject_user_id = auth.uid());

-- The diary award. SERVER-AUTHORITATIVE: the client says "I logged a new drink";
-- the server CHECKS the entries table before it pays. You cannot mint a spark by
-- claiming one — same discipline as award_checkin.
--   kind 'new-drink' → key is the drink name. Paid only if this is the ONLY time
--                      that name appears in your diary (i.e. you just tried it).
--   kind 'dry-day'   → key is the day. Paid only if that day really is logged as
--                      a dry day (an entry of type 'none') in YOUR diary.
create or replace function public.award_diary(kind text, key text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r text; n int;
begin
  if uid is null then raise exception 'not signed in'; end if;
  if kind not in ('new-drink', 'dry-day') then raise exception 'unknown kind'; end if;

  if kind = 'new-drink' then
    select count(*) into n from public.entries e
    where e.user_id = uid
      and lower(trim(e.drink)) = lower(trim(key))
      and coalesce(e.type, '') <> 'none';
    if n <> 1 then return false; end if;             -- not new (or not yours)
    r := 'new-drink:' || lower(trim(key));
  else
    select count(*) into n from public.entries e
    where e.user_id = uid and e.date = key::date and e.type = 'none';
    if n < 1 then return false; end if;              -- that dry day isn't real
    r := 'dry-day:' || key;
  end if;

  begin
    insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
    values (null, uid, null, 'spark', r, 1);
  exception when unique_violation then
    return false;                                    -- already paid; harmless
  end;
  return true;
end; $$;
revoke all on function public.award_diary(text, text) from public;
grant execute on function public.award_diary(text, text) to authenticated;

-- ── 2. check-in now pays for a NEW PLACE, not for turning up again ───────────
-- Still idempotent, still server-decided. The change: if this room belongs to a
-- venue you have ALREADY checked into before, you get no spark. Going back to
-- your local is lovely — it just isn't a score. (Your perk still counts it.)
create or replace function public.award_checkin(pid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); vid uuid; seen boolean;
begin
  if uid is null then raise exception 'not signed in'; end if;
  if not public.is_party_member(pid, uid) then raise exception 'not in this room'; end if;

  select room.venue_id into vid from public.parties room where room.id = pid;

  if vid is not null then
    -- have I checked into ANY room of this venue before?
    select exists (
      select 1 from public.point_events pe
      join public.parties room on room.id = pe.party_id
      where pe.subject_user_id = uid
        and pe.currency = 'spark'
        and pe.reason = 'checkin'
        and room.venue_id = vid
        and pe.party_id <> pid
    ) into seen;
    if seen then return false; end if;    -- a regular, not an explorer. No spark.
  end if;

  begin
    insert into public.point_events (party_id, subject_user_id, awarder_id, currency, reason, value)
    values (pid, uid, null, 'spark', 'checkin', 1);
  exception when unique_violation then
    return false;
  end;
  return true;
end; $$;
revoke all on function public.award_checkin(uuid) from public;
grant execute on function public.award_checkin(uuid) to authenticated;

-- ── 3. consent to a bar's screen: per room, and it expires ───────────────────
-- The bar decides how long its board lives.
alter table public.parties add column if not exists board_until timestamptz;

-- The guest decides, for THIS room only, whether they're on the board and
-- whether their tab shows. No row = not on the screen. Deleting the room
-- deletes the consent with it.
create table public.room_consent (
  party_id   uuid not null references public.parties(id)  on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  on_board   boolean not null default false,
  show_tab   boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (party_id, user_id)
);
alter table public.room_consent enable row level security;

create policy room_consent_read on public.room_consent for select to authenticated
  using (user_id = auth.uid() or public.is_party_member(party_id, auth.uid()));
create policy room_consent_write on public.room_consent for insert to authenticated
  with check (user_id = auth.uid() and public.is_party_member(party_id, auth.uid()));
create policy room_consent_update on public.room_consent for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy room_consent_delete on public.room_consent for delete to authenticated
  using (user_id = auth.uid());

-- Is a room's board still live? Default: until the end of the day it was held.
create or replace function public.board_live(room public.parties)
returns boolean
language sql immutable set search_path = public as $$
  select now() < coalesce(room.board_until, (room.date + 1)::timestamptz);
$$;

-- The wall board — anon, per-room consent, and DEAD once the night is over.
create or replace function public.room_board(code text)
returns table (display_name text, sparks int, vibe int)
language sql stable security definer set search_path = public as $$
  select coalesce(p.display_name, 'guest') as display_name,
         coalesce(sum(pe.value) filter (where pe.currency = 'spark'), 0)::int as sparks,
         coalesce(sum(pe.value) filter (where pe.currency = 'vibe'),  0)::int as vibe
  from public.parties party
  join public.room_consent rc on rc.party_id = party.id and rc.on_board = true
  join public.point_events pe on pe.party_id = party.id and pe.subject_user_id = rc.user_id
  join public.profiles p on p.id = rc.user_id
  where party.invite_code = lower(trim(code))
    and public.board_live(party)
  group by p.id, p.display_name
  order by 2 desc, 3 desc, 1;
$$;
revoke all on function public.room_board(text) from public;
grant execute on function public.room_board(text) to anon, authenticated;

-- The tab strip — still double-gated (on the board AND showing your tab), still
-- only a figure the BAR recorded, and now it dies with the night too.
create or replace function public.room_tabs(code text)
returns table (display_name text, spend numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(p.display_name, 'guest') as display_name,
         sum(se.amount)::numeric as spend
  from public.parties party
  join public.room_consent rc on rc.party_id = party.id
                             and rc.on_board = true and rc.show_tab = true
  join public.spend_events se on se.party_id = party.id and se.subject_user_id = rc.user_id
  join public.profiles p on p.id = rc.user_id
  where party.invite_code = lower(trim(code))
    and public.board_live(party)
  group by p.id, p.display_name
  order by 2 desc, 1;
$$;
revoke all on function public.room_tabs(text) from public;
grant execute on function public.room_tabs(text) to anon, authenticated;
