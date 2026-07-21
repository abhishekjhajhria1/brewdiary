import { describe, it, expect } from "vitest";
import type { Entry } from "@/lib/types";
import { adjacentStamps, familyCatalog, passport, palateNeighbours, weeklyDiscovery } from "@/lib/passport";
import { recapVisible } from "@/lib/recap";

// Build a valid drink Entry with sensible defaults.
let seq = 0;
function entry(p: Partial<Entry> = {}): Entry {
  seq += 1;
  return {
    id: `e${seq}`,
    date: "2026-07-09",
    createdAt: new Date(2026, 6, 9, 20, 0, 0).toISOString(),
    drink: "Latte",
    ...p,
  };
}

describe("familyCatalog", () => {
  it("groups dictionary families into worlds by type, without duplicates", () => {
    const cat = familyCatalog();
    const coffee = cat.find((w) => w.type === "coffee");
    expect(coffee).toBeTruthy();
    expect(coffee!.families).toContain("Latte");
    // "Latte" and "Iced Latte" share the Latte family — it appears once.
    expect(coffee!.families.filter((f) => f === "Latte").length).toBe(1);
    // Cocktails are their own world.
    expect(cat.find((w) => w.type === "cocktail")!.families).toContain("Negroni");
  });
});

describe("passport — breadth, never volume", () => {
  it("logging the same family many times is ONE stamp (repeats earn nothing)", () => {
    const p = passport([entry({ drink: "Latte" }), entry({ drink: "latte" }), entry({ drink: "Iced Latte" })]);
    const latte = p.worlds.find((w) => w.type === "coffee")!.stamps.find((s) => s.family === "Latte")!;
    expect(latte.explored).toBe(true);
    // "Latte", "latte", "Iced Latte" all fold into the Latte family → one explored stamp.
    expect(p.exploredFamilies).toBe(1);
  });

  it("a non-alcoholic family advances the map identically to a spirit", () => {
    expect(passport([entry({ drink: "Latte" })]).exploredFamilies).toBe(1);
    expect(passport([entry({ drink: "Negroni" })]).exploredFamilies).toBe(1);
  });

  it("a dry day is neutral — no stamp, no off-map region", () => {
    const p = passport([entry({ drink: "dry day", type: "none" })]);
    expect(p.exploredFamilies).toBe(0);
    expect(p.offMap.length).toBe(0);
  });

  it("counts distinct drinks in a family in your own words", () => {
    const p = passport([entry({ drink: "Espresso" }), entry({ drink: "doppio" })]); // both Espresso family
    const espresso = p.worlds.find((w) => w.type === "coffee")!.stamps.find((s) => s.family === "Espresso")!;
    expect(espresso.drinks.sort()).toEqual(["Espresso", "doppio"]);
  });
});

describe("passport — off-map discoveries", () => {
  it("a novel drink becomes its own region, never forced into a family", () => {
    const p = passport([entry({ drink: "Zzyzx Fizzwallop" })]);
    expect(p.offMap.length).toBe(1);
    expect(p.offMap[0].matched).toBe(false);
    expect(p.worlds.every((w) => w.exploredCount === 0)).toBe(true);
    expect(p.exploredFamilies).toBe(1); // off-map still counts as palate breadth
  });
});

describe("passport — palate shape & keepsake", () => {
  it("palateShape counts distinct families explored per type", () => {
    const p = passport([entry({ drink: "Latte" }), entry({ drink: "Espresso" }), entry({ drink: "Negroni" })]);
    expect(p.palateShape.coffee).toBe(2); // Latte + Espresso
    expect(p.palateShape.cocktail).toBe(1);
  });

  it("firstExplored keeps the earliest day you entered a family", () => {
    const p = passport([entry({ drink: "Latte", date: "2026-05-10" }), entry({ drink: "Latte", date: "2026-03-01" })]);
    const latte = p.worlds.find((w) => w.type === "coffee")!.stamps.find((s) => s.family === "Latte")!;
    expect(latte.firstExplored).toBe("2026-03-01");
  });
});

