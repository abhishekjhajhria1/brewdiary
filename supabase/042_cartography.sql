-- ============================================================================
-- brewdiary — the CARTOGRAPHER: letting drinkers chart the shared dictionary.
--
-- See internal/phase-b-cartographer.md. Every "off-map" drink in someone's Taste
-- Passport is a gap in drinks.ts: real enough that they drank it, unknown to the
-- app. This lets them propose it, and once a moderator accepts it, EVERYONE's
-- passport can light that family. It is the app's first genuine commons.
--
-- ── WHY THIS IS SHAPED THE WAY IT IS ────────────────────────────────────────
-- A proposal is user-authored text destined for a surface every other user sees.
-- That makes it a publication, and publications here are DENY-BY-DEFAULT: an
-- unreviewed proposal is visible to its author and to moderators, and to nobody
-- else, ever. The dictionary only grows by a deliberate act.
--
-- ── A GUEST CAN NEVER WRITE THEIR OWN REWARD ────────────────────────────────
-- Same rule as spend_events / perk_redemptions / user_sanctions, for the same
-- reason. `status` is FORCED to 'pending' by a trigger on insert, and there is NO
-- client UPDATE policy at all — the only way a row becomes 'accepted' is the
-- moderator-only definer rpc below, gated on is_moderator() re-derived server-side.
-- If a client could set its own status, charting would be a self-serve byline.
--
-- ── AND THE THING THAT IS DELIBERATELY ABSENT ───────────────────────────────
-- There is NO per-author contribution count, rank, or board anywhere in this file,
-- and none should ever be added. That absence is the feature. Visible contribution
-- status is precisely what would make it rational to log drinks you never had, and
-- a fabricated corpus is worth less than no corpus at all — it would attack the one
-- asset (honest logs) the whole data strategy rests on. The payout is one quiet line
-- of attribution, deliberately too small to be worth cheating for. If a future
-- session wants a leaderboard here, the answer is no; see §2 of the spec.
--
-- Nothing here rewards drinking more: charting is free, instant, unrelated to volume,
-- and charting a chamomile is worth exactly what charting a mezcal is worth.
--
-- Runs on top of 002..041.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. PROPOSALS
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.chart_proposals (
  -- Client-generated: a SECURITY DEFINER read policy makes PostgREST's
  -- INSERT … RETURNING fail, so the app inserts with its own id and no .select().
  id          uuid primary key,
  author      uuid not null references public.profiles(id) on delete cascade,
  raw_name    text not null check (char_length(raw_name) between 1 and 60),   -- their words, verbatim
  canonical   text not null check (char_length(canonical) between 1 and 60),  -- the tidy spelling proposed
  family      text not null check (char_length(family) between 1 and 60),     -- the family it joins, or founds
  type        text check (type in ('coffee','tea','beer','wine','cocktail','spirit','soft','other')),
  status      text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id)
);
alter table public.chart_proposals enable row level security;

-- One pending proposal per person per drink — re-sending is a no-op, not a duplicate row.
create unique index if not exists chart_proposals_author_pending_idx
  on public.chart_proposals (author, lower(canonical))
  where status = 'pending';

-- The reviewed queue, and the accepted-lookup the app reads on every passport.
create index if not exists chart_proposals_status_idx  on public.chart_proposals (status);
create index if not exists chart_proposals_family_idx  on public.chart_proposals (lower(family))
  where status = 'accepted';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. STATUS IS SERVER-FORCED — a client can never insert an accepted row.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.force_proposal_pending()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Whatever the client sent, a new proposal starts unreviewed. Review metadata is
  -- likewise not the author's to write.
  new.status      := 'pending';
  new.reviewed_at := null;
  new.reviewed_by := null;
  return new;
end;
$$;

drop trigger if exists chart_proposals_force_pending on public.chart_proposals;
create trigger chart_proposals_force_pending
  before insert on public.chart_proposals
  for each row execute function public.force_proposal_pending();

-- ────────────────────────────────────────────────────────────────────────────
-- 3. RLS — deny-by-default; unreviewed is not published.
-- ────────────────────────────────────────────────────────────────────────────

-- Read: your own proposals (any status), plus every ACCEPTED proposal (those are
-- the dictionary — they're meant to be seen). Another person's PENDING or REJECTED
-- row is readable by nobody but a moderator.
drop policy if exists chart_proposals_read on public.chart_proposals;
create policy chart_proposals_read on public.chart_proposals for select to authenticated
  using (
    author = auth.uid()
    or status = 'accepted'
    or public.is_moderator(auth.uid())
  );

-- Insert: only as yourself. The trigger above pins status regardless of what's sent.
drop policy if exists chart_proposals_insert on public.chart_proposals;
create policy chart_proposals_insert on public.chart_proposals for insert to authenticated
  with check (author = auth.uid());

-- Delete: you may WITHDRAW your own proposal while it is still unreviewed. You may not
-- delete it once it has been decided — an accepted chart is part of the shared map now,
-- and a rejected one is a moderation record.
drop policy if exists chart_proposals_withdraw on public.chart_proposals;
create policy chart_proposals_withdraw on public.chart_proposals for delete to authenticated
  using (author = auth.uid() and status = 'pending');

-- NO UPDATE POLICY. Deliberate, and load-bearing: status transitions happen only in
-- review_chart_proposal() below. db:audit asserts this policy's continued absence.

-- ────────────────────────────────────────────────────────────────────────────
-- 4. REVIEW — moderator-only, the single path by which the map grows.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.review_chart_proposal(pid uuid, decision text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  if decision not in ('accepted', 'rejected') then
    raise exception 'decision must be accepted or rejected';
  end if;

  update public.chart_proposals
     set status      = decision,
         reviewed_at = now(),
         reviewed_by = auth.uid()
   where id = pid
     and status = 'pending';   -- a decision is made once; re-deciding is not a thing
end;
$$;
revoke all on function public.review_chart_proposal(uuid, text) from public;
grant execute on function public.review_chart_proposal(uuid, text) to authenticated;

-- The moderator queue. Kept as an rpc (not a view) so the is_moderator() gate is
-- re-derived server-side on every call, exactly like the reports queue in 034.
create or replace function public.pending_chart_proposals()
returns table (id uuid, raw_name text, canonical text, family text, type text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_moderator(auth.uid()) then
    raise exception 'not a moderator';
  end if;
  return query
    select p.id, p.raw_name, p.canonical, p.family, p.type, p.created_at
      from public.chart_proposals p
     where p.status = 'pending'
     order by p.created_at;
end;
$$;
revoke all on function public.pending_chart_proposals() from public;
grant execute on function public.pending_chart_proposals() to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. THE ACCEPTED MAP — what every client reads to draw attribution.
--
-- Returns the FIRST accepted proposal per family (the honest scarcity: someone
-- really did get there first) with its author's handle. Counts-only elsewhere:
-- note there is no aggregate per author here, by design.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.charted_families()
returns table (family text, handle text, charted_at timestamptz)
language sql stable security definer set search_path = public as $$
  select distinct on (lower(p.family))
         p.family,
         pr.handle,
         p.created_at
    from public.chart_proposals p
    join public.profiles pr on pr.id = p.author
   where p.status = 'accepted'
   order by lower(p.family), p.created_at;
$$;
revoke all on function public.charted_families() from public;
grant execute on function public.charted_families() to authenticated, anon;
