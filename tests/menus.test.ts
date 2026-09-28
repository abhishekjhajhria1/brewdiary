import { describe, it, expect } from "vitest";
import { checkMenuItem, groupMenu, menuPicks, menuUrl, type Menu } from "@/lib/menus";
import type { Entry } from "@/lib/types";

const row = (over: Record<string, unknown>) => ({
  venue_name: "Soka",
  venue_city: "Bengaluru",
  venue_kind: "bar",
  currency: "INR",
  item_id: "i1",
  section: "Cocktails",
  name: "Negroni",
  description: null,
  price: "450.00",
  kind: "cocktail",
  no_alcohol: false,
  ...over,
});

let n = 0;
const entry = (drink: string, type?: Entry["type"]): Entry => ({
  id: `e${n++}`,
  date: "2026-09-01",
  createdAt: "2026-09-01T20:00:00Z",
  drink,
  type,
});

describe("menuUrl", () => {
  it("is the plain link a tag holds", () => {
    expect(menuUrl("soka")).toBe("https://bwdy.site/m/soka");
    expect(menuUrl("soka", "http://localhost:3000/")).toBe("http://localhost:3000/m/soka");
  });
});

describe("groupMenu", () => {
  it("groups items into sections in the order the rpc returns them", () => {
    const m = groupMenu([
      row({ item_id: "a", section: "Cocktails", name: "Negroni" }),
      row({ item_id: "b", section: "Beer", name: "Hazy IPA", kind: "beer", price: null }),
      row({ item_id: "c", section: "Cocktails", name: "Virgin Mojito", no_alcohol: true, kind: "soft" }),
    ])!;
    expect(m.venueName).toBe("Soka");
    expect(m.sections.map((s) => s.name)).toEqual(["Cocktails", "Beer"]);
    expect(m.sections[0].items.map((i) => i.name)).toEqual(["Negroni", "Virgin Mojito"]);
    expect(m.sections[0].items[0].price).toBe(450);
    expect(m.sections[1].items[0].price).toBeUndefined();
    expect(m.sections[0].items[1].noAlcohol).toBe(true);
  });

  it("a verified venue with no items yet is a menu with no sections; no rows is no venue", () => {
    const m = groupMenu([row({ item_id: null, section: null, name: null })])!;
    expect(m.venueName).toBe("Soka");
    expect(m.sections).toEqual([]);
    expect(groupMenu([])).toBeNull();
  });
});

describe("menuPicks (on the device, from the guest's own diary)", () => {
  const menu: Menu = groupMenu([
    row({ item_id: "neg", name: "Negroni" }),
    row({ item_id: "boul", name: "Boulevardier" }),
    row({ item_id: "ipa", section: "Beer", name: "Hazy IPA", kind: "beer" }),
    row({ item_id: "fries", section: "Food", name: "Fries", kind: "food" }),
    row({ item_id: "tea", section: "Hot", name: "Masala chai", kind: "tea" }),
  ])!;

  it("ranks the family you drink most, and skips what you've already had", () => {
    const picks = menuPicks(menu, [entry("negroni", "cocktail"), entry("Negroni", "cocktail"), entry("IPA", "beer")]);
    expect(picks[0]).toBe("boul"); // same family as your negronis, not one you've had
    expect(picks).toContain("ipa");
    expect(picks).not.toContain("neg");
  });

  it("never suggests food, and says nothing to an empty diary", () => {
    expect(menuPicks(menu, [entry("fries")])).not.toContain("fries");
    expect(menuPicks(menu, [])).toEqual([]);
  });

  it("a dry day is not a taste", () => {
    expect(menuPicks(menu, [entry("dry day", "none")])).toEqual([]);
  });
});

describe("checkMenuItem", () => {
  const ok = { section: "Cocktails", name: "Negroni", noAlcohol: false };
  it("accepts a plain item, with or without a price", () => {
    expect(checkMenuItem(ok)).toBeNull();
    expect(checkMenuItem({ ...ok, price: 450 })).toBeNull();
  });
  it("explains what's wrong in plain words", () => {
    expect(checkMenuItem({ ...ok, name: "  " })).toMatch(/name/);
    expect(checkMenuItem({ ...ok, section: "" })).toMatch(/section/);
    expect(checkMenuItem({ ...ok, price: -1 })).toMatch(/price/);
  });
});
