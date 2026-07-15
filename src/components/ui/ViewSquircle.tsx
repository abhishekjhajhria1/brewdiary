"use client";

// The morphing squircle in the TopBar that toggles the home between the month grid and
// the year mosaic. It drives the shared calendarView store.
//
// The glyph hints at the view you'll switch TO: in MONTH view it shows a 3×3 of tiny
// squircles (a miniature of the year mosaic); in YEAR view it shows the month's name
// (restyled — uppercase, tracked), the month grid you'd go back to. One amber accent, calm.
import { MONTH_NAMES } from "@/lib/date";
import { useCalendarView, toggleCalendarView } from "@/lib/calendarView";

export function ViewSquircle() {
  const view = useCalendarView();
  const monthAbbr = MONTH_NAMES[new Date().getMonth()].slice(0, 3);

  return (
    <button
      type="button"
      onClick={toggleCalendarView}
      aria-label={view === "month" ? "Showing the month. Tap for the year mosaic." : "Showing the year. Tap for the month."}
      title={view === "month" ? "Month · tap for year" : "Year · tap for month"}
      className="glass glass-press flex h-9 w-9 items-center justify-center rounded-xl text-muted transition-colors hover:text-ink"
    >
      {view === "month" ? (
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
      ) : (
        <span aria-hidden className="text-[8px] font-semibold uppercase leading-none tracking-[0.12em] text-ink">
          {monthAbbr}
        </span>
      )}
    </button>
  );
}
