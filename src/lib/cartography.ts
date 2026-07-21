// The Cartographer — charting your off-map drinks into the SHARED dictionary.
//
// See internal/phase-b-cartographer.md. Every off-map stamp in your Passport is a gap in
// drinks.ts: a drink real enough that you drank it, but one the app doesn't know. Charting
// lets you propose it, and once a moderator accepts it, EVERYONE's Passport can light that
// family. Your logging stops improving only your map and starts improving the map.
//
// Two rules govern this file, and both are load-bearing:
//
//  1. Charting is entirely disconnected from consumption. It is free, instant, and charting
//     a chamomile is worth exactly what charting a mezcal is worth: one quiet line of
//     attribution. No spark, no perk, no discount — the same intrinsic-only posture as the
//     Passport, for the same reason (CLAUDE.md rule #6).
//  2. There is NO cartographer count, rank, board or badge — anywhere, for anyone, including
//     yourself. That is not an oversight to be tidied up later: visible contribution status is
//     what would make it rational to log drinks you never had, and a fabricated corpus is worth
//     less than no corpus. The payout is deliberately too small to be worth cheating for.
//
// This module is PURE — no hooks, no network, no DB. The store seam passes everything in.
import type { DrinkType } from "./types";
import { DRINKS, canonicalize, normalize, similarity } from "./drinks";
import type { Stamp } from "./passport";

/** A proposal to add a drink to the shared dictionary. Mirrors the chart_proposals row. */
export interface ChartProposal {
  id: string;
  author: string;
  /** Exactly what they typed in their diary — their words, kept verbatim. */
  rawName: string;
  /** The tidy spelling they propose the dictionary should carry. */
  canonical: string;
  /** The family it joins, or founds. */
  family: string;
  type: DrinkType;
  status: "pending" | "accepted" | "rejected";
  createdAt: string;
}

/** Why a proposal can't be sent. Every reason is recoverable and costs the author nothing. */
export type ChartRejection =
  | { ok: false; reason: "empty"; message: string }
  | { ok: false; reason: "too-long"; message: string }
  | { ok: false; reason: "already-known"; message: string; existing: string }
  | { ok: false; reason: "already-proposed"; message: string };

export type ChartCheck = { ok: true } | ChartRejection;

/** A name longer than this isn't a drink name, it's a note. Keeps the dictionary tidy. */
const MAX_NAME = 60;

/**
 * Would this proposal duplicate something the dictionary already knows? Deliberately FUZZY:
 * an exact-match check alone would let "esspresso" found a rival Espresso family and quietly
 * fork the map. Reuses the same similarity threshold canonicalize() uses, so anything the
 * autocomplete would already have folded is caught here too.
 */
export function existingMatch(name: string): string | null {
  const c = canonicalize(name);
  // canonicalize() already applies the fuzzy threshold — a match means the dictionary has it.
  return c.matched ? c.canonical : null;
}

/**
 * Can this drink be charted, and is the proposal sane? Runs before anything is sent, so the
 * person gets a plain answer instead of a silent failure.
 *
 * `pending` is the author's own outstanding proposals — proposing the same thing twice is a
 * no-op, not an error worth punishing.
 */
export function checkProposal(
  canonicalName: string,
  pending: ChartProposal[] = [],
): ChartCheck {
  const name = canonicalName.trim();
  if (!name) {
    return { ok: false, reason: "empty", message: "Give it a name first." };
  }
  if (name.length > MAX_NAME) {
    return { ok: false, reason: "too-long", message: `Keep it under ${MAX_NAME} characters.` };
  }

  const existing = existingMatch(name);
  if (existing) {
    return {
      ok: false,
      reason: "already-known",
      message: `The map already has this — it's filed as ${existing}.`,
      existing,
    };
  }

  const norm = normalize(name);
  if (pending.some((p) => p.status === "pending" && normalize(p.canonical) === norm)) {
    return { ok: false, reason: "already-proposed", message: "You've already sent this one in." };
  }

  return { ok: true };
}

/**
 * Which of your off-map stamps are worth charting. An off-map stamp is BY DEFINITION unknown
 * to the dictionary, so this is mostly a pass-through — but it drops anything you've already
 * proposed (no nagging you to do what you've done) and anything the dictionary has since
 * learned (someone else charted it first; that's the honest scarcity, and it costs you nothing).
 */
export function chartable(offMap: Stamp[], mine: ChartProposal[] = []): Stamp[] {
  const proposed = new Set(
    mine.filter((p) => p.status !== "rejected").map((p) => normalize(p.rawName)),
  );
  return offMap.filter((s) => !proposed.has(normalize(s.family)) && !existingMatch(s.family));
}

/** A family a drinker drew, and the handle to credit. Mirrors the charted_families() row. */
export interface Charted {
  family: string;
  handle: string;
}

/**
 * The one-line attribution a charted family carries: who drew it. This is the entire reward.
 * Returns null for the overwhelming majority of families — the dictionary's original entries
 * have no author, and saying "charted by brewdiary" everywhere would cheapen the real ones.
 *
 * Which proposal wins when two people charted the same thing is settled in SQL, not here:
 * charted_families() returns `distinct on (lower(family)) … order by created_at`, so the
 * first charter wins and the client is handed one row per family. That keeps the honest
 * scarcity in one place instead of two that can disagree.
 */
export function chartedBy(family: string, charted: Charted[]): string | null {
  const norm = normalize(family);
  return charted.find((c) => normalize(c.family) === norm)?.handle ?? null;
}

/**
 * The commons line: how big the shared map is, and how much of it drinkers drew. Collective
 * progress (CD1) with nothing individual in it — a count of FAMILIES, never of people, so
 * there is nothing here to rank anyone by.
 */
export function commons(charted: Charted[]): { families: number; charted: number } {
  const dictionary = new Set(DRINKS.map((d) => normalize(d.family)));
  // A charted family that has since been folded into the dictionary proper isn't counted twice.
  const drawn = new Set(
    charted.map((c) => normalize(c.family)).filter((f) => !dictionary.has(f)),
  );
  return { families: dictionary.size + drawn.size, charted: drawn.size };
}

/**
 * Suggest which existing family a novel drink might join, so charting is a small choice rather
 * than a blank form. Returns the nearest families by name similarity — never auto-files it,
 * because "your words stay your words" and founding a new family is a legitimate answer.
 */
export function suggestFamilies(name: string, n = 3): string[] {
  const norm = normalize(name);
  if (!norm) return [];
  const seen = new Set<string>();
  const scored: { family: string; score: number }[] = [];
  for (const d of DRINKS) {
    if (seen.has(d.family)) continue;
    seen.add(d.family);
    scored.push({ family: d.family, score: similarity(norm, normalize(d.family)) });
  }
  return scored
    .sort((a, b) => b.score - a.score || a.family.localeCompare(b.family))
    .slice(0, n)
    .map((s) => s.family);
}
