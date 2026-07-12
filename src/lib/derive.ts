// Everything visual is DERIVED from entries here — so it can never drift from the truth.
import type { Entry } from "./types";
import { addDays, MONTH_NAMES, parseKey, toKey, todayKey } from "./date";

/** count of entries per day-key. */
export function countsByDate(entries: Entry[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const e of entries) m.set(e.date, (m.get(e.date) ?? 0) + 1);
  return m;
}

/** Intensity bucket 0–4 for the mosaic. Darker = more logged that day. */
export function intensityLevel(count: number): 0 | 1 | 2 | 3 | 4 {
  if (count <= 0) return 0;
  if (count === 1) return 1;
  if (count === 2) return 2;
  if (count === 3) return 3;
  return 4;
}

/**
 * Current streak with GRACE: walking back from today, count days that have ≥1 entry.
 * Today being empty doesn't break it (you might still log tonight). Grace replenishes
 * on every logged day, so any isolated miss is forgiven — only `grace + 1` misses
 * in a row end the streak.
 */
export function currentStreak(counts: Map<string, number>, grace = 1): number {
  const today = parseKey(todayKey());
  let cursor = today;
  // Today not-yet-logged: start from yesterday without penalty.
  if (!counts.get(toKey(cursor))) cursor = addDays(cursor, -1);

  let streak = 0;
  let graceLeft = grace;
  while (true) {
    const k = toKey(cursor);
    if (counts.get(k)) {
      streak++;
      graceLeft = grace; // a logged day restores the gap allowance
      cursor = addDays(cursor, -1);
    } else if (graceLeft > 0) {
      graceLeft--;
      cursor = addDays(cursor, -1);
    } else {
      break;
    }
  }
  return streak;
}

/** Longest run of logged days anywhere in history, same replenishing grace. */
export function longestStreak(counts: Map<string, number>, grace = 1): number {
  const keys = [...counts.keys()].sort();
  if (keys.length === 0) return 0;
  const start = parseKey(keys[0]);
  const end = parseKey(keys[keys.length - 1]);

  let best = 0;
  let run = 0;
  let graceLeft = grace;
  for (let d = start; d.getTime() <= end.getTime(); d = addDays(d, 1)) {
    if (counts.get(toKey(d))) {
      run++;
      best = Math.max(best, run);
      graceLeft = grace; // a logged day restores the gap allowance
    } else if (graceLeft > 0) {
      graceLeft--; // forgive an isolated gap inside the run
    } else {
      run = 0;
      graceLeft = grace;
    }
  }
  return best;
}

export interface Stats {
  total: number;
  kinds: number;
  current: number;
  longest: number;
}

export function stats(entries: Entry[]): Stats {
  const counts = countsByDate(entries);
  const kinds = new Set(entries.map((e) => e.drink.trim().toLowerCase()).filter(Boolean));
  return {
    total: entries.length,
    kinds: kinds.size,
    current: currentStreak(counts),
    longest: longestStreak(counts),
  };
}

export const MILESTONES = [10, 25, 50, 100, 250, 500];

/** The most recent milestone reached, and the next one ahead. */
export function milestoneProgress(total: number): { reached: number | null; next: number | null } {
  let reached: number | null = null;
  let next: number | null = null;
  for (const m of MILESTONES) {
    if (total >= m) reached = m;
    else {
      next = m;
      break;
    }
  }
  return { reached, next };
}

export interface MoodWord {
  word: string;
  count: number;
}

/** The accumulating personal lexicon — distinct mood words by frequency. */
export function lexicon(entries: Entry[]): MoodWord[] {
  const m = new Map<string, number>();
  for (const e of entries) {
    const w = e.mood?.trim().toLowerCase();
    if (w) m.set(w, (m.get(w) ?? 0) + 1);
  }
  return [...m.entries()]
    .map(([word, count]) => ({ word, count }))
    .sort((a, b) => b.count - a.count || a.word.localeCompare(b.word));
}

