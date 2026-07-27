// Orders — the money maths and the diary seam.
//
// These are the three pure helpers out of src/lib/orders.ts, and they are tested
// hard for one reason each:
//   • billTotals    — the three numbers it returns must ADD UP, because 051 has a
//                     CHECK constraint that refuses the row if they don't.
//   • splitEvenly   — a naive divide loses a paise, and a bill that doesn't
//                     reconcile is a bill a venue stops trusting.
//   • drinkLinesFor — this is the payload that gets OFFERED to a guest's diary.
//                     If food leaks through here, the product has broken its own
//                     promise in the most visible possible way.
import { describe, it, expect } from "vitest";
import { billTotals, splitEvenly, drinkLinesFor, type OrderItem, type PricedLine } from "../src/lib/orders";
import { minorPerMajor, fromMinor, toMinor } from "../src/lib/money";

const line = (qty: number, unitPriceMinor: number): PricedLine => ({ qty, unitPriceMinor });

// A full order item, with only the bits drinkLinesFor cares about varying.
const item = (over: Partial<OrderItem>): OrderItem => ({
  id: crypto.randomUUID(),
  orderId: "o1",
  qty: 1,
  unitPriceMinor: 0,
  name: "thing",
  ...over,
});

describe("billTotals", () => {
  it("is all zeroes for an empty ticket", () => {
    expect(billTotals([], 0, 0)).toEqual({ subtotalMinor: 0, taxMinor: 0, totalMinor: 0 });
  });

  it("multiplies qty by unit price", () => {
    // 2 × ₹450.00 + 1 × ₹120.00 = ₹1020.00
    const t = billTotals([line(2, 45000), line(1, 12000)]);
    expect(t.subtotalMinor).toBe(102000);
    expect(t.taxMinor).toBe(0);
    expect(t.totalMinor).toBe(102000);
  });

  it("applies tax as a fraction and rounds to a whole minor unit", () => {
    const t = billTotals([line(1, 33333)], 0.05);
    expect(t.taxMinor).toBe(1667); // 1666.65 → 1667
    expect(t.totalMinor).toBe(33333 + 1667);
  });

  it("takes a tip with no tax", () => {
    const t = billTotals([line(1, 50000)], 0, 7500);
    expect(t).toEqual({ subtotalMinor: 50000, taxMinor: 0, totalMinor: 57500 });
  });

  it("always satisfies the DB's CHECK: total = subtotal + tax + tip", () => {
    for (const [qty, price, rate, tip] of [
      [1, 1, 0.18, 0],
      [3, 12345, 0.05, 999],
      [99, 99999, 0.28, 1],
      [7, 0, 0.5, 250],
    ] as const) {
      const t = billTotals([line(qty, price)], rate, tip);
      expect(t.totalMinor).toBe(t.subtotalMinor + t.taxMinor + tip);
    }
  });

  it("refuses to be poisoned by junk input", () => {
    const t = billTotals(
      [line(NaN, 5000), line(2, Number.POSITIVE_INFINITY), line(1, 2000)],
      Number.NaN,
      Number.NEGATIVE_INFINITY,
    );
    expect(Number.isFinite(t.subtotalMinor)).toBe(true);
    expect(t.subtotalMinor).toBe(2000);
    expect(t.taxMinor).toBe(0);
    expect(t.totalMinor).toBe(2000);
  });

  it("ignores a negative tax rate rather than discounting the bill", () => {
    const t = billTotals([line(1, 10000)], -0.5);
    expect(t.taxMinor).toBe(0);
    expect(t.totalMinor).toBe(10000);
  });
});

