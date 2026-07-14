-- ============================================================================
-- brewdiary — "Venue verification" (Phase 7): the request → approve path that
-- replaces hand-written SQL. A venue MANAGER submits a request with a contact;
-- WE approve it out-of-band with the service role (scripts/verify-venue.mjs),
-- which is the only thing that can flip venues.verified (the 010 trigger refuses
-- any change to `verified` from a signed-in session).
--
-- A venue can therefore NEVER self-verify: there is no UPDATE policy here for
-- `authenticated`, so status can only be changed by the service role (which
-- bypasses RLS). They may withdraw a pending/rejected request and resubmit.
-- Runs on top of schema.sql + 002..014. Idempotent-ish.
-- ============================================================================

drop table if exists public.venue_verifications cascade;

create table public.venue_verifications (
  venue_id     uuid primary key references public.venues(id) on delete cascade, -- one open request per venue
  requested_by uuid not null references public.profiles(id) on delete cascade,
  contact      text not null check (char_length(trim(contact)) between 3 and 200), -- how we reach the venue
  note         text check (note is null or char_length(note) <= 500),
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz
);

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.venue_verifications enable row level security;

-- the team can see their venue's request…
create policy venue_verifications_read on public.venue_verifications for select to authenticated
  using (public.is_venue_staff(venue_id, auth.uid()));

-- …a manager may submit one, and only ever as 'pending' (never pre-approved)…
create policy venue_verifications_insert on public.venue_verifications for insert to authenticated
  with check (
    public.is_venue_manager(venue_id, auth.uid())
    and requested_by = auth.uid()
    and status = 'pending'
  );

-- …and may withdraw a pending (or rejected) request to resubmit. Deliberately NO
-- update policy: a venue can never move its own request to 'approved'.
create policy venue_verifications_delete on public.venue_verifications for delete to authenticated
  using (
    public.is_venue_manager(venue_id, auth.uid())
    and status in ('pending', 'rejected')
  );
