"use client";

// The collectible tile above the YEAR mosaic (where the day-counters sit in month view).
//
// Purely DECORATIVE for now — three quiet amber "designs", no numbers. It shows a
// different one each refresh (no timer); the dots let you flip between them by hand.
// Deliberately a small set of three; we'll grow the collection (and tie designs to real
// achievements) later. Kept monochrome-plus-amber so it never drifts into ornament.
import { useState } from "react";
import clsx from "clsx";

const DESIGNS = 3;

export function AchievementTile({ className }: { className?: string }) {
  // A different design each mount/refresh — the "it changes" the collectible wants.
  const [i, setI] = useState(() => Math.floor(Math.random() * DESIGNS));

  return (
    <div className={clsx("glass relative overflow-hidden rounded-tile p-4", className)}>
      <div className="h-24 w-full overflow-hidden rounded-ctl">
        {i === 0 && <Rings />}
        {i === 1 && <Weave />}
        {i === 2 && <Waves />}
      </div>

      {/* flip between the three by hand */}
      <div className="mt-3 flex items-center gap-1.5">
        {Array.from({ length: DESIGNS }).map((_, d) => (
          <button
            key={d}
            type="button"
            onClick={() => setI(d)}
            aria-label={`Design ${d + 1} of ${DESIGNS}`}
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

// concentric amber arcs blooming from a corner
function Rings() {
  return (
    <div
      aria-hidden
      className="h-full w-full"
      style={{
        background:
          "repeating-radial-gradient(circle at 20% 130%, color-mix(in srgb, var(--accent) 22%, transparent) 0 2px, transparent 2px 24px)",
      }}
    />
  );
}

// a decorative mosaic band — the streak-mosaic motif, at rest
function Weave() {
  return (
    <div aria-hidden className="grid h-full grid-cols-12 grid-rows-4 gap-1">
      {Array.from({ length: 48 }).map((_, i) => (
        <span key={i} className="rounded-xs" style={{ background: `var(--ycell-${((i * 5 + (i % 3)) % 4) + 1})` }} />
      ))}
    </div>
  );
}

// soft diagonal amber bands
function Waves() {
  return (
    <div
      aria-hidden
      className="h-full w-full"
      style={{
        background:
          "repeating-linear-gradient(115deg, color-mix(in srgb, var(--accent) 16%, transparent) 0 5px, transparent 5px 18px)",
      }}
    />
  );
}
