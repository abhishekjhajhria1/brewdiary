// The Palate Score — one lifetime number for a diary, and the level/title that comes with it.
//
// Built ONLY from breadth and consistency, never volume. Research-grounded: points systems
// earn trust when they reward *meaningful, quality* engagement and stay focused on a couple of
// clear signals (arounda.agency & improveworkspace gamification write-ups, 2025) — so this
// counts four things and no more:
//   • kinds        — distinct drinks you've met (BREADTH)
//   • activeDays    — distinct days you showed up to the diary, a DRY DAY included (CONSISTENCY)
//   • longestStreak — your best run (CONSISTENCY)
//   • monthsActive  — how many months you've kept it (LONGEVITY)
//
// None of these move when you log the SAME drink again, or a second drink tonight — logging
// more never raises the number. That is rule #6 ("nothing rewards drinking more") made
// structural, the same way the streak counts days-shown-up rather than drinks-drunk.
import type { Entry } from "./types";
import { loggedDates, stats } from "./derive";

export interface ScoreInput {
  /** Distinct drinks — breadth. */
  kinds: number;
  /** Distinct days logged (dry days included) — consistency. */
  activeDays: number;
  /** Longest run of logged days — consistency. */
  longestStreak: number;
  /** Distinct calendar months with a log — longevity. */
  monthsActive: number;
}

export interface PaletteScore {
  score: number;
  /** 1-based rung on the ladder. */
  level: number;
  title: string;
  nextTitle: string | null;
  /** 0..1 progress toward the next title (1 at the top of the ladder). */
  intoLevel: number;
  /** Points remaining to the next title (0 at the top). */
  toNext: number;
}

// The title ladder — an exploration arc, in the app's plain voice (no "pro/elite" ladder-speak).
const LADDER: { at: number; title: string }[] = [
  { at: 0, title: "Newcomer" },
  { at: 40, title: "Curious" },
  { at: 90, title: "Wanderer" },
  { at: 160, title: "Explorer" },
  { at: 260, title: "Voyager" },
  { at: 400, title: "Pathfinder" },
  { at: 600, title: "Cartographer" },
  { at: 850, title: "Master Cartographer" },
];

const WEIGHT = { kinds: 14, activeDay: 3, streak: 6, month: 10 } as const;
// Cap the consistency terms so a very old diary can't run the number away from breadth — the
// point is a wide, well-paced palate, not sheer longevity.
const ACTIVE_DAYS_CAP = 400;
const MONTHS_CAP = 60;

export function computeScore(input: ScoreInput): number {
  const kinds = Math.max(0, input.kinds);
  const activeDays = Math.min(Math.max(0, input.activeDays), ACTIVE_DAYS_CAP);
  const longest = Math.max(0, input.longestStreak);
  const months = Math.min(Math.max(0, input.monthsActive), MONTHS_CAP);
  return Math.round(kinds * WEIGHT.kinds + activeDays * WEIGHT.activeDay + longest * WEIGHT.streak + months * WEIGHT.month);
}

export function paletteScore(input: ScoreInput): PaletteScore {
  const score = computeScore(input);
  let idx = 0;
  for (let i = 0; i < LADDER.length; i++) if (score >= LADDER[i].at) idx = i;
  const cur = LADDER[idx];
  const next = LADDER[idx + 1] ?? null;
  const intoLevel = next ? (score - cur.at) / (next.at - cur.at) : 1;
  return {
    score,
    level: idx + 1,
    title: cur.title,
    nextTitle: next?.title ?? null,
    intoLevel: Math.min(1, Math.max(0, intoLevel)),
    toNext: next ? Math.max(0, next.at - score) : 0,
  };
}

/** Derive the four inputs from a full local diary. */
export function scoreInput(entries: Entry[]): ScoreInput {
  const s = stats(entries);
  const logged = loggedDates(entries); // every day you logged anything (dry included)
  const months = new Set<string>();
  for (const k of logged.keys()) months.add(k.slice(0, 7));
  return { kinds: s.kinds, activeDays: logged.size, longestStreak: s.longest, monthsActive: months.size };
}

/** The whole thing, straight from entries — for the owner's own views. */
export function scoreFromEntries(entries: Entry[]): PaletteScore {
  return paletteScore(scoreInput(entries));
}
