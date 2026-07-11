import { describe, it, expect } from "vitest";
import { normalize, similarity, canonicalize, drinkFamily, suggestDrinks } from "@/lib/drinks";

describe("normalize", () => {
  it("lowercases, strips accents and punctuation, collapses space", () => {
    expect(normalize("  Flat-White ")).toBe("flat white");
    expect(normalize("Rosé")).toBe("rose");
    expect(normalize("G&T")).toBe("g t");
  });
});

describe("similarity", () => {
  it("is 1 for the same normalized name", () => {
    expect(similarity("Flat White", "flat-white")).toBe(1);
  });
  it("rates typos high and unrelated drinks low", () => {
    expect(similarity("cappuccino", "cappucino")).toBeGreaterThan(0.85);
    expect(similarity("espresso", "chamomile")).toBeLessThan(0.4);
  });
});

describe("canonicalize", () => {
  it("folds a known alias to its canonical + family", () => {
    const c = canonicalize("flatwhite");
    expect(c.matched).toBe(true);
    expect(c.canonical).toBe("Flat White");
    expect(c.family).toBe("Flat White");
    expect(c.type).toBe("coffee");
  });

  it("catches a typo via fuzzy fallback", () => {
    const c = canonicalize("cappucino");
    expect(c.matched).toBe(true);
    expect(c.canonical).toBe("Cappuccino");
  });

  it("groups near-twins under one family (the 'bigger class')", () => {
    expect(drinkFamily("Negroni")).toBe("Negroni");
    expect(drinkFamily("Negroni Sbagliato")).toBe("Negroni");
    expect(drinkFamily("Boulevardier")).toBe("Negroni");
    expect(drinkFamily("Hazy IPA")).toBe("IPA");
    expect(drinkFamily("West Coast IPA")).toBe("IPA");
  });

  it("leaves a novel drink as its own canonical, unmatched", () => {
    const c = canonicalize("Homebrew kvass #3");
    expect(c.matched).toBe(false);
    expect(c.canonical).toBe("Homebrew kvass #3");
    expect(c.family).toBe("Homebrew kvass #3");
  });
});

describe("suggestDrinks", () => {
  it("prefixes rank first and the user's own history beats the dictionary", () => {
    const out = suggestDrinks("neg", ["Negroni night special"]);
    expect(out[0]).toBe("Negroni night special");
    expect(out).toContain("Negroni");
  });

  it("does not echo an exact history entry back at you", () => {
    const out = suggestDrinks("Negroni", ["Negroni"]);
    expect(out).not.toContain("Negroni");
  });

  it("returns nothing for an empty query with no history", () => {
    expect(suggestDrinks("", [])).toEqual([]);
  });
});
