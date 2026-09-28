import { describe, it, expect } from "vitest";
import type { Entry } from "@/lib/types";
import { toKey, addDays, parseKey, todayKey } from "@/lib/date";
import {
  countsByDate,
  intensityLevel,
  currentStreak,
  longestStreak,
  milestoneProgress,
  lexicon,
  recentDrinks,
  stats,
  tasteProfile,
  friendPicks,
} from "@/lib/derive";

// Build a valid Entry with sensible defaults.
let seq = 0;
function entry(p: Partial<Entry> = {}): Entry {
  seq += 1;
  return {
    id: `e${seq}`,
    date: "2026-07-09",
    createdAt: new Date(2026, 6, 9, 20, 0, 0).toISOString(),
    drink: "Negroni",
    ...p,
  };
}

// A day-key N days before today (keeps streak tests independent of the real date).
const dayBack = (n: number) => toKey(addDays(new Date(), -n));

describe("intensityLevel", () => {
  it("buckets a day's count into 0..4", () => {
    expect(intensityLevel(0)).toBe(0);
    expect(intensityLevel(1)).toBe(1);
    expect(intensityLevel(2)).toBe(2);
    expect(intensityLevel(3)).toBe(3);
    expect(intensityLevel(9)).toBe(4);
  });
});

describe("countsByDate", () => {
  it("counts multiple entries on the same day", () => {
    const counts = countsByDate([entry({ date: "2026-07-09" }), entry({ date: "2026-07-09" }), entry({ date: "2026-07-08" })]);
    expect(counts.get("2026-07-09")).toBe(2);
    expect(counts.get("2026-07-08")).toBe(1);
  });
});

describe("currentStreak (with grace)", () => {
  it("counts consecutive logged days back from today", () => {
    const counts = countsByDate([entry({ date: dayBack(0) }), entry({ date: dayBack(1) }), entry({ date: dayBack(2) })]);
    expect(currentStreak(counts)).toBe(3);
  });

  it("an empty today does not break the streak", () => {
    const counts = countsByDate([entry({ date: dayBack(1) }), entry({ date: dayBack(2) })]);
    expect(currentStreak(counts)).toBe(2);
  });

  it("forgives one missed day but two misses in a row end it", () => {
    // logged today and day-2, but day-1 and day-3/day-4 missed
    const counts = countsByDate([entry({ date: dayBack(0) }), entry({ date: dayBack(2) })]);
    expect(currentStreak(counts)).toBe(2); // grace bridges day-1; day-3+day-4 misses stop it
  });

  it("grace replenishes — separated single misses don't end the streak", () => {
    // logged 0, 2, 4 — days 1 and 3 each missed in isolation
    const counts = countsByDate([entry({ date: dayBack(0) }), entry({ date: dayBack(2) }), entry({ date: dayBack(4) })]);
    expect(currentStreak(counts)).toBe(3);
  });

  it("is 0 with no entries", () => {
    expect(currentStreak(countsByDate([]))).toBe(0);
  });
});

describe("longestStreak (with grace)", () => {
  it("finds the longest run and bridges a single gap", () => {
    // 1,2, gap on 3, 4,5 → grace bridges the gap → run of 4
    const counts = countsByDate([
      entry({ date: "2026-06-01" }),
      entry({ date: "2026-06-02" }),
      entry({ date: "2026-06-04" }),
      entry({ date: "2026-06-05" }),
    ]);
    expect(longestStreak(counts)).toBe(4);
  });

  it("bridges any number of isolated gaps, but a double gap breaks the run", () => {
    // 1,2, gap 3, 4, gap 5, 6 → replenishing grace bridges both → run of 4 logged days
    // then gaps 7+8 (two in a row) end it; 9 starts a new run of 1
    const counts = countsByDate([
      entry({ date: "2026-06-01" }),
      entry({ date: "2026-06-02" }),
      entry({ date: "2026-06-04" }),
      entry({ date: "2026-06-06" }),
      entry({ date: "2026-06-09" }),
    ]);
    expect(longestStreak(counts)).toBe(4);
  });

  it("is 0 with no entries", () => {
    expect(longestStreak(countsByDate([]))).toBe(0);
  });
});

