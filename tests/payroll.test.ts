import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { csvField, hm, hoursDecimal, parsePayrollDay, payrollCsv, payrollTotalCents, payrollTotals } from "@/lib/payroll";

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
  });

  it("a name can't run as a spreadsheet formula, and commas and quotes are escaped", () => {
    expect(csvField("=SUM(A1)")).toBe("'=SUM(A1)");
    expect(csvField("+91 98765")).toBe("'+91 98765");
    expect(csvField('Sam "Ace", Jr')).toBe('"Sam ""Ace"", Jr"');
    expect(csvField("Noor")).toBe("Noor");
  });
});
