// The passport game — everything here is DERIVED from entries, never stored.
// Twin: packages/brewdiary_core/lib/game.dart (same rules, same test cases).
//
// Built on the Octalysis drives, white-hat first: a rank you grow into (meaning),
// miles and feats (accomplishment), eight collections to fill (ownership), a stamp
// only each season gives (scarcity), first tastes that sometimes come out gilded
// (curiosity), and a gentle "the monsoon stamp closes in 12 days" — never a streak
// to lose.
//
// THE RULE: nothing rewards drinking more. Miles come from range — a first taste,
// a new kind, a new place, a dry night — never from a count. Two first tastes a
// night is the most that counts; one new place a night; every dry night earns, and
// every season and every week has an alcohol-free way through.
import { addDays, parseKey, toKey, todayKey } from "./date";
import { isDryDay } from "./derive";
import { canonicalize, DRINKS, FLAVOURS } from "./drinks";
import type { DrinkType, Entry } from "./types";

export const MILES = { firstTaste: 10, newKind: 25, newPlace: 15, dryNight: 10, collection: 50, quest: 20, season: 30 } as const;
export const FIRST_TASTES_PER_NIGHT = 2;

export type MileSource = keyof typeof MILES;

export interface MileEvent {
  source: MileSource;
  label: string;
  date: string;
  miles: number;
  gilded: boolean;
}
const eventKey = (e: MileEvent) => `${e.source}|${e.label}|${e.date}`;

export interface Rank {
  index: number;
  title: string;
  from: number;
  line: string;
}

export const RANKS: Rank[] = [
  { index: 0, title: "Newcomer", from: 0, line: "The first pages are blank on purpose." },
  { index: 1, title: "Taster", from: 50, line: "You notice what is in the glass." },
  { index: 2, title: "Explorer", from: 150, line: "The menu reads like a map now." },
  { index: 3, title: "Voyager", from: 300, line: "Places and pours you can name." },
  { index: 4, title: "Connoisseur", from: 500, line: "You know what you like, and why." },
  { index: 5, title: "Cartographer", from: 800, line: "You have drawn most of the map." },
  { index: 6, title: "Polymath", from: 1200, line: "Coffee to cognac, all of it yours." },
  { index: 7, title: "Legend", from: 1700, line: "A passport other people ask about." },
];

export function rankFor(miles: number): Rank {
  return [...RANKS].reverse().find((r) => miles >= r.from)!;
}

export interface Collection {
  id: string;
  title: string;
  families: string[];
}

/** Every drink family (but Water) sits in exactly one collection. */
export const COLLECTIONS: Collection[] = [
  { id: "coffee", title: "Coffee bar", families: ["Espresso", "Americano", "Macchiato", "Cortado", "Flat White", "Cappuccino", "Latte", "Mocha", "Cold Brew", "Filter Coffee"] },
  { id: "tea", title: "Tea house", families: ["Chai", "Black Tea", "Green Tea", "Matcha", "Chamomile"] },
  { id: "zero", title: "Zero proof", families: ["Kombucha", "Juice", "Soft Drink"] },
  { id: "brewery", title: "The brewery", families: ["Lager", "Pale Ale", "IPA", "Wheat Beer", "Sour", "Stout"] },
  { id: "cellar", title: "The cellar", families: ["White Wine", "Rosé", "Red Wine", "Sparkling"] },
  { id: "classics", title: "Classic cocktails", families: ["Negroni", "Old Fashioned", "Martini", "Manhattan", "Margarita", "Daiquiri", "Sour Cocktail", "Mojito"] },
  { id: "long", title: "Long & bright", families: ["Spritz", "Gin & Tonic", "Paloma", "Mule", "Cosmopolitan", "Piña Colada", "Espresso Martini"] },
  { id: "backbar", title: "The back bar", families: ["Whiskey", "Tequila", "Gin", "Vodka", "Rum", "Brandy"] },
];

export interface CollectionState {
  collection: Collection;
  tried: Record<string, string>; // family → first date, in the collection's order
  completedOn: string | null;
}

export interface SeasonDef {
  id: string;
  title: string;
  line: string;
  families: string[];
}

