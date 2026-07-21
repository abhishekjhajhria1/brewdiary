import { describe, it, expect } from "vitest";
import { CUP_AXES, CUP_SKINS, isValidCupName, isValidWindow, axisLabel, type CupAxis } from "@/lib/cups";

// The DB CHECK on cups.axis (044) allows exactly these. The client palette must
// never drift outside it, and must never grow a volume/spend axis.
const DB_ALLOWED: CupAxis[] = ["drinks", "venues", "varied", "dry"];

describe("cups — the anti-volume boundary (rule #6, in the axis palette)", () => {
  it("offers no volume or spend axis, by any name", () => {
    const ids = CUP_AXES.map((a) => a.id.toLowerCase());
    for (const banned of ["volume", "spend", "most_drinks", "amount", "count", "total"]) {
      expect(ids).not.toContain(banned);
    }
  });

  it("every offered axis is one the database will actually accept", () => {
    for (const a of CUP_AXES) expect(DB_ALLOWED).toContain(a.id);
  });

  it("every axis has a human label and blurb", () => {
    for (const a of CUP_AXES) {
      expect(a.label.length).toBeGreaterThan(0);
      expect(a.blurb.length).toBeGreaterThan(0);
      expect(axisLabel(a.id)).toBe(a.label);
    }
  });

  it("skins are a fixed cosmetic set (no arbitrary values)", () => {
    expect(CUP_SKINS).toContain("classic");
    expect(CUP_SKINS.length).toBeGreaterThanOrEqual(2);
  });
});

describe("cups — name validation", () => {
  it("rejects empty or whitespace-only names", () => {
    expect(isValidCupName("")).toBe(false);
    expect(isValidCupName("   ")).toBe(false);
  });
  it("accepts a normal name and rejects an over-long one", () => {
    expect(isValidCupName("The Wanderer's Cup")).toBe(true);
    expect(isValidCupName("a".repeat(40))).toBe(true);
    expect(isValidCupName("a".repeat(41))).toBe(false);
  });
});

describe("cups — window validation", () => {
  it("requires both dates and an end no earlier than the start", () => {
    expect(isValidWindow("2026-07-21", "2026-07-28")).toBe(true);
    expect(isValidWindow("2026-07-21", "2026-07-21")).toBe(true);
    expect(isValidWindow("2026-07-28", "2026-07-21")).toBe(false);
    expect(isValidWindow("", "2026-07-28")).toBe(false);
    expect(isValidWindow("2026-07-21", "")).toBe(false);
  });
});
