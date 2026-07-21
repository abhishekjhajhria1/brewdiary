-- ============================================================================
-- brewdiary — "Cups" (Phase C-2): user-made exploration competitions.
-- Incremental migration — runs on top of schema.sql + 002..043. Re-runnable
-- (drops its own objects via cascade first).
--
-- A CUP is a time-boxed competition a user creates, names, skins, and scores on
-- ONE axis they pick. Anyone can join by code; friends/fof cups are also
-- discoverable by the owner's circle. The leaderboard is NEVER stored:
-- cup_board() derives each member's score from their own entries in the window.
--
-- THE ONE LOAD-BEARING LINE (CLAUDE.md rule #6, made structural):
-- the `axis` CHECK lists ONLY breadth/behaviour metrics. There is deliberately
-- no 'volume' and no 'spend' axis — "who drank most" / "who spent most" cannot
-- be inserted, by any client, ever. Deny-by-default, exactly like plans'
-- join_policy has no 'strangers' tier. This is what keeps the game store-legal
-- (no inducement to consume) and the data corpus honest (no reward for volume).
--
-- NOTE ON THE AXES: `family` (drinks.ts) is a CLIENT-side derivation, not a DB
-- column, so the DB can't fold to families. The breadth axis here is 'drinks'
-- (distinct drink NAMES in the window) — the same COUNT(distinct lower(drink))
-- proxy challenge_board already uses. Still breadth, never volume: logging the
-- same drink twice adds nothing.
-- ============================================================================

-- (no standalone DROP TRIGGER here: it errors on a fresh run when public.cups
--  doesn't exist yet — the drop table … cascade below removes the trigger too.)
drop table     if exists public.cup_members cascade;
drop table     if exists public.cups        cascade;
drop function  if exists public.cup_board(uuid)          cascade;
drop function  if exists public.join_cup(text)           cascade;
drop function  if exists public.cup_visible_to(uuid, uuid) cascade;
drop function  if exists public.is_cup_member(uuid, uuid)  cascade;
drop function  if exists public.cups_add_owner()         cascade;

create table public.cups (
  id          uuid primary key default gen_random_uuid(),
  created_by  uuid not null references public.profiles(id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  -- a cosmetic look the creator picks — "your cup, your colours" (CD Expression),
  -- constrained to a known set so a skin can't smuggle in arbitrary markup.
  skin        text not null default 'classic'
                check (skin in ('classic', 'amber', 'forest', 'dusk', 'rose', 'mono')),
  -- THE ANTI-VOLUME PALETTE. Only breadth/behaviour axes exist here:
  --   drinks = distinct drinks tried · venues = distinct places · varied =
  --   distinct kinds · dry = dry days. No 'volume', no 'spend' — deny-by-default.
  axis        text not null check (axis in ('drinks', 'venues', 'varied', 'dry')),
  join_policy text not null default 'invite'
                check (join_policy in ('friends', 'fof', 'invite')),  -- NO 'public'/'strangers' tier
  invite_code text not null unique
                default substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
  starts_on   date not null,
  ends_on     date not null,
  created_at  timestamptz not null default now(),
  check (ends_on >= starts_on)
);
create index cups_owner_idx on public.cups (created_by);
create index cups_code_idx  on public.cups (invite_code);

create table public.cup_members (
  cup_id    uuid not null references public.cups(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (cup_id, user_id)   -- one membership per person (anti-double-join)
);

-- "is uid in this cup?" — definer, so cup_members' policy can't re-enter cups' RLS.
create or replace function public.is_cup_member(cup uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.cup_members m where m.cup_id = cup and m.user_id = uid);
$$;

-- THE one visibility authority (owner / member / eligible-by-policy, and never a
-- blocked pair). Reused by the read policy AND join_cup so they cannot drift.
-- An 'invite' cup is not discoverable — you reach it only with the code.
create or replace function public.cup_visible_to(cup uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.cups c
    where c.id = cup
      and not public.blocked_between(c.created_by, uid)
      and (
        c.created_by = uid
        or public.is_cup_member(cup, uid)
        or (c.join_policy = 'friends' and public.are_friends(c.created_by, uid))
        or (c.join_policy = 'fof'
            and (public.are_friends(c.created_by, uid) or public.is_fof(uid, c.created_by)))
      )
  );
$$;

-- The leaderboard. SECURITY DEFINER because members' entries are private rows the
-- caller can't select — joining a cup consents to COUNT visibility only, never
-- entry content. One integer per member, computed on the cup's axis over its
-- window. Every axis is a COUNT(distinct …): repeats never help, so it can never
-- reward volume. Non-members get an empty set.
create or replace function public.cup_board(cup uuid)
returns table (user_id uuid, display_name text, handle text, score int)
language sql stable security definer set search_path = public as $$
  select m.user_id,
         coalesce(p.display_name, 'player'),
         p.handle,
         coalesce(case c.axis
           when 'drinks' then count(distinct lower(btrim(e.drink)))
                                filter (where e.type is distinct from 'none')
           when 'venues' then count(distinct lower(btrim(e.venue)))
                                filter (where e.venue is not null and btrim(e.venue) <> '')
           when 'varied' then count(distinct e.type)
                                filter (where e.type is not null and e.type <> 'none')
           when 'dry'    then count(distinct e.date)
                                filter (where e.type = 'none')
         end, 0)::int
  from public.cup_members m
  join public.cups c     on c.id = m.cup_id
  join public.profiles p on p.id = m.user_id
  left join public.entries e
    on e.user_id = m.user_id and e.date >= c.starts_on and e.date <= c.ends_on
  where m.cup_id = cup
    and public.is_cup_member(cup, auth.uid())   -- members only, checked server-side
  group by m.user_id, p.display_name, p.handle, c.axis;
$$;

revoke all on function public.cup_board(uuid) from public;
grant execute on function public.cup_board(uuid) to authenticated;

-- Join a cup by its code. Writes are ONLY here (cup_members has no insert policy),
-- so a client can never forge a membership. The code admits you to an 'invite'
-- cup; a friends/fof cup still requires the tie. A blocked pair, or a cup that has
-- already ended, is refused.
create or replace function public.join_cup(code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  c  public.cups;
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into c from public.cups where invite_code = lower(btrim(code));
  if not found then raise exception 'no such cup'; end if;
  if public.blocked_between(c.created_by, me) then raise exception 'unavailable'; end if;
  if c.ends_on < current_date then raise exception 'this cup has ended'; end if;
  if not (c.join_policy = 'invite' or public.cup_visible_to(c.id, me)) then
    raise exception 'not eligible to join this cup';
  end if;
  insert into public.cup_members (cup_id, user_id)
  values (c.id, me)
  on conflict (cup_id, user_id) do nothing;
  return c.id;
end;
$$;

revoke all on function public.join_cup(text) from public;
grant execute on function public.join_cup(text) to authenticated;

-- The owner is always a member (so they appear on their own board). Runs on insert
-- as definer, since cup_members has no client insert policy.
create or replace function public.cups_add_owner()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.cup_members (cup_id, user_id)
  values (new.id, new.created_by)
  on conflict do nothing;
  return new;
end;
$$;

create trigger cups_add_owner_trg
  after insert on public.cups
  for each row execute function public.cups_add_owner();

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.cups        enable row level security;
alter table public.cup_members enable row level security;

-- cups: readable by anyone it's visible to; you create your own; owner edits/deletes.
create policy cups_read on public.cups for select to authenticated
  using (public.cup_visible_to(id, auth.uid()));
create policy cups_insert on public.cups for insert to authenticated
  with check (created_by = auth.uid());
create policy cups_update on public.cups for update to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy cups_delete on public.cups for delete to authenticated
  using (created_by = auth.uid());

-- membership: the roster is visible to members; there is deliberately NO insert
-- policy (joining goes through join_cup only); you may leave (delete your own row).
create policy cup_members_read on public.cup_members for select to authenticated
  using (public.is_cup_member(cup_id, auth.uid()));
create policy cup_members_delete on public.cup_members for delete to authenticated
  using (user_id = auth.uid());