export const SEASONS: SeasonDef[] = [
  { id: "winter", title: "Winter warmer", line: "Something warm and deep.", families: ["Chai", "Mocha", "Latte", "Black Tea", "Stout", "Red Wine", "Brandy", "Whiskey", "Old Fashioned"] },
  { id: "spring", title: "Spring bloom", line: "Something green and floral.", families: ["Chamomile", "Green Tea", "Matcha", "Kombucha", "Gin & Tonic", "Spritz", "Rosé", "Mojito", "Gin"] },
  { id: "monsoon", title: "Monsoon", line: "Something for the rain.", families: ["Chai", "Filter Coffee", "Black Tea", "Cappuccino", "Mocha", "Stout", "Whiskey", "Rum"] },
  { id: "harvest", title: "Harvest", line: "Something from the vine and the field.", families: ["Cold Brew", "Americano", "Juice", "Red Wine", "White Wine", "Sparkling", "Wheat Beer", "Brandy", "Manhattan"] },
];

export interface SeasonWindow {
  def: SeasonDef;
  year: number;
  start: string;
  end: string;
  id: string;
  label: string;
}

/** Dec–Feb winter, Mar–May spring, Jun–Sep monsoon, Oct–Nov harvest. */
export function seasonWindow(dayKey: string): SeasonWindow {
  const d = parseKey(dayKey);
  const m = d.getMonth() + 1;
  const y = d.getFullYear();
  const make = (def: SeasonDef, year: number, start: Date, end: Date): SeasonWindow => ({
    def,
    year,
    start: toKey(start),
    end: toKey(end),
    id: `${def.id}-${year}`,
    label: `${def.title} ${year}`,
  });
  if (m === 12 || m <= 2) {
    const wy = m === 12 ? y : y - 1;
    return make(SEASONS[0], wy, new Date(wy, 11, 1), new Date(wy + 1, 2, 0));
  }
  if (m <= 5) return make(SEASONS[1], y, new Date(y, 2, 1), new Date(y, 4, 31));
  if (m <= 9) return make(SEASONS[2], y, new Date(y, 5, 1), new Date(y, 8, 30));
  return make(SEASONS[3], y, new Date(y, 9, 1), new Date(y, 10, 30));
}

export interface SeasonNow {
  window: SeasonWindow;
  daysLeft: number;
  earnedOn: string | null;
  earnedWith: string | null;
  picks: string[];
}

export interface QuestDef {
  id: string;
  title: string;
  line: string;
  target: number;
}

const GENTLE_QUESTS: QuestDef[] = [
  { id: "dry_two", title: "Two quiet nights", line: "Keep two dry nights this week.", target: 2 },
  { id: "free_new", title: "Alcohol-free first", line: "A coffee, tea or soft drink you never have had.", target: 1 },
];
const OTHER_QUESTS: QuestDef[] = [
  { id: "new_family", title: "Something new", line: "A first taste — any drink you have never logged.", target: 1 },
  { id: "new_place", title: "Somewhere new", line: "Log from a place you have never been.", target: 1 },
  { id: "new_note", title: "A new note", line: "A drink with a flavour you have not met yet.", target: 1 },
  { id: "with_friend", title: "Good company", line: "Log a moment with someone — coffee counts.", target: 1 },
  { id: "write_it", title: "Write it down", line: "Add a line to an entry: what made it.", target: 1 },
  { id: "new_kind", title: "A new kind", line: "A kind you have never had — tea, beer, wine…", target: 1 },
];

const mondayIndex = (d: Date) => (d.getDay() + 6) % 7;
const utcDays = (key: string) => {
  const [y, m, d] = key.split("-").map(Number);
  return Date.UTC(y, m - 1, d) / 86_400_000;
};

/** The Monday a day's week starts on. */
export function weekStart(dayKey: string): string {
  const d = parseKey(dayKey);
  return toKey(addDays(d, -mondayIndex(d)));
}

