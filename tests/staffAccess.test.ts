import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  CLAIM_ERRORS,
  claimMessage,
  codeDigits,
  codeLifeLeft,
  enrolShareText,
  parseStaffStatus,
  reportLine,
  roleWithArticle,
  validStaffEmail,
  validStaffPhone,
} from "@/lib/staffAccess";

// The migration is the authority. The same cases run in mobile-bar/test/staff_test.dart,
// so the website and the venue app word every refusal the same way.
const sql = readFileSync("supabase/053_staff_access.sql", "utf8");

describe("staff access: the rules the database keeps (parity with 053)", () => {
  it("every way a code can fail is one the website can word", () => {
    const m = sql.match(/'error', case when e\.attempts \+ 1 >= 5 then '(\w+)' else '(\w+)' end/)!;
    const raised = new Set([m[1], m[2], ...[...sql.matchAll(/jsonb_build_object\('ok', false, 'error', '(\w+)'\)/g)].map((x) => x[1])]);
    expect([...raised].sort()).toEqual([...CLAIM_ERRORS].sort());
  });

  it("the phone and email shapes are the database's", () => {
    expect(sql).toContain(String.raw`phone ~ '^\+?[0-9 ()-]{6,20}$'`);
    for (const ok of ["+91 98765 43210", "080-2345 6789", "(022) 1234567"]) expect(validStaffPhone(ok)).toBe(true);
    for (const bad of ["12345", "call me", "+91 98765 43210 ext 5"]) expect(validStaffPhone(bad)).toBe(false);
    expect(validStaffEmail("rahul@gmail.com")).toBe(true);
    expect(validStaffEmail(" Rahul@Gmail.com ")).toBe(true);
    expect(validStaffEmail("rahul@gmail")).toBe(false);
    expect(validStaffEmail("rahul gmail.com")).toBe(false);
  });

  it("statuses: waiting, working, paused — anything else reads as working", () => {
    expect(sql).toContain("check (status in ('pending', 'active', 'locked'))");
    expect(parseStaffStatus("locked")).toBe("locked");
    expect(parseStaffStatus(undefined)).toBe("active");
  });

  it("a code lives 48 hours and allows 5 tries", () => {
    expect(sql).toContain("interval '48 hours'");
    expect(sql).toContain("attempts between 0 and 5");
    const text = enrolShareText({ venue: "The Amber Room", roleWord: "Server", email: "r@x.com", code: "482913" });
    expect(text).toContain("48 hours");
    expect(text).toContain("482913");
    expect(text).toContain("r@x.com");
    expect(text).toContain("as a server");
  });
});

describe("staff access: the words", () => {
  it("a wrong code says how many tries are left", () => {
    expect(claimMessage("wrong_code", 4)).toBe("That's not the code — 4 tries left.");
    expect(claimMessage("wrong_code", 1)).toBe("That's not the code — 1 try left.");
    expect(claimMessage("too_many", null, "Meenakshi")).toBe("Too many wrong tries — ask Meenakshi for a new code.");
    expect(claimMessage("not_found")).toContain("the email your manager added");
    expect(claimMessage("locked", null, "")).toBe("Your access here is paused — talk to your manager.");
  });

  it("the code as typed: digits only, six at most", () => {
    expect(codeDigits("482 913")).toBe("482913");
    expect(codeDigits(" 48-29-13 ")).toBe("482913");
    expect(codeDigits("4829130")).toBe("482913");
    expect(codeDigits("12a")).toBe("12");
  });

  it("roles in a sentence", () => {
    expect(roleWithArticle("Server")).toBe("a server");
    expect(roleWithArticle("Owner")).toBe("an owner");
    expect(roleWithArticle("Kitchen")).toBe("kitchen staff");
    expect(roleWithArticle("Shift lead")).toBe("a shift lead");
  });

  it("who to report to", () => {
    expect(reportLine("Arjun", "manager")).toBe("Please report to Arjun (manager).");
    expect(reportLine("Arjun", null)).toBe("Please report to Arjun.");
    expect(reportLine(null, null)).toBe("Please talk to the owner or a manager.");
  });

  it("how long a code has left", () => {
    const now = new Date(2026, 8, 30, 20);
    expect(codeLifeLeft(new Date(now.getTime() + (31 * 60 + 20) * 60_000), now)).toBe("runs out in 31h");
    expect(codeLifeLeft(new Date(now.getTime() + 40 * 60_000), now)).toBe("runs out in 40 min");
    expect(codeLifeLeft(new Date(now.getTime() - 60_000), now)).toBe("ran out");
  });
});
