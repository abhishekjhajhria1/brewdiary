"use client";

import clsx from "clsx";
import { addDays, parseKey, toKey, todayKey, MONTH_NAMES } from "@/lib/date";
import { intensityLevel } from "@/lib/derive";
import { useParallax } from "../ui/useParallax";

// Year view has no numbers → use the DRAMATIC ramp for a striking collectible.
const FILL = ["transparent", "var(--ycell-1)", "var(--ycell-2)", "var(--ycell-3)", "var(--ycell-4)"] as const;

/** GitHub-style contribution grid for the whole year — the collectible "year fills in" view. */
export function YearMosaic({
  year,
  counts,
  onSelect,
}: {
  year: number;
  counts: Map<string, number>;
  onSelect: (key: string) => void;
}) {
  const drift = useParallax<HTMLDivElement>();
  const jan1 = new Date(year, 0, 1);
  const lead = (jan1.getDay() + 6) % 7; // Monday-first offset
  const gridStart = addDays(jan1, -lead);

  const todayK = todayKey();
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // 53 weeks × 7 days
  const weeks: { key: string; inYear: boolean; future: boolean; isToday: boolean; count: number }[][] = [];
  let cursor = gridStart;
  for (let w = 0; w < 53; w++) {
    const col: typeof weeks[number] = [];
    for (let dow = 0; dow < 7; dow++) {
      const key = toKey(cursor);
      col.push({
        key,
        inYear: cursor.getFullYear() === year,
        future: cursor.getTime() > today.getTime(),
        isToday: key === todayK,
        count: counts.get(key) ?? 0,
      });
      cursor = addDays(cursor, 1);
    }
    weeks.push(col);
  }

  // Month tick positions (the week index where each month begins).
  const monthTicks: { label: string; week: number }[] = [];
  weeks.forEach((col, wi) => {
    const firstInYear = col.find((d) => d.inYear);
    if (firstInYear) {
      const dt = parseKey(firstInYear.key); // never new Date("YYYY-MM-DD") — that parses as UTC and shifts a day west of Greenwich
      if (dt.getDate() <= 7) monthTicks.push({ label: MONTH_NAMES[dt.getMonth()].slice(0, 3), week: wi });
    }
  });

  return (
    <section>
      <header className="mb-5 flex items-baseline gap-3 border-b border-line pb-4">
        <h1 className="font-display text-5xl leading-none tracking-tight sm:text-6xl">{year}</h1>
        <span className="label">the year so far</span>
      </header>

      <div ref={drift} className="glass overflow-x-auto rounded-tile p-4">
        <div className="inline-flex flex-col gap-1">
          <div className="flex gap-0.75 pl-0">
            {weeks.map((_, wi) => {
              const tick = monthTicks.find((t) => t.week === wi);
              return (
                <div key={wi} className="w-2.75 text-[9px] text-faint">
                  {tick ? tick.label : ""}
                </div>
              );
            })}
          </div>
          <div className="flex gap-0.75">
            {weeks.map((col, wi) => (
              <div key={wi} className="flex flex-col gap-0.75">
                {col.map((day) => {
                  const level = intensityLevel(day.count);
                  const interactive = day.inYear && !day.future;
                  return (
                    <button
                      key={day.key}
                      type="button"
                      disabled={!interactive}
                      onClick={() => onSelect(day.key)}
                      aria-label={`${day.key}${day.count ? `, ${day.count} logged` : ""}`}
                      className={clsx(
                        "h-2.75 w-2.75 rounded-xs transition-colors",
                        interactive ? "cursor-pointer hover:shadow-[inset_0_0_0_1px_var(--color-ink)]" : "cursor-default",
                        level === 0 && day.inYear && "shadow-[inset_0_0_0_1px_var(--color-line)]",
                        !day.inYear && "opacity-0",
                        day.isToday && "shadow-[inset_0_0_0_1.5px_var(--color-ink)]",
                      )}
                      style={{ background: FILL[level] }}
                    />
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      </div>

      <Legend />
    </section>
  );
}

function Legend() {
  return (
    <div className="mt-4 flex items-center gap-2 text-faint">
      <span className="text-[10px] uppercase tracking-[0.14em]">less</span>
      <div className="flex gap-0.75">
        {[0, 1, 2, 3, 4].map((l) => (
          <span
            key={l}
            className={clsx("h-2.75 w-2.75 rounded-xs", l === 0 && "shadow-[inset_0_0_0_1px_var(--color-line)]")}
            style={{ background: FILL[l] }}
          />
        ))}
      </div>
      <span className="text-[10px] uppercase tracking-[0.14em]">more</span>
    </div>
  );
}
