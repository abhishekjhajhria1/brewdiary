import { describe, it, expect } from "vitest";
import { CHALLENGE_PRESETS, SCORED_KINDS, V2_KINDS, scoreRow } from "@/lib/challenges";

describe("challenge kinds (043): variety and consistency, never volume", () => {
  it("scores each kind from its own count", () => {
    const r = { total: 9, kinds: 4, dates: ["2026-09-01", "2026-09-02", "2026-09-04"], days_kept: 6, dry_nights: 2, new_drinks: 3, new_places: 1, water_days: 5 };
    expect(scoreRow("most_logged", r)).toBe(9);
    expect(scoreRow("most_kinds", r)).toBe(4);
    expect(scoreRow("longest_streak", r)).toBeGreaterThanOrEqual(2);
    expect(scoreRow("days_kept", r)).toBe(6);
    expect(scoreRow("dry_nights", r)).toBe(2);
    expect(scoreRow("new_drinks", r)).toBe(3);
    expect(scoreRow("new_places", r)).toBe(1);
    expect(scoreRow("hydration", r)).toBe(5);
    expect(scoreRow("freeform", r)).toBe(0);
  });

  it("offers the gentle kinds first and the volume-shaped one last", () => {
    expect(SCORED_KINDS[0]).toBe("days_kept");
    expect(SCORED_KINDS.at(-1)).toBe("most_logged");
  });

  it("no preset can be won by drinking more", () => {
    for (const p of CHALLENGE_PRESETS) expect(["most_logged", "most_kinds"]).not.toContain(p.kind);
    for (const p of CHALLENGE_PRESETS) if (p.kind !== "freeform") expect(V2_KINDS).toContain(p.kind);
  });
});
