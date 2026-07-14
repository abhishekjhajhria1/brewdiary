import { describe, it, expect } from "vitest";
import { isAlcoholic, weekBalance } from "@/lib/derive";
import type { Entry } from "@/lib/types";

function entry(date: string, drink: string, type?: Entry["type"]): Entry {
  return { id: `${date}-${drink}`, date, createdAt: `${date}T20:00:00.000Z`, drink, type };
}

describe("isAlcoholic", () => {
  it("trusts an explicitly tagged type", () => {
    expect(isAlcoholic({ drink: "mystery", type: "beer" })).toBe(true);
    expect(isAlcoholic({ drink: "mystery", type: "wine" })).toBe(true);
    expect(isAlcoholic({ drink: "mystery", type: "cocktail" })).toBe(true);
    expect(isAlcoholic({ drink: "mystery", type: "spirit" })).toBe(true);
    expect(isAlcoholic({ drink: "mystery", type: "coffee" })).toBe(false);
    expect(isAlcoholic({ drink: "mystery", type: "tea" })).toBe(false);
    expect(isAlcoholic({ drink: "mystery", type: "soft" })).toBe(false);
  });

  it("infers from the drink name when untagged", () => {
    expect(isAlcoholic({ drink: "IPA" })).toBe(true);
    expect(isAlcoholic({ drink: "Negroni" })).toBe(true);
    expect(isAlcoholic({ drink: "Flat White" })).toBe(false);
    expect(isAlcoholic({ drink: "Matcha" })).toBe(false);
  });

  it("never assumes an unrecognised drink is alcoholic", () => {
    expect(isAlcoholic({ drink: "grandma's kombucha experiment" })).toBe(false);
    expect(isAlcoholic({ drink: "" })).toBe(false);
  });
});

describe("weekBalance", () => {
  const today = "2026-07-13";

  it("counts alcohol in the rolling 7 days and nothing older", () => {
    const entries = [
      entry("2026-07-13", "IPA"), // today
      entry("2026-07-08", "Negroni"), // 5 days ago — inside
      entry("2026-07-07", "Lager"), // 6 days ago — inside (window edge)
      entry("2026-07-06", "Stout"), // 7 days ago — OUTSIDE
    ];
    expect(weekBalance(entries, today).drinks).toBe(3);
  });

  it("ignores non-alcoholic logs entirely", () => {
    const entries = [entry("2026-07-13", "Flat White"), entry("2026-07-12", "Matcha"), entry("2026-07-12", "IPA")];
    const b = weekBalance(entries, today);
    expect(b.drinks).toBe(1);
    expect(b.dryDays).toBe(6); // only 07-12 had alcohol
  });

  it("counts dry days, not dry entries (two drinks on one night = one wet day)", () => {
    const entries = [entry("2026-07-13", "IPA"), entry("2026-07-13", "Lager"), entry("2026-07-13", "Negroni")];
    const b = weekBalance(entries, today);
    expect(b.drinks).toBe(3);
    expect(b.dryDays).toBe(6);
  });

  it("a week with nothing logged is fully dry", () => {
    const b = weekBalance([], today);
    expect(b).toEqual({ drinks: 0, dryDays: 7, windowDays: 7 });
  });

  it("a coffee-only week is fully dry", () => {
    const entries = [entry("2026-07-13", "Latte"), entry("2026-07-11", "Cold Brew")];
    expect(weekBalance(entries, today).dryDays).toBe(7);
  });
});
