-- ============================================================================
-- brewdiary — "Parties" (events inside Together: host, invite, RSVP, shared
-- party log → the party page doubles as the recap once the night has passed).
-- Incremental migration — runs on top of schema.sql + 002 + 003. Idempotent-ish.
--
-- Model mirrors circles: PARTIES + PARTY_MEMBERS (with an rsvp column) +
-- PARTY_SHARES (one entry exposed to one party without touching
-- entries.visibility). The invite code doubles as a shareable LINK (/p/<code>)
-- that even non-users can open — party_preview() is anon-callable and returns
-- only safe surface (name/date/venue/host/headcount), never entries.
-- ============================================================================

drop table if exists public.party_shares  cascade;
drop table if exists public.party_members cascade;
drop table if exists public.parties       cascade;
drop function if exists public.is_party_member(uuid, uuid)   cascade;
drop function if exists public.entry_in_my_party(uuid, uuid) cascade;
drop function if exists public.join_party(text)              cascade;
drop function if exists public.party_preview(text)           cascade;

create table public.parties (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(trim(name)) between 1 and 80),
  host_id     uuid not null references public.profiles(id) on delete cascade,
  venue       text,
  date        date not null,
  invite_code text unique not null default substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
  created_at  timestamptz not null default now()
);
create index parties_host_idx on public.parties (host_id);

create table public.party_members (
  party_id  uuid not null references public.parties(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  rsvp      text not null default 'going' check (rsvp in ('going', 'maybe', 'no')),
  joined_at timestamptz not null default now(),
  primary key (party_id, user_id)
);
create index party_members_user_idx on public.party_members (user_id);

create table public.party_shares (
  entry_id   uuid not null references public.entries(id) on delete cascade,
  party_id   uuid not null references public.parties(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,  -- the sharer = entry owner
  created_at timestamptz not null default now(),
  primary key (entry_id, party_id)
);
create index party_shares_party_idx on public.party_shares (party_id);

create or replace function public.is_party_member(pid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.party_members m
    where m.party_id = pid and m.user_id = uid
  );
$$;

create or replace function public.entry_in_my_party(eid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.party_shares s
    join public.party_members m on m.party_id = s.party_id
    where s.entry_id = eid and m.user_id = uid
  );
$$;

-- join (or re-RSVP 'going') by invite code — definer, since a non-member can't
-- SELECT the party row to resolve the code under RLS.
create or replace function public.join_party(code text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public as $$
declare p public.parties;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  select * into p from public.parties where invite_code = lower(trim(code));
  if p.id is null then
    raise exception 'invalid code';
  end if;
  insert into public.party_members (party_id, user_id)
    values (p.id, auth.uid())
    on conflict do nothing;
  return query select p.id, p.name;
end; $$;

revoke all on function public.join_party(text) from public;
grant execute on function public.join_party(text) to authenticated;

-- safe public surface for the shareable invite link — callable WITHOUT auth.
create or replace function public.party_preview(code text)
returns table (name text, date date, venue text, host_name text, going int)
language sql stable security definer set search_path = public as $$
  select p.name, p.date, p.venue,
         coalesce(h.display_name, 'someone') as host_name,
         (select count(*)::int from public.party_members m
           where m.party_id = p.id and m.rsvp = 'going') as going
  from public.parties p
  left join public.profiles h on h.id = p.host_id
  where p.invite_code = lower(trim(code));
$$;

revoke all on function public.party_preview(text) from public;
grant execute on function public.party_preview(text) to anon, authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.parties       enable row level security;
alter table public.party_members enable row level security;
alter table public.party_shares  enable row level security;

create policy parties_read on public.parties for select to authenticated
  using (host_id = auth.uid() or public.is_party_member(id, auth.uid()));
create policy parties_insert on public.parties for insert to authenticated
  with check (host_id = auth.uid());
create policy parties_update on public.parties for update to authenticated
  using (host_id = auth.uid());
create policy parties_delete on public.parties for delete to authenticated
  using (host_id = auth.uid());

-- members: guest list visible to fellow members; the host seeds themself
-- (others come through join_party, which is definer); you change your own
-- rsvp; you can leave and the host can remove people.
create policy party_members_read on public.party_members for select to authenticated
  using (public.is_party_member(party_id, auth.uid()));
create policy party_members_insert on public.party_members for insert to authenticated
  with check (user_id = auth.uid()
          and exists (select 1 from public.parties p where p.id = party_id and p.host_id = auth.uid()));
create policy party_members_update on public.party_members for update to authenticated
  using (user_id = auth.uid());
create policy party_members_delete on public.party_members for delete to authenticated
  using (user_id = auth.uid()
      or exists (select 1 from public.parties p where p.id = party_id and p.host_id = auth.uid()));

create policy party_shares_read on public.party_shares for select to authenticated
  using (public.is_party_member(party_id, auth.uid()));
create policy party_shares_insert on public.party_shares for insert to authenticated
  with check (user_id = auth.uid()
          and public.is_party_member(party_id, auth.uid())
          and exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()));
create policy party_shares_delete on public.party_shares for delete to authenticated
  using (user_id = auth.uid());

-- party members may READ entries (and their photos/cheers/comments) shared
-- into their parties — additive, ORed with the owner/friends/circle policies.
create policy entries_party_read on public.entries for select to authenticated
  using (public.entry_in_my_party(id, auth.uid()));
create policy photos_party_read on public.entry_photos for select to authenticated
  using (public.entry_in_my_party(entry_id, auth.uid()));
create policy reactions_party_read on public.reactions for select to authenticated
  using (public.entry_in_my_party(entry_id, auth.uid()));
create policy comments_party_read on public.comments for select to authenticated
  using (public.entry_in_my_party(entry_id, auth.uid()));
