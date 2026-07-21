// The Taste Passport — a living map of the palate you're building, DERIVED entirely
// from your entries + the drinks dictionary (drinks.ts). Nothing here is stored, exactly
// like the mosaic and the lexicon: delete any cache and it recomputes identically.
//
// The one hard rule (see internal/phase-a-taste-passport.md): it rewards BREADTH, never
// volume. A family is a binary stamp — logging the same Negroni fifty times fills the map
// exactly as much as logging it once (i.e. not at all past the first). Coffee, tea and soft
// families fill it identically to spirits, so the Passport never points at alcohol. There is
// no completion %, no scarcity, no spark or perk — the reward is the map itself. This is the
// "spark for variety, never frequency" rule (points.ts) applied to collecting.
import type { DrinkType, Entry } from "./types";
import { DRINK_TYPES } from "./types";
import { DRINKS, canonicalize, drinkFamily } from "./drinks";
import { drinkEntries, memory } from "./derive";
import { addDays, parseKey, toKey, todayKey } from "./date";

/** One family + the diary's standing in it. A stamp is EXPLORED or not — never "how much". */
export interface Stamp {
  /** The family this stamp represents ("Latte", "Negroni", "IPA"…), or a novel drink's own name. */
  family: string;
  /** Which world it lives in. Absent for an off-map (novel) stamp, which has no dictionary type. */
  type?: DrinkType;
  /** True once you've logged ≥1 drink in this family. */
  explored: boolean;
  /** Day-key of the first log in it — a keepsake, shown on the stamp. */
  firstExplored?: string;
  /** The distinct drinks YOU logged in it, in your own words (deduped case-insensitively). */
  drinks: string[];
  /** False for an off-map stamp: a novel drink the dictionary doesn't know, filed under itself. */
  matched: boolean;
}

export interface World {
  type: DrinkType;
  stamps: Stamp[];
  /** How many families in this world you've explored — the world's breadth, never a target. */
  exploredCount: number;
}

export interface Passport {
  /** The dictionary's families grouped into worlds by type, each stamp flagged explored/not. */
  worlds: World[];
  /** "Regions all your own" — novel drinks that aren't in the dictionary. Celebrated, not forced. */
  offMap: Stamp[];
  /** Breadth headline: a COUNT of distinct families explored (incl. off-map). Never a percentage. */
  exploredFamilies: number;
  /** Distinct families explored per type — the silhouette of a taste. The ownable identity. */
  palateShape: Partial<Record<DrinkType, number>>;
}

// ── the catalog (built once from the dictionary) ─────────────────────────────
let CATALOG: { type: DrinkType; families: string[] }[] | null = null;

/**
 * Every family the dictionary knows, grouped into worlds by DrinkType, in the log form's
 * type order. Built once and memoised. It GROWS automatically as DRINKS grows — which is why
 * the Passport is deliberately open-ended and never shows a "you've collected X of N" total.
 */
export function familyCatalog(): { type: DrinkType; families: string[] }[] {
  if (CATALOG) return CATALOG;
  const byType = new Map<DrinkType, string[]>();
  for (const d of DRINKS) {
    const list = byType.get(d.type) ?? [];
    if (!list.includes(d.family)) list.push(d.family);
    byType.set(d.type, list);
  }
  // Keep the log form's type order (coffee, tea, beer…); skip types the dictionary has no family for.
  CATALOG = DRINK_TYPES.map((t) => t.value)
    .filter((type) => byType.has(type))
    .map((type) => ({ type, families: byType.get(type)! }));
  return CATALOG;
}

// ── the map for a diary ──────────────────────────────────────────────────────
interface Acc {
  matched: boolean;
  type?: DrinkType;
  display: string;
  drinks: Map<string, string>; // lowercased → original casing (your words, deduped)
  first: string;
}

// A one-slot memo keyed on the ENTRIES REFERENCE. The store hands back a stable array between
// renders, and a single You render folds the passport several times over (the map itself, plus
// palateNeighbours / adjacentStamps / weeklyDiscovery, each of which folds it again). This makes
// those repeats free. It is not state: drop it and every call recomputes the identical result —
// the "derived, never stored" rule is untouched.
let memoKey: Entry[] | null = null;
let memoVal: Passport | null = null;

/** Fold a diary into its Taste Passport. Pure and deterministic. */
export function passport(entries: Entry[]): Passport {
  if (memoKey === entries && memoVal) return memoVal;
  const result = computePassport(entries);
  memoKey = entries;
  memoVal = result;
  return result;
}

function computePassport(entries: Entry[]): Passport {
  // Dry days aren't a drink and don't touch palate breadth — so they're simply neutral here.
  const drinks = drinkEntries(entries);

  const exploredMatched = new Map<string, Acc>(); // key: family
  const offMapAcc = new Map<string, Acc>(); // key: lowercased novel name

  for (const e of drinks) {
    const name = e.drink.trim();
    if (!name) continue;
    const c = canonicalize(name);
    const bucket = c.matched ? exploredMatched : offMapAcc;
    const key = c.matched ? c.family : name.toLowerCase();
    let acc = bucket.get(key);
    if (!acc) {
      acc = { matched: c.matched, type: c.type, display: c.matched ? c.family : name, drinks: new Map(), first: e.date };
      bucket.set(key, acc);
    }
    acc.drinks.set(name.toLowerCase(), name);
    if (e.date < acc.first) acc.first = e.date; // day-keys sort lexicographically
  }

  const worlds: World[] = familyCatalog().map(({ type, families }) => {
    const stamps: Stamp[] = families.map((family) => {
      const acc = exploredMatched.get(family);
      return {
        family,
        type,
        explored: !!acc,
        firstExplored: acc?.first,
        drinks: acc ? [...acc.drinks.values()] : [],
        matched: true,
      };
    });
    return { type, stamps, exploredCount: stamps.filter((s) => s.explored).length };
  });

  const offMap: Stamp[] = [...offMapAcc.values()]
    .map((acc) => ({
      family: acc.display,
      type: acc.type,
      explored: true,
      firstExplored: acc.first,
      drinks: [...acc.drinks.values()],
      matched: false,
    }))
    .sort((a, b) => a.family.localeCompare(b.family));

  const palateShape: Partial<Record<DrinkType, number>> = {};
  for (const w of worlds) palateShape[w.type] = w.exploredCount;

  const exploredFamilies = worlds.reduce((n, w) => n + w.exploredCount, 0) + offMap.length;

  return { worlds, offMap, exploredFamilies, palateShape };
}

