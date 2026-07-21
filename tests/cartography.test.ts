import { describe, it, expect } from "vitest";
import {
  chartable,
  chartedBy,
  checkProposal,
  commons,
  existingMatch,
  suggestFamilies,
  type ChartProposal,
} from "@/lib/cartography";
import { passport } from "@/lib/passport";
import type { Entry } from "@/lib/types";

let seq = 0;
function entry(p: Partial<Entry> = {}): Entry {
  seq += 1;
  return {
    id: `e${seq}`,
    date: "2026-07-09",
    createdAt: new Date(2026, 6, 9, 20, 0, 0).toISOString(),
    drink: "Latte",
    ...p,
  };
}
function proposal(p: Partial<ChartProposal> = {}): ChartProposal {
  seq += 1;
  return {
    id: `p${seq}`,
    author: "@ada",
    rawName: "Grandpa's punch",
    canonical: "Grandpa's Punch",
    family: "Grandpa's Punch",
    type: "cocktail",
    status: "pending",
    createdAt: "2026-07-09T20:00:00.000Z",
    ...p,
  };
}

describe("checkProposal — a plain answer, never a silent failure", () => {
  it("refuses an empty or whitespace-only name", () => {
    expect(checkProposal("")).toMatchObject({ ok: false, reason: "empty" });
    expect(checkProposal("   ")).toMatchObject({ ok: false, reason: "empty" });
  });

  it("refuses a name that's a note rather than a drink", () => {
    expect(checkProposal("x".repeat(61))).toMatchObject({ ok: false, reason: "too-long" });
  });

  it("accepts a genuinely novel drink", () => {
    expect(checkProposal("Zzyzx Fizzwallop")).toEqual({ ok: true });
  });

  it("refuses something the dictionary already knows", () => {
    const r = checkProposal("Negroni");
    expect(r).toMatchObject({ ok: false, reason: "already-known", existing: "Negroni" });
  });

  it("refuses a FUZZY duplicate, so a typo can't fork the map", () => {
    // Without the fuzzy check this founds a rival Espresso family and quietly splits everyone's
    // passport in two — the single most damaging thing a proposal could do.
    const r = checkProposal("esspresso");
    expect(r.ok).toBe(false);
    expect((r as { reason: string }).reason).toBe("already-known");
  });

  it("treats re-sending your own pending proposal as a no-op, not an error to punish", () => {
    const mine = [proposal({ canonical: "Zzyzx Fizzwallop", status: "pending" })];
    expect(checkProposal("Zzyzx Fizzwallop", mine)).toMatchObject({
      ok: false,
      reason: "already-proposed",
    });
  });

  it("lets a REJECTED proposal be sent again — rejection costs nothing", () => {
    const mine = [proposal({ canonical: "Zzyzx Fizzwallop", status: "rejected" })];
    expect(checkProposal("Zzyzx Fizzwallop", mine)).toEqual({ ok: true });
  });
});

describe("existingMatch", () => {
  it("finds the dictionary entry behind an exact name and a typo alike", () => {
    expect(existingMatch("Negroni")).toBe("Negroni");
    expect(existingMatch("esspresso")).toBeTruthy();
    expect(existingMatch("Zzyzx Fizzwallop")).toBeNull();
  });
});

describe("chartable — what's worth offering to chart", () => {
  it("offers your off-map drinks", () => {
    const p = passport([entry({ drink: "Zzyzx Fizzwallop" })]);
    expect(chartable(p.offMap).map((s) => s.family)).toEqual(["Zzyzx Fizzwallop"]);
  });

  it("stops offering one you've already sent in (no nagging)", () => {
    const p = passport([entry({ drink: "Zzyzx Fizzwallop" })]);
    const mine = [proposal({ rawName: "Zzyzx Fizzwallop", status: "pending" })];
    expect(chartable(p.offMap, mine)).toEqual([]);
  });

  it("offers it again if it was rejected", () => {
    const p = passport([entry({ drink: "Zzyzx Fizzwallop" })]);
    const mine = [proposal({ rawName: "Zzyzx Fizzwallop", status: "rejected" })];
    expect(chartable(p.offMap, mine).length).toBe(1);
  });
});

describe("chartedBy — attribution is the whole reward", () => {
  // charted_families() hands the client ONE row per family (the first charter — the SQL
  // settles that), so this is a lookup, and it must survive spelling drift.
  const charted = [{ family: "Grandpa's Punch", handle: "@ada" }];

  it("credits the charter", () => {
    expect(chartedBy("Grandpa's Punch", charted)).toBe("@ada");
  });

  it("matches through case and spacing drift", () => {
    expect(chartedBy("  GRANDPA'S   punch ", charted)).toBe("@ada");
  });

  it("does NOT credit on a near-miss — attribution is precise or absent", () => {
    // normalize() folds case and spacing but not punctuation ("grandpa s" ≠ "grandpas"),
    // and that's the behaviour we want here: naming the wrong person as the charter is a
    // worse failure than naming nobody. Discovery is fuzzy (canonicalize); credit is not.
    expect(chartedBy("grandpas punch", charted)).toBeNull();
  });

  it("credits nobody for the dictionary's own families", () => {
    expect(chartedBy("Negroni", charted)).toBeNull();
    expect(chartedBy("Negroni", [])).toBeNull();
  });
});

describe("commons — collective progress with nobody to rank", () => {
  it("counts FAMILIES, never people", () => {
    const c = commons([
      { family: "Grandpa's Punch", handle: "@ada" },
      { family: "Bathtub Sherbet", handle: "@cy" },
    ]);
    // There is no per-person figure here to build a leaderboard out of, by construction.
    expect(c.charted).toBe(2);
    expect(c.families).toBeGreaterThan(c.charted);
  });

  it("never double-counts a charted family the dictionary has since absorbed", () => {
    const c = commons([{ family: "Negroni", handle: "@ada" }]);
    expect(c.charted).toBe(0);
    expect(c.families).toBe(commons([]).families);
  });
});

describe("suggestFamilies", () => {
  it("offers near families so charting is a choice, not a blank form", () => {
    const s = suggestFamilies("hazy session ipa");
    expect(s.length).toBe(3);
    expect(s).toContain("IPA");
  });

  it("returns nothing for an empty name", () => {
    expect(suggestFamilies("")).toEqual([]);
  });
});
