import { describe, it, expect } from "vitest";
import { recipeMedals, isValidRecipe } from "@/lib/cookbook";

describe("recipe medals — derived from positive reactions, never volume", () => {
  it("awards nothing below bronze", () => {
    expect(recipeMedals({ made: 2, love: 0, totry: 2 })).toEqual([]);
  });

  it("awards the highest tier per kind", () => {
    const medals = recipeMedals({ made: 3, love: 10, totry: 25 });
    expect(medals.map((m) => m.tier)).toEqual(["bronze", "silver", "gold"]);
    expect(medals.map((m) => m.kind)).toEqual(["made", "love", "totry"]);
  });

  it("uses the same thresholds for every kind (no kind is worth more)", () => {
    const a = recipeMedals({ made: 10, love: 0, totry: 0 })[0];
    const b = recipeMedals({ made: 0, love: 10, totry: 0 })[0];
    expect(a.tier).toBe("silver");
    expect(b.tier).toBe("silver");
  });

  it("titles are per-kind flavour, not generic rank-speak", () => {
    const [gold] = recipeMedals({ made: 25, love: 0, totry: 0 });
    expect(gold.title).toBe("A classic now");
  });
});

describe("recipe validation", () => {
  it("requires a name and a method within DB bounds", () => {
    expect(isValidRecipe({ name: "", method: "stir" })).toBe(false);
    expect(isValidRecipe({ name: "Monsoon Fizz", method: "" })).toBe(false);
    expect(isValidRecipe({ name: "Monsoon Fizz", method: "stir & top with soda" })).toBe(true);
    expect(isValidRecipe({ name: "x".repeat(81), method: "stir" })).toBe(false);
    expect(isValidRecipe({ name: "ok", method: "x".repeat(801) })).toBe(false);
  });
});
