"use client";

// The optional per-day quick-trackers (cigarettes, water…) — enabled in You › Extras.
// Lives on the HOME screen above the calendar, not in the log sheet: things like
// cigarettes get tapped many times a day, far more often than you open a drink, so
// they want one-tap access. Operates on whatever day is passed (the home passes today).
import clsx from "clsx";
import { useExtras, enabledCounters, type ExtraDef } from "@/lib/features";
import { useTally, bumpTally } from "@/lib/tallies";

export function DayCounters({ dateKey, className }: { dateKey: string; className?: string }) {
  const extras = useExtras();
  const counters = enabledCounters(extras);
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
  const n = useTally(dateKey, def.key);
  return (
    <div className="glass flex flex-1 basis-40 items-center justify-between gap-3 rounded-tile px-4 py-3">
      <div className="min-w-0">
        <p className="label text-faint">{def.label}</p>
        <p className="tnum mt-0.5 text-2xl leading-none text-ink">{n}</p>
      </div>
      <div className="flex items-center gap-1.5">
        <Step label={`One fewer ${def.unit}`} disabled={n === 0} onClick={() => bumpTally(dateKey, def.key, -1)}>
          −
        </Step>
        <Step label={`One more ${def.unit}`} primary onClick={() => bumpTally(dateKey, def.key, 1)}>
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