describe("milestoneProgress", () => {
  it("reports the reached and next milestone", () => {
    expect(milestoneProgress(0)).toEqual({ reached: null, next: 10 });
    expect(milestoneProgress(10)).toEqual({ reached: 10, next: 25 });
    expect(milestoneProgress(600)).toEqual({ reached: 500, next: null });
  });
});

describe("lexicon", () => {
  it("collects distinct moods by frequency, then alphabetically", () => {
    const lex = lexicon([
      entry({ mood: "cozy" }),
      entry({ mood: "Cozy" }),
      entry({ mood: "happy" }),
      entry({ mood: " " }),
    ]);
    expect(lex).toEqual([
      { word: "cozy", count: 2 },
      { word: "happy", count: 1 },
    ]);
  });
});

describe("recentDrinks", () => {
  it("ranks by frequency, keeping original casing", () => {
    const drinks = recentDrinks([
      entry({ drink: "Negroni", createdAt: "2026-07-01T20:00:00Z" }),
      entry({ drink: "negroni", createdAt: "2026-07-02T20:00:00Z" }),
      entry({ drink: "Cortado", createdAt: "2026-07-03T20:00:00Z" }),
    ]);
    expect(drinks[0]).toBe("negroni"); // most frequent (2), casing from most-recent occurrence
    expect(drinks).toContain("Cortado");
  });
});

describe("friendPicks", () => {
  const fd = [
    { drink: "Negroni", author: "A" },
    { drink: "negroni", author: "B" }, // 2 distinct friends
    { drink: "Martini", author: "A" }, // 1 friend
    { drink: "Cortado", author: "A" }, // I already drink this → excluded
    { drink: "Mezcal", author: "C" }, // on my wishlist → excluded
  ];

  it("ranks by distinct friends, excludes what I drink and what I saved", () => {
    const picks = friendPicks(fd, ["cortado"], ["mezcal"]);
    expect(picks).toEqual(["Negroni", "Martini"]); // Negroni (2 friends) before Martini (1)
  });

  it("respects the limit and keeps display casing", () => {
    const picks = friendPicks(fd, [], [], 1);
    expect(picks).toEqual(["Negroni"]);
  });
});

describe("stats", () => {
  it("totals and counts distinct kinds", () => {
    const s = stats([entry({ drink: "Negroni" }), entry({ drink: "negroni" }), entry({ drink: "Cortado" })]);
    expect(s.total).toBe(3);
    expect(s.kinds).toBe(2); // negroni (case-insensitive) + cortado
  });
});

describe("tasteProfile (the taste card, derived on the device)", () => {
  const t = todayKey();
  const e = (drink: string, type?: Entry["type"], mood?: string, date = t): Entry => ({
    id: Math.random().toString(36),
    date,
    createdAt: `${date}T20:00:00Z`,
    drink,
    type,
    mood,
  });

  it("favourites are families you came back to, most first", () => {
    const p = tasteProfile([
      e("Negroni"), e("Boulevardier"), e("negroni"),
      e("IPA", "beer"), e("Hazy IPA", "beer"),
      e("Pinot Noir"), // once is a visit, not a taste
    ]);
    expect(p.favourites).toEqual(["Negroni", "IPA"]);
    expect(p.kinds[0]).toBe("cocktail");
    expect(p.basedOn).toBe(6);
  });

  it("counts alcohol-free drinks, ignores dry days, and forgets the old diary", () => {
    const old = toKey(addDays(parseKey(t), -400));
    const p = tasteProfile([
      e("Flat white", "coffee", "cozy"), e("Flat white", "coffee", "cozy"), e("Negroni", undefined, "bright"),
      e("dry day", "none"), e("Negroni", undefined, undefined, old),
    ]);
    expect(p.basedOn).toBe(3);
    expect(p.noAlcoholShare).toBeCloseTo(2 / 3);
    expect(p.moods).toEqual(["cozy", "bright"]);
    expect(p.favourites).toEqual(["Flat White"]);
  });

  it("an empty diary is an empty card", () => {
    expect(tasteProfile([])).toEqual({ favourites: [], kinds: [], moods: [], noAlcoholShare: 0, basedOn: 0 });
  });
});
