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
  /** A venue can offer several TIERS now — each is its own row, its own card, and
   *  its own claim clock. Reaching the big one doesn't consume the small one. */
  id: string;
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

/** on-trade (drink here) vs off-trade (carry out). */
export type VenueKind = "bar" | "store";

// An OFF-LICENCE is not a quieter bar, and its perk isn't a milder version of a
// bar's — it's a different legal object. At a bar you can turn up and buy nothing,
// so a visits card rewards presence. In a bottle shop the visit IS the purchase and
// the purchase is alcohol, so the same card is an alcohol loyalty scheme wearing a
// hat. Hence three cuts, and the last two are OURS, tighter than any statute:
//
//   1. a store needs its own jurisdiction permission (allowOfftradePerks),
//   2. a store perk counts VISITS, never spend — spend there is just the alcohol,
//   3. a store reward is NEVER alcohol, anywhere, not even in India where it would
//      be lawful. A bar's alcoholic prize is one poured drink; a bottle shop's is a
//      BOTTLE. "Buy nine, get the tenth free" is the exact loop we refuse to build.
//
// The DATABASE enforces all three (030's venue_perks_guard). This mirror exists so
// the dashboard can explain the rule instead of just failing.
export function perkPolicy(country?: string | null, region?: string | null, kind: VenueKind = "bar"): PerkPolicy {
  const j = jurisdiction(country, region);
  if (kind === "store") {
    return {
      allowPerks: j.allowPerks && j.allowOfftradePerks,
      allowAlcoholReward: false,
      allowSpendPerk: false,
    };
  }
  return { allowPerks: j.allowPerks, allowAlcoholReward: j.allowAlcoholReward, allowSpendPerk: j.allowSpendPerk };
}

/** Plain-English reason a perk is limited here — shown to the venue, never hidden.
 *  A licensee has to understand the rule, not just bump into a disabled button. */
export function perkPolicyNote(
  country?: string | null,
  region?: string | null,
  kind: VenueKind = "bar",
): string | null {
  const j = jurisdiction(country, region);
  if (kind === "store" && j.allowPerks && !j.allowOfftradePerks) {
    return (
      "A loyalty card isn't permitted for an off-licence here — at a shop, a visit is a purchase, " +
      "so the card would count as an alcohol loyalty scheme. Bars nearby can still run one."
    );
  }
  return j.note ?? null;
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
    id: (row.id as string) ?? (row.perk_id as string),
    kind: (row.kind as PerkKind) ?? "visits",
    threshold: Number(row.threshold), // numeric comes back as a string from PostgREST
    reward: row.reward as string,
    rewardAlcoholic: Boolean(row.reward_alcoholic),
    currency: (row.currency as string) || DEFAULT_CURRENCY,
  };
}

