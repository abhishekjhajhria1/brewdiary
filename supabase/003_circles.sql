-- ============================================================================
-- brewdiary — "Circles" (private groups inside Together).
-- Incremental migration — safe to run on top of schema.sql + 002_split.sql.
-- Idempotent-ish: drops its own objects first, then recreates.
--
-- Model: a CIRCLE is a private group you join with an invite code (no public
-- discovery — social stays invite-only). CIRCLE_MEMBERS is the roster.
-- Sharing an entry to a circle is a separate act (diary stays private by
-- default): a CIRCLE_SHARES row makes one entry visible to one circle without
-- touching entries.visibility — an entry can be private-to-the-world yet
-- shared to a circle, or shared to friends AND circles. The circle's combined
-- mosaic is DERIVED client-side from the entries shared into it.
--
-- RLS gotchas honored:
--  * circle_members policies must not reference circle_members directly
--    (infinite recursion) → is_circle_member() is SECURITY DEFINER.
--  * inserts from the app avoid INSERT..RETURNING on tables whose select
--    policy calls a definer fn (PostgREST trips — learned on expenses).
--  * joining by code can't be a plain insert (you can't SELECT a circle you
--    aren't in to find the code) → join_circle() is SECURITY DEFINER.
-- ============================================================================

drop table if exists public.circle_shares  cascade;
drop table if exists public.circle_members cascade;
drop table if exists public.circles        cascade;
drop function if exists public.is_circle_member(uuid, uuid)      cascade;
drop function if exists public.entry_in_my_circle(uuid, uuid)    cascade;
drop function if exists public.join_circle(text)                 cascade;

create table public.circles (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(trim(name)) between 1 and 60),
  created_by  uuid not null references public.profiles(id) on delete cascade,
  -- short shareable join code; lowercase hex, unique. No public listing exists,
  -- so the code IS the invitation.
  invite_code text unique not null default substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
  created_at  timestamptz not null default now()
);
create index circles_creator_idx on public.circles (created_by);

create table public.circle_members (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);
create index circle_members_user_idx on public.circle_members (user_id);

create table public.circle_shares (
  entry_id   uuid not null references public.entries(id) on delete cascade,
  circle_id  uuid not null references public.circles(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,  -- the sharer = entry owner
  created_at timestamptz not null default now(),
  primary key (entry_id, circle_id)
);
create index circle_shares_circle_idx on public.circle_shares (circle_id);

-- membership check, SECURITY DEFINER so policies can call it without recursion
create or replace function public.is_circle_member(cid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.circle_members m
    where m.circle_id = cid and m.user_id = uid
  );
$$;

-- "is this entry shared into any circle uid belongs to?" — lets entries /
-- photos / reactions / comments RLS grant circle members read access.
create or replace function public.entry_in_my_circle(eid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.circle_shares s
    join public.circle_members m on m.circle_id = s.circle_id
    where s.entry_id = eid and m.user_id = uid
  );
$$;

-- join by invite code. SECURITY DEFINER because a non-member can't SELECT the
-- circle row to resolve the code under RLS. Returns the joined circle.
create or replace function public.join_circle(code text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public as $$
declare c public.circles;
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  select * into c from public.circles where invite_code = lower(trim(code));
  if c.id is null then
    raise exception 'invalid code';
  end if;
  insert into public.circle_members (circle_id, user_id)
    values (c.id, auth.uid())
    on conflict do nothing;
  return query select c.id, c.name;
end; $$;

revoke all on function public.join_circle(text) from public;
grant execute on function public.join_circle(text) to authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.circles        enable row level security;
alter table public.circle_members enable row level security;
alter table public.circle_shares  enable row level security;

-- circles: members (and the creator) can read; creator writes/renames/deletes
create policy circles_read on public.circles for select to authenticated
  using (created_by = auth.uid() or public.is_circle_member(id, auth.uid()));
create policy circles_insert on public.circles for insert to authenticated
  with check (created_by = auth.uid());
create policy circles_update on public.circles for update to authenticated
  using (created_by = auth.uid());
create policy circles_delete on public.circles for delete to authenticated
  using (created_by = auth.uid());

-- members: the roster is visible to fellow members; you add yourself only to a
-- circle you created (everyone else joins via join_circle, which is definer);
-- you can leave, and the creator can remove people.
create policy members_read on public.circle_members for select to authenticated
  using (public.is_circle_member(circle_id, auth.uid()));
create policy members_insert on public.circle_members for insert to authenticated
  with check (user_id = auth.uid()
          and exists (select 1 from public.circles c where c.id = circle_id and c.created_by = auth.uid()));
create policy members_delete on public.circle_members for delete to authenticated
  using (user_id = auth.uid()
      or exists (select 1 from public.circles c where c.id = circle_id and c.created_by = auth.uid()));

-- shares: members see what's shared into the circle; only the entry's owner
-- (who must be a member) shares or unshares it.
create policy circle_shares_read on public.circle_shares for select to authenticated
  using (public.is_circle_member(circle_id, auth.uid()));
create policy circle_shares_insert on public.circle_shares for insert to authenticated
  with check (user_id = auth.uid()
          and public.is_circle_member(circle_id, auth.uid())
          and exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()));
create policy circle_shares_delete on public.circle_shares for delete to authenticated
  using (user_id = auth.uid());

-- entries + photos + reactions + comments: circle members may READ entries
-- shared into their circles. Additive policies — Postgres ORs them with the
-- owner/friends policies from schema.sql; nothing existing changes.
create policy entries_circle_read on public.entries for select to authenticated
  using (public.entry_in_my_circle(id, auth.uid()));
create policy photos_circle_read on public.entry_photos for select to authenticated
  using (public.entry_in_my_circle(entry_id, auth.uid()));
create policy reactions_circle_read on public.reactions for select to authenticated
  using (public.entry_in_my_circle(entry_id, auth.uid()));
create policy comments_circle_read on public.comments for select to authenticated
  using (public.entry_in_my_circle(entry_id, auth.uid()));
