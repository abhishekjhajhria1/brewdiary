import { describe, it, expect } from "vitest";
import { chunks, PHOTO_DAYS } from "@/lib/photoRetention";

describe("photo retention (057)", () => {
  it("keeps photos a year", () => {
    expect(PHOTO_DAYS).toBe(365);
  });
  it("removes files in batches the storage API accepts", () => {
    expect(chunks([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunks([], 100)).toEqual([]);
    expect(chunks([1], 0)).toEqual([[1]]);
  });
});
