import { describe, it, expect } from "vitest";
import type { Entry } from "@/lib/types";
import { journey } from "@/lib/journey";

let seq = 0;
function entry(p: Partial<Entry> = {}): Entry {
  seq += 1;
  return { id: `e${seq}`, date: "2026-07-09", createdAt: new Date(2026, 6, 9, 20).toISOString(), drink: "Latte", ...p };
}

describe("journey — the exploration path", () => {
  it("an empty diary has a road but no position (frontier -1), all nodes dim", () => {
    const j = journey([]);
    expect(j.nodes.length).toBeGreaterThan(5);
    expect(j.frontier).toBe(-1);
    expect(j.nodes.every((n) => !n.reached)).toBe(true);
  });

  it("one drink lights the first node and parks you there", () => {
    const j = journey([entry({ drink: "Latte" })]);
    expect(j.nodes[0].reached).toBe(true);
    expect(j.frontier).toBe(0);
    expect(j.exploredFamilies).toBe(1);
  });

  it("BREADTH not volume: five of the same drink never advances past the first node", () => {
    const same = [1, 2, 3, 4, 5].map(() => entry({ drink: "Latte" }));
    const j = journey(same);
    expect(j.exploredFamilies).toBe(1);
    expect(j.nodes.find((n) => n.id === "fam3")!.reached).toBe(false);
    expect(j.frontier).toBe(0);
  });

  it("five distinct families reaches the '3 families' and '5 families' landmarks", () => {
    const five = ["Latte", "IPA", "Negroni", "Cold Brew", "Mojito"].map((d) => entry({ drink: d }));
    const j = journey(five);
    expect(j.nodes.find((n) => n.id === "fam5")!.reached).toBe(true);
    expect(j.exploredFamilies).toBe(5);
    expect(j.frontier).toBeGreaterThanOrEqual(3);
  });

  it("an off-map find lights the 'Off the map' landmark", () => {
    const j = journey([entry({ drink: "Grandma's secret punch" })]);
    expect(j.nodes.find((n) => n.id === "offmap")!.reached).toBe(true);
  });
});
