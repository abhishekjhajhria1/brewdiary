// Spending — your own money, aggregated for you.
//
// The thing these tests exist to pin down is the CURRENCY TRAP: a Goa weekend and
// a Berlin trip are in different money, and every aggregate here must keep them
// apart. A single grand total would be wrong in the most confident possible way,
// so there is no function that produces one — and these tests assert that the
// ones that exist never quietly merge two currencies into one row.
import { describe, it, expect } from "vitest";
import { totalsByCurrency, byMonth, byVenue, typicalNight, type SpendRow } from "../src/lib/spending";

const row = (over: Partial<SpendRow>): SpendRow => ({
  source: "order",
  refId: crypto.randomUUID(),
  date: "2026-07-04",
  venueName: "Toit",
  currency: "INR",
  amountMinor: 100000,
  settled: true,
  ...over,
});

describe("totalsByCurrency", () => {
  it("is empty for no rows", () => {
    expect(totalsByCurrency([])).toEqual([]);
  });

  it("sums within a currency", () => {
    const t = totalsByCurrency([row({ amountMinor: 100000 }), row({ amountMinor: 45000 })]);
    expect(t).toEqual([{ currency: "INR", totalMinor: 145000, count: 2 }]);
  });

  it("NEVER adds two currencies together", () => {
    const t = totalsByCurrency([
      row({ currency: "INR", amountMinor: 250000 }),
      row({ currency: "EUR", amountMinor: 4200 }),
      row({ currency: "INR", amountMinor: 50000 }),
    ]);
    expect(t).toHaveLength(2);
    expect(t.find((x) => x.currency === "INR")).toEqual({ currency: "INR", totalMinor: 300000, count: 2 });
    expect(t.find((x) => x.currency === "EUR")).toEqual({ currency: "EUR", totalMinor: 4200, count: 1 });
  });

  it("leads with the currency you actually live in", () => {
    const t = totalsByCurrency([row({ currency: "EUR", amountMinor: 4200 }), row({ currency: "INR", amountMinor: 300000 })]);
    expect(t[0].currency).toBe("INR");
  });

  it("treats a negative or junk amount as zero, not a credit", () => {
    const t = totalsByCurrency([row({ amountMinor: -5000 }), row({ amountMinor: NaN }), row({ amountMinor: 20000 })]);
    expect(t[0].totalMinor).toBe(20000);
    expect(t[0].count).toBe(3);
  });
});

describe("byMonth", () => {
  it("groups by calendar month, newest first", () => {
    const m = byMonth([
      row({ date: "2026-05-02", amountMinor: 10000 }),
      row({ date: "2026-07-04", amountMinor: 20000 }),
      row({ date: "2026-07-28", amountMinor: 30000 }),
    ]);
    expect(m.map((x) => x.month)).toEqual(["2026-07", "2026-05"]);
    expect(m[0].totalMinor).toBe(50000);
    expect(m[0].count).toBe(2);
  });

  it("keeps a month abroad on its own row", () => {
    const m = byMonth([
      row({ date: "2026-07-04", currency: "INR", amountMinor: 20000 }),
      row({ date: "2026-07-11", currency: "EUR", amountMinor: 3500 }),
    ]);
    expect(m).toHaveLength(2);
    expect(new Set(m.map((x) => x.month))).toEqual(new Set(["2026-07"]));
    expect(new Set(m.map((x) => x.currency))).toEqual(new Set(["INR", "EUR"]));
  });

  it("skips a row with no usable date rather than inventing a month", () => {
    expect(byMonth([row({ date: "" }), row({ date: "nope" })])).toEqual([]);
  });
});