describe("splitEvenly", () => {
  it("sums to exactly the total, for awkward numbers", () => {
    const cases: [number, number][] = [
      [100, 3],
      [1, 7],
      [0, 4],
      [10000, 3],
      [99999, 7],
      [1, 1],
      [7, 100],
      [1234567, 13],
    ];
    for (const [total, n] of cases) {
      const parts = splitEvenly(total, n);
      expect(parts).toHaveLength(n);
      expect(parts.reduce((a, b) => a + b, 0)).toBe(total);
    }
  });

  it("gives the remainder to the first payers, deterministically", () => {
    expect(splitEvenly(100, 3)).toEqual([34, 33, 33]);
    expect(splitEvenly(1, 7)).toEqual([1, 0, 0, 0, 0, 0, 0]);
    // same input, same output — no shuffling under a re-render
    expect(splitEvenly(100, 3)).toEqual(splitEvenly(100, 3));
  });

  it("never returns a negative part", () => {
    for (const [total, n] of [
      [-500, 3],
      [0, 5],
      [7, 9],
    ] as const) {
      for (const p of splitEvenly(total, n)) expect(p).toBeGreaterThanOrEqual(0);
    }
  });

  it("returns nothing for a nonsense payer count", () => {
    expect(splitEvenly(1000, 0)).toEqual([]);
    expect(splitEvenly(1000, -2)).toEqual([]);
    expect(splitEvenly(1000, NaN)).toEqual([]);
  });

  it("never invents or loses a unit, across a sweep", () => {
    for (let total = 0; total <= 200; total++) {
      for (let n = 1; n <= 9; n++) {
        const parts = splitEvenly(total, n);
        expect(parts.reduce((a, b) => a + b, 0)).toBe(total);
        // no part is more than one minor unit away from any other
        expect(Math.max(...parts) - Math.min(...parts)).toBeLessThanOrEqual(1);
      }
    }
  });
});

describe("drinkLinesFor", () => {
  const ada = "ada";
  const bob = "bob";

  it("drops food — the diary is a drink diary", () => {
    const items = [
      item({ guestUserId: ada, drinkKey: "negroni", name: "Negroni", qty: 1 }),
      item({ guestUserId: ada, name: "Calamari", qty: 2 }), // no drinkKey → food
      item({ guestUserId: ada, drinkKey: "", name: "Cover charge", qty: 1 }),
    ];
    expect(drinkLinesFor(items, ada)).toEqual([{ drink_key: "negroni", name: "Negroni", qty: 1 }]);
  });

  it("collapses duplicate drink_keys by summing qty", () => {
    const items = [
      item({ guestUserId: ada, drinkKey: "negroni", name: "Negroni", qty: 1 }),
      item({ guestUserId: ada, drinkKey: "negroni", name: "Negroni (house)", qty: 2 }),
      item({ guestUserId: ada, drinkKey: "kingfisher", name: "Kingfisher", qty: 1 }),
    ];
    expect(drinkLinesFor(items, ada)).toEqual([
      // first-seen name wins, so a mid-ticket rename doesn't rewrite history
      { drink_key: "negroni", name: "Negroni", qty: 3 },
      { drink_key: "kingfisher", name: "Kingfisher", qty: 1 },
    ]);
  });

  it("returns only the asked-for guest's lines", () => {
    const items = [
      item({ guestUserId: ada, drinkKey: "negroni", name: "Negroni", qty: 1 }),
      item({ guestUserId: bob, drinkKey: "old-fashioned", name: "Old Fashioned", qty: 4 }),
      item({ drinkKey: "espresso", name: "Espresso", qty: 1 }), // unattributed
    ];
    expect(drinkLinesFor(items, ada)).toEqual([{ drink_key: "negroni", name: "Negroni", qty: 1 }]);
    expect(drinkLinesFor(items, bob)).toEqual([{ drink_key: "old-fashioned", name: "Old Fashioned", qty: 4 }]);
  });

  it("offers nothing to nobody — an unattributed line belongs to no one", () => {
    const items = [item({ drinkKey: "espresso", name: "Espresso", qty: 1 })];
    expect(drinkLinesFor(items, null)).toEqual([]);
    expect(drinkLinesFor(items, undefined)).toEqual([]);
    expect(drinkLinesFor(items, "")).toEqual([]);
  });

  it("carries no price — a diary entry has never had one", () => {
    const items = [item({ guestUserId: ada, drinkKey: "negroni", name: "Negroni", qty: 1, unitPriceMinor: 95000 })];
    const [only] = drinkLinesFor(items, ada);
    expect(Object.keys(only).sort()).toEqual(["drink_key", "name", "qty"]);
  });

  it("skips a zero or junk quantity instead of offering a phantom drink", () => {
    const items = [
      item({ guestUserId: ada, drinkKey: "negroni", name: "Negroni", qty: 0 }),
      item({ guestUserId: ada, drinkKey: "gimlet", name: "Gimlet", qty: NaN }),
    ];
    expect(drinkLinesFor(items, ada)).toEqual([]);
  });

  it("is empty for an empty ticket", () => {
    expect(drinkLinesFor([], ada)).toEqual([]);
  });
});

