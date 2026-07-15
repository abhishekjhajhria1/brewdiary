-- ============================================================================
-- brewdiary — Report de-duplication: a report is a signal, not a weapon.
--
-- ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
-- 031 gave users a one-way "report" and 034 surfaced reports to moderators with a
-- repeat-offender count. But nothing stopped ONE person from filing the same report
-- fifty times: the `reports` table had no per-reporter uniqueness, and open_reports()
-- counted count(*) — total rows — so a single actor could make an innocent person look
-- like a serial offender, biasing a human moderator and (once the planned auto-safeguards
-- ship) auto-suspending the victim. That turns a safety tool into a harassment tool.
--
-- ── THE FIX ─────────────────────────────────────────────────────────────────
-- One person counts ONCE against a given subject, no matter how many times they press
-- "report". We (a) collapse existing duplicates to the most recent, (b) add a unique
-- index on (reporter_id, subject_user_id) so the client's ON CONFLICT DO NOTHING upsert
-- makes a repeat report a silent no-op, and (c) rewrite open_reports() to count DISTINCT
-- reporters. No new write surface: reports still has ONLY an insert policy — DO NOTHING
-- needs no UPDATE policy, so a report stays a one-way message that can't be read back.
--
-- ── THE RULE FOR WHOEVER BUILDS AUTO-SAFEGUARDS NEXT ────────────────────────
-- When N-reports-auto-hides-a-plan lands, threshold on **distinct reporter_id** (this
-- migration makes that the honest number) with a **floor** (≥3 distinct reporters), and
-- the auto-action must be reversible (hide + pending), never a ban. See
-- internal/phase2-strangers-plan.md → NEXT BUILD QUEUE §2. A count(*) threshold would
-- re-open exactly the hole this migration closes.
--
-- Runs on top of schema.sql + 002..034. One implicit transaction — lands whole or not.
-- ============================================================================

-- ── 1. Collapse existing duplicates to the newest row per (reporter, subject) ──
-- Ties broken by ctid so exactly one row survives per pair. Rows with a null subject
-- (not user-reports) are left alone — they never conflict on the index below.
delete from public.reports r
using public.reports keep
where r.reporter_id = keep.reporter_id
  and r.subject_user_id = keep.subject_user_id
  and r.subject_user_id is not null
  and (keep.created_at, keep.ctid) > (r.created_at, r.ctid);

-- ── 2. One live report per (reporter, subject). The client upserts ON CONFLICT DO
--       NOTHING against this index, so a repeat report is a no-op — no inflation. ──
create unique index if not exists reports_reporter_subject_uidx
  on public.reports (reporter_id, subject_user_id);

-- ── 3. The queue counts DISTINCT reporters, not total rows. (Rewrites 034's
--       open_reports; identical otherwise.) One angry person = one on the counter. ──
create or replace function public.open_reports()
returns table (
  id uuid, reporter_name text, subject_id uuid, subject_name text, subject_handle text,
  reason text, note text, created_at timestamptz,
  subject_report_count int, subject_sanctioned boolean
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_moderator(auth.uid()) then raise exception 'moderators only'; end if;
  return query
    select r.id, rp.display_name, r.subject_user_id, sp.display_name, sp.handle,
           r.reason, r.note, r.created_at,
           (select count(distinct r2.reporter_id)::int
              from public.reports r2 where r2.subject_user_id = r.subject_user_id),
           public.is_sanctioned(r.subject_user_id)
    from public.reports r
    left join public.profiles rp on rp.id = r.reporter_id
    left join public.profiles sp on sp.id = r.subject_user_id
    order by r.created_at desc
    limit 200;
end; $$;
revoke all on function public.open_reports() from public;
grant execute on function public.open_reports() to authenticated;
