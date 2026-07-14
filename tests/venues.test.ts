import { describe, it, expect } from "vitest";
import { slugify, isValidSlug } from "@/lib/venues";
import { perkPolicy, perkPolicyNote } from "@/lib/perks";

describe("slugify", () => {
  it("lowercases and hyphenates words", () => {
    expect(slugify("The Daily Tap")).toBe("the-daily-tap");
  });
  it("strips punctuation and collapses separators", () => {
    expect(slugify("Joe's Bar & Grill!!")).toBe("joe-s-bar-grill");
  });
  it("strips accents", () => {
    expect(slugify("Café Crème")).toBe("cafe-creme");
  });
  it("trims leading/trailing hyphens", () => {
    expect(slugify("  --Hello--  ")).toBe("hello");
  });
  it("caps length at 40 with no trailing hyphen", () => {
    const s = slugify("a".repeat(60));
    expect(s.length).toBeLessThanOrEqual(40);
    expect(s.endsWith("-")).toBe(false);
  });
});

describe("isValidSlug", () => {
  it("accepts web-safe slugs of length 2..40", () => {
    expect(isValidSlug("the-daily-tap")).toBe(true);
    expect(isValidSlug("ab")).toBe(true);
    expect(isValidSlug("bar00")).toBe(true);
  });
  it("rejects too-short, edge-hyphen, and illegal characters", () => {
    expect(isValidSlug("a")).toBe(false); // 1 char
    expect(isValidSlug("-lead")).toBe(false);
    expect(isValidSlug("trail-")).toBe(false);
    expect(isValidSlug("Caps")).toBe(false);
    expect(isValidSlug("has space")).toBe(false);
    expect(isValidSlug("a".repeat(41))).toBe(false);
  });
});

// ── off-trade: a bottle shop is not a quieter bar ────────────────────────────
// These assertions are the difference between a loyalty card and a prosecution, so
// they are pinned here as well as in the database. The DB is the authority (030's
// venue_perks_guard); this catches a regression before it ever reaches it.
describe("perkPolicy — off-trade (liquor stores / off-licences)", () => {
  it("a shop needs its OWN country permission — a bar's isn't enough", () => {
    // Ireland lets a bar run a visits card (turn up, get a coffee: nothing is awarded
    // "in relation to the sale of alcohol"). A SHOP can't: there, turning up IS the
    // sale. s.23, Public Health (Alcohol) Act 2018.
    expect(perkPolicy("IE", null, "bar").allowPerks).toBe(true);
    expect(perkPolicy("IE", null, "store").allowPerks).toBe(false);
  });

  it("Northern Ireland has NO perks at all — not even for a bar", () => {
    // Art. 57ZB reaches every licensed premises, on-trade included. It had been
    // silently inheriting Great Britain's row.
    expect(perkPolicy("GB", null, "bar").allowPerks).toBe(true);
    expect(perkPolicy("GB", "NIR", "bar").allowPerks).toBe(false);
    expect(perkPolicy("GB", "NIR", "store").allowPerks).toBe(false);
  });

  it("Scotland keeps its bar card but loses the shop card", () => {
    expect(perkPolicy("GB", "SCT", "bar").allowPerks).toBe(true);
    expect(perkPolicy("GB", "SCT", "store").allowPerks).toBe(false);
  });

  it("a shop's reward is NEVER alcohol — not even in India, where it would be legal", () => {
    // Our rule, tighter than the statute. A bar's alcoholic prize is one poured
    // drink; a bottle shop's is a BOTTLE. "Buy nine, get the tenth free" is exactly
    // the loop this product refuses to build.
    expect(perkPolicy("IN", null, "bar").allowAlcoholReward).toBe(true);
    expect(perkPolicy("IN", null, "store").allowAlcoholReward).toBe(false);
    expect(perkPolicy("US", "NY", "store").allowAlcoholReward).toBe(false);
  });

  it("a shop's card counts VISITS, never spend — spend there IS the alcohol", () => {
    expect(perkPolicy("IN", null, "bar").allowSpendPerk).toBe(true);
    expect(perkPolicy("IN", null, "store").allowSpendPerk).toBe(false);
    expect(perkPolicy("US", null, "store").allowSpendPerk).toBe(false);
  });

  it("an unresearched country denies a shop card, as it denies everything", () => {
    expect(perkPolicy("ZW", null, "store").allowPerks).toBe(false);
    expect(perkPolicy("ZW", null, "bar").allowPerks).toBe(false);
  });

  it("where a shop card is off, the venue is TOLD why", () => {
    expect(perkPolicyNote("IE", null, "store")).toMatch(/off-licence|visit is a purchase/i);
    expect(perkPolicyNote("GB", "NIR", "bar")).toMatch(/Northern Ireland/i);
  });

  it("the four researched off-trade markets do allow a shop card", () => {
    for (const c of ["IN", "US", "GB", "AU"]) {
      expect(perkPolicy(c, null, "store").allowPerks).toBe(true);
    }
  });
});
