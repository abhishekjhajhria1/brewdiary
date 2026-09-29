// The heat map's grid — the same answers as packages/brewdiary_core/test/geo_test.dart.
import { describe, expect, it } from "vitest";
import { directionFrom, encodeGeohash, isGeohash, subcells, VENUE_PRECISION } from "@/lib/geohash";

describe("the area heat map grid", () => {
  it("splits an area into 32 neighbourhoods, 8 across and 4 down", () => {
    const g = subcells("tdr1");
    expect(g).toHaveLength(32);
    expect(new Set(g.map((c) => c.cell)).size).toBe(32);
    expect(new Set(g.map((c) => c.col))).toEqual(new Set([0, 1, 2, 3, 4, 5, 6, 7]));
    expect(new Set(g.map((c) => c.row))).toEqual(new Set([0, 1, 2, 3]));
  });

  it("puts the corners where geohash does", () => {
    const at = Object.fromEntries(subcells("tdr1").map((c) => [c.cell, [c.col, c.row]]));
    expect(at.tdr10).toEqual([0, 3]);
    expect(at.tdr1z).toEqual([7, 0]);
    expect(at.tdr1b).toEqual([0, 0]);
    expect(at.tdr1p).toEqual([7, 3]);
    expect(subcells("tdr1")[0].cell).toBe("tdr1b");
  });

  it("reads directions like a person would say them", () => {
    expect(directionFrom("tdr1v9", "tdr1v")).toBe("your own neighbourhood");
    expect(directionFrom("tdr1v", "tdr1y")).toBe("~5 km east");
    expect(directionFrom("tdr1v", "tdr1u")).toBe("~5 km west");
    expect(directionFrom("tdr1v", "tdr1t")).toBe("~5 km south");
    expect(directionFrom("tdr1v", "tdr10")).toBe("~25 km south-west");
    expect(directionFrom("tdr1v", "tdr1b")).toBe("~25 km west");
    expect(directionFrom("tdr1s", "tdr1v")).toBe("~5 km north-east");
  });

  it("accepts geohash characters only", () => {
    expect(isGeohash("tdr1v9")).toBe(true);
    expect(isGeohash("tdr1 main st")).toBe(false);
    expect(isGeohash("tdra")).toBe(false);
    expect(encodeGeohash(12.9716, 77.5946, VENUE_PRECISION)).toBe("tdr1v9");
  });
});
