-- ============================================================================
-- brewdiary — "Venue rooms" (Phase 7 bridge): a venue OPENS a room, where a
-- room IS a party (host, invite code, members, the sparks/vibe board). This
-- just LINKS the two — parties gain an optional venue_id.
--
-- Deliberately ADDITIVE — it does NOT modify any existing parties policy:
--  * a nullable venue_id column (individual parties stay venue_id = null);
--  * a guard trigger so you can only tag a room to a venue you staff (same
--    shape as venues' admin-field guard; service role bypasses);
--  * ONE NEW select policy, ORed with the existing parties_read, so a venue's
--    staff can see their venue's rooms.
-- Runs on top of schema.sql + 002..010. Idempotent-ish.
-- ============================================================================

drop policy   if exists parties_venue_staff_read on public.parties;
drop function if exists public.parties_guard_venue() cascade;

alter table public.parties add column if not exists venue_id uuid references public.venues(id) on delete set null;
create index if not exists parties_venue_idx on public.parties (venue_id);

-- You may only link a room to a venue you're staff of. Guard only fires when
-- venue_id is actually being SET or CHANGED (so a host editing an existing room's
-- name/date isn't blocked even if their staff role later changed); venue_id null
-- (an ordinary party) is untouched; the service role (auth.uid() null) bypasses.
create or replace function public.parties_guard_venue()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.venue_id is not null
     and (tg_op = 'INSERT' or new.venue_id is distinct from old.venue_id)
     and auth.uid() is not null
     and not public.is_venue_staff(new.venue_id, auth.uid()) then
    raise exception 'only this venue''s staff can open a room for it';
  end if;
  return new;
end; $$;
create trigger parties_check_venue before insert or update on public.parties
  for each row execute function public.parties_guard_venue();

-- Additive read: a venue's staff can see that venue's rooms (ORed with the
-- existing host/member parties_read — nothing existing changes).
create policy parties_venue_staff_read on public.parties for select to authenticated
  using (venue_id is not null and public.is_venue_staff(venue_id, auth.uid()));
