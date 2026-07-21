import { describe, it, expect } from "vitest";
import { computeScore, paletteScore, scoreInput, scoreFromEntries } from "@/lib/score";
import type { Entry } from "@/lib/types";
import { todayKey, addDays, toKey, parseKey } from "@/lib/date";

let seq = 0;
function e(date: string, drink: string, type: Entry["type"] = "beer"): Entry {
  return { id: `e${seq++}`, date, drink, type, createdAt: `${date}T12:00:00.000Z` };
}

describe("palette score — breadth + consistency, never volume", () => {
  it("is monotonic in each input", () => {
    const base = { kinds: 3, activeDays: 5, longestStreak: 2, monthsActive: 1 };
    const s = computeScore(base);
    expect(computeScore({ ...base, kinds: 4 })).toBeGreaterThan(s);
    expect(computeScore({ ...base, activeDays: 6 })).toBeGreaterThan(s);
    expect(computeScore({ ...base, longestStreak: 3 })).toBeGreaterThan(s);
    expect(computeScore({ ...base, monthsActive: 2 })).toBeGreaterThan(s);
  });

  it("does NOT rise when you log the same drink more (rule #6)", () => {
    const day = todayKey();
    const one = scoreFromEntries([e(day, "Lager")]);
    // three more of the SAME drink on the SAME day — pure volume
    const many = scoreFromEntries([e(day, "Lager"), e(day, "Lager"), e(day, "Lager"), e(day, "Lager")]);
    expect(many.score).toBe(one.score);
  });

  it("DOES rise for a new distinct drink (breadth) and a new day (consistency)", () => {
    const day = todayKey();
    const one = scoreFromEntries([e(day, "Lager")]);
    const broader = scoreFromEntries([e(day, "Lager"), e(day, "Espresso", "coffee")]);
    expect(broader.score).toBeGreaterThan(one.score); // +1 kind
    const yesterday = toKey(addDays(parseKey(day), -1));
    const longer = scoreFromEntries([e(day, "Lager"), e(yesterday, "Lager")]);
    expect(longer.score).toBeGreaterThan(one.score); // +1 active day (& streak)
  });

  it("a DRY DAY counts toward the score (showing up, not drinking)", () => {
    const day = todayKey();
    const yesterday = toKey(addDays(parseKey(day), -1));
    const withDry = scoreFromEntries([e(day, "Lager"), e(yesterday, "dry day", "none")]);
    const without = scoreFromEntries([e(day, "Lager")]);
    expect(withDry.score).toBeGreaterThan(without.score);
  });

  it("walks the title ladder and reports progress within a level", () => {
    expect(paletteScore({ kinds: 0, activeDays: 0, longestStreak: 0, monthsActive: 0 }).title).toBe("Newcomer");
    const wanderer = paletteScore({ kinds: 6, activeDays: 2, longestStreak: 0, monthsActive: 0 }); // 84+6 = 90
    expect(wanderer.score).toBe(90);
    expect(wanderer.title).toBe("Wanderer");
    expect(wanderer.intoLevel).toBeGreaterThanOrEqual(0);
    expect(wanderer.intoLevel).toBeLessThanOrEqual(1);
  });

  it("tops out cleanly at the last title", () => {
    const top = paletteScore({ kinds: 400, activeDays: 400, longestStreak: 400, monthsActive: 400 });
    expect(top.title).toBe("Master Cartographer");
    expect(top.nextTitle).toBeNull();
    expect(top.intoLevel).toBe(1);
    expect(top.toNext).toBe(0);
  });

  it("scoreInput reads distinct kinds/days/months off entries", () => {
    const day = todayKey();
    const inp = scoreInput([e(day, "Lager"), e(day, "Lager"), e(day, "Stout")]);
    expect(inp.kinds).toBe(2);
    expect(inp.activeDays).toBe(1);
    expect(inp.monthsActive).toBe(1);
  });
});