// ── the curiosity loop: palate-neighbours (CD7) ──────────────────────────────
/**
 * Gentle "you might wander here" suggestions — UNEXPLORED families to try next. It WIDENS the
 * palate and never deepens a habit: it only ever surfaces families you haven't logged, and it
 * NEVER ranks by alcohol (a chamomile can outrank a mezcal). Sources: friends who pour it, a
 * world you already wander (relevance), and a deliberate seed from a world you've barely touched
 * (the widener). Anything already on your wishlist is left out — you saved it, no need to nudge.
 *
 * `friendDrinks` mirrors derive.friendPicks' input; `wishlist` is your to-try drink names.
 */
export function palateNeighbours(
  entries: Entry[],
  friendDrinks: { drink: string; author: string }[] = [],
  wishlist: string[] = [],
  n = 4,
): Stamp[] {
  const p = passport(entries);
  const exploredType = new Map<DrinkType, number>();
  for (const w of p.worlds) exploredType.set(w.type, w.exploredCount);

  const wishFamilies = new Set(wishlist.map((d) => drinkFamily(d)));

  // How many distinct friends pour something in each family (a soft, positive interest signal).
  const friendAuthors = new Map<string, Set<string>>();
  for (const { drink, author } of friendDrinks) {
    const c = canonicalize(drink);
    if (!c.matched) continue;
    const set = friendAuthors.get(c.family) ?? new Set<string>();
    set.add(author);
    friendAuthors.set(c.family, set);
  }

  const candidates: { stamp: Stamp; score: number }[] = [];
  for (const w of p.worlds) {
    const typeExplored = exploredType.get(w.type) ?? 0;
    for (const s of w.stamps) {
      if (s.explored || wishFamilies.has(s.family)) continue;
      const friends = friendAuthors.get(s.family)?.size ?? 0;
      const adjacency = typeExplored > 0 ? 1 : 0; // a world you already wander → relevant
      candidates.push({ stamp: s, score: friends * 2 + adjacency });
    }
  }
  candidates.sort((a, b) => b.score - a.score || a.stamp.family.localeCompare(b.stamp.family));

  const pick = candidates.slice(0, n);
  // The widener: make sure at least one suggestion is from a world you haven't entered yet.
  const isNovelWorld = (s: Stamp) => (exploredType.get(s.type!) ?? 0) === 0;
  if (pick.length && !pick.some((c) => isNovelWorld(c.stamp))) {
    const seed = candidates.find((c) => isNovelWorld(c.stamp));
    if (seed) pick[pick.length - 1] = seed;
  }
  return pick.map((c) => c.stamp);
}

/**
 * The one or two nearest UNEXPLORED families in the same world as `stamp` — "next door to
 * here". Shown in the stamp sheet so every stamp is a door to another, not a dead end. Same
 * discipline as palateNeighbours: only ever families you HAVEN'T logged (widen, never deepen),
 * and an off-map stamp has no world, so it has no neighbours.
 */
export function adjacentStamps(entries: Entry[], stamp: Stamp, n = 2): Stamp[] {
  if (!stamp.matched || !stamp.type) return [];
  const world = passport(entries).worlds.find((w) => w.type === stamp.type);
  if (!world) return [];
  return world.stamps
    .filter((s) => !s.explored && s.family !== stamp.family)
    .sort((a, b) => a.family.localeCompare(b.family))
    .slice(0, n);
}

// ── the weekly return-pull ────────────────────────────────────────────────────
export interface WeeklyDiscovery {
  /** Stamps you first lit in the last 7 days — "look what you found". */
  newStamps: Stamp[];
  /** A resurfaced older entry (derive.memory) — a calm "looking back". */
  memory: Entry | null;
  /** One gentle door to wander through next. */
  nudge: Stamp | null;
}

/**
 * A calm weekly recap — the white-hat "come back today" we otherwise lack. Opt-in at the UI
 * layer; never a push to consume, only "look what you found / here's a door".
 */
export function weeklyDiscovery(
  entries: Entry[],
  opts: { today?: string; friendDrinks?: { drink: string; author: string }[]; wishlist?: string[] } = {},
): WeeklyDiscovery {
  const today = opts.today ?? todayKey();
  const cutoff = toKey(addDays(parseKey(today), -6)); // 7-day window, today included
  const p = passport(entries);
  const newStamps = [...p.worlds.flatMap((w) => w.stamps), ...p.offMap].filter(
    (s) => s.explored && s.firstExplored && s.firstExplored >= cutoff && s.firstExplored <= today,
  );
  const nudge = palateNeighbours(entries, opts.friendDrinks, opts.wishlist, 1)[0] ?? null;
  return { newStamps, memory: memory(entries), nudge };
}
