"use client";

// The morphing squircle that toggles the home between the month grid and the year
// mosaic. It lives in the TopBar (where the theme toggle used to sit) and drives the
// shared calendarView store, so tapping it flips the home view.
//
// The glyph IS the state, quietly: in MONTH view it shows this month's initial (a
// single editorial letter); in YEAR view it becomes a 3×3 of tiny squircles — a
// miniature of the heat-mosaic you're switching to. One amber accent, calm, no icon lib.
import { MONTH_NAMES } from "@/lib/date";
import { useCalendarView, toggleCalendarView } from "@/lib/calendarView";

export function ViewSquircle() {
  const view = useCalendarView();
  const monthInitial = MONTH_NAMES[new Date().getMonth()].charAt(0);

  return (
    <button
      type="button"
      onClick={toggleCalendarView}
      aria-label={view === "month" ? "Showing the month. Tap for the year mosaic." : "Showing the year. Tap for the month."}
      title={view === "month" ? "Month · tap for year" : "Year · tap for month"}
      className="glass glass-press flex h-9 w-9 items-center justify-center rounded-xl text-muted transition-colors hover:text-ink"
    >
      {view === "month" ? (
        <span aria-hidden className="font-display text-[17px] italic leading-none">
          {monthInitial}
        </span>
      ) : (
        <span aria-hidden className="grid grid-cols-3 gap-0.5">
          {/* a tiny mosaic — the year view in miniature */}
          {[3, 1, 4, 2, 4, 1, 4, 2, 3].map((lvl, i) => (
            <span
              key={i}
              className="h-0.75 w-0.75 rounded-xs"
              style={{ background: `var(--ycell-${lvl})` }}
            />
          ))}
        </span>
      )}
    </button>
  );
}
