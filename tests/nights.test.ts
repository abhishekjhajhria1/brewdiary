import { describe, it, expect } from "vitest";
import { nightPhase, groupNights, prettyTime, type Night } from "@/lib/nights";

// A night with sensible defaults — only the fields a test cares about get passed.
let seq = 0;
function night(p: Partial<Night> = {}): Night {
  seq += 1;
  return {
    id: `n${seq}`,
    hostId: "me",
    hostName: "Ash",
    title: "Negronis",
    date: "2026-08-10",
    audience: "friends",
    status: "open",
    going: 2,
    pending: 0,
    host: true,
    ...p,
  };
}

describe("nightPhase", () => {
  const today = "2026-08-10";

  it("calls today's night tonight", () => {
    expect(nightPhase("2026-08-10", today)).toBe("tonight");
  });

  it("calls a later date upcoming and an earlier one past", () => {
    expect(nightPhase("2026-08-11", today)).toBe("upcoming");
    expect(nightPhase("2026-08-09", today)).toBe("past");
  });

  // Day keys are compared as strings, so the boundaries that matter are the ones
  // where lexical and chronological order could disagree.
  it("orders correctly across month and year boundaries", () => {
    expect(nightPhase("2026-09-01", "2026-08-31")).toBe("upcoming");
    expect(nightPhase("2025-12-31", "2026-01-01")).toBe("past");
    expect(nightPhase("2026-01-02", "2026-01-10")).toBe("past");
  });
});

describe("groupNights", () => {
  const today = "2026-08-10";

  it("splits into tonight / upcoming / past", () => {
    const { tonight, upcoming, past } = groupNights(
      [
        night({ date: "2026-08-10", title: "now" }),
        night({ date: "2026-08-12", title: "later" }),
        night({ date: "2026-08-01", title: "before" }),
      ],
      today,
    );
    expect(tonight.map((n) => n.title)).toEqual(["now"]);
    expect(upcoming.map((n) => n.title)).toEqual(["later"]);
    expect(past.map((n) => n.title)).toEqual(["before"]);
  });

  it("puts the soonest night first, and the most recent recap first", () => {
    const { upcoming, past } = groupNights(
      [
        night({ date: "2026-08-20", title: "far" }),
        night({ date: "2026-08-12", title: "near" }),
        night({ date: "2026-07-01", title: "old" }),
        night({ date: "2026-08-05", title: "recent" }),
      ],
      today,
    );
    expect(upcoming.map((n) => n.title)).toEqual(["near", "far"]);
    expect(past.map((n) => n.title)).toEqual(["recent", "old"]);
  });

  // A called-off night is gone from every list — it must never sit in "coming up"
  // still looking like it's happening.
  it("drops cancelled nights entirely", () => {
    const { tonight, upcoming, past } = groupNights(
      [
        night({ date: "2026-08-10", status: "cancelled" }),
        night({ date: "2026-08-12", status: "cancelled" }),
        night({ date: "2026-08-01", status: "cancelled" }),
      ],
      today,
    );
    expect([...tonight, ...upcoming, ...past]).toEqual([]);
  });

  it("keeps a closed night — closed means 'not taking people', not 'off'", () => {
    const { upcoming } = groupNights([night({ date: "2026-08-12", status: "closed" })], today);
    expect(upcoming).toHaveLength(1);
  });

  it("handles an empty list", () => {
    const { tonight, upcoming, past } = groupNights([], today);
    expect([tonight, upcoming, past]).toEqual([[], [], []]);
  });
});

describe("prettyTime", () => {
  it("renders a postgres time as a spoken one", () => {
    expect(prettyTime("21:30:00")).toBe("9:30 pm");
    expect(prettyTime("09:05:00")).toBe("9:05 am");
  });

  it("drops a zero minute rather than saying 'nine oh oh'", () => {
    expect(prettyTime("21:00:00")).toBe("9 pm");
  });

  it("gets both ends of the clock right", () => {
    expect(prettyTime("00:00:00")).toBe("12 am");
    expect(prettyTime("12:00:00")).toBe("12 pm");
    expect(prettyTime("12:30:00")).toBe("12:30 pm");
  });

  it("returns undefined for nothing or nonsense", () => {
    expect(prettyTime()).toBeUndefined();
    expect(prettyTime("")).toBeUndefined();
    expect(prettyTime("later")).toBeUndefined();
  });
});
