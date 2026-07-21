"use client";

// The Palate Score banner — the dial + the level/title it earns + a bar of progress toward
// the next title. One shared piece so the score reads identically on the public profile, the
// You header, and the passport.
import { ScoreDial } from "./ScoreDial";
import type { PaletteScore } from "@/lib/score";

export function ScoreBanner({ ps, size = 96 }: { ps: PaletteScore; size?: number }) {
  return (
    <div className="flex items-center gap-4">
      <ScoreDial ps={ps} size={size} />
      <div className="min-w-0 flex-1">
        <p className="label text-faint">Level {ps.level}</p>
        <p className="mt-0.5 font-display text-2xl leading-tight text-ink">{ps.title}</p>
        {ps.nextTitle ? (
          <>
            <div className="mt-2.5 h-1.5 overflow-hidden rounded-full bg-ink/8">
              <div
                className="h-full rounded-full bg-accent transition-[width] duration-700 ease-out motion-reduce:transition-none"
                style={{ width: `${Math.round(ps.intoLevel * 100)}%` }}
              />
            </div>
            <p className="mt-1.5 text-xs text-faint">
              <span className="tnum">{ps.toNext}</span> to {ps.nextTitle}
            </p>
          </>
        ) : (
          <p className="mt-2 text-xs text-faint">The top of the map — a full palate.</p>
        )}
      </div>
    </div>
  );
}
