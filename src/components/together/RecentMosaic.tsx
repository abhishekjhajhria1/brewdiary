"use client";

import clsx from "clsx";
import { intensityLevel } from "@/lib/derive";
import { addDays, toKey, todayKey, parseKey } from "@/lib/date";

const FILL = ["transparent", "var(--ycell-1)", "var(--ycell-2)", "var(--ycell-3)", "var(--ycell-4)"] as const;

/** Compact, read-only 12-week mosaic — a friend's shared days, or a circle's combined ones. */
export function RecentMosaic({ counts }: { counts: Map<string, number> }) {
  const WEEKS = 12;
  const today = parseKey(todayKey());
  const dow = (today.getDay() + 6) % 7; // Monday-first
  const end = addDays(today, 6 - dow);
  const start = addDays(end, -(WEEKS * 7 - 1));

  const cols: { key: string; level: number; future: boolean }[][] = [];
  let cursor = start;
  for (let w = 0; w < WEEKS; w++) {
    const col: { key: string; level: number; future: boolean }[] = [];
    for (let d = 0; d < 7; d++) {
      const key = toKey(cursor);
      col.push({ key, level: intensityLevel(counts.get(key) ?? 0), future: cursor.getTime() > today.getTime() });
      cursor = addDays(cursor, 1);
    }
    cols.push(col);
  }

  return (
    <div className="flex gap-1">
      {cols.map((col, wi) => (
        <div key={wi} className="flex flex-1 flex-col gap-1">
          {col.map((day) => (
            <span
              key={day.key}
              className={clsx(
                "aspect-square rounded-xs",
                day.level === 0 && !day.future && "shadow-[inset_0_0_0_1px_var(--color-line)]",
                day.future && "opacity-0",
              )}
              style={{ background: FILL[day.level] }}
            />
          ))}
        </div>
      ))}
    </div>
  );
}
