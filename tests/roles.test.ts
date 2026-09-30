import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { CAPABILITIES, ROLE_CAPS, STAFF_ROLES, canGrant, roleCan } from "@/lib/roles";

// The migration is the authority; this file and mobile-bar/lib/logic/roles.dart mirror it.
// If this fails, someone changed one side of the matrix without the other.
const seeded = (() => {
  const sql = readFileSync("supabase/045_staff_roles.sql", "utf8");
  const rows = [...sql.matchAll(/^\s*\('([a-z]+)', '([a-z0-9_.]+)'\)[,;]/gm)];
  return rows.map((m) => `${m[1]}:${m[2]}`).sort();
})();

describe("role capabilities (parity with supabase/045_staff_roles.sql)", () => {
  it("the seeded matrix is exactly the mirror's", () => {
    const mirror = STAFF_ROLES.flatMap((r) => [...ROLE_CAPS[r]].map((c) => `${r}:${c}`)).sort();
    expect(seeded.length).toBeGreaterThan(100);
    expect(mirror).toEqual(seeded);
  });

  it("owner holds everything; a manager everything but deleting the venue", () => {
    expect(CAPABILITIES.every((c) => roleCan("owner", c))).toBe(true);
    expect(roleCan("manager", "venue.delete")).toBe(false);
    expect(CAPABILITIES.filter((c) => c !== "venue.delete").every((c) => roleCan("manager", c))).toBe(true);
  });

  it("the kitchen and the door never touch a guest's tab, perks, card or notes", () => {
    for (const role of ["kitchen", "host"] as const) {
      for (const cap of ["spend.record", "perks.redeem", "guests.card", "guests.notes"] as const) {
        expect(roleCan(role, cap)).toBe(false);
      }
    }
  });

  it("today's bartender keeps every power it had", () => {
    for (const cap of ["spend.record", "guests.vibe", "perks.redeem", "rooms.open", "guests.card", "guests.notes"] as const) {
      expect(roleCan("bartender", cap)).toBe(true);
    }
  });
});

describe("who may grant which role (mirrors can_grant_role)", () => {
  it("nobody grants 'owner'", () => {
    for (const r of STAFF_ROLES) expect(canGrant(r, "owner")).toBe(false);
  });
  it("an owner manages everyone else; a manager only the floor", () => {
    expect(canGrant("owner", "manager")).toBe(true);
    expect(canGrant("manager", "manager")).toBe(false);
    expect(canGrant("manager", "supervisor")).toBe(true);
    expect(canGrant("manager", "kitchen")).toBe(true);
    expect(canGrant("supervisor", "server")).toBe(false);
    expect(canGrant("server", "server")).toBe(false);
  });
});
