import { describe, expect, it } from "vitest";
import { perkPolicy } from "@/lib/perks";
import { VENUE_KINDS, isCounter, legalClass, sellsAlcohol } from "@/lib/venueKinds";

// Mirrors venue_legal_class() / venue_is_counter() in supabase/047 (db:audit checks the
// same truth table against the live function) and mobile-bar/lib/logic/venue_kinds.dart.
describe("what the law sees is what a place SELLS", () => {
  it("classifies every kind", () => {
    expect(legalClass("bar")).toBe("on_trade");
    expect(legalClass("club")).toBe("on_trade");
    expect(legalClass("store")).toBe("off_trade");
    expect(legalClass("cafe")).toBe("no_alcohol");
    expect(legalClass("cafe", true)).toBe("on_trade");
    expect(legalClass("restaurant", true)).toBe("on_trade");
    expect(legalClass("sweet_shop", true)).toBe("no_alcohol");
    expect(legalClass("bakery")).toBe("no_alcohol");
    expect(legalClass("shop", true)).toBe("no_alcohol");
    expect(sellsAlcohol("bar")).toBe(true);
  });

  it("counters run no rooms", () => {
    expect(VENUE_KINDS.filter(isCounter)).toEqual(["store", "sweet_shop", "bakery", "shop"]);
  });
});

describe("the loyalty card by what's sold", () => {
  it("a sweet shop's card is just a loyalty card — never an alcoholic reward", () => {
    const p = perkPolicy("IN", null, "sweet_shop");
    expect(p.allowPerks).toBe(true);
    expect(p.allowAlcoholReward).toBe(false);
    expect(p.allowSpendPerk).toBe(false); // a counter's spend waits for the till
  });
  it("an unlicensed café in Thailand may run a card (Thailand bans ALCOHOL promotion)", () => {
    const p = perkPolicy("TH", null, "cafe", false);
    expect(p.allowPerks).toBe(true);
    expect(p.allowSpendPerk).toBe(true);
    expect(perkPolicy("TH", null, "cafe", true).allowPerks).toBe(false);
  });
  it("deny by default for every kind", () => {
    expect(perkPolicy("ZW", null, "bakery").allowPerks).toBe(false);
  });
  it("a liquor store keeps the store rules", () => {
    const p = perkPolicy("IN", null, "store");
    expect(p.allowSpendPerk).toBe(false);
    expect(p.allowAlcoholReward).toBe(false);
  });
});
