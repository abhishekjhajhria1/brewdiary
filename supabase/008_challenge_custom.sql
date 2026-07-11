-- ============================================================================
-- brewdiary — 008: CUSTOM-NAMED CHALLENGES + FREE-FORM COMPETITIONS.
-- Runs on top of 005_challenges.sql. Two upgrades to the circle challenges:
--   (a) any auto-scored challenge can carry its own TITLE and any length;
--   (b) a new FREE-FORM competition (kind='freeform') — a written RULE, judged
--       by the creator, who declares a WINNER (no auto-scoring / no counts).
-- Everything stays opt-in and inside circles; the Calendar never shows a score.
-- Idempotent-ish (additive columns + constraint swap).
-- ============================================================================

alter table public.challenges add column if not exists title text;
alter table public.challenges add column if not exists rule  text;
alter table public.challenges add column if not exists winner_id uuid
  references public.profiles(id) on delete set null;

-- allow the free-form kind alongside the three auto-scored ones
alter table public.challenges drop constraint if exists challenges_kind_check;
alter table public.challenges add constraint challenges_kind_check
  check (kind in ('most_logged', 'most_kinds', 'longest_streak', 'freeform'));

-- The creator declares (or clears) the winner of a free-form competition.
-- definer: verifies the caller created it, and that the winner actually joined.
create or replace function public.set_challenge_winner(cid uuid, winner uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.challenges c where c.id = cid and c.created_by = auth.uid()) then
    raise exception 'not the creator';
  end if;
  if winner is not null and not exists (
    select 1 from public.challenge_members m where m.challenge_id = cid and m.user_id = winner
  ) then
    raise exception 'winner must be a participant';
  end if;
  update public.challenges set winner_id = winner where id = cid;
end; $$;
revoke all on function public.set_challenge_winner(uuid, uuid) from public;
grant execute on function public.set_challenge_winner(uuid, uuid) to authenticated;
