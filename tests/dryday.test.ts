import { describe, it, expect } from "vitest";
import {
  countsByDate,
  loggedDates,
  dryDates,
  drinkEntries,
  isDryDay,
  currentStreak,
  stats,
  recentDrinks,
  yearReview,
} from "../src/lib/derive";
import type { Entry } from "../src/lib/types";
import { addDays, toKey, todayKey } from "../src/lib/date";

// A dry day is the load-bearing idea here: brewdiary's streak counts days you
// showed up to your DIARY, not days you drank. A streak only a drink can extend
// is loss aversion pointed at drinking. So a dry day must KEEP the streak while
// never counting as a drink anywhere else.

const day = (offset: number) => toKey(addDays(new Date(todayKey() + "T00:00:00"), offset));

function drink(date: string, name = "negroni"): Entry {
  return { id: `d${date}${name}`, date, createdAt: `${date}T20:00:00.000Z`, drink: name, type: "cocktail" };
}
function dry(date: string): Entry {
  return { id: `n${date}`, date, createdAt: `${date}T20:00:00.000Z`, drink: "dry day", type: "none" };
}

describe("dry days", () => {
  it("identifies a dry day by type, not by name", () => {
    expect(isDryDay(dry(day(0)))).toBe(true);
    expect(isDryDay(drink(day(0)))).toBe(false);
    // a drink someone happened to name "dry day" is still a drink
    expect(isDryDay({ ...drink(day(0), "dry day"), type: "cocktail" })).toBe(false);
  });

  it("KEEPS the streak — the whole point", () => {
    // drank, drank, then a logged dry day, then drank: an unbroken 4-day chain
    const entries = [drink(day(-3)), drink(day(-2)), dry(day(-1)), drink(day(0))];
    expect(currentStreak(loggedDates(entries))).toBe(4);
  });

  it("keeps a streak alive across several dry days in a row", () => {
    const entries = [drink(day(-4)), dry(day(-3)), dry(day(-2)), dry(day(-1)), drink(day(0))];
    expect(currentStreak(loggedDates(entries))).toBe(5);
  });

  it("a run of dry days ALONE is still a streak (you showed up)", () => {
    const entries = [dry(day(-2)), dry(day(-1)), dry(day(0))];
    expect(currentStreak(loggedDates(entries))).toBe(3);
  });

  it("does NOT shade the mosaic — a dry day is not a drink", () => {
    const entries = [dry(day(-1)), drink(day(0))];
    const counts = countsByDate(entries);
    expect(counts.get(day(-1))).toBeUndefined(); // no amber on a dry day
    expect(counts.get(day(0))).toBe(1);
    // …but the day IS logged, which is what the streak reads
    expect(loggedDates(entries).get(day(-1))).toBe(1);
  });

  it("is reported as its own thing, and never as a drink", () => {
    const entries = [drink(day(-2)), dry(day(-1)), drink(day(0), "old fashioned")];
    const s = stats(entries);
    expect(s.total).toBe(2); // two drinks, not three entries
    expect(s.kinds).toBe(2); // "dry day" is not a kind of drink
    expect(s.dry).toBe(1);
    expect(s.current).toBe(3); // …yet all three days count for the streak
  });

  it("never appears in suggestions or the year review", () => {
    const entries = [dry(day(-2)), dry(day(-1)), drink(day(0))];
    expect(recentDrinks(entries)).not.toContain("dry day");
    expect(recentDrinks(entries)).toEqual(["negroni"]);

    const yr = yearReview(entries);
    expect(yr.total).toBe(1);
    expect(yr.topDrink).toBe("negroni"); // not "dry day", despite being 2× as common
  });

  it("exposes dry days for the calendar's quiet marker", () => {
    const entries = [dry(day(-1)), drink(day(0))];
    expect(dryDates(entries).has(day(-1))).toBe(true);
    expect(dryDates(entries).has(day(0))).toBe(false);
    expect(drinkEntries(entries)).toHaveLength(1);
  });
});
