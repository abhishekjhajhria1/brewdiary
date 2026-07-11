// Drink canonicalization — the "bigger class" grouping.
//
// Many drinks are the same thing wearing a different name ("flat white",
// "flatwhite", "flat-white") or near-twins that share ~90% of their build
// ("negroni", "negroni sbagliato", "boulevardier" → the Negroni family). This
// module folds those together so the diary can:
//   • suggest a name while you type (autocomplete),
//   • quietly propose the canonical spelling if you type a variant, and
//   • group your history by family for cleaner counts.
//
// Nothing here is STORED — grouping is derived on the fly from the free-text you
// typed, exactly like the mosaic and lexicon. Your words stay your words; the
// family is just how we file them. Curated dictionary first, then a fuzzy
// fallback for anything unknown (typos, rare drinks) using string similarity.
import type { DrinkType } from "./types";

export interface DrinkDef {
  /** The tidy display spelling we suggest. */
  canonical: string;
  /** The wider class near-identical drinks share. */
  family: string;
  /** Best-guess kind, so picking a suggestion can pre-fill "Kind". */
  type: DrinkType;
  /** Other spellings/variants that fold into this one. */
  aliases?: string[];
}

// A compact, growable dictionary of the drinks people actually log. Add freely —
// each entry teaches the app one more name it can suggest and group by.
export const DRINKS: DrinkDef[] = [
  // ── coffee ────────────────────────────────────────────────────────────────
  { canonical: "Espresso", family: "Espresso", type: "coffee", aliases: ["shot", "short black", "doppio"] },
  { canonical: "Flat White", family: "Flat White", type: "coffee", aliases: ["flatwhite"] },
  { canonical: "Latte", family: "Latte", type: "coffee", aliases: ["caffe latte", "cafe latte", "latté"] },
  { canonical: "Cappuccino", family: "Cappuccino", type: "coffee", aliases: ["cappucino", "capp"] },
  { canonical: "Cortado", family: "Cortado", type: "coffee", aliases: ["gibraltar"] },
  { canonical: "Americano", family: "Americano", type: "coffee", aliases: ["long black", "caffe americano"] },
  { canonical: "Macchiato", family: "Macchiato", type: "coffee", aliases: ["espresso macchiato"] },
  { canonical: "Mocha", family: "Mocha", type: "coffee", aliases: ["mochaccino", "caffe mocha"] },
  { canonical: "Cold Brew", family: "Cold Brew", type: "coffee", aliases: ["coldbrew", "cold-brew"] },
  { canonical: "Iced Latte", family: "Latte", type: "coffee", aliases: ["iced coffee", "ice latte"] },
  { canonical: "Pour-over", family: "Filter Coffee", type: "coffee", aliases: ["pourover", "pour over", "filter", "filter coffee", "drip", "v60"] },

  // ── tea ───────────────────────────────────────────────────────────────────
  { canonical: "Matcha", family: "Matcha", type: "tea", aliases: ["matcha latte"] },
  { canonical: "Green Tea", family: "Green Tea", type: "tea", aliases: ["sencha", "greentea"] },
  { canonical: "Chamomile", family: "Chamomile", type: "tea", aliases: ["camomile"] },
  { canonical: "Earl Grey", family: "Black Tea", type: "tea", aliases: ["earlgrey", "english breakfast", "breakfast tea"] },
  { canonical: "Chai", family: "Chai", type: "tea", aliases: ["chai latte", "masala chai"] },

  // ── beer ──────────────────────────────────────────────────────────────────
  { canonical: "IPA", family: "IPA", type: "beer", aliases: ["india pale ale"] },
  { canonical: "Hazy IPA", family: "IPA", type: "beer", aliases: ["neipa", "new england ipa", "juicy ipa"] },
  { canonical: "West Coast IPA", family: "IPA", type: "beer", aliases: ["wc ipa"] },
  { canonical: "Double IPA", family: "IPA", type: "beer", aliases: ["dipa", "imperial ipa"] },
  { canonical: "Lager", family: "Lager", type: "beer", aliases: ["pilsner", "pils", "helles"] },
  { canonical: "Pale Ale", family: "Pale Ale", type: "beer", aliases: ["apa", "american pale ale"] },
  { canonical: "Stout", family: "Stout", type: "beer", aliases: ["imperial stout", "milk stout"] },
  { canonical: "Guinness", family: "Stout", type: "beer" },
  { canonical: "Porter", family: "Stout", type: "beer" },
  { canonical: "Wheat Beer", family: "Wheat Beer", type: "beer", aliases: ["hefeweizen", "witbier", "wit", "weissbier"] },
  { canonical: "Sour", family: "Sour", type: "beer", aliases: ["gose", "berliner weisse"] },

  // ── wine ──────────────────────────────────────────────────────────────────
  { canonical: "Riesling", family: "White Wine", type: "wine" },
  { canonical: "Sauvignon Blanc", family: "White Wine", type: "wine", aliases: ["sauv blanc", "sancerre"] },
  { canonical: "Chardonnay", family: "White Wine", type: "wine", aliases: ["chard"] },
  { canonical: "Pinot Grigio", family: "White Wine", type: "wine", aliases: ["pinot gris"] },
  { canonical: "Cabernet Sauvignon", family: "Red Wine", type: "wine", aliases: ["cabernet", "cab sauv", "cab"] },
  { canonical: "Merlot", family: "Red Wine", type: "wine" },
  { canonical: "Pinot Noir", family: "Red Wine", type: "wine", aliases: ["pinot"] },
  { canonical: "Malbec", family: "Red Wine", type: "wine" },
  { canonical: "Barolo", family: "Red Wine", type: "wine", aliases: ["nebbiolo"] },
  { canonical: "Syrah", family: "Red Wine", type: "wine", aliases: ["shiraz"] },
  { canonical: "Rosé", family: "Rosé", type: "wine", aliases: ["rose wine", "rosado"] },
  { canonical: "Prosecco", family: "Sparkling", type: "wine", aliases: ["cava", "champagne", "sparkling wine", "fizz"] },

  // ── cocktails ─────────────────────────────────────────────────────────────
  { canonical: "Negroni", family: "Negroni", type: "cocktail" },
  { canonical: "Negroni Sbagliato", family: "Negroni", type: "cocktail", aliases: ["sbagliato"] },
  { canonical: "Boulevardier", family: "Negroni", type: "cocktail" },
  { canonical: "White Negroni", family: "Negroni", type: "cocktail" },
  { canonical: "Old Fashioned", family: "Old Fashioned", type: "cocktail", aliases: ["oldfashioned", "old-fashioned"] },
  { canonical: "Martini", family: "Martini", type: "cocktail", aliases: ["dry martini", "gin martini"] },
  { canonical: "Dirty Martini", family: "Martini", type: "cocktail" },
  { canonical: "Vodka Martini", family: "Martini", type: "cocktail" },
  { canonical: "Espresso Martini", family: "Espresso Martini", type: "cocktail", aliases: ["espresso martini"] },
  { canonical: "Margarita", family: "Margarita", type: "cocktail", aliases: ["tommy's margarita", "spicy margarita", "mezcal margarita"] },
  { canonical: "Daiquiri", family: "Daiquiri", type: "cocktail", aliases: ["hemingway daiquiri"] },
  { canonical: "Aperol Spritz", family: "Spritz", type: "cocktail", aliases: ["aperol", "spritz"] },
  { canonical: "Campari Spritz", family: "Spritz", type: "cocktail" },
  { canonical: "Hugo Spritz", family: "Spritz", type: "cocktail", aliases: ["hugo"] },
  { canonical: "Manhattan", family: "Manhattan", type: "cocktail" },
  { canonical: "Whiskey Sour", family: "Sour Cocktail", type: "cocktail", aliases: ["whisky sour"] },
  { canonical: "Amaretto Sour", family: "Sour Cocktail", type: "cocktail" },
  { canonical: "Mojito", family: "Mojito", type: "cocktail" },
  { canonical: "Moscow Mule", family: "Mule", type: "cocktail", aliases: ["mule"] },
  { canonical: "Gin & Tonic", family: "Gin & Tonic", type: "cocktail", aliases: ["gin and tonic", "g&t", "gt", "gin tonic"] },
  { canonical: "Paloma", family: "Paloma", type: "cocktail" },
  { canonical: "Cosmopolitan", family: "Cosmopolitan", type: "cocktail", aliases: ["cosmo"] },
  { canonical: "Piña Colada", family: "Piña Colada", type: "cocktail", aliases: ["pina colada", "colada"] },

  // ── spirits ───────────────────────────────────────────────────────────────
  { canonical: "Whiskey", family: "Whiskey", type: "spirit", aliases: ["whisky", "bourbon", "scotch", "rye"] },
  { canonical: "Tequila", family: "Tequila", type: "spirit", aliases: ["mezcal"] },
  { canonical: "Gin", family: "Gin", type: "spirit" },
  { canonical: "Vodka", family: "Vodka", type: "spirit" },
  { canonical: "Rum", family: "Rum", type: "spirit", aliases: ["dark rum", "white rum"] },
  { canonical: "Brandy", family: "Brandy", type: "spirit", aliases: ["cognac", "armagnac"] },

  // ── soft ──────────────────────────────────────────────────────────────────
  { canonical: "Water", family: "Water", type: "soft", aliases: ["sparkling water", "still water"] },
  { canonical: "Kombucha", family: "Kombucha", type: "soft" },
  { canonical: "Lemonade", family: "Soft Drink", type: "soft", aliases: ["sprite", "7up"] },
  { canonical: "Cola", family: "Soft Drink", type: "soft", aliases: ["coke", "pepsi", "coca cola", "coca-cola"] },
  { canonical: "Orange Juice", family: "Juice", type: "soft", aliases: ["oj", "juice"] },
  { canonical: "Ginger Beer", family: "Soft Drink", type: "soft" },
];

