// The passport game. Twin: packages/brewdiary_core/test/game_test.dart — the same
// cases, the same numbers, so the two copies can't drift.
import { describe, expect, it } from "vitest";
import {
  COLLECTIONS,
  KNOWN_FAMILIES,
  fnv1a,
  isGilded,
  passportGame,
  questsForWeek,
  rankFor,
  seasonWindow,
  unlocksBetween,
  weekStart,
  type MileSource,
} from "@/lib/passportGame";
import type { DrinkType, Entry } from "@/lib/types";

let seq = 0;
function e(date: string, drink: string, p: { type?: DrinkType; venue?: string; who?: string[]; note?: string } = {}): Entry {
  seq++;
  return {
    id: `g${seq}`,
    date,
    createdAt: `${date}T20:${String(seq % 60).padStart(2, "0")}:00.000Z`,
    drink,
    type: p.type,
    venue: p.venue,
    whoWith: p.who,
    note: p.note,
  };
}
const dry = (date: string) => e(date, "Dry day", { type: "none" });

// A fortnight in September 2026 (Mon 14 → Sun 27).
const diary = [
  e("2026-09-14", "Negroni", { venue: "Soka" }),
  e("2026-09-14", "Paloma", { venue: "Soka" }),
  e("2026-09-14", "Margarita", { venue: "Bar Termini" }), // third first taste, second place: neither counts tonight
  dry("2026-09-15"),
  e("2026-09-16", "Flat White", { who: ["Mira"] }),
  dry("2026-09-17"),
  e("2026-09-19", "Negroni", { venue: "Soka" }), // the second Negroni earns nothing
  e("2026-09-21", "Chai", { note: "Ginger, a lot of it" }),
  e("2026-09-22", "Kombucha", { venue: "Third Wave" }),
  dry("2026-09-23"),
  e("2026-09-24", "Stout", { who: ["Arjun", "Mira"] }),
];

describe("passport game", () => {
  it("every family but Water sits in exactly one collection", () => {
    const all = new Set(KNOWN_FAMILIES.filter((f) => f !== "Water"));
    const placed = COLLECTIONS.flatMap((c) => c.families);
    expect(new Set(placed)).toEqual(all);
    expect(placed.length).toBe(all.size);
  });

  it("ranks climb with miles", () => {
    expect(rankFor(0).title).toBe("Newcomer");
    expect(rankFor(49).title).toBe("Newcomer");
    expect(rankFor(50).title).toBe("Taster");
    expect(rankFor(1700).title).toBe("Legend");
  });

  it("seasons: winter belongs to its December", () => {
    expect(seasonWindow("2027-01-15").id).toBe("winter-2026");
    expect(seasonWindow("2026-12-01").end).toBe("2027-02-28");
    expect(seasonWindow("2026-07-01").id).toBe("monsoon-2026");
    expect(seasonWindow("2026-10-31").def.id).toBe("harvest");
    expect(seasonWindow("2026-04-02").start).toBe("2026-03-01");
  });

  it("quests: three a week, one always gentle, fixed by the week", () => {
    expect(weekStart("2026-09-27")).toBe("2026-09-21");
    expect(questsForWeek("2026-09-14").map((q) => q.id)).toEqual(["dry_two", "new_family", "write_it"]);
    expect(questsForWeek("2026-09-21").map((q) => q.id)).toEqual(["free_new", "new_place", "new_family"]);
    for (let i = 0; i < 40; i++) {
      const ids = questsForWeek(`2026-${String(1 + Math.floor(i / 4)).padStart(2, "0")}-0${1 + (i % 4)}`).map((q) => q.id);
      expect(new Set(ids).size).toBe(3);
      expect(["dry_two", "free_new"]).toContain(ids[0]);
    }
  });

  it("gilding is fixed by the drink and the day", () => {
    expect(fnv1a("")).toBe(0x811c9dc5);
    expect(fnv1a("Paloma|2026-09-14")).toBe(1528518063);
    expect(isGilded("Kombucha", "2026-09-22")).toBe(true);
  });

  it("miles come from range, never volume", () => {
    const g = passportGame(diary, "2026-09-27");
    const by: Partial<Record<MileSource, number>> = {};
    for (const x of g.ledger) by[x.source] = (by[x.source] ?? 0) + x.miles;
    expect(by.firstTaste).toBe(60);
    expect(by.newKind).toBe(125);
    expect(by.newPlace).toBe(30);
    expect(by.dryNight).toBe(30);
    expect(by.season).toBe(30);
    expect(g.ledger.filter((x) => x.source === "season").map((x) => x.label)).toEqual(["Monsoon 2026"]);
    expect(by.quest).toBe(100);
    expect(g.miles).toBe(375);
    expect(g.rank.title).toBe("Voyager");
    expect(g.next?.title).toBe("Connoisseur");
    expect(g.toNext).toBe(125);
    expect(g.families).toBe(7);
  });

  it("collections, feats and this week", () => {
    const g = passportGame(diary, "2026-09-27");
    const classics = g.collections.find((c) => c.collection.id === "classics")!;
    expect(Object.keys(classics.tried)).toEqual(["Negroni", "Margarita"]);
    expect(g.feats.filter((f) => f.earnedOn).map((f) => f.def.id)).toEqual(["first_page", "kinds_5", "zero_3", "places_3", "balanced_week", "notes_8"]);
    expect(g.feats.find((f) => f.def.id === "company_3")!.progress).toBe(2);
    expect(g.quests.map((q) => [q.def.id, q.progress, !!q.doneOn])).toEqual([["free_new", 1, true], ["new_place", 1, true], ["new_family", 1, true]]);
    expect([...g.gilded]).toEqual(["Kombucha"]);
    expect(g.questDaysLeft).toBe(0);
    expect(g.season.window.id).toBe("monsoon-2026");
    expect(g.season.daysLeft).toBe(3);
    expect(g.season.earnedWith).toBe("Chai");
    expect(g.season.picks[0]).toBe("Filter Coffee");
    expect(g.season.picks.slice(6)).toEqual(["Chai", "Stout"]);
  });

  it("an empty diary is a Newcomer with everything ahead", () => {
    const g = passportGame([], "2026-09-27");
    expect(g.miles).toBe(0);
    expect(g.rank.title).toBe("Newcomer");
    expect(g.ledger).toEqual([]);
    expect(g.feats.filter((f) => f.earnedOn)).toEqual([]);
    expect(g.season.earnedOn).toBeNull();
    expect(g.quests).toHaveLength(3);
  });

  it("unlocks: what a save added", () => {
    const before = passportGame(diary.slice(0, 3), "2026-09-14");
    const after = passportGame([...diary.slice(0, 3), e("2026-09-14", "Espresso")], "2026-09-14");
    const u = unlocksBetween(before, after);
    expect(u.events.map((x) => [x.source, x.label, x.miles])).toEqual([["newKind", "coffee", 25]]);
    expect(Object.keys(after.collections.find((c) => c.collection.id === "coffee")!.tried)).toEqual(["Espresso"]);
  });
});
