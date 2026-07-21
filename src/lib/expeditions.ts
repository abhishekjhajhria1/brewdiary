// Expeditions — the exploration GAME layer over the Taste Passport.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHAT THIS IS, AND WHERE EVERY PART OF IT CAME FROM (provenance is a house rule)
// Full spec + decision trail: internal/phase-c-expeditions.md
//
//  • Candy Crush → the never-ending JOURNEY feel ("always one more door"). We took the
//    endlessness; we deliberately DROPPED its difficulty ramp and its lives/pay-to-continue
//    gate. Endless here comes from the size of the map, not from levels getting harder.
//  • Pokémon GO ("Choose Your Path" research + Routes) → the pick-your-VIBE paths, and the
//    "get people out of their usual place" nudge, kept "accessible, not a chore list".
//  • Untappd → collection TROPHIES for variety, never for skill or volume.
//  • Duolingo → a small daily HAND of do-able tasks (you can always finish today's).
//  • LeBlanc's "8 Kinds of Fun" (MDA framework) → the theory that makes it cohere: a
//    difficulty curve only feeds ONE kind of fun (Challenge). This app is built on the
//    others — Discovery, Fellowship, Expression, Submission — so Challenge is demoted to a
//    descriptive TAG (`effort`), never the spine. (Maintainer's correction: "not difficulty
//    based… fun, not hard"; researched → this design.)
//
// THE INVARIANTS (inherit the Passport's six, add these — see spec §1):
//  1. NO VOLUME AXIS. Everything is derived from BREADTH/behaviour (new families, new worlds,
//     charting, varied weeks, dry days). There is no "count of drinks" metric anywhere in this
//     file. That is rule #6 ("nothing rewards drinking more") made structural.
//  2. Fun-first, not difficulty-based. Every quest is do-able tonight. `effort` is a tag, never
//     a gate and never an escalation. A hand is mostly `chill`, with at most one bolder card.
//  3. Endless via the POOL, not escalation — the pool is derived from your gaps in an
//     ever-growing dictionary + venue space, so it never repeats stalely and never runs out.
//  4. 100% DERIVED. No table, no stored column. A quest is "done" when the Passport reflects it,
//     so the hand advances itself. Delete any of this and it recomputes identically.
//
// The competitive "cups" layer (user-generated competitions) is Phase C-2 and needs the one
// migration; this file is the solo half and stays pure + offline + private.
import type { DrinkType, Entry } from "./types";
import { DRINK_TYPES } from "./types";
import { canonicalize } from "./drinks";
import { weekBalance } from "./derive";
import { todayKey } from "./date";
import { passport, palateNeighbours } from "./passport";
import { makeable } from "./recipes";

// A path the player chooses — biases which do-able cards surface (Pokémon GO "Choose Your Path").
// It changes the FLAVOUR of the hand, never the difficulty.
export type Vibe = "cozy" | "social" | "explorer" | "bold";

// Difficulty as a DESCRIPTIVE TAG only (invariant #2). Never sorted on, never gated on.
export type Effort = "chill" | "a stretch" | "bold";

// What a quest asks of the palate/behaviour. Note the absence of any volume/spend axis (#1).
export type Axis = "family" | "world" | "make" | "friend" | "offmap" | "venue" | "balance";

// Where you'd do it — lets a homebody and a night-out person get different hands.
export type Where = "home" | "out" | "any";

export interface Quest {
  /** Stable + derived from axis+target, so completion is detectable from state alone. */
  id: string;
  title: string;
  hint?: string;
  vibe: Vibe;
  effort: Effort;
  axis: Axis;
  where: Where;
  /** The matched family this points at (for completion detection). Absent on open invitations. */
  target?: string;
  targetType?: DrinkType;
}

