import { describe, it, expect } from "vitest";
import { dedupeTags } from "../src/lib/plans";

describe("dedupeTags", () => {
  it("trims, lowercases, and de-dupes", () => {
    expect(dedupeTags([" Negroni ", "negroni", "MEZCAL"])).toEqual(["negroni", "mezcal"]);
  });
  it("drops empties", () => {
    expect(dedupeTags(["", "  ", "gin"])).toEqual(["gin"]);
  });
  it("caps the count at 8 (a wall of tags is noise)", () => {
    const many = Array.from({ length: 20 }, (_, i) => `t${i}`);
    expect(dedupeTags(many).length).toBe(8);
  });
  it("caps each tag's length", () => {
    expect(dedupeTags(["x".repeat(50)])[0].length).toBe(24);
  });
  it("handles undefined", () => {
    expect(dedupeTags(undefined)).toEqual([]);
  });
});
