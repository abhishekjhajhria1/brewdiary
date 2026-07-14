"use client";

// House perks — a venue's return incentive. Two kinds:
//   'visits' → "come 5 times, get a free pour"
//   'spend'  → "order above ₹2000, get a free drink next visit"  (the original ask)
//
// A guest's progress is DERIVED and self-only: venue_visits() counts their
// check-ins, venue_spend() sums their tab. Spend itself is NEVER self-reported —
// only a bar's staff can record it (see record_spend in points.ts / 017).
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { jurisdiction } from "./jurisdiction";
import { DEFAULT_CURRENCY } from "./money";

export type PerkKind = "visits" | "spend";

export interface VenuePerk {
  kind: PerkKind;
  /** Visits (a count) or money (an amount), depending on `kind`. */
  threshold: number;
  reward: string;
  /** ISO-4217, set by the server from the venue's country. Never assume ₹. */
  currency: string;
  /** Is the prize itself a drink? Defaults to false — the answer that's legal
   *  nearly everywhere (see perkPolicy). */
  rewardAlcoholic: boolean;
}

// ── what the law allows, by jurisdiction ─────────────────────────────────────
// A loyalty scheme whose prize is NOT alcohol is not an alcohol loyalty scheme —
// which is why this feature survives at all outside India. Full research and
// citations in internal/legal-and-compliance.md. Summary:
//   IE  — awarding loyalty points on alcohol purchases is banned outright.
//   GB  — "an alcoholic drink free or at a reduced price on the purchase of one
//          or more drinks" IS the statutory definition of an irresponsible
//          promotion; England/Wales also ban "rewards for drinking large amounts".
//          The LICENSEE is liable — a bad perk of ours could cost a bar its licence.
//   US  — MA and UT still restrict drink deals (state by state; assume nothing).
//   IN  — the perk is lawful; it's the *advertising* that's restricted, so a perk
//          must stay private between one guest and one bar. Never a public feed.
//
// This mirrors public.perk_policy() in 020_perk_policy.sql. The DATABASE is the
// authority — this copy exists so the dashboard can explain itself before a bar
// hits an error, not to be trusted on its own.
export interface PerkPolicy {
  /** May this venue run a loyalty perk at all? */
  allowPerks: boolean;
  /** May the prize be an alcoholic drink? */
  allowAlcoholReward: boolean;
  /** May progress accrue from MONEY SPENT (rather than visits)? */
  allowSpendPerk: boolean;
}

export function perkPolicy(country?: string | null, region?: string | null): PerkPolicy {
  const j = jurisdiction(country, region);
  return { allowPerks: j.allowPerks, allowAlcoholReward: j.allowAlcoholReward, allowSpendPerk: j.allowSpendPerk };
}

/** Plain-English reason a perk is limited here — shown to the venue, never hidden.
 *  A licensee has to understand the rule, not just bump into a disabled button. */
export function perkPolicyNote(country?: string | null, region?: string | null): string | null {
  return jurisdiction(country, region).note ?? null;
}

// ── shared refresh signal ────────────────────────────────────────────────────
let version = 0;
const subs = new Set<() => void>();
function bump() {
  version++;
  subs.forEach((s) => s());
}
function useVersion(): number {
  const [, set] = useState(0);
  useEffect(() => {
    const cb = () => set((n) => n + 1);
    subs.add(cb);
    return () => {
      subs.delete(cb);
    };
  }, []);
  return version;
}

function toPerk(row: Record<string, unknown> | null): VenuePerk | null {
  if (!row) return null;
  return {
    kind: (row.kind as PerkKind) ?? "visits",
    threshold: Number(row.threshold), // numeric comes back as a string from PostgREST
    reward: row.reward as string,
    rewardAlcoholic: Boolean(row.reward_alcoholic),
    currency: (row.currency as string) || DEFAULT_CURRENCY,
  };
}

// ── the venue's perk (for the dashboard editor) ──────────────────────────────
export function useVenuePerk(venueId: string | null): { perk: VenuePerk | null; loading: boolean } {
  const v = useVersion();
  const [perk, setPerk] = useState<VenuePerk | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setPerk(null);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.from("venue_perks").select("kind, threshold, reward, reward_alcoholic, currency").eq("venue_id", venueId).maybeSingle();
      if (!active) return;
      setPerk(toPerk(data as Record<string, unknown> | null));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { perk, loading };
}

// ── a guest's standing at a venue (perk + their progress → earned?) ──────────
export function usePerkProgress(venueId: string | null): {
  perk: VenuePerk | null;
  /** Visits so far, or ₹ spent so far — matching the perk's kind. */
  progress: number;
  earned: boolean;
  loading: boolean;
} {
  const v = useVersion();
  const [state, setState] = useState<{ perk: VenuePerk | null; progress: number; loading: boolean }>({
    perk: null,
    progress: 0,
    loading: true,
  });

  useEffect(() => {
    if (!supabase || !venueId) {
      setState({ perk: null, progress: 0, loading: false });
      return;
    }
    let active = true;
    setState((s) => ({ ...s, loading: true }));
    (async () => {
      const [p, visits, spend] = await Promise.all([
        supabase!.from("venue_perks").select("kind, threshold, reward, reward_alcoholic, currency").eq("venue_id", venueId).maybeSingle(),
        supabase!.rpc("venue_visits", { vid: venueId }),
        supabase!.rpc("venue_spend", { vid: venueId }),
      ]);
      if (!active) return;
      const perk = toPerk(p.data as Record<string, unknown> | null);
      const progress = !perk ? 0 : perk.kind === "spend" ? Number(spend.data ?? 0) : Number(visits.data ?? 0);
      setState({ perk, progress, loading: false });
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { ...state, earned: state.perk ? state.progress >= state.perk.threshold : false };
}

// ── mutations (venue managers of a VERIFIED venue; the DB enforces both) ─────
export async function setVenuePerk(
  venueId: string,
  kind: PerkKind,
  threshold: number,
  reward: string,
  rewardAlcoholic = false,
): Promise<string | null> {
  if (!supabase) return "offline";
  const r = reward.trim();
  if (!r) return "Describe the reward.";
  if (!Number.isFinite(threshold) || threshold <= 0) return "Set a target above zero.";
  if (kind === "visits" && threshold > 100) return "Keep visits to 100 or fewer.";

  const { error } = await supabase.from("venue_perks").upsert({
    venue_id: venueId,
    kind,
    threshold,
    reward: r,
    reward_alcoholic: rewardAlcoholic,
    updated_at: new Date().toISOString(),
  });
  bump();
  if (!error) return null;
  // The DB is the authority on what's lawful where — surface its reason verbatim
  // rather than a generic failure, because the venue needs to know WHY.
  if (/not permitted|cannot be a loyalty reward/i.test(error.message)) return error.message;
  return /row-level security|violates/i.test(error.message) ? "Only a verified venue can offer perks." : error.message;
}

export async function clearVenuePerk(venueId: string) {
  if (!supabase) return;
  await supabase.from("venue_perks").delete().eq("venue_id", venueId);
  bump();
}