// Similarity threshold for calling two names "the same drink" — ~0.82 lands near
// the user's "90% same" intuition once you account for shared tokens.
const MATCH_THRESHOLD = 0.82;

/** lowercase, drop accents/punctuation, collapse whitespace — the comparison key. */
export function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "") // strip accents (é → e)
    .replace(/[^a-z0-9\s]/g, " ") // punctuation → space (keeps "g&t" ~ "gt")
    .replace(/\s+/g, " ")
    .trim();
}

// ── string similarity: char-level (Levenshtein) blended with token overlap ────
function levenshtein(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  let curr = new Array<number>(b.length + 1);
  for (let i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    [prev, curr] = [curr, prev];
  }
  return prev[b.length];
}

function tokenJaccard(a: string, b: string): number {
  const sa = new Set(a.split(" ").filter(Boolean));
  const sb = new Set(b.split(" ").filter(Boolean));
  if (!sa.size || !sb.size) return 0;
  let inter = 0;
  for (const t of sa) if (sb.has(t)) inter++;
  return inter / (sa.size + sb.size - inter);
}

/** 0..1 similarity of two drink names (already-normalized-tolerant). */
export function similarity(a: string, b: string): number {
  const na = normalize(a);
  const nb = normalize(b);
  if (!na || !nb) return 0;
  if (na === nb) return 1;
  const charRatio = 1 - levenshtein(na, nb) / Math.max(na.length, nb.length);
  const tokenRatio = tokenJaccard(na, nb);
  // Either strong char match OR strong shared vocabulary counts.
  return Math.max(charRatio, tokenRatio);
}

