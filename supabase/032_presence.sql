-- ============================================================================
-- brewdiary — "Presence": the free, self-built trust signal (no paid KYC yet).
--
-- A person can pass a quick LIVE-CAMERA check (blink / smile on cue, all inference
-- on-device via MediaPipe — no frame ever leaves the browser). Passing sets a flag
-- that feeds the trust level (see src/lib/verify.ts).
--
-- ── WHAT THIS IS, AND IS NOT ────────────────────────────────────────────────
-- This is an ANTI-BOT / anti-throwaway signal, NOT identity verification. A live
-- blink challenge raises the cost of mass fake accounts; it does NOT prove who
-- someone is and does NOT stop a determined video-replay or deepfake — that needs a
-- paid vendor, which is stubbed as a void until funding (verify.ts). So the flag is
-- honestly a "trusted member" cue, never "verified identity", and it is deliberately
-- SELF-SETTABLE: the check runs client-side, so there's nothing to enforce server-
-- side beyond recording that it happened. We don't pretend otherwise.
--
-- (When funded, a real vendor sets profiles.verified — a SEPARATE, stronger column
-- already present. presence_checked never implies verified.)
--
-- Runs on top of schema.sql + 002..031.
-- ============================================================================

alter table public.profiles
  add column if not exists presence_checked    boolean not null default false,
  add column if not exists presence_checked_at timestamptz;

comment on column public.profiles.presence_checked is
  'Passed an on-device live-camera check. Anti-bot trust signal, NOT identity '
  'verification (that is profiles.verified, vendor-set). Client-side, so self-settable.';
