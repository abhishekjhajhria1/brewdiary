import { describe, it, expect } from "vitest";
import { toKey, parseKey, addDays, monthGrid, timeOfDayLabel, formatDayLong } from "@/lib/date";

describe("date helpers", () => {
  it("toKey / parseKey round-trip a local date", () => {
    const d = new Date(2026, 6, 9); // 9 Jul 2026 (month is 0-based)
    expect(toKey(d)).toBe("2026-07-09");
    const back = parseKey("2026-07-09");
    expect(back.getFullYear()).toBe(2026);
    expect(back.getMonth()).toBe(6);
    expect(back.getDate()).toBe(9);
  });

  it("addDays crosses month boundaries", () => {
    expect(toKey(addDays(parseKey("2026-01-31"), 1))).toBe("2026-02-01");
    expect(toKey(addDays(parseKey("2026-03-01"), -1))).toBe("2026-02-28");
  });

  it("monthGrid is a Monday-first 6x7 grid", () => {
    const grid = monthGrid(2026, 6); // July 2026; 1 Jul 2026 is a Wednesday
    expect(grid).toHaveLength(42);
    // Monday-first: the grid's first cell is the Monday on/before the 1st.
    expect(grid[0].date.getDay()).toBe(1); // 1 = Monday
    const inMonth = grid.filter((g) => g.inMonth);
    expect(inMonth).toHaveLength(31); // July has 31 days
    expect(inMonth[0].key).toBe("2026-07-01");
    expect(inMonth[30].key).toBe("2026-07-31");
  });

  it("timeOfDayLabel buckets the hour", () => {
    const at = (h: number) => timeOfDayLabel(new Date(2026, 0, 1, h).toISOString());
    expect(at(2)).toBe("Late night");
    expect(at(8)).toBe("Morning");
    expect(at(13)).toBe("Midday");
    expect(at(16)).toBe("Afternoon");
    expect(at(20)).toBe("Evening");
    expect(at(23)).toBe("Nightcap");
  });

  it("formatDayLong reads a key", () => {
    expect(formatDayLong("2026-07-09")).toBe("July 9");
  });
});
