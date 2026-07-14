-- ============================================================================
-- brewdiary — "Points" (Phase 1 of Rooms/Points/Venues — the loud, opt-in,
-- Together-only layer; the Calendar never shows a score).
--
-- Two POSITIVE-ONLY currencies, earned inside a PARTY (the existing "room"):
--   spark = fun / exploration (games, variety, check-ins) — the PUBLIC currency.
--   vibe  = positive behaviour recognition — bar staff / your group GIVE it,
--           they can never dock it. Positive-only is enforced by check (value > 0):
--           there is no negative vibe anywhere in our graph (no blacklist).
--
-- A balance is NEVER stored. party_points_board() SUMS an append-only ledger and
-- returns COUNTS ONLY, party-members-only — same discipline as challenge_board().
-- Runs on top of schema.sql + 002..008. Idempotent-ish.
-- ============================================================================

drop table if exists public.point_events cascade;
drop function if exists public.party_points_board(uuid) cascade;

create table public.point_events (
  id              uuid primary key default gen_random_uuid(),
  party_id        uuid not null references public.parties(id)  on delete cascade,
  subject_user_id uuid not null references public.profiles(id) on delete cascade, -- who EARNED it
  awarder_id      uuid          references public.profiles(id) on delete set null, -- who GAVE it (null = self/auto)
  currency        text not null check (currency in ('spark', 'vibe')),
  reason          text not null,
  value           int  not null default 1 check (value > 0),   -- positive-only, always
  dedupe_day      date not null default current_date,
  created_at      timestamptz not null default now()
);
create index point_events_party_idx   on public.point_events (party_id);
create index point_events_subject_idx on public.point_events (subject_user_id);

-- Anti-farming (the hard line — ratelimit.ts is only the soft API-layer one):
-- a spark reason can be earned once per subject per party per day…
create unique index point_events_spark_dedupe
  on public.point_events (party_id, subject_user_id, reason, dedupe_day)
  where currency = 'spark';
-- …and one person can give another a given vibe once per party (no clique spam).
create unique index point_events_vibe_dedupe
  on public.point_events (party_id, awarder_id, subject_user_id, reason)
  where currency = 'vibe';

-- The board: sums the ledger per subject, COUNTS ONLY, members-only. DEFINER
-- because point_events rows a caller can't otherwise select are summed for them;
-- opting into a party consents to count visibility, never entry content.
create or replace function public.party_points_board(pid uuid)
returns table (user_id uuid, display_name text, sparks int, vibe int)
language sql stable security definer set search_path = public as $$
  select pe.subject_user_id,
         coalesce(p.display_name, 'guest'),
         coalesce(sum(pe.value) filter (where pe.currency = 'spark'), 0)::int,
         coalesce(sum(pe.value) filter (where pe.currency = 'vibe'),  0)::int
  from public.point_events pe
  join public.profiles p on p.id = pe.subject_user_id
  where pe.party_id = pid
    and public.is_party_member(pid, auth.uid())
  group by pe.subject_user_id, p.display_name;
$$;
revoke all on function public.party_points_board(uuid) from public;
grant execute on function public.party_points_board(uuid) to authenticated;

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.point_events enable row level security;

-- read: any member of the party sees its ledger.
create policy point_events_read on public.point_events for select to authenticated
  using (public.is_party_member(party_id, auth.uid()));

-- record a SPARK: you log your OWN earned sparks (a game win, a new kind tried,
-- a check-in). Auto-scored fun → subject is always self in Phase 1.
create policy point_events_insert_spark on public.point_events for insert to authenticated
  with check (
    currency = 'spark'
    and subject_user_id = auth.uid()
    and public.is_party_member(party_id, auth.uid())
  );

-- give a VIBE: you (the awarder) recognise ANOTHER member. Positive-only is the
-- column check; you can't award yourself; both of you must be in the party.
create policy point_events_insert_vibe on public.point_events for insert to authenticated
  with check (
    currency = 'vibe'
    and awarder_id = auth.uid()
    and subject_user_id <> auth.uid()
    and public.is_party_member(party_id, auth.uid())
    and public.is_party_member(party_id, subject_user_id)
  );

-- undo: delete a vibe YOU gave (awarder) or a spark you recorded (subject).
create policy point_events_delete on public.point_events for delete to authenticated
  using (awarder_id = auth.uid() or subject_user_id = auth.uid());