describe("palateNeighbours — widens, never deepens", () => {
  const entries = [entry({ drink: "Latte" })]; // explored: coffee only
  const friends = [
    { drink: "IPA", author: "A" },
    { drink: "ipa", author: "B" }, // 2 distinct friends pour the IPA family
    { drink: "Negroni", author: "A" }, // 1 friend
  ];

  it("never suggests an explored family, and ranks a friend-favourite first", () => {
    const picks = palateNeighbours(entries, friends, [], 4);
    const fams = picks.map((s) => s.family);
    expect(fams).not.toContain("Latte"); // explored
    expect(picks.every((s) => s.explored === false)).toBe(true);
    expect(fams[0]).toBe("IPA"); // 2 friends beats everything else
  });

  it("leaves out anything already on the wishlist", () => {
    const picks = palateNeighbours(entries, friends, ["IPA"], 4);
    expect(picks.map((s) => s.family)).not.toContain("IPA");
  });

  it("always seeds at least one suggestion from a world you haven't entered", () => {
    // explored only coffee, no friends → the widener must reach beyond coffee
    const picks = palateNeighbours(entries, [], [], 4);
    expect(picks.some((s) => s.type !== "coffee")).toBe(true);
  });
});

describe("weeklyDiscovery", () => {
  it("surfaces stamps first lit in the last 7 days, not older ones", () => {
    const today = "2026-07-17";
    const wd = weeklyDiscovery(
      [entry({ drink: "Latte", date: "2026-07-15" }), entry({ drink: "Negroni", date: "2026-01-01" })],
      { today },
    );
    const fams = wd.newStamps.map((s) => s.family);
    expect(fams).toContain("Latte"); // within the window
    expect(fams).not.toContain("Negroni"); // logged in January
    expect(wd.nudge === null || wd.nudge.explored === false).toBe(true); // a door, never something you've done
  });
});

describe("adjacentStamps — every stamp is a door, never a dead end", () => {
  it("offers only UNEXPLORED families from the same world (widen, never deepen)", () => {
    const entries = [entry({ drink: "Latte" }), entry({ drink: "Espresso" })];
    const latte = passport(entries)
      .worlds.find((w) => w.type === "coffee")!
      .stamps.find((s) => s.family === "Latte")!;
    const next = adjacentStamps(entries, latte);

    expect(next.length).toBeGreaterThan(0);
    expect(next.every((s) => s.type === "coffee")).toBe(true); // same world
    expect(next.every((s) => !s.explored)).toBe(true); // never something you already drink
    expect(next.map((s) => s.family)).not.toContain("Latte"); // never itself
    expect(next.map((s) => s.family)).not.toContain("Espresso"); // never an explored neighbour
  });

  it("gives an off-map (novel) stamp no neighbours — it has no world to be adjacent in", () => {
    const entries = [entry({ drink: "Grandpa's punch" })];
    const own = passport(entries).offMap[0];
    expect(own.matched).toBe(false);
    expect(adjacentStamps(entries, own)).toEqual([]);
  });
});

describe("recapVisible — off unless asked for, quiet after a dismissal", () => {
  it("is off by default", () => {
    expect(recapVisible({}, "2026-07-17")).toBe(false);
  });

  it("shows once switched on", () => {
    expect(recapVisible({ on: true }, "2026-07-17")).toBe(true);
  });

  it("stays gone for a week after a dismissal, then quietly returns", () => {
    expect(recapVisible({ on: true, dismissed: "2026-07-16" }, "2026-07-17")).toBe(false); // yesterday
    expect(recapVisible({ on: true, dismissed: "2026-07-11" }, "2026-07-17")).toBe(false); // six days — still quiet
    expect(recapVisible({ on: true, dismissed: "2026-07-10" }, "2026-07-17")).toBe(true); // a full week later
  });
})