/** Three quests a week — always one with a gentle, alcohol-free way through. */
export function questsForWeek(monday: string): QuestDef[] {
  const w = Math.floor((utcDays(monday) - utcDays("1970-01-05")) / 7);
  const n = OTHER_QUESTS.length;
  const i1 = w % n;
  const i2 = (i1 + 1 + (w % (n - 1))) % n;
  return [GENTLE_QUESTS[w % GENTLE_QUESTS.length], OTHER_QUESTS[i1], OTHER_QUESTS[i2]];
}

export interface QuestState {
  def: QuestDef;
  progress: number;
  doneOn: string | null;
}

export interface FeatDef {
  id: string;
  title: string;
  line: string;
  target: number;
}

export const FEATS: FeatDef[] = [
  { id: "first_page", title: "First page", line: "Log your first moment — a drink or a dry night.", target: 1 },
  { id: "kinds_5", title: "Five kinds", line: "Five kinds of drink, from coffee to cocktails.", target: 5 },
  { id: "zero_3", title: "Zero-proof palate", line: "Three alcohol-free families.", target: 3 },
  { id: "places_3", title: "Local map", line: "Three places in your passport.", target: 3 },
  { id: "quiet_month", title: "Quiet month", line: "Four dry nights in one month.", target: 4 },
  { id: "balanced_week", title: "Balanced week", line: "Two dry nights and a first taste in one week.", target: 1 },
  { id: "notes_8", title: "Wide palate", line: "Eight different flavour notes.", target: 8 },
  { id: "company_3", title: "Good company", line: "Moments with three different people.", target: 3 },
  { id: "full_set", title: "Full set", line: "Complete any collection.", target: 1 },
  { id: "places_10", title: "Wanderer", line: "Ten places in your passport.", target: 10 },
  { id: "kinds_7", title: "Every kind", line: "Coffee, tea, soft, beer, wine, cocktail and spirit.", target: 7 },
  { id: "families_25", title: "Half the map", line: "Twenty-five drink families.", target: 25 },
  { id: "seasons_4", title: "Four seasons", line: "A stamp from every season.", target: 4 },
];

export interface FeatState {
  def: FeatDef;
  progress: number;
  earnedOn: string | null;
}

/** FNV-1a over UTF-16 code units — the same number in Dart and TypeScript. */
export function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** About one first taste in six comes out gilded — fixed by the drink and the day. */
export function isGilded(family: string, date: string): boolean {
  return fnv1a(`${family}|${date}`) % 6 === 0;
}

export interface PassportGame {
  miles: number;
  rank: Rank;
  next: Rank | null;
  progress: number;
  toNext: number;
  ledger: MileEvent[]; // newest first
  collections: CollectionState[];
  feats: FeatState[];
  seasonsEarned: SeasonWindow[];
  season: SeasonNow;
  quests: QuestState[];
  questDaysLeft: number;
  gilded: Set<string>;
  families: number;
}

interface Week {
  dry: number;
  firstTaste: boolean;
  freeNew: boolean;
  newPlace: boolean;
  newNote: boolean;
  withFriend: boolean;
  wrote: boolean;
  newKind: boolean;
}
const newWeek = (): Week => ({ dry: 0, firstTaste: false, freeNew: false, newPlace: false, newNote: false, withFriend: false, wrote: false, newKind: false });

const FREE_KINDS = new Set<DrinkType>(["coffee", "tea", "soft"]);

function questProgress(q: QuestDef, w: Week): number {
  switch (q.id) {
    case "dry_two": return w.dry;
    case "free_new": return w.freeNew ? 1 : 0;
    case "new_family": return w.firstTaste ? 1 : 0;
    case "new_place": return w.newPlace ? 1 : 0;
    case "new_note": return w.newNote ? 1 : 0;
    case "with_friend": return w.withFriend ? 1 : 0;
    case "write_it": return w.wrote ? 1 : 0;
    case "new_kind": return w.newKind ? 1 : 0;
    default: return 0;
  }
}

