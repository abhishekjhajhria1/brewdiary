import { describe, it, expect } from "vitest";
import { perkPolicy, perkPolicyNote } from "../src/lib/perks";
import { jurisdiction, minDrinkingAge, STRICT } from "../src/lib/jurisdiction";

// These assertions encode actual law (research + citations: internal/legal-and-compliance.md).
// If one starts failing, someone has made the app unlawful in a live market — fix the
// code, not the test. Mirrors public.jurisdiction_policy / perk_policy() in 021.

describe("deny by default — the rule that makes the rest safe", () => {
  it("an UNRESEARCHED country gets the strictest setting, not the loosest", () => {
    // This is the whole point of 021. Before it, an unknown place fell through to
    // "anything goes", so launching in a country we'd never read about would have
    // silently done the illegal thing.
    expect(perkPolicy("ZZ")).toEqual({ allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false });
    expect(perkPolicy(undefined)).toEqual({ allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false });
    expect(perkPolicy("")).toEqual({ allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false });
    expect(jurisdiction("ZZ")).toBe(STRICT);
  });

  it("an unknown country's drinking age is 21, never 18", () => {
    expect(minDrinkingAge("ZZ")).toBe(21);
    expect(minDrinkingAge(null)).toBe(21);
  });
});

describe("perkPolicy — a loyalty scheme whose prize isn't alcohol isn't an alcohol loyalty scheme", () => {
  it("India: everything allowed (home market)", () => {
    expect(perkPolicy("IN")).toEqual({ allowPerks: true, allowAlcoholReward: true, allowSpendPerk: true });
  });

  it("Ireland: perks yes, but NO alcohol reward and NO spend-based accrual", () => {
    expect(perkPolicy("IE")).toEqual({ allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false });
  });

  it("UK: a free drink earned by buying drinks IS the statutory 'irresponsible promotion'", () => {
    expect(perkPolicy("GB")).toEqual({ allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false });
  });

  it("Australia: loyalty schemes that encourage drinking are an unacceptable promotion", () => {
    expect(perkPolicy("AU").allowAlcoholReward).toBe(false);
  });

  it("Thailand and Norway: NO perk of any kind (outright promotion bans)", () => {
    expect(perkPolicy("TH").allowPerks).toBe(false);
    expect(perkPolicy("NO").allowPerks).toBe(false);
    expect(perkPolicy("TR").allowPerks).toBe(false);
    expect(perkPolicy("PL").allowPerks).toBe(false);
  });

  it("US: allowed by default, but NOT in Massachusetts or Utah", () => {
    expect(perkPolicy("US", "NY")).toEqual({ allowPerks: true, allowAlcoholReward: true, allowSpendPerk: true });
    expect(perkPolicy("US", "MA")).toEqual({ allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false });
    expect(perkPolicy("US", "UT").allowAlcoholReward).toBe(false);
  });

  it("where alcohol is prohibited, the venue layer is off entirely", () => {
    for (const c of ["SA", "KW", "LY", "IR", "PK", "BD"]) {
      expect(jurisdiction(c).alcoholLegal).toBe(false);
      expect(perkPolicy(c).allowPerks).toBe(false);
    }
  });

  it("is case-insensitive", () => {
    expect(perkPolicy("ie").allowAlcoholReward).toBe(false);
    expect(perkPolicy("us", "ma").allowSpendPerk).toBe(false);
    expect(perkPolicy("in").allowAlcoholReward).toBe(true);
  });

  it("explains itself to the venue rather than silently blocking", () => {
    expect(perkPolicyNote("IE")).toMatch(/Ireland/i);
    expect(perkPolicyNote("GB")).toMatch(/irresponsible promotion/i);
    expect(perkPolicyNote("TH")).toMatch(/Thailand/i);
    expect(perkPolicyNote("US", "MA")).toMatch(/Massachusetts/i);
    expect(perkPolicyNote("ZZ")).toMatch(/haven't confirmed/i); // honest about ignorance
    expect(perkPolicyNote("IN")).toBeNull(); // nothing to warn about at home
  });
});

describe("the legal drinking age is not one number", () => {
  it("uses the real age for each market", () => {
    expect(minDrinkingAge("US")).toBe(21); // NOT 18 — the old hardcoded gate was wrong
    expect(minDrinkingAge("IN")).toBe(21); // varies 18–25 by state; we take the common bar
    expect(minDrinkingAge("JP")).toBe(20);
    expect(minDrinkingAge("TH")).toBe(20);
    expect(minDrinkingAge("KR")).toBe(19);
    expect(minDrinkingAge("CA")).toBe(19);
    expect(minDrinkingAge("GB")).toBe(18);
    expect(minDrinkingAge("FR")).toBe(18);
  });
});
