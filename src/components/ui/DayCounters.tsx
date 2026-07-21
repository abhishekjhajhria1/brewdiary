"use client";

// The optional per-day quick-trackers (cigarettes, water…) — enabled in You › Extras.
// Lives on the HOME screen above the calendar (month view), for one-tap access to the
// things you touch many times a day.
//
// Each tap writes a REAL diary entry (a "Water" / "Cigarette" row), so the count lands on
// the calendar + mosaic and syncs to the DB like any other log — not a separate tally.
// The count is simply how many of those rows exist for the day; −1 removes the latest.
import { useMemo } from "react";
import clsx from "clsx";
import { useExtras, enabledCounters, type ExtraDef, type ExtraKey } from "@/lib/features";
import { useWaterMl, formatVolume } from "@/lib/waterPref";
import { useEntries, addEntry, deleteEntry } from "@/lib/store";
import { normalize } from "@/lib/drinks";

// `only` scopes the row to a subset of trackers — the calendar home shows the
// all-day tallies (cigarettes, water) while the drink tallies (pegs, beers)
// live in Together, where a night out actually happens. Omit it for all.
export function DayCounters({
  dateKey,
  className,
  only,
}: {
  dateKey: string;
  className?: string;
  only?: ExtraKey[];
}) {
  const extras = useExtras();
  let counters = enabledCounters(extras);
  if (only) counters = counters.filter((c) => only.includes(c.key));
  if (counters.length === 0) return null;
  return (
    <div className={clsx("flex flex-wrap gap-2", className)}>
      {counters.map((c) => (
        <DayCounter key={c.key} dateKey={dateKey} def={c} />
      ))}
    </div>
  );
}

function DayCounter({ dateKey, def }: { dateKey: string; def: ExtraDef }) {
  const entries = useEntries();
  const waterMl = useWaterMl();

  // This day's entries for this tracker (e.g. every "Water" row on this date).
  const mine = useMemo(
    () => entries.filter((e) => e.date === dateKey && normalize(e.drink) === normalize(def.entryDrink)),
    [entries, dateKey, def.entryDrink],
  );
  const n = mine.length;
  const volume = def.key === "water" && waterMl ? n * waterMl : null;

  function add() {
    addEntry({ date: dateKey, drink: def.entryDrink, type: def.entryType });
  }
  function remove() {
    if (mine.length === 0) return;
    // drop the most-recently created one
    const last = mine.reduce((a, b) => (a.createdAt >= b.createdAt ? a : b));
    deleteEntry(last.id);
  }

  return (
    <div className="glass flex flex-1 basis-40 items-center justify-between gap-3 rounded-tile px-4 py-3">
      <div className="min-w-0">
        <p className="label text-faint">{def.label}</p>
        <p className="tnum mt-0.5 text-2xl leading-none text-ink">{n}</p>
        {volume !== null && <p className="tnum mt-1 text-xs text-faint">{formatVolume(volume)}</p>}
      </div>
      <div className="flex items-center gap-1.5">
        <Step label={`One fewer ${def.unit}`} disabled={n === 0} onClick={remove}>
          −
        </Step>
        <Step label={`One more ${def.unit}`} primary onClick={add}>
          +
        </Step>
      </div>
    </div>
  );
}

function Step({
  children,
  label,
  onClick,
  disabled,
  primary,
}: {
  children: React.ReactNode;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  primary?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      className={clsx(
        "flex h-9 w-9 items-center justify-center rounded-full text-xl leading-none transition-colors active:scale-95",
        disabled
          ? "cursor-not-allowed text-faint/40"
          : primary
            ? "bg-accent/15 text-accent hover:bg-accent/25"
            : "text-muted hover:bg-ink/5 hover:text-ink",
      )}
    >
      {children}
    </button>
  );
}