/** Recent/common drinks for the log sheet quick-pick — frequency, then recency. */
export function recentDrinks(entries: Entry[], n = 5): string[] {
  const info = new Map<string, { count: number; last: string }>();
  for (const e of entries) {
    const name = e.drink.trim();
    if (!name) continue;
    const key = name.toLowerCase();
    const prev = info.get(key);
    if (prev) {
      prev.count++;
      if (e.createdAt > prev.last) prev.last = e.createdAt;
    } else {
      info.set(key, { count: 1, last: e.createdAt });
    }
  }
  // Preserve original casing from the most recent occurrence.
  const casing = new Map<string, string>();
  for (const e of entries) {
    const name = e.drink.trim();
    if (!name) continue;
    casing.set(name.toLowerCase(), name);
  }
  return [...info.entries()]
    .sort((a, b) => b[1].count - a[1].count || b[1].last.localeCompare(a[1].last))
    .slice(0, n)
    .map(([key]) => casing.get(key) ?? key);
}

/** Recent mood words for the quick-pick chips. */
export function recentMoods(entries: Entry[], n = 6): string[] {
  return lexicon(entries).slice(0, n).map((m) => m.word);
}

/**
 * A gentle "looking back" memory — an older entry (≥14 days), preferring ones with a
 * note or photo. Picked deterministically by the current date so it's stable within a day.
 */
export function memory(entries: Entry[]): Entry | null {
  const today = parseKey(todayKey());
  const cutoff = addDays(today, -14).getTime();
  const old = entries.filter((e) => parseKey(e.date).getTime() <= cutoff);
  if (old.length === 0) return null;
  const rich = old.filter((e) => e.note || (e.photos && e.photos.length));
  const pool = rich.length ? rich : old;
  return pool[today.getDate() % pool.length];
}

/**
 * Friend recommendations — drinks your friends pour that you haven't logged yet,
 * ranked by how many DISTINCT friends pour them (then total frequency). The
 * "regulars" half of the recommendation spec, derived purely from their shared feed.
 * `excluded` (e.g. your wishlist) is filtered out so we never suggest what you saved.
 */
export function friendPicks(
  friendDrinks: { drink: string; author: string }[],
  myDrinks: string[],
  excluded: string[] = [],
  n = 4,
): string[] {
  const skip = new Set([...myDrinks, ...excluded].map((d) => d.trim().toLowerCase()).filter(Boolean));
  const info = new Map<string, { display: string; authors: Set<string>; total: number }>();
  for (const { drink, author } of friendDrinks) {
    const name = drink.trim();
    if (!name) continue;
    const key = name.toLowerCase();
    if (skip.has(key)) continue;
    const cur = info.get(key);
    if (cur) {
      cur.authors.add(author);
      cur.total += 1;
    } else {
      info.set(key, { display: name, authors: new Set([author]), total: 1 });
    }
  }
  return [...info.values()]
    .sort((a, b) => b.authors.size - a.authors.size || b.total - a.total || a.display.localeCompare(b.display))
    .slice(0, n)
    .map((v) => v.display);
}

export interface YearReview {
  total: number;
  kinds: number;
  days: number;
  topDrink?: string;
  topMood?: string;
  busiestMonth?: string;
}

/** A calm look-back over everything logged — all derived, no rating logic. */
export function yearReview(entries: Entry[]): YearReview {
  const drinkCounts = new Map<string, number>();
  const casing = new Map<string, string>();
  const monthCounts = new Map<number, number>();
  const days = new Set<string>();

  for (const e of entries) {
    const name = e.drink.trim();
    if (name) {
      const key = name.toLowerCase();
      drinkCounts.set(key, (drinkCounts.get(key) ?? 0) + 1);
      casing.set(key, name);
    }
    const m = parseKey(e.date).getMonth();
    monthCounts.set(m, (monthCounts.get(m) ?? 0) + 1);
    days.add(e.date);
  }

  const topDrinkKey = [...drinkCounts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const topMonthIdx = [...monthCounts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];

  return {
    total: entries.length,
    kinds: casing.size,
    days: days.size,
    topDrink: topDrinkKey ? casing.get(topDrinkKey) : undefined,
    topMood: lexicon(entries)[0]?.word,
    busiestMonth: topMonthIdx !== undefined ? MONTH_NAMES[topMonthIdx] : undefined,
  };
}