export function passportGame(entries: Entry[], today?: string): PassportGame {
  const now = today ?? todayKey();
  const sorted = entries
    .filter((e) => e.date <= now)
    .sort((a, b) => (a.date !== b.date ? (a.date < b.date ? -1 : 1) : a.createdAt < b.createdAt ? -1 : a.createdAt > b.createdAt ? 1 : 0));

  const ledger: MileEvent[] = [];
  const families = new Map<string, string>();
  const kinds = new Set<DrinkType>();
  const places = new Set<string>();
  const dry = new Set<string>();
  const notes = new Set<string>();
  const people = new Set<string>();
  const freeFamilies = new Set<string>();
  const gilded = new Set<string>();
  const tastesOn = new Map<string, number>();
  const placeOn = new Set<string>();
  const dryByMonth = new Map<string, number>();
  const weeks = new Map<string, Week>();
  const questDone = new Map<string, string>();
  const seasonEarned = new Map<string, { window: SeasonWindow; date: string; family: string }>();
  const collectionDone = new Map<string, string>();
  const featOn = new Map<string, string>();

  const add = (source: MileSource, label: string, date: string, gild = false) =>
    ledger.push({ source, label, date, miles: MILES[source], gilded: gild });
  const feat = (id: string, value: number, date: string) => {
    const d = FEATS.find((f) => f.id === id)!;
    if (value >= d.target && !featOn.has(id)) featOn.set(id, date);
  };
  const seasonKinds = () => new Set([...seasonEarned.values()].map((s) => s.window.def.id)).size;

  for (const e of sorted) {
    const monday = weekStart(e.date);
    if (!weeks.has(monday)) weeks.set(monday, newWeek());
    const w = weeks.get(monday)!;
    feat("first_page", 1, e.date);

    const who = e.whoWith ?? [];
    if (who.length) w.withFriend = true;
    for (const p of who) {
      const k = p.trim().toLowerCase();
      if (k) people.add(k);
    }
    feat("company_3", people.size, e.date);
    if ((e.note ?? "").trim()) w.wrote = true;

    const place = e.venue?.trim();
    if (place && !places.has(place.toLowerCase())) {
      places.add(place.toLowerCase());
      w.newPlace = true;
      if (!placeOn.has(e.date)) {
        placeOn.add(e.date);
        add("newPlace", place, e.date);
      }
      feat("places_3", places.size, e.date);
      feat("places_10", places.size, e.date);
    }

    if (isDryDay(e)) {
      if (!dry.has(e.date)) {
        dry.add(e.date);
        w.dry++;
        add("dryNight", "Dry night", e.date);
        const m = e.date.slice(0, 7);
        dryByMonth.set(m, (dryByMonth.get(m) ?? 0) + 1);
        feat("quiet_month", dryByMonth.get(m)!, e.date);
      }
    } else {
      const c = canonicalize(e.drink);
      const t = e.type ?? c.type;
      if (t && t !== "none" && t !== "other" && !kinds.has(t)) {
        kinds.add(t);
        w.newKind = true;
        add("newKind", t, e.date);
        feat("kinds_5", kinds.size, e.date);
        feat("kinds_7", kinds.size, e.date);
      }
      if (c.matched && c.family !== "Water" && !families.has(c.family)) {
        families.set(c.family, e.date);
        w.firstTaste = true;
        const g = isGilded(c.family, e.date);
        if (g) gilded.add(c.family);
        const n = tastesOn.get(e.date) ?? 0;
        if (n < FIRST_TASTES_PER_NIGHT) {
          tastesOn.set(e.date, n + 1);
          add("firstTaste", c.family, e.date, g);
        }
        feat("families_25", families.size, e.date);
        if (t && FREE_KINDS.has(t)) {
          freeFamilies.add(c.family);
          w.freeNew = true;
          feat("zero_3", freeFamilies.size, e.date);
        }
        for (const note of FLAVOURS[c.family] ?? []) {
          if (!notes.has(note)) {
            notes.add(note);
            w.newNote = true;
          }
        }
        feat("notes_8", notes.size, e.date);
        for (const col of COLLECTIONS) {
          if (!col.families.includes(c.family) || collectionDone.has(col.id)) continue;
          if (col.families.every((f) => families.has(f))) {
            collectionDone.set(col.id, e.date);
            add("collection", col.title, e.date);
            feat("full_set", 1, e.date);
          }
        }
      }
      if (c.matched) {
        const sw = seasonWindow(e.date);
        if (sw.def.families.includes(c.family) && !seasonEarned.has(sw.id)) {
          seasonEarned.set(sw.id, { window: sw, date: e.date, family: c.family });
          add("season", sw.label, e.date);
          feat("seasons_4", seasonKinds(), e.date);
        }
      }
    }

    if (w.dry >= 2 && w.firstTaste) feat("balanced_week", 1, e.date);
    for (const q of questsForWeek(monday)) {
      const k = `${monday}|${q.id}`;
      if (questDone.has(k)) continue;
      if (questProgress(q, w) >= q.target) {
        questDone.set(k, e.date);
        add("quest", q.title, e.date);
      }
    }
  }

  const miles = ledger.reduce((s, x) => s + x.miles, 0);
  const rank = rankFor(miles);
  const next = rank.index + 1 < RANKS.length ? RANKS[rank.index + 1] : null;

  const thisMonday = weekStart(now);
  const tw = weeks.get(thisMonday) ?? newWeek();
  const quests = questsForWeek(thisMonday).map((q) => ({
    def: q,
    progress: Math.min(questProgress(q, tw), q.target),
    doneOn: questDone.get(`${thisMonday}|${q.id}`) ?? null,
  }));

  const sw = seasonWindow(now);
  const earned = seasonEarned.get(sw.id);
  const picks = [...sw.def.families.filter((f) => !families.has(f)), ...sw.def.families.filter((f) => families.has(f))];

  const dryBest = Math.max(0, ...dryByMonth.values());
  const progressOf = (id: string): number => {
    switch (id) {
      case "first_page": return sorted.length ? 1 : 0;
      case "kinds_5": case "kinds_7": return kinds.size;
      case "zero_3": return freeFamilies.size;
      case "places_3": case "places_10": return places.size;
      case "quiet_month": return dryBest;
      case "balanced_week": return featOn.has("balanced_week") ? 1 : 0;
      case "notes_8": return notes.size;
      case "company_3": return people.size;
      case "full_set": return collectionDone.size;
      case "families_25": return families.size;
      case "seasons_4": return seasonKinds();
      default: return 0;
    }
  };

  return {
    miles,
    rank,
    next,
    progress: next ? (miles - rank.from) / (next.from - rank.from) : 1,
    toNext: next ? next.from - miles : 0,
    ledger: [...ledger].reverse(),
    collections: COLLECTIONS.map((col) => ({
      collection: col,
      tried: Object.fromEntries(col.families.filter((f) => families.has(f)).map((f) => [f, families.get(f)!])),
      completedOn: collectionDone.get(col.id) ?? null,
    })),
    feats: FEATS.map((f) => ({ def: f, progress: Math.min(progressOf(f.id), f.target), earnedOn: featOn.get(f.id) ?? null })),
    seasonsEarned: [...seasonEarned.values()].map((s) => s.window),
    season: { window: sw, daysLeft: utcDays(sw.end) - utcDays(now), earnedOn: earned?.date ?? null, earnedWith: earned?.family ?? null, picks },
    quests,
    questDaysLeft: 6 - mondayIndex(parseKey(now)),
    gilded,
    families: families.size,
  };
}

export interface Unlocks {
  events: MileEvent[];
  feats: FeatDef[];
  rankUp: Rank | null;
}

/** What a save added — for the little moment after you log. */
export function unlocksBetween(before: PassportGame, after: PassportGame): Unlocks {
  const had = new Set(before.ledger.map(eventKey));
  const hadFeats = new Set(before.feats.filter((f) => f.earnedOn).map((f) => f.def.id));
  return {
    events: [...after.ledger].reverse().filter((e) => !had.has(eventKey(e))),
    feats: after.feats.filter((f) => f.earnedOn && !hadFeats.has(f.def.id)).map((f) => f.def),
    rankUp: after.rank.index > before.rank.index ? after.rank : null,
  };
}

/** Every family the dictionary knows (for the collection test). */
export const KNOWN_FAMILIES = [...new Set(DRINKS.map((d) => d.family))];