describe("byVenue", () => {
  it("ranks places, biggest first", () => {
    const v = byVenue([
      row({ venueName: "Toit", amountMinor: 50000 }),
      row({ venueName: "Koshy's", amountMinor: 120000 }),
      row({ venueName: "Toit", amountMinor: 30000 }),
    ]);
    expect(v.map((x) => x.venueName)).toEqual(["Koshy's", "Toit"]);
    expect(v[1]).toEqual({ venueName: "Toit", currency: "INR", totalMinor: 80000, visits: 2 });
  });

  it("splits one venue's rows if it somehow billed in two currencies", () => {
    const v = byVenue([
      row({ venueName: "Airport bar", currency: "INR", amountMinor: 90000 }),
      row({ venueName: "Airport bar", currency: "USD", amountMinor: 1800 }),
    ]);
    expect(v).toHaveLength(2);
  });
});

describe("typicalNight", () => {
  it("uses the median, so one big night doesn't describe every night", () => {
    // four ordinary nights and one anniversary; the mean would be ~₹1,880
    const rows = [
      row({ amountMinor: 80000 }),
      row({ amountMinor: 90000 }),
      row({ amountMinor: 95000 }),
      row({ amountMinor: 100000 }),
      row({ amountMinor: 580000 }),
    ];
    const [inr] = typicalNight(rows);
    expect(inr.totalMinor).toBe(95000);
    const mean = rows.reduce((a, r) => a + r.amountMinor, 0) / rows.length;
    expect(inr.totalMinor).toBeLessThan(mean);
  });

  it("averages the middle two on an even count", () => {
    const [inr] = typicalNight([row({ amountMinor: 10000 }), row({ amountMinor: 20000 })]);
    expect(inr.totalMinor).toBe(15000);
  });

  it("keeps currencies apart here too", () => {
    const t = typicalNight([
      row({ currency: "INR", amountMinor: 100000 }),
      row({ currency: "INR", amountMinor: 200000 }),
      row({ currency: "EUR", amountMinor: 4000 }),
    ]);
    expect(t).toHaveLength(2);
    expect(t[0].currency).toBe("INR"); // more rows leads
    expect(t.find((x) => x.currency === "EUR")!.totalMinor).toBe(4000);
  });

  it("is empty for no rows", () => {
    expect(typicalNight([])).toEqual([]);
  });
});

// The property that keeps this module honest: an aggregate never merges money
// that doesn't belong together, and never conjures value.
describe("aggregates are currency-safe and lossless", () => {
  it("every aggregate's per-currency sum matches the input's", () => {
    const rows: SpendRow[] = [
      row({ date: "2026-07-04", currency: "INR", venueName: "Toit", amountMinor: 120000 }),
      row({ date: "2026-07-19", currency: "INR", venueName: "Koshy's", amountMinor: 45000 }),
      row({ date: "2026-06-02", currency: "INR", venueName: "Toit", amountMinor: 78000 }),
      row({ date: "2026-06-15", currency: "EUR", venueName: "Prater", amountMinor: 3200 }),
      row({ date: "2026-05-30", currency: "JPY", venueName: "Bar Trench", amountMinor: 6800 }),
    ];

    for (const cur of ["INR", "EUR", "JPY"]) {
      const expected = rows.filter((r) => r.currency === cur).reduce((a, r) => a + r.amountMinor, 0);
      expect(totalsByCurrency(rows).find((t) => t.currency === cur)!.totalMinor).toBe(expected);
      expect(
        byMonth(rows)
          .filter((m) => m.currency === cur)
          .reduce((a, m) => a + m.totalMinor, 0),
      ).toBe(expected);
      expect(
        byVenue(rows)
          .filter((v) => v.currency === cur)
          .reduce((a, v) => a + v.totalMinor, 0),
      ).toBe(expected);
    }
  });

  it("no aggregate row ever carries more than one currency's money", () => {
    const rows = [
      row({ currency: "INR", amountMinor: 100000 }),
      row({ currency: "EUR", amountMinor: 100000 }),
    ];
    // if these ever merged, each aggregate would collapse to a single row
    expect(totalsByCurrency(rows)).toHaveLength(2);
    expect(byMonth(rows)).toHaveLength(2);
    expect(byVenue(rows)).toHaveLength(2);
    expect(typicalNight(rows)).toHaveLength(2);
  });
});