export interface ExpeditionContext {
  entries: Entry[];
  /** Your shelf (pantry.ts) — powers the cozy "make something" cards. */
  pantry?: string[];
  /** Friends' shared pours (same shape as derive.friendPicks / palateNeighbours). */
  friendDrinks?: { drink: string; author: string }[];
  /** Your to-try list — a saved drink is left out of nudges (you already chose it). */
  wishlist?: string[];
  today?: string;
}

const TYPE_LABEL = new Map<DrinkType, string>(DRINK_TYPES.map((t) => [t.value, t.label]));
function typeLabel(t: DrinkType): string {
  return TYPE_LABEL.get(t) ?? t;
}

// Which axes each vibe path leans toward. Used to bias the hand, not to hard-filter it — a
// path shapes the flavour, but the hand still values variety over purity (see expeditionHand).
const VIBE_AXES: Record<Vibe, Axis[]> = {
  cozy: ["make", "balance", "family"],
  social: ["friend", "venue", "family"],
  explorer: ["world", "venue", "family"],
  bold: ["offmap", "world", "venue"],
};

// A tiny deterministic string hash (FNV-1a). Used only to order equal-priority quests by a
// day-seed, so a hand is stable within a day and gently reshuffles tomorrow — the Pokémon GO
// "Daily Discoveries" feel, with zero stored state.
function hash(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/**
 * The whole candidate pool for a diary — every do-able "try this" card the app can offer right
 * now, derived from your gaps. Deterministic and pure. `expeditionHand` picks from this; nothing
 * here is difficulty-ordered (invariant #2).
 */
export function generateQuests(ctx: ExpeditionContext): Quest[] {
  const { entries, pantry = [], friendDrinks = [], wishlist = [] } = ctx;
  const today = ctx.today ?? todayKey();
  const p = passport(entries);
  const quests: Quest[] = [];
  const usedFamilies = new Set<string>(); // one card per family, first axis wins

  // ── friend (social): a family a friend pours that you haven't explored ──────────────
  const friendByFamily = new Map<string, Set<string>>();
  for (const { drink, author } of friendDrinks) {
    const c = canonicalize(drink);
    if (!c.matched) continue;
    let set = friendByFamily.get(c.family);
    if (!set) friendByFamily.set(c.family, (set = new Set()));
    set.add(author);
  }
  const exploredFamilies = new Set<string>();
  for (const w of p.worlds) for (const s of w.stamps) if (s.explored) exploredFamilies.add(s.family);

  for (const [family, authors] of friendByFamily) {
    if (exploredFamilies.has(family) || usedFamilies.has(family)) continue;
    const type = p.worlds.find((w) => w.stamps.some((s) => s.family === family))?.type;
    usedFamilies.add(family);
    quests.push({
      id: `friend:${family}`,
      title: `${authors.size > 1 ? `${authors.size} friends pour` : "A friend pours"} ${family}`,
      hint: "Try theirs — a new stamp for you, a reason to meet.",
      vibe: "social",
      effort: "a stretch",
      axis: "friend",
      where: "any",
      target: family,
      targetType: type,
    });
  }

  // ── family (explorer, chill): an unexplored family next to a world you already wander ─
  for (const s of palateNeighbours(entries, friendDrinks, wishlist, 6)) {
    if (!s.matched || !s.type || usedFamilies.has(s.family)) continue;
    usedFamilies.add(s.family);
    quests.push({
      id: `family:${s.family}`,
      title: `Try a ${s.family}`,
      hint: `Next door to a world you already wander.`,
      vibe: "explorer",
      effort: "chill",
      axis: "family",
      where: "any",
      target: s.family,
      targetType: s.type,
    });
  }

  // ── world (explorer, a stretch): a whole world you've never entered — the widener ─────
  for (const w of p.worlds) {
    if (w.exploredCount > 0) continue;
    const entry = w.stamps.find((s) => !usedFamilies.has(s.family)) ?? w.stamps[0];
    if (!entry) continue;
    usedFamilies.add(entry.family);
    quests.push({
      id: `world:${w.type}`,
      title: `Step into ${typeLabel(w.type)} — try a ${entry.family}`,
      hint: "A whole world you haven't opened yet.",
      vibe: "explorer",
      effort: "a stretch",
      axis: "world",
      where: "any",
      target: entry.family,
      targetType: w.type,
    });
  }

  // ── make (cozy, chill, home): something you can make with what's already on your shelf ─
  for (const { recipe } of makeable(pantry)) {
    if (exploredFamilies.has(recipe.family) || usedFamilies.has(recipe.family)) continue;
    usedFamilies.add(recipe.family);
    quests.push({
      id: `make:${recipe.family}`,
      title: `Make a ${recipe.name}`,
      hint: "Everything for it is already on your shelf.",
      vibe: "cozy",
      effort: "chill",
      axis: "make",
      where: "home",
      target: recipe.family,
      targetType: recipe.type,
    });
  }

  // ── balance (cozy, chill): a gentle dry-day nudge if the week's been busy ─────────────
  const wb = weekBalance(entries, today);
  if (wb.drinks >= 3 && wb.dryDays < wb.windowDays) {
    quests.push({
      id: "balance:dry",
      title: "Make tonight a dry one",
      hint: "It still keeps the streak — a good night is a night you chose.",
      vibe: "cozy",
      effort: "chill",
      axis: "balance",
      where: "home",
    });
  }

  // ── open invitations (no target → never "done", they just rotate) ─────────────────────
  // offmap (bold): ties into Phase B — drink something the map doesn't know, then chart it.
  quests.push({
    id: "offmap",
    title: "Find a drink the map has never seen",
    hint: "Something off the map — then chart it so everyone's passport can light it.",
    vibe: "bold",
    effort: "bold",
    axis: "offmap",
    where: "out",
  });
  // venue (bold, out): the "get out of your place" card. A NAMED venue comes with the geo layer.
  quests.push({
    id: "venue",
    title: "Drink somewhere you've never been",
    hint: "A new bar, a new café — one street further than usual.",
    vibe: "explorer",
    effort: "bold",
    axis: "venue",
    where: "out",
  });

  return quests;
}

/** A matched-family quest is done once the Passport shows that family explored. Open
 *  invitations (no target) are never "done" — they're standing doors, they simply rotate. */
export function isQuestDone(entries: Entry[], quest: Quest): boolean {
  if (!quest.target) return false;
  const p = passport(entries);
  for (const w of p.worlds) {
    for (const s of w.stamps) if (s.family === quest.target) return s.explored;
  }
  return false;
}

export interface HandOptions {
  vibe?: Vibe;
  n?: number;
  today?: string;
}

/**
 * Tonight's HAND — the few cards a player actually sees. Derived, day-seeded (stable within a
 * day, reshuffles tomorrow), and shaped so it always feels fun and do-able:
 *  • DROPS anything already done (so the hand self-advances — the "always one more door" loop).
 *  • BIASES to the chosen vibe path, but values VARIETY over purity (never 3 of one axis).
 *  • Stays MOSTLY CHILL — at most one bolder card rides along as spice (invariant #2). It is
 *    never ordered by difficulty; `effort` is only a label the UI can show.
 */
export function expeditionHand(ctx: ExpeditionContext, opts: HandOptions = {}): Quest[] {
  const n = opts.n ?? 3;
  const today = opts.today ?? ctx.today ?? todayKey();
  const preferred = new Set(opts.vibe ? VIBE_AXES[opts.vibe] : []);

  const pool = generateQuests({ ...ctx, today }).filter((q) => !isQuestDone(ctx.entries, q));

  // Rank: preferred-vibe first, then chill-before-bolder (a soft nudge, not a hard sort), then a
  // day-seeded shuffle within ties so equal cards rotate day to day rather than by name.
  const effortWeight: Record<Effort, number> = { chill: 0, "a stretch": 1, bold: 2 };
  // Affinity rank of an axis within the chosen path (earlier in VIBE_AXES = stronger fit).
  // Used only to break ties among equally-preferred, equally-chill cards, so the LEAD card is
  // the best-fit-for-your-vibe rather than a coin flip — deeper cards still day-shuffle.
  const affinity = (axis: Axis) => {
    if (!opts.vibe) return 99;
    const i = VIBE_AXES[opts.vibe].indexOf(axis);
    return i < 0 ? 99 : i;
  };
  const ranked = [...pool].sort((a, b) => {
    const pa = preferred.has(a.axis) ? 0 : 1;
    const pb = preferred.has(b.axis) ? 0 : 1;
    if (pa !== pb) return pa - pb; // your path first
    if (effortWeight[a.effort] !== effortWeight[b.effort]) return effortWeight[a.effort] - effortWeight[b.effort]; // chill first (fun-first)
    const aa = affinity(a.axis), ab = affinity(b.axis);
    if (aa !== ab) return aa - ab; // best-fit lead card
    return hash(today + a.id) - hash(today + b.id); // day-seeded shuffle within true ties
  });

  // Greedy pick with two shaping rules: variety (prefer a new axis) and "mostly chill"
  // (allow at most one non-chill card in the hand).
  const hand: Quest[] = [];
  const seenAxes = new Set<Axis>();
  let bolder = 0;
  const maxBolder = 1;

  const tryTake = (allowRepeatAxis: boolean) => {
    for (const q of ranked) {
      if (hand.length >= n) break;
      if (hand.includes(q)) continue;
      if (!allowRepeatAxis && seenAxes.has(q.axis)) continue;
      if (q.effort !== "chill" && bolder >= maxBolder) continue;
      hand.push(q);
      seenAxes.add(q.axis);
      if (q.effort !== "chill") bolder++;
    }
  };
  tryTake(false); // first pass: distinct axes, honour the bolder cap
  tryTake(true); // fill any remaining slots, still honouring the bolder cap

  return hand;
}

// ── trophies (collection, Untappd-style — breadth & behaviour, never volume/difficulty) ─────
export interface Trophy {
  id: string;
  title: string;
  note: string;
  earned: boolean;
}

/**
 * The trophy shelf — a calm collection you fill by EXPLORING, not by drinking more or by beating
 * a hard level. Every trophy is derived from the Passport's breadth or a gentle behaviour signal;
 * none of them count volume, spend or difficulty (invariant #1). No tiers-as-a-race, no "X to go".
 */
export function trophies(entries: Entry[], today = todayKey()): Trophy[] {
  const p = passport(entries);
  const worldsEntered = p.worlds.filter((w) => w.exploredCount > 0).length;
  const totalWorlds = p.worlds.length;
  const wb = weekBalance(entries, today);

  return [
    {
      id: "first-stamp",
      title: "First light",
      note: "Lit your first stamp.",
      earned: p.exploredFamilies >= 1,
    },
    {
      id: "wanderer-5",
      title: "Wanderer",
      note: "Explored five different families.",
      earned: p.exploredFamilies >= 5,
    },
    {
      id: "wanderer-15",
      title: "Far-wanderer",
      note: "Fifteen families, and counting.",
      earned: p.exploredFamilies >= 15,
    },
    {
      id: "world-hopper",
      title: "World-hopper",
      note: "Set foot in three different worlds.",
      earned: worldsEntered >= 3,
    },
    {
      id: "all-worlds",
      title: "Round the compass",
      note: "A stamp in every world on the map.",
      earned: totalWorlds > 0 && worldsEntered === totalWorlds,
    },
    {
      id: "cartographer",
      title: "Cartographer",
      note: "Drew a region of your own — an off-map find.",
      earned: p.offMap.length >= 1,
    },
    {
      id: "balanced-week",
      title: "Well-paced",
      note: "A week with room to breathe — a dry day in it.",
      earned: wb.dryDays >= 1 && wb.drinks >= 1,
    },
  ];
}
