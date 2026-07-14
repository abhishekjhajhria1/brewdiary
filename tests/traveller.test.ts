import { describe, it, expect, beforeEach, vi } from "vitest";
import { minDrinkingAge } from "../src/lib/jurisdiction";

// The traveller rule, in one file.
//
// Drinking age is TERRITORIAL: it follows where you ARE, not your passport. A
// 20-year-old American is legal in Berlin and illegal in New York. So moving to a
// stricter country must force a fresh age check — and we have to do that WITHOUT
// ever storing a date of birth, because the age gate promises we don't. We store
// only the age bar the person cleared.
//
// The mirror rule (not testable here, it's in SQL): what a BAR may offer follows
// where the BAR is. A perk given in Dublin is an Irish promotion no matter whose
// phone receives it — a traveller does not bring their home rules with them.

const store = new Map<string, string>();
vi.stubGlobal("window", {
  localStorage: {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => void store.set(k, v),
    removeItem: (k: string) => void store.delete(k),
  },
});

// imported after the stub so the module sees our fake localStorage
const { confirmAge, canMoveTo, moveTo, savedCountry, legalAgeFor } = await import("../src/lib/age");

const dobFor = (age: number) => {
  const d = new Date();
  d.setFullYear(d.getFullYear() - age);
  d.setDate(d.getDate() - 1); // safely past the birthday
  return d;
};

describe("the age bar is per-country, not one number", () => {
  it("uses the real bar where you are", () => {
    expect(legalAgeFor("US")).toBe(21);
    expect(legalAgeFor("DE")).toBe(18);
    expect(legalAgeFor("JP")).toBe(20);
    expect(legalAgeFor("ZZ")).toBe(21); // unknown → strictest, never 18
    expect(minDrinkingAge("CA")).toBe(19);
  });
});

describe("a traveller", () => {
  beforeEach(() => store.clear());

  it("a 19-year-old gets into Germany but NOT the US", () => {
    expect(confirmAge(dobFor(19), "DE")).toBe(true);
    store.clear();
    expect(confirmAge(dobFor(19), "US")).toBe(false); // 21 there
  });

  it("moving to a STRICTER country forces a fresh age check", () => {
    expect(confirmAge(dobFor(19), "DE")).toBe(true); // cleared an 18 bar
    expect(canMoveTo("GB")).toBe(true); // also 18 — fine
    expect(canMoveTo("US")).toBe(false); // 21 — must re-confirm

    const res = moveTo("US");
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.needsAge).toBe(21);
    expect(savedCountry()).not.toBe("US"); // and we did NOT move them
  });

  it("moving to a LOOSER country just works", () => {
    expect(confirmAge(dobFor(30), "US")).toBe(true);
    expect(moveTo("DE")).toEqual({ ok: true });
    expect(savedCountry()).toBe("DE");
  });

  it("a 30-year-old can go anywhere", () => {
    expect(confirmAge(dobFor(30), "DE")).toBe(true);
    for (const c of ["US", "JP", "CA", "GB", "ZZ"]) expect(canMoveTo(c)).toBe(true);
  });

  it("never stores a date of birth — only the bar that was cleared", () => {
    confirmAge(dobFor(23), "IN");
    const keys = [...store.keys()];
    const values = [...store.values()];
    expect(keys.some((k) => /dob|birth/i.test(k))).toBe(false);
    // the only age-ish thing we keep is a small integer bar, not a date
    expect(values.some((v) => /\d{4}-\d{2}-\d{2}/.test(v))).toBe(false);
  });

  it("an unconfirmed person cannot move anywhere at all", () => {
    expect(canMoveTo("DE")).toBe(false); // cleared bar is 0
    expect(canMoveTo("US")).toBe(false);
  });
});
