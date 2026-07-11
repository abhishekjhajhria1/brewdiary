-- ============================================================================
-- brewdiary — fresh schema for a clean Supabase project (Postgres).
--
-- HOW TO RUN: Supabase dashboard → SQL Editor → New query → paste all → Run.
-- Safe to re-run: it DROPs and recreates ONLY brewdiary's own public tables.
-- It does NOT touch auth.* or storage.* internals (only adds a photos bucket).
--
-- Security model: Row Level Security ON for every table. The anon key is public,
-- so these policies are what actually protect the data. Default visibility is
-- private; a row is shared only to accepted mutual friends when visibility='friends'.
-- ============================================================================

-- ---------- FULL RESET — wipes EVERYTHING in the public schema ---------------
-- This project still holds an old project's tables (profiles/parties/events…).
-- Per "remove everything from supabase", we drop the whole public schema and
-- rebuild it. This is DESTRUCTIVE: all public tables + data are deleted. It does
-- NOT touch auth.* (your users) or storage internals. Re-grant the roles Supabase
-- expects so PostgREST/anon/authenticated see the new tables.
drop schema if exists public cascade;
create schema public;
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on all tables    in schema public to postgres, anon, authenticated, service_role;
grant all on all routines  in schema public to postgres, anon, authenticated, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on tables    to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on routines  to postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to postgres, anon, authenticated, service_role;

create extension if not exists "pgcrypto";  -- gen_random_uuid()

-- ---------- profiles --------------------------------------------------------
-- One row per auth user. `handle` is the public identity used for friend search.
create table public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  handle           text unique not null,
  display_name     text not null default 'you',
  avatar_url       text,
  bio              text,
  reminder_enabled boolean not null default false,
  created_at       timestamptz not null default now()
);

-- ---------- entries (the heart) ---------------------------------------------
create table public.entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  date        date not null,                          -- the day the entry is FOR (mosaic counts THIS)
  drink       text not null,
  type        text,                                   -- coffee|tea|beer|wine|cocktail|spirit|soft|other
  mood        text,                                   -- one word; feeds the derived lexicon
  note        text,
  venue       text,
  who_with    text[],                                 -- free-text names (real friend ids arrive later)
  visibility  text not null default 'private',        -- private | friends
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (visibility in ('private', 'friends'))
);
create index entries_user_date_idx  on public.entries (user_id, date);
create index entries_shared_idx      on public.entries (user_id) where visibility = 'friends';

-- ---------- entry_photos (several per entry) --------------------------------
create table public.entry_photos (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references public.entries(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  url        text not null,                           -- path/URL in the 'photos' storage bucket
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index entry_photos_entry_idx on public.entry_photos (entry_id);

-- ---------- friendships (mutual) --------------------------------------------
create table public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.profiles(id) on delete cascade,
  addressee_id  uuid not null references public.profiles(id) on delete cascade,
  status        text not null default 'pending',      -- pending | accepted
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  unique (requester_id, addressee_id),
  check (requester_id <> addressee_id),
  check (status in ('pending', 'accepted'))
);
create index friendships_addressee_idx on public.friendships (addressee_id, status);

-- accepted-friends check, SECURITY DEFINER so entry RLS can call it without recursion
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;

-- ---------- reactions (cheers) ----------------------------------------------
create table public.reactions (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references public.entries(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  type       text not null default 'cheers',
  created_at timestamptz not null default now(),
  unique (entry_id, user_id, type)
);

-- ---------- comments --------------------------------------------------------
create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  entry_id   uuid not null references public.entries(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);
create index comments_entry_idx on public.comments (entry_id);

-- ---------- wishlist (to-try) -----------------------------------------------
create table public.wishlist_items (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  drink_name text not null,
  type       text,
  note       text,
  fulfilled  boolean not null default false,
  created_at timestamptz not null default now()
);
create index wishlist_user_idx on public.wishlist_items (user_id);

-- keep entries.updated_at fresh
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
create trigger entries_touch_updated before update on public.entries
  for each row execute function public.touch_updated_at();

-- ============================================================================
-- Row Level Security
-- ============================================================================
alter table public.profiles       enable row level security;
alter table public.entries        enable row level security;
alter table public.entry_photos   enable row level security;
alter table public.friendships    enable row level security;
alter table public.reactions      enable row level security;
alter table public.comments       enable row level security;
alter table public.wishlist_items enable row level security;

-- profiles: anyone signed in can read (friend search + feed author names); write only your own
create policy profiles_read   on public.profiles for select to authenticated using (true);
create policy profiles_insert on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid());

-- entries: owner sees own; friends see your 'friends'-visible rows
create policy entries_read on public.entries for select to authenticated
  using (user_id = auth.uid()
      or (visibility = 'friends' and public.are_friends(auth.uid(), user_id)));
create policy entries_insert on public.entries for insert to authenticated
  with check (user_id = auth.uid());
create policy entries_update on public.entries for update to authenticated
  using (user_id = auth.uid());
create policy entries_delete on public.entries for delete to authenticated
  using (user_id = auth.uid());

-- entry_photos: visible if you can see the parent entry; write only your own
create policy photos_read on public.entry_photos for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id
           and (e.user_id = auth.uid()
             or (e.visibility = 'friends' and public.are_friends(auth.uid(), e.user_id)))));
create policy photos_insert on public.entry_photos for insert to authenticated
  with check (user_id = auth.uid()
          and exists (select 1 from public.entries e where e.id = entry_id and e.user_id = auth.uid()));
create policy photos_delete on public.entry_photos for delete to authenticated
  using (user_id = auth.uid());

-- friendships: you can see/act on rows where you're a party
create policy friendships_read on public.friendships for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy friendships_insert on public.friendships for insert to authenticated
  with check (requester_id = auth.uid());
create policy friendships_update on public.friendships for update to authenticated
  using (addressee_id = auth.uid() or requester_id = auth.uid());
create policy friendships_delete on public.friendships for delete to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- reactions + comments: visible on entries you can see; you write/remove only your own
create policy reactions_read on public.reactions for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id
           and (e.user_id = auth.uid()
             or (e.visibility = 'friends' and public.are_friends(auth.uid(), e.user_id)))));
create policy reactions_write on public.reactions for insert to authenticated
  with check (user_id = auth.uid());
create policy reactions_delete on public.reactions for delete to authenticated
  using (user_id = auth.uid());

create policy comments_read on public.comments for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id
           and (e.user_id = auth.uid()
             or (e.visibility = 'friends' and public.are_friends(auth.uid(), e.user_id)))));
create policy comments_write on public.comments for insert to authenticated
  with check (user_id = auth.uid());
create policy comments_delete on public.comments for delete to authenticated
  using (user_id = auth.uid());

-- wishlist: fully private to its owner
create policy wishlist_all on public.wishlist_items for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================================
-- Storage: a 'photos' bucket, each user writing under their own uid/ folder
-- ============================================================================
insert into storage.buckets (id, name, public)
  values ('photos', 'photos', true)
  on conflict (id) do nothing;

create policy "photos read"   on storage.objects for select to authenticated
  using (bucket_id = 'photos');
create policy "photos write"  on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "photos delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
