-- ============================================================================
-- Just enough of Supabase for brewdiary's migrations to run on a plain Postgres.
--
-- Used ONLY by scripts/db-local.sh, which builds a throwaway database, applies
-- supabase/schema.sql and every numbered migration, then runs db:audit and
-- db:verify against it. It never touches a real project.
--
-- What the migrations need from Supabase, and nothing more:
--   • the roles anon / authenticated / service_role (RLS is written against them);
--   • auth.users and auth.uid() — auth.uid() reads the JWT claims exactly the way
--     Supabase's does, so `set local request.jwt.claims = '{"sub": …}'` (what
--     scripts/verify-flow.mjs does) signs a session in as that user;
--   • storage.buckets / storage.objects / storage.foldername() (the photos bucket
--     in schema.sql);
--   • pgcrypto.
-- ============================================================================

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

-- The connecting superuser must be able to `set role` into each of them.
grant anon, authenticated, service_role to current_user;

-- Supabase installs extensions into their own schema, not public — so a function pinned
-- to `set search_path = public` cannot see pgcrypto there. Mirror that, so a migration that
-- would only work locally fails locally too.
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

-- ── auth ────────────────────────────────────────────────────────────────────
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id                 uuid primary key,
  instance_id        uuid,
  aud                text,
  role               text,
  email              text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Supabase's own definition: the `sub` claim of the request's JWT, or null.
create or replace function auth.uid()
returns uuid language sql stable as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid;
$$;

create or replace function auth.role()
returns text language sql stable as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.role', true),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
    ),
    ''
  );
$$;

grant execute on function auth.uid()  to anon, authenticated, service_role;
grant execute on function auth.role() to anon, authenticated, service_role;

-- ── storage ─────────────────────────────────────────────────────────────────
create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id         text primary key,
  name       text not null,
  public     boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text references storage.buckets(id),
  name       text,
  owner      uuid,
  created_at timestamptz not null default now()
);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated, service_role;

-- Every folder of an object path, without the file name ('uid/a/b.jpg' → {uid,a}).
create or replace function storage.foldername(name text)
returns text[] language plpgsql immutable as $$
declare parts text[];
begin
  parts := string_to_array(name, '/');
  return parts[1:array_length(parts, 1) - 1];
end; $$;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;
