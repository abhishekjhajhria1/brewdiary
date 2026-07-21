-- ============================================================================
-- brewdiary — "Community recipes" (Phase D): make your own drink (by hand or with
-- Ninkasi), share it, and earn medals from other people's POSITIVE reactions.
-- Incremental migration on top of schema.sql + 002..044. Re-runnable.
--
-- Reward model (same spine as vibe / cartographer): a medal celebrates a RECIPE'S
-- popularity — CREATIVITY, never consumption. Reactions are POSITIVE-ONLY (no
-- downvote, so no pile-on) and one-of-each-KIND per person (anti-farming, in the PK).
-- Medals are DERIVED from reaction counts, never a stored total.
--
-- Visibility grows organically (maintainer's design):
--   friends  → visible to your friends & circle-mates (the default on create)
--   pending  → once >=50% of your friends have reacted (and you have >=3 friends),
--              a trigger flips it to 'pending' — it enters the moderator queue
--   public   → a moderator approves it; now anyone can see & react. (Reject → back
--              to 'friends'.) Deny-by-default: nothing reaches the public surface
--              without both social proof AND a human review (like the Cartographer).
--
-- No axis of this rewards drinking more, and — like recipes.ts — a recipe is a
-- MAKING prompt: no "buy X", no shopping list (inducement stays out).
-- ============================================================================

drop table    if exists public.recipe_reactions cascade;
drop table    if exists public.recipes          cascade;
drop function if exists public.recipe_visible_to(uuid, uuid)     cascade;
drop function if exists public.recipe_reaction_counts(uuid)      cascade;
drop function if exists public.recipe_friend_ratio(uuid)         cascade;
drop function if exists public.edit_recipe(uuid, text, text[], text) cascade;
drop function if exists public.review_recipe(uuid, boolean)      cascade;
drop function if exists public.pending_recipes()                 cascade;
drop function if exists public.recipes_maybe_promote()           cascade;

create table public.recipes (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references public.profiles(id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 80),
  ingredients text[] not null default '{}',
  method      text not null check (char_length(btrim(method)) between 1 and 800),
  -- who wrote it: 'ninkasi' = drafted with the AI then edited by the author (the
  -- author always owns the final — the AI co-writes, it never authors).
  source      text not null default 'self' check (source in ('self', 'ninkasi')),
  -- the visibility ladder — deny-by-default: created 'friends', never straight to public.
  state       text not null default 'friends' check (state in ('friends', 'pending', 'public')),
  created_at  timestamptz not null default now()
);
create index recipes_author_idx on public.recipes (author_id);
create index recipes_state_idx  on public.recipes (state);

create table public.recipe_reactions (
  recipe_id  uuid not null references public.recipes(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  -- POSITIVE-ONLY. No 'dislike' exists, so a reaction can never become a weapon.
  kind       text not null check (kind in ('made', 'love', 'totry')),
  created_at timestamptz not null default now(),
  primary key (recipe_id, user_id, kind)   -- one of each kind per person (anti-farm)
);

-- Can uid see this recipe? Author always; a public one to anyone; a friends/pending one
-- to the author's friends or circle-mates. Never across a block. THE one authority — the
-- read policy, the reaction-insert check and the counts fn all defer to it.
create or replace function public.recipe_visible_to(rid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.recipes r
    where r.id = rid
      and not public.blocked_between(r.author_id, uid)
      and (
        r.author_id = uid
        or r.state = 'public'
        or (r.state in ('friends', 'pending') and (
              public.are_friends(r.author_id, uid)
              or exists (
                select 1 from public.circle_members a
                join public.circle_members b on b.circle_id = a.circle_id
                where a.user_id = r.author_id and b.user_id = uid
              )
        ))
      )
  );
$$;

-- Reaction tallies — COUNTS ONLY, and only if you can see the recipe. Never who reacted.
-- Always returns the three kinds (0-filled) so the client can render medals uniformly.
create or replace function public.recipe_reaction_counts(rid uuid)
returns table (kind text, n int)
language sql stable security definer set search_path = public as $$
  select k.kind, count(rr.recipe_id)::int
  from (values ('made'), ('love'), ('totry')) as k(kind)
  left join public.recipe_reactions rr on rr.recipe_id = rid and rr.kind = k.kind
  where public.recipe_visible_to(rid, auth.uid())
  group by k.kind;
$$;
revoke all on function public.recipe_reaction_counts(uuid) from public;
grant execute on function public.recipe_reaction_counts(uuid) to authenticated;

-- What fraction of the author's friends have reacted (any kind)? Drives promotion.
create or replace function public.recipe_friend_ratio(rid uuid)
returns numeric
language sql stable security definer set search_path = public as $$
  with r as (select author_id from public.recipes where id = rid),
  friends as (
    select case when f.requester_id = (select author_id from r) then f.addressee_id
                else f.requester_id end as fid
    from public.friendships f
    where f.status = 'accepted'
      and (f.requester_id = (select author_id from r) or f.addressee_id = (select author_id from r))
  ),
  reacted as (
    select distinct rr.user_id from public.recipe_reactions rr
    where rr.recipe_id = rid and rr.user_id in (select fid from friends)
  )
  select case when (select count(*) from friends) = 0 then 0
              else (select count(*) from reacted)::numeric / (select count(*) from friends) end;
$$;

-- On each reaction, promote a 'friends' recipe to 'pending' once its author has a real
-- circle of friends (>=3) and at least half of them have backed it. Definer, because it
-- writes a column no client may set. From 'pending'/'public' it does nothing.
create or replace function public.recipes_maybe_promote()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  st text;
  fc int;
begin
  select state into st from public.recipes where id = new.recipe_id;
  if st is distinct from 'friends' then return new; end if;

  select count(*) into fc from public.friendships f
  where f.status = 'accepted'
    and (f.requester_id = (select author_id from public.recipes where id = new.recipe_id)
      or f.addressee_id = (select author_id from public.recipes where id = new.recipe_id));

  if fc >= 3 and public.recipe_friend_ratio(new.recipe_id) >= 0.5 then
    update public.recipes set state = 'pending' where id = new.recipe_id and state = 'friends';
  end if;
  return new;
end;
$$;
create trigger recipe_reactions_promote
  after insert on public.recipe_reactions
  for each row execute function public.recipes_maybe_promote();

-- Authors edit CONTENT via this definer fn only (there is no client UPDATE policy on
-- recipes) — so an author can fix the name/method but can never touch `state` to jump
-- the queue. Author-only.
create or replace function public.edit_recipe(rid uuid, new_name text, new_ingredients text[], new_method text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.recipes where id = rid and author_id = auth.uid()) then
    raise exception 'not your recipe';
  end if;
  update public.recipes
     set name = new_name, ingredients = coalesce(new_ingredients, '{}'), method = new_method
   where id = rid;
end;
$$;
revoke all on function public.edit_recipe(uuid, text, text[], text) from public;
grant execute on function public.edit_recipe(uuid, text, text[], text) to authenticated;

-- The moderator gate to the public surface. Approve → public; reject → back to friends.
-- Re-derives is_moderator server-side (never trusts the client).
create or replace function public.review_recipe(rid uuid, approve boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator(auth.uid()) then raise exception 'not a moderator'; end if;
  update public.recipes
     set state = case when approve then 'public' else 'friends' end
   where id = rid and state = 'pending';
end;
$$;
revoke all on function public.review_recipe(uuid, boolean) from public;
grant execute on function public.review_recipe(uuid, boolean) to authenticated;

-- The moderator queue: recipes awaiting the public gate. Moderator-only (empty otherwise).
create or replace function public.pending_recipes()
returns table (id uuid, author_id uuid, name text, ingredients text[], method text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, r.author_id, r.name, r.ingredients, r.method, r.created_at
  from public.recipes r
  where r.state = 'pending' and public.is_moderator(auth.uid())
  order by r.created_at asc;
$$;
revoke all on function public.pending_recipes() from public;
grant execute on function public.pending_recipes() to authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.recipes          enable row level security;
alter table public.recipe_reactions enable row level security;

-- recipes: read anything visible to you; create your own (only ever as 'friends'); no
-- client UPDATE (edits + state changes go through the definer fns above); delete your own.
create policy recipes_read on public.recipes for select to authenticated
  using (public.recipe_visible_to(id, auth.uid()));
create policy recipes_insert on public.recipes for insert to authenticated
  with check (author_id = auth.uid() and state = 'friends');
create policy recipes_delete on public.recipes for delete to authenticated
  using (author_id = auth.uid());

-- reactions: you see your OWN (to toggle them); you react only to a recipe you can see;
-- you remove your own. Nobody reads the full reaction list — tallies come from the
-- counts fn, so "who reacted" never leaks.
create policy recipe_reactions_read on public.recipe_reactions for select to authenticated
  using (user_id = auth.uid());
create policy recipe_reactions_insert on public.recipe_reactions for insert to authenticated
  with check (user_id = auth.uid() and public.recipe_visible_to(recipe_id, auth.uid()));
create policy recipe_reactions_delete on public.recipe_reactions for delete to authenticated
  using (user_id = auth.uid());
