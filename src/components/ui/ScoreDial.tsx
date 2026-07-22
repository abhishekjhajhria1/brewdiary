"use client";

// The Palate Score dial — a circular ring that fills to your progress toward the next
// title, the big score in the middle. Used on the public profile, the You header, and the
// passport. The ring animates from empty on mount (juice), respecting reduced-motion.
import { useEffect, useState } from "react";
import clsx from "clsx";
import type { PaletteScore } from "@/lib/score";

export function ScoreDial({ ps, size = 132, className }: { ps: PaletteScore; size?: number; className?: string }) {
  const stroke = Math.max(6, Math.round(size * 0.07));
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;

  // Start empty, then animate to the real fill one frame later.
  const [p, setP] = useState(0);
  useEffect(() => {
    const t = requestAnimationFrame(() => setP(ps.intoLevel));
    return () => cancelAnimationFrame(t);
  }, [ps.intoLevel]);

  // The big number counts UP from zero on mount (game-juice), eased, ~900ms —
  // unless the viewer asked for reduced motion, in which case it just shows.
  const [shown, setShown] = useState(0);
  useEffect(() => {
    const target = ps.score;
    const reduce =
      typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    if (reduce || target === 0) {
      setShown(target);
      return;
    }
    const dur = 900;
    const start = performance.now();
    let raf = requestAnimationFrame(function tick(now) {
      const t = Math.min(1, (now - start) / dur);
      const eased = 1 - Math.pow(1 - t, 3); // easeOutCubic — fast then settles
      setShown(Math.round(target * eased));
      if (t < 1) raf = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(raf);
  }, [ps.score]);

  return (
    <div className={clsx("relative shrink-0", className)} style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90" aria-hidden>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--color-line)" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="var(--color-accent)"
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c * (1 - p)}
          className="transition-[stroke-dashoffset] duration-[1100ms] ease-out motion-reduce:transition-none"
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="tnum font-display leading-none text-ink" style={{ fontSize: size * 0.3 }}>
          {shown}
        </span>
        <span className="label mt-1 text-faint">score</span>
      </div>
    </div>
  );
}
