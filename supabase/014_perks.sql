-- ============================================================================
-- brewdiary — "House perks" (Phase 7): a venue's return-incentive. The venue
-- offers ONE reward at a visit threshold ("5 visits → a free pour"); a guest's
-- "visits" = distinct rooms at that venue they checked into. Progress is DERIVED
-- (venue_visits counts check-in sparks), never stored.
--
-- Locked rule enforced here: only a VERIFIED venue may offer a real-world perk
-- (unverified venues can still run Sparks-only rooms). A guest can only read
-- their OWN visit count (venue_visits uses auth.uid(), takes no user arg).
-- Runs on top of schema.sql + 002..013. Idempotent-ish.
-- ============================================================================

drop function if exists public.venue_visits(uuid) cascade;
drop table    if exists public.venue_perks cascade;

create table public.venue_perks (
  venue_id   uuid primary key references public.venues(id) on delete cascade, -- one active perk per venue
  threshold  int  not null check (threshold between 1 and 100),
  reward     text not null check (char_length(trim(reward)) between 1 and 120),
  updated_at timestamptz not null default now()
);

-- The caller's distinct check-in count at a venue (a "visit" = a room there you
-- checked into). DEFINER + auth.uid() so you can only ever see your OWN count.
create or replace function public.venue_visits(vid uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(distinct pe.party_id)::int
  from public.point_events pe
  join public.parties party on party.id = pe.party_id
  where party.venue_id = vid
    and pe.subject_user_id = auth.uid()
    and pe.currency = 'spark'
    and pe.reason = 'checkin';
$$;
revoke all on function public.venue_visits(uuid) from public;
grant execute on function public.venue_visits(uuid) to authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.venue_perks enable row level security;

-- read: any signed-in user (a perk is a public promo). write: a venue MANAGER,
-- and only while the venue is VERIFIED. delete: a manager (can pull it anytime).
create policy venue_perks_read on public.venue_perks for select to authenticated
  using (true);
create policy venue_perks_insert on public.venue_perks for insert to authenticated
  with check (
    public.is_venue_manager(venue_id, auth.uid())
    and exists (select 1 from public.venues v where v.id = venue_id and v.verified)
  );
create policy venue_perks_update on public.venue_perks for update to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()))
  with check (
    public.is_venue_manager(venue_id, auth.uid())
    and exists (select 1 from public.venues v where v.id = venue_id and v.verified)
  );
create policy venue_perks_delete on public.venue_perks for delete to authenticated
  using (public.is_venue_manager(venue_id, auth.uid()));
