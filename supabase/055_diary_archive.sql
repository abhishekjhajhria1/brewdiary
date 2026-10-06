-- ============================================================================
-- brewdiary — a diary is never deleted, only put away (055).
--
-- The maintainer's rule (1 Oct 2026): we always keep a person's diary. Clearing
-- it shows them a fresh one; removing an entry takes it out of view. Nothing is
-- destroyed. Clearing the WHOLE diary needs a fresh emailed code — checked HERE,
-- from the session's own sign-in record, not by trusting the app.
--
--   • entries.archived_at — set when an entry is put away.
--   • Every read sees only the live diary (a RESTRICTIVE policy, ANDed with the
--     owner / friends / circle / party read policies).
--   • No client deletes an entry any more, and no client sets archived_at: only
--     archive_entry() (one entry) and archive_my_diary() (all, code required).
--   • Deleting the ACCOUNT still removes everything (the auth cascade, run by the
--     server route with the service key) — that's the law (GDPR Art. 17, DPDP).
-- ============================================================================

alter table public.entries add column if not exists archived_at timestamptz;
create index if not exists entries_live_idx on public.entries (user_id, date) where archived_at is null;

drop policy if exists entries_live_only on public.entries;
create policy entries_live_only on public.entries as restrictive for select to authenticated
  using (archived_at is null);

drop policy if exists entries_delete on public.entries;

-- A client (the authenticated or anon role) may never touch archived_at; the two
-- definer functions below run as the owner, so they can.
create or replace function public.entries_guard_archive()
returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' and new.archived_at is not null then
      raise exception 'an entry can''t be written already put away' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and new.archived_at is distinct from old.archived_at then
      raise exception 'entries are put away with archive_entry() or archive_my_diary()' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists entries_guard_archive on public.entries;
create trigger entries_guard_archive before insert or update on public.entries
  for each row execute function public.entries_guard_archive();

-- One entry out of view (the "remove" in the log sheet). No code needed.
create or replace function public.archive_entry(eid uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '28000'; end if;
  update public.entries set archived_at = now()
   where id = eid and user_id = auth.uid() and archived_at is null;
  get diagnostics n = row_count;
  return n > 0;
end $$;
revoke all on function public.archive_entry(uuid) from public;
grant execute on function public.archive_entry(uuid) to authenticated;

-- True when this session signed in with an emailed code in the last 10 minutes.
-- Supabase records how a session was made in the JWT's `amr` claim.
create or replace function public.signed_in_by_code_recently(window_seconds int default 600)
returns boolean language sql stable set search_path = public as $$
  select exists (
    select 1
      from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) a
     where a ->> 'method' in ('otp', 'magiclink', 'email/signup')
       and (a ->> 'timestamp') ~ '^[0-9]+$'
       and (a ->> 'timestamp')::bigint >= extract(epoch from now())::bigint - window_seconds
  );
$$;
revoke all on function public.signed_in_by_code_recently(int) from public;
grant execute on function public.signed_in_by_code_recently(int) to authenticated;

-- Clear the diary: everything live is put away; the person starts fresh.
create or replace function public.archive_my_diary()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '28000'; end if;
  if not public.signed_in_by_code_recently() then
    raise exception 'confirm with the code we email you, then try again' using errcode = '42501';
  end if;
  update public.entries set archived_at = now() where user_id = auth.uid() and archived_at is null;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.archive_my_diary() from public;
grant execute on function public.archive_my_diary() to authenticated;

-- How much of your past is kept, for the Settings line ("312 earlier entries kept").
create or replace function public.my_archive()
returns table (entries bigint, since date, last_put_away timestamptz)
language sql stable security definer set search_path = public as $$
  select count(*), min(date)::date, max(archived_at)
    from public.entries where user_id = auth.uid() and archived_at is not null;
$$;
revoke all on function public.my_archive() from public;
grant execute on function public.my_archive() to authenticated;
