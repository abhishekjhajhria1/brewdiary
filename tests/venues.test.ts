import { describe, it, expect } from "vitest";
import { slugify, isValidSlug } from "@/lib/venues";

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