// ── lookup index (built once) ─────────────────────────────────────────────────
interface Indexed {
  def: DrinkDef;
  key: string; // normalized alias or canonical
}
const INDEX: Indexed[] = DRINKS.flatMap((def) => [
  { def, key: normalize(def.canonical) },
  ...(def.aliases ?? []).map((a) => ({ def, key: normalize(a) })),
]);
const BY_KEY = new Map<string, DrinkDef>();
for (const { def, key } of INDEX) if (!BY_KEY.has(key)) BY_KEY.set(key, def);

export interface Canon {
  /** The tidy family/canonical name this drink belongs under. */
  canonical: string;
  /** The wider class it shares with near-twins. */
  family: string;
  type?: DrinkType;
  /** True when it matched the dictionary (exact or fuzzy); false when it's novel. */
  matched: boolean;
}

/**
 * Resolve a free-text drink to its canonical name + family.
 * Exact alias hit first, then a fuzzy fallback (typos, unlisted variants).
 * Unknowns come back as their own canonical (matched: false) — never forced.
 */
export function canonicalize(name: string): Canon {
  const trimmed = name.trim();
  const norm = normalize(trimmed);
  if (!norm) return { canonical: trimmed, family: "Other", matched: false };

  const exact = BY_KEY.get(norm);
  if (exact) return { canonical: exact.canonical, family: exact.family, type: exact.type, matched: true };

  let best: DrinkDef | null = null;
  let bestScore = 0;
  for (const { def, key } of INDEX) {
    const score = similarity(norm, key);
    if (score > bestScore) {
      bestScore = score;
      best = def;
    }
  }
  if (best && bestScore >= MATCH_THRESHOLD) {
    return { canonical: best.canonical, family: best.family, type: best.type, matched: true };
  }
  // Novel drink: it's its own canonical, filed under itself.
  return { canonical: trimmed, family: trimmed, matched: false };
}

/** The family a drink belongs to — for grouping history/counts. */
export function drinkFamily(name: string): string {
  return canonicalize(name).family;
}

/**
 * Autocomplete for the log window. Ranks the user's OWN history first (their
 * words matter most), then the dictionary, by how well each matches what they've
 * typed so far. Case-insensitive, dedup-by-normalized-name, excludes an exact echo.
 */
export function suggestDrinks(query: string, history: string[] = [], n = 6): string[] {
  const q = normalize(query);
  if (!q) return []; // nothing to autocomplete — the log window shows recent chips instead
  const seen = new Set<string>();
  const scored: { display: string; score: number; own: boolean }[] = [];

  function consider(display: string, own: boolean) {
    const key = normalize(display);
    if (!key || seen.has(key)) return;
    let score: number;
    if (key === q) {
      // exact match — don't suggest an exact echo of what's already typed/logged
      return;
    } else if (key.startsWith(q)) {
      score = 0.9;
    } else if (key.includes(q)) {
      score = 0.75;
    } else {
      const sim = similarity(q, key);
      if (sim < 0.55) return; // too far to bother
      score = sim * 0.7;
    }
    seen.add(key);
    scored.push({ display, score: score + (own ? 0.08 : 0), own });
  }

  for (const h of history) consider(h, true);
  for (const d of DRINKS) consider(d.canonical, false);

  return scored.sort((a, b) => b.score - a.score).slice(0, n).map((s) => s.display);
}
