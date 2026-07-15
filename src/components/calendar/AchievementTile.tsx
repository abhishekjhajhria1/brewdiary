"use client";

// The collectible tile that sits above the YEAR mosaic (where the day-counters sit in
// month view — those are for tapping today; on the year view they made no sense).
//
// It cycles three quiet "designs", each a real fact drawn from the diary — a current
// run, the palette of kinds explored, the year filling in. They rotate on their own
// every few seconds (and on tap), crossfading. This is deliberately a SMALL set for
// now: three, monochrome-plus-amber, type-driven — the collectible surface we'll grow
// later, kept on-spec so it never drifts into ornament.
import { useEffect, useMemo, useState } from "react";
import clsx from "clsx";
import type { Entry, DrinkType } from "@/lib/types";
import { DRINK_TYPES } from "@/lib/types";
import { stats, yearReview } from "@/lib/derive";

const ROTATE_MS = 5000;
const DESIGNS = 3;

export function AchievementTile({ entries, className }: { entries: Entry[]; className?: string }) {
  const [i, setI] = useState(0);

  const data = useMemo(() => {
    const s = stats(entries);
    const yr = yearReview(entries);
    // Distinct drink KINDS actually poured — a dry day ('none') isn't a kind.
    const kinds = new Set<string>(
      entries.map((e) => e.type).filter((t): t is DrinkType => !!t && t !== "none"),
    );
    return { current: s.current, longest: s.longest, kinds, days: yr.days };
  }, [entries]);

  // Auto-advance. Reduced-motion users still get the rotation, just without the
  // crossfade (the global CSS collapses the animation duration).
  useEffect(() => {
    const t = setInterval(() => setI((n) => (n + 1) % DESIGNS), ROTATE_MS);
    return () => clearInterval(t);
  }, []);

  return (
    <div className={clsx("glass relative overflow-hidden rounded-tile p-5", className)}>
      <div key={i} className="animate-fade min-h-17">
        {i === 0 && <StreakDesign current={data.current} longest={data.longest} />}
        {i === 1 && <PaletteDesign kinds={data.kinds} />}
        {i === 2 && <YearDesign days={data.days} />}
      </div>

      {/* which of the three — tap any to jump */}
      <div className="mt-4 flex items-center gap-1.5">
        {Array.from({ length: DESIGNS }).map((_, d) => (
          <button
            key={d}
            type="button"
            onClick={() => setI(d)}
            aria-label={`Show design ${d + 1} of ${DESIGNS}`}
            aria-current={d === i}
            className={clsx(
              "h-1.5 rounded-full transition-all duration-300",
              d === i ? "w-5 bg-accent" : "w-1.5 bg-ink/15 hover:bg-ink/30",
            )}
          />
        ))}
      </div>
    </div>
  );
}

// ── 1. the run ────────────────────────────────────────────────────────────────
function StreakDesign({ current, longest }: { current: number; longest: number }) {
  const pips = Math.min(current, 7);
  return (
    <div className="flex items-center gap-4">
      <div className="relative flex h-16 w-16 shrink-0 items-center justify-center">
        <span
          aria-hidden
          className="absolute inset-0 rounded-full"
          style={{ background: "radial-gradient(closest-side, transparent 60%, color-mix(in srgb, var(--accent) 24%, transparent))" }}
        />
        <span className="tnum font-display text-3xl leading-none text-ink">{current}</span>
      </div>
      <div className="min-w-0">
        <p className="label text-faint">current run</p>
        <p className="mt-0.5 text-[15px] text-ink">
          {current === 0 ? "A fresh page — log tonight" : `${current} night${current === 1 ? "" : "s"} unbroken`}
        </p>
        {pips > 0 && (
          <div className="mt-1.5 flex gap-1" aria-hidden>
            {Array.from({ length: pips }).map((_, p) => (
              <span key={p} className="h-1.5 w-1.5 rounded-full bg-accent" />
            ))}
          </div>
        )}
        {longest > current && <p className="mt-1 text-xs text-faint">best so far · {longest}</p>}
      </div>
    </div>
  );
}

// ── 2. the palette ──────────────────────────────────────────────────────────────
function PaletteDesign({ kinds }: { kinds: Set<string> }) {
  return (
    <div>
      <p className="label text-faint">palette</p>
      <p className="mt-0.5 font-display text-3xl leading-none text-ink">
        {kinds.size} <span className="align-baseline text-base text-muted">of {DRINK_TYPES.length} kinds</span>
      </p>
      <div className="mt-3 flex flex-wrap gap-1.5" aria-hidden>
        {DRINK_TYPES.map((t) => (
          <span
            key={t.value}
            className={clsx(
              "h-2.5 w-2.5 rounded-full transition-colors",
              kinds.has(t.value) ? "bg-accent" : "bg-ink/12",
            )}
            title={t.label}
          />
        ))}
      </div>
    </div>
  );
}

// ── 3. the year filling in ──────────────────────────────────────────────────────
function YearDesign({ days }: { days: number }) {
  const year = new Date().getFullYear();
  const dayOfYear = Math.floor((Date.now() - new Date(year, 0, 0).getTime()) / 86_400_000);
  const pct = Math.max(0, Math.min(100, dayOfYear > 0 ? (days / dayOfYear) * 100 : 0));
  return (
    <div>
      <p className="label text-faint">{year} so far</p>
      <p className="mt-0.5 font-display text-3xl leading-none text-ink">
        {days} <span className="align-baseline text-base text-muted">day{days === 1 ? "" : "s"} poured</span>
      </p>
      <div className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-ink/10">
        <div className="h-full rounded-full bg-accent transition-[width] duration-500" style={{ width: `${pct}%` }} />
      </div>
      <p className="mt-1.5 text-xs text-faint">
        {days} of {dayOfYear} days this year have a log
      </p>
    </div>
  );
}