// The property that ties all three together: nothing in this module can conjure
// value. Every helper's output is bounded by the inputs it was handed — which is
// the arithmetic version of "a guest can never write their own reward".
describe("no helper can invent value", () => {
  const rnd = (seed: number) => {
    // deterministic LCG, so a failure is reproducible
    let s = seed >>> 0;
    return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 0x100000000);
  };

  it("holds over 500 pseudo-random tickets", () => {
    const next = rnd(20260726);
    for (let round = 0; round < 500; round++) {
      const n = Math.floor(next() * 8);
      const items: OrderItem[] = Array.from({ length: n }, (_, i) => {
        const qty = 1 + Math.floor(next() * 5);
        return item({
          qty,
          unitPriceMinor: Math.floor(next() * 100000),
          drinkKey: next() < 0.5 ? `drink-${i % 3}` : undefined,
          guestUserId: next() < 0.7 ? "ada" : undefined,
        });
      });
      const rate = next() * 0.3;
      const tip = Math.floor(next() * 5000);

      const t = billTotals(items, rate, tip);

      // the bill's parts reconcile, always — 051's CHECK depends on it
      expect(t.totalMinor).toBe(t.subtotalMinor + t.taxMinor + tip);
      // and the total is never more than the sum of what went into it
      expect(t.totalMinor).toBeLessThanOrEqual(t.subtotalMinor + Math.ceil(t.subtotalMinor * rate) + tip);
      expect(t.subtotalMinor).toBeGreaterThanOrEqual(0);

      // a split redistributes the total; it never grows or shrinks it
      const payers = 1 + Math.floor(next() * 6);
      const parts = splitEvenly(t.totalMinor, payers);
      expect(parts.reduce((a, b) => a + b, 0)).toBe(t.totalMinor);
      for (const p of parts) expect(p).toBeLessThanOrEqual(t.totalMinor);

      // an offer can never contain more drinks than were actually rung up
      const offeredQty = drinkLinesFor(items, "ada").reduce((a, l) => a + l.qty, 0);
      const servedQty = items
        .filter((i) => i.guestUserId === "ada" && i.drinkKey)
        .reduce((a, i) => a + Math.max(0, i.qty), 0);
      expect(offeredQty).toBe(servedQty);
    }
  });
});

// The conversion factor is not always 100, and a bar in Tokyo is where that stops
// being trivia: dividing ¥ by 100 would bill its guests a hundredth of the tab.
describe("minor units", () => {
  it("knows which currencies have no minor unit", () => {
    expect(minorPerMajor("INR")).toBe(100);
    expect(minorPerMajor("USD")).toBe(100);
    expect(minorPerMajor("JPY")).toBe(1);
    expect(minorPerMajor("KRW")).toBe(1);
  });

  it("round-trips through major units", () => {
    expect(fromMinor(102000, "INR")).toBe(1020);
    expect(fromMinor(1000, "JPY")).toBe(1000);
    expect(toMinor(1020, "INR")).toBe(102000);
    expect(toMinor(1000, "JPY")).toBe(1000);
  });

  it("rounds a typed fraction away rather than storing it", () => {
    expect(toMinor(12.005, "INR")).toBe(1201);
    expect(Number.isInteger(toMinor(0.1 + 0.2, "INR"))).toBe(true);
  });
});