// ── the venue's perks (for the dashboard editor) — a LIST now ───────────────
export function useVenuePerks(venueId: string | null): { perks: VenuePerk[]; loading: boolean } {
  const v = useVersion();
  const [perks, setPerks] = useState<VenuePerk[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setPerks([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("venue_perks")
        .select("id, kind, threshold, reward, reward_alcoholic, currency")
        .eq("venue_id", venueId)
        .order("threshold");
      if (!active) return;
      setPerks(((data as Record<string, unknown>[]) ?? []).map((r) => toPerk(r)!).filter(Boolean));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { perks, loading };
}

// ── a guest's standing on every TIER at a venue ──────────────────────────────
// perk_status() is the ONE source of truth, and it counts progress SINCE THE LAST
// CLAIM OF THAT TIER. That's the rule that stops a perk being claimed forever off
// a single earn. `earned` is decided by the server; the client never gets to say
// "they earned it" (redeem_perk re-derives it anyway).
export interface PerkTier extends VenuePerk {
  /** Visits, or money spent — matching the tier's kind. Since your last claim of it. */
  progress: number;
  earned: boolean;
  /** How many times this guest has claimed THIS tier. */
  claims: number;
}

export function usePerkTiers(
  venueId: string | null,
  userId?: string | null,
): { tiers: PerkTier[]; loading: boolean } {
  const v = useVersion();
  const [state, setState] = useState<{ tiers: PerkTier[]; loading: boolean }>({ tiers: [], loading: true });

  useEffect(() => {
    if (!supabase || !venueId || !userId) {
      setState({ tiers: [], loading: false });
      return;
    }
    let active = true;
    setState((s) => ({ ...s, loading: true }));
    (async () => {
      const { data } = await supabase!.rpc("perk_status", { vid: venueId, uid: userId });
      if (!active) return;
      const tiers: PerkTier[] = ((data as Record<string, unknown>[]) ?? []).map((r) => ({
        id: r.perk_id as string,
        kind: (r.kind as PerkKind) ?? "visits",
        threshold: Number(r.threshold),
        reward: r.reward as string,
        currency: (r.currency as string) || DEFAULT_CURRENCY,
        rewardAlcoholic: false, // the venue owns this; a guest doesn't need it to see progress
        progress: Number(r.progress ?? 0),
        earned: Boolean(r.earned),
        claims: Number(r.claims ?? 0),
      }));
      setState({ tiers, loading: false });
    })();
    return () => {
      active = false;
    };
  }, [venueId, userId, v]);

  return state;
}

/** The weekdays this venue calls quiet (0 = Sun … 6 = Sat). A visit on one counts
 *  double toward the perk — so the guest needs to be TOLD, or it can't change what
 *  they do. Readable straight off `venues` (a verified venue is world-readable to
 *  signed-in users). */
export function useQuietNights(venueId: string | null): number[] {
  const [nights, setNights] = useState<number[]>([]);
  useEffect(() => {
    if (!supabase || !venueId) {
      setNights([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("venues").select("quiet_nights").eq("id", venueId).maybeSingle();
      if (active) setNights((data?.quiet_nights as number[]) ?? []);
    })();
    return () => {
      active = false;
    };
  }, [venueId]);
  return nights;
}

/** Punch a guest's card at a STORE. A bar records visits implicitly (you joined the
 *  room); a shop has no room, so staff have to do it — which means, exactly like
 *  spend, a guest can NEVER record their own. The server clamps it to ONE PER DAY:
 *  a shop can't punch your card ten times because you bought ten bottles, or the
 *  visits card quietly becomes a volume card. */
export async function recordVisit(venueId: string, userId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("record_visit", { vid: venueId, uid: userId });
  bump();
  if (!error) return null;
  if (/own card/i.test(error.message)) return "You can't punch your own card.";
  if (/verified/i.test(error.message)) return "Only a verified venue can record a visit.";
  if (/staff/i.test(error.message)) return "Only this shop's staff can record a visit.";
  return "Couldn't record that — try again.";
}

/** A bartender hands the perk over. The SERVER re-checks that it's actually been
 *  earned and records the claim — so it can only ever be given once per earn, and
 *  two bartenders can't both honour the same one. */
export async function redeemPerk(perkId: string, userId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("redeem_perk", { pk: perkId, uid: userId });
  bump();
  if (!error) return null;
  if (/not earned/i.test(error.message)) return "Not earned yet.";
  if (/verified/i.test(error.message)) return "Only a verified venue can hand out a perk.";
  return "Couldn't record that — try again.";
}

// ── mutations (venue managers of a VERIFIED venue; the DB enforces both) ─────

/** How many tiers a venue may run. Three is plenty: the research is blunt that
 *  confusing or unattractive rewards are the main reason people abandon a loyalty
 *  programme, and a bartender has to be able to explain it while pouring. */
export const MAX_TIERS = 3;

/** Add a tier. A venue can run up to MAX_TIERS of them, each its own punch-card. */
export async function addVenuePerk(
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

  const { error } = await supabase.from("venue_perks").insert({
    venue_id: venueId,
    kind,
    threshold,
    reward: r,
    reward_alcoholic: rewardAlcoholic,
    updated_at: new Date().toISOString(),
  });
  bump();
  if (!error) return null;
  if (/duplicate|unique/i.test(error.message)) return "You already offer that reward at that target.";
  // The DB is the authority on what's lawful where — surface its reason verbatim
  // rather than a generic failure, because the venue needs to know WHY.
  if (/not permitted|cannot be a loyalty reward/i.test(error.message)) return error.message;
  return /row-level security|violates/i.test(error.message) ? "Only a verified venue can offer perks." : error.message;
}

/** Remove one tier. Claims already made against it are KEPT (perk_id goes null) —
 *  a record of what a guest was actually given must survive the offer changing. */
export async function removeVenuePerk(perkId: string) {
  if (!supabase) return;
  await supabase.from("venue_perks").delete().eq("id", perkId);
  bump();
}
