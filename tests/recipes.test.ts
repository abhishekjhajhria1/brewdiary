import { describe, it, expect } from "vitest";
import { RECIPES, makeable, commonStaples } from "@/lib/recipes";

describe("makeable — only what's already on the shelf", () => {
  it("returns nothing for an empty pantry", () => {
    expect(makeable([])).toEqual([]);
    expect(makeable(["   "])).toEqual([]);
  });

  it("offers a drink only when EVERY required ingredient is there", () => {
    // gin + campari but no vermouth: not a Negroni yet, and we never say so.
    const partial = makeable(["gin", "campari"]).map((m) => m.recipe.name);
    expect(partial).not.toContain("Negroni");

    const full = makeable(["gin", "campari", "sweet vermouth"]).map((m) => m.recipe.name);
    expect(full).toContain("Negroni");
  });

  it("never returns anything the shelf can't make (no shopping prompts, ever)", () => {
    // The one rule that keeps this from being alcohol advertising: no "one away" list.
    const pantry = ["coffee", "milk"];
    for (const { recipe } of makeable(pantry)) {
      expect(recipe.needs.every((n) => pantry.some((p) => n.includes(p) || p.includes(n)))).toBe(true);
    }
  });

  it("treats a soft shelf exactly like a spirits shelf", () => {
    const soft = makeable(["coffee", "milk", "ice"]).map((m) => m.recipe.name);
    expect(soft).toContain("Latte");
    expect(soft).toContain("Iced Latte");
    // …and the same shape of answer comes back for spirits, no richer, no poorer.
    const hard = makeable(["gin", "tonic"]).map((m) => m.recipe.name);
    expect(hard).toContain("Gin & Tonic");
  });

  it("matches plurals and loose wording the way a person types a shelf", () => {
    const names = makeable(["limes", "white rum", "sugar"]).map((m) => m.recipe.name);
    expect(names).toContain("Daiquiri"); // "limes" → lime, "white rum" → rum
  });

  it("surfaces the extras you happen to have, without ever requiring them", () => {
    const plain = makeable(["gin", "campari", "sweet vermouth"]);
    const garnished = makeable(["gin", "campari", "sweet vermouth", "orange", "ice"]);
    expect(plain[0].recipe.name).toBe("Negroni");
    expect(plain[0].extras).toEqual([]);
    expect(garnished.find((m) => m.recipe.name === "Negroni")!.extras).toEqual(["orange", "ice"]);
  });

  it("puts the most-complete drinks first, then settles alphabetically", () => {
    const list = makeable(["gin", "tonic", "lime", "ice", "dry vermouth"]);
    const names = list.map((m) => m.recipe.name);
    // Gin & Tonic has both its extras here; Martini has none of its own.
    expect(names[0]).toBe("Gin & Tonic");
    expect(names).toContain("Martini");
  });
});

describe("the recipe set itself", () => {
  it("is not an alcohol catalogue — soft, coffee and tea are first-class", () => {
    const soft = RECIPES.filter((r) => ["coffee", "tea", "soft"].includes(r.type));
    expect(soft.length).toBeGreaterThanOrEqual(10);
  });

  it("every recipe can actually be made (needs + a method)", () => {
    for (const r of RECIPES) {
      expect(r.needs.length).toBeGreaterThan(0);
      expect(r.method.trim().length).toBeGreaterThan(10);
      expect(r.family.trim()).not.toBe("");
    }
  });

  it("has no duplicate names", () => {
    const names = RECIPES.map((r) => r.name.toLowerCase());
    expect(new Set(names).size).toBe(names.length);
  });
});

describe("commonStaples", () => {
  it("names the ingredients that unlock the most, to help you finish describing the shelf", () => {
    const s = commonStaples(5);
    expect(s.length).toBe(5);
    expect(s).toContain("lime"); // appears across many builds
  });
});
