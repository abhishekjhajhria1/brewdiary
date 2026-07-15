"use client";

// Verification & trust — the free, build-it-ourselves approach, with a clean void
// where a paid identity vendor will plug in once there's funding.
//
// ── TWO SEPARATE THINGS, DON'T CONFLATE THEM ─────────────────────────────────
//
// 1. IDENTITY VERIFICATION (paid, later): a vendor proving "this is a real, unique
//    human of age X" via government ID + anti-spoof liveness. We CAN'T afford this
//    yet, so `beginIdentityVerification` is a VOID — it returns "unavailable" and is
//    the single seam a provider (Persona / Signzy / HyperVerge) slots into on funding.
//    Its output is `profiles.verified` (already a column). Nothing else changes.
//
// 2. TRUST LEVEL (free, now): a coarse, anti-FRAUD signal built from things we already
//    have — how long you've been here, how much you actually use the diary, and how
//    many real friends vouch for your existence. It answers "is this a real, settled
//    human or a throwaway account", NOT "is this a good person". It is deliberately:
//      • coarse (four bands, not a number),
//      • about the person themselves (a badge they can raise), never a public ranking
//        of people against each other — that stayed dead in Phase 1,
//      • anti-bot, not anti-deepfake. It raises the cost of fake accounts; it is NOT
//        identity proof, and we will never claim it is.
//
// Liveness (a live camera check) and vouches are ADDITIVE signals that fold into the
// same score — see TrustSignals. They're wired in as they land.

import { useMemo } from "react";
import { useAuth, markPresenceChecked } from "./profile";
import { useEntries } from "./store";
import { useFriends } from "./friends";
import { useMyVouchCount } from "./vouch";

// ── 1. the paid-vendor VOID ──────────────────────────────────────────────────
export type IdentityResult =
  | { status: "unavailable"; reason: string }
  | { status: "started"; url: string }
  | { status: "verified" };

/**
 * Begin government-ID + liveness verification. TODO(funding): implement against a
 * vendor. In India use a DigiLocker/Aadhaar-*offline* provider (Signzy / HyperVerge /
 * IDfy) and store ONLY a boolean + an age band — never the Aadhaar number or the
 * document (Aadhaar Act + DPDP). The seam: read a `VERIFY_PROVIDER` env, hand off,
 * and on the provider's webhook set `profiles.verified = true`. Until then, void.
 */
export async function beginIdentityVerification(): Promise<IdentityResult> {
  return {
    status: "unavailable",
    reason: "Photo-ID verification isn't switched on yet. For now, your trust level grows as you use brewdiary and friends vouch for you.",
  };
}

/** Is paid identity verification configured on this deployment? (Always false until
 *  funded — the UI uses this to show "coming soon" instead of a dead button.) */
export const identityVerificationAvailable = false;

// ── 2. the free TRUST LEVEL ──────────────────────────────────────────────────
export type TrustLevel = "new" | "active" | "established" | "trusted";

export interface TrustSignals {
  /** Days since the account was created. */
  tenureDays: number;
  /** Distinct days the person has logged a drink — real use, not sign-up-and-vanish. */
  activeDays: number;
  /** Accepted friends — other real accounts that connected to this one. */
  friends: number;
  /** Passed a live-camera presence check (additive; anti-bot, NOT identity). Later. */
  presenceChecked?: boolean;
  /** Friends who explicitly vouched for this person (additive). Later. */
  vouches?: number;
}

// Weights are intentionally boring and explainable — no magic. Each signal is capped
// so no single one can carry an account to "trusted", and the whole thing is additive
// so liveness + vouches raise a genuinely-new account without gaming tenure.
export function trustScore(s: TrustSignals): number {
  const tenure = Math.min(s.tenureDays, 90) / 9; // 0..10 over ~3 months
  const active = Math.min(s.activeDays, 30) / 3; // 0..10 over 30 logged days
  const social = Math.min(s.friends, 8) * 1.25; // 0..10
  const presence = s.presenceChecked ? 8 : 0; // a live check is worth a lot vs a bot
  const vouched = Math.min(s.vouches ?? 0, 5) * 3; // 0..15, a real person's word
  return tenure + active + social + presence + vouched;
}

/** Map the score to a coarse band. Thresholds chosen so a brand-new account is 'new',
 *  a week of real use is 'active', a settled month with friends is 'established', and
 *  'trusted' needs sustained use PLUS a strong signal (liveness or vouches) — the
 *  free signals alone top out at 'established' (max 30 < 34). */
export function trustLevelFrom(s: TrustSignals): TrustLevel {
  const score = trustScore(s);
  if (score >= 34) return "trusted";
  if (score >= 14) return "established";
  if (score >= 4) return "active";
  return "new";
}

export const TRUST_LABEL: Record<TrustLevel, string> = {
  new: "New here",
  active: "Active",
  established: "Established",
  trusted: "Trusted",
};

/**
 * Record that the person passed the on-device live-camera check. The check runs
 * entirely client-side (no frame ever leaves the browser), so there is nothing to
 * enforce server-side — this persists the flag on their own profile and refreshes the
 * store so the trust badge updates at once. A soft anti-bot signal, never identity proof.
 */
export async function recordPresence(): Promise<boolean> {
  return markPresenceChecked();
}

/** My own trust level, derived from data I already have on the client. (Someone
 *  ELSE's trust can't be computed here — RLS hides their entries/friends — so that
 *  path is a definer function, folded into plan_signals when liveness/vouches land.) */
export function useMyTrust(): { level: TrustLevel; signals: TrustSignals } {
  const profile = useAuth().profile;
  const entries = useEntries();
  const { friends } = useFriends();
  const vouches = useMyVouchCount();

  return useMemo(() => {
    const created = profile?.createdAt ? new Date(profile.createdAt) : new Date();
    const tenureDays = Math.max(0, Math.floor((Date.now() - created.getTime()) / 86_400_000));
    const activeDays = new Set(entries.map((e) => e.date)).size;
    const signals: TrustSignals = {
      tenureDays,
      activeDays,
      friends: friends.length,
      presenceChecked: profile?.presenceChecked,
      vouches,
    };
    return { level: trustLevelFrom(signals), signals };
  }, [profile?.createdAt, profile?.presenceChecked, entries, friends.length, vouches]);
}
