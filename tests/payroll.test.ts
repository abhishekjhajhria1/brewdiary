import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  PAY_PERIODS,
  csvField,
  hm,
  hoursDecimal,
  minutesWords,
  parsePayrollDay,
  payPeriod,
  payrollCsv,
  payrollFileName,
  payrollFileText,
  payrollTotalCents,
  payrollTotals,
  todayIn,
  venueTimeZone,
} from "@/lib/payroll";

// One fixture for both sides: mobile-bar/test/payroll_test.dart reads the same file, so the
// website and the venue app export the same CSV byte for byte.
const fx = JSON.parse(readFileSync("tests/fixtures/payroll.json", "utf8"));
const rows = (fx.rows as Record<string, unknown>[]).map(parsePayrollDay);

describe("payroll export (parity with the venue app)", () => {
  it("builds the fixture's CSV exactly", () => {
    expect(payrollCsv({ venue: fx.venue, currency: fx.currency, from: fx.from, to: fx.to, rows })).toBe(fx.csv);
  });

  it("totals per person, in name order, in whole paise", () => {
    const people = payrollTotals(rows);
    expect(
      people.map((p) => ({
        user_id: p.userId,
        days_worked: p.daysWorked,
        worked_minutes: p.workedMinutes,
        planned_minutes: p.plannedMinutes,
        pay_cents: p.payCents,
        missing_rate: p.missingRate,
      })),
    ).toEqual(fx.totals);
    expect(payrollTotalCents(people)).toBe(fx.team_pay_cents);
  });

  it("hours read as hours", () => {
    expect(hm(0)).toBe("0:00");
    expect(hm(425)).toBe("7:05");
    expect(hoursDecimal(425)).toBe("7.08");
    expect(hoursDecimal(1)).toBe("0.02");
    expect(hoursDecimal(30)).toBe("0.50");
    expect([minutesWords(0), minutesWords(45), minutesWords(120), minutesWords(425)]).toEqual(["0m", "45m", "2h", "7h 05m"]);
  });

  it("a name can't run as a spreadsheet formula, and commas and quotes are escaped", () => {
    expect(csvField("=SUM(A1)")).toBe("'=SUM(A1)");
    expect(csvField("+91 98765")).toBe("'+91 98765");
    expect(csvField('Sam "Ace", Jr')).toBe('"Sam ""Ace"", Jr"');
    expect(csvField("Noor")).toBe("Noor");
  });
});

describe("the file, the period and the venue's clock (parity with the venue app)", () => {
  it("opens in Excel with any script: a byte-order mark, then UTF-8", () => {
    const bytes = new TextEncoder().encode(payrollFileText("Name\nनूर\n"));
    expect([...bytes.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    expect(payrollFileName("The Amber Room!", "2026-09-01", "2026-09-30")).toBe("payroll-the-amber-room-2026-09-01-to-2026-09-30.csv");
    expect(payrollFileName("मिठाई", "2026-09-01", "2026-09-01")).toBe("payroll-venue-2026-09-01-to-2026-09-01.csv");
  });

  it("periods: this week to today, last week Monday to Sunday, months across a year end", () => {
    const wed = "2026-09-30";
    expect(payPeriod("thisWeek", wed)).toEqual(["2026-09-28", "2026-09-30"]);
    expect(payPeriod("lastWeek", wed)).toEqual(["2026-09-21", "2026-09-27"]);
    expect(payPeriod("thisMonth", wed)).toEqual(["2026-09-01", "2026-09-30"]);
    expect(payPeriod("lastMonth", wed)).toEqual(["2026-08-01", "2026-08-31"]);
    expect(payPeriod("lastMonth", "2027-01-10")).toEqual(["2026-12-01", "2026-12-31"]);
    expect(payPeriod("lastMonth", "2028-03-03")).toEqual(["2028-02-01", "2028-02-29"]);
    expect(payPeriod("thisWeek", "2026-10-04")).toEqual(["2026-09-28", "2026-10-04"]); // a Sunday
    for (const p of PAY_PERIODS) {
      const [a, b] = payPeriod(p.id, wed);
      expect((Date.parse(b) - Date.parse(a)) / 864e5).toBeLessThanOrEqual(62);
    }
  });

  it("a day is the venue's day, whatever the viewer's clock", () => {
    expect(venueTimeZone("IN", "KA")).toBe("Asia/Kolkata");
    expect(venueTimeZone("US", "NY")).toBe("America/New_York");
    expect(venueTimeZone("US", "CA")).toBe("America/Los_Angeles");
    expect(venueTimeZone("ZZ", null)).toBe("UTC");
    const lateUtc = new Date("2026-09-30T20:00:00Z"); // 01:30 the next day in Kolkata
    expect(todayIn("Asia/Kolkata", lateUtc)).toBe("2026-10-01");
    expect(todayIn("America/New_York", lateUtc)).toBe("2026-09-30");
    expect(todayIn("Not/AZone", lateUtc)).toBe("2026-09-30");
  });
});
