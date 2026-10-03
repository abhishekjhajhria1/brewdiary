-- ============================================================================
-- brewdiary — photos are kept for a year, at most (057).
--
-- The maintainer's rule (1 Oct 2026): we keep the data a diary needs, but not its
-- images for longer than a year. A daily job (src/app/api/cron/photo-retention,
-- run by Vercel Cron with the service key) asks the database which photo files
-- are older than 365 days, removes them from storage, then removes their rows.
-- The entry itself stays — the words of a night outlive its pictures.
--
-- And account deletion (src/app/api/account/delete) asks for EVERY file a person
-- has, however deep the folder (photos live at <user>/<entry>/<photo>), so erasure
-- doesn't miss them the way a one-level storage listing did.
--
-- Both functions are for the server's service key only.
-- ============================================================================

create or replace function public.photo_files_older_than(days int default 365, max_rows int default 500)
returns table (name text)
language sql stable security definer set search_path = public, storage as $$
  select o.name
    from storage.objects o
   where o.bucket_id = 'photos'
     and o.created_at < now() - make_interval(days => greatest(days, 30))
   order by o.created_at
   limit least(greatest(max_rows, 1), 1000);
$$;
revoke all on function public.photo_files_older_than(int, int) from public, anon, authenticated;
grant execute on function public.photo_files_older_than(int, int) to service_role;

create or replace function public.photo_files_of(uid uuid)
returns table (name text)
language sql stable security definer set search_path = public, storage as $$
  select o.name from storage.objects o
   where o.bucket_id = 'photos' and o.name like uid::text || '/%';
$$;
revoke all on function public.photo_files_of(uuid) from public, anon, authenticated;
grant execute on function public.photo_files_of(uuid) to service_role;
