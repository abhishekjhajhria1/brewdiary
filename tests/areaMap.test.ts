// The area heat map's spend bands live twice: spend_band_floor() in supabase/048 (the
// database decides the band) and spendBand() in money.ts (the screens say it). This
// reads the SQL step table and checks each step is where money.ts puts the first band.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { formatMoney, spendBand } from "@/lib/money";

const sql = readFileSync("supabase/048_area_map.sql", "utf8");
const fn = sql.slice(sql.indexOf("function public.spend_band_floor"), sql.indexOf("revoke all on function public.spend_band_floor"));
const steps = [...fn.matchAll(/\('([A-Z]{3})',\s*(\d+)\)/g)].map((m) => [m[1], Number(m[2])] as const);
const fallback = Number(/\),\s*(\d+)\)::numeric as step/.exec(fn)?.[1]);

describe("spend bands: SQL and money.ts agree", () => {
  it("reads the SQL step table", () => {
    expect(steps.length).toBeGreaterThanOrEqual(12);
    expect(fallback).toBe(25);
  });

  it.each(steps)("%s: the first band starts at %d", (code, step) => {
    expect(spendBand(step, code)).toBe(`${formatMoney(step, code, { round: true })}+`);
    expect(spendBand(step - 1, code)).toBe(`under ${formatMoney(step, code, { round: true })}`);
  });

  it("any other currency falls back to the same step", () => {
    expect(spendBand(fallback, "USD")).toBe(`${formatMoney(fallback, "USD", { round: true })}+`);
    expect(spendBand(fallback - 1, "EUR")).toContain("under");
  });
});
