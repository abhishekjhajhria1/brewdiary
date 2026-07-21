"use client";

// The Passport journey — your exploration as ONE winding road you scroll along, the
// Duolingo/level-map pattern made literal. Reached landmarks glow amber; ahead ones are
// dim invitations. A "you are here" dot glides along the squiggle as you scroll, a caption
// reads out whichever landmark it's on, and each landmark you pass gives a little haptic
// buzz (navigator.vibrate — a no-op on desktop). Data is derived (lib/journey.ts).
//
// Researched principles applied: one path not a grid; distinctive landmarks; golden-vs-dim
// so "how far / what's ahead" is legible at a glance; and "juice" (visual + haptic feedback
// at reward moments) — while keeping the road itself clean, the current node in the caption.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { journey } from "@/lib/journey";

// ── road geometry ────────────────────────────────────────────────────────────
const PAD = 84; // lead-in / lead-out before the first & after the last landmark
const STEP = 132; // horizontal gap between landmarks
const CY = 60; // centre-line
const AMP = 26; // squiggle height
const R = 9; // landmark radius
const HEIGHT = 150;

/** The road as a continuous function of x — used for BOTH the drawn path and the dot's y,
 *  so the dot rides exactly on the road. A gentle sine gives the winding "trail" feel. */
function roadY(x: number): number {
  return CY + AMP * Math.sin(((x - PAD) / STEP) * Math.PI * 0.9);
}

function buzz(ms: number) {
  try {
    if (typeof navigator !== "undefined" && typeof navigator.vibrate === "function") navigator.vibrate(ms);
  } catch {
    /* some browsers throw on vibrate in insecure contexts — never fatal */
  }
}

export function Journey() {
  const entries = useEntries();
  const j = journey(entries);
  const n = j.nodes.length;

  const width = PAD * 2 + (n - 1) * STEP;
  const nodeX = useMemo(() => Array.from({ length: n }, (_, i) => PAD + i * STEP), [n]);
  const frontierX = j.frontier >= 0 ? nodeX[j.frontier] : PAD;

  // The full road, and the "travelled" road up to the frontier — drawn as two paths so the
  // journey behind you reads golden and the road ahead reads dim.
  const fullD = useMemo(() => buildRoad(0, width), [width]);
  const travelledD = useMemo(
    () => (j.frontier >= 0 ? buildRoad(0, frontierX) : ""),
    [j.frontier, frontierX],
  );

  const scrollRef = useRef<HTMLDivElement>(null);
  const [playX, setPlayX] = useState(frontierX); // content-x of the dot (the viewport centre)
  const focused = clampIndex(Math.round((playX - PAD) / STEP), n);
  const lastBuzzed = useRef<number>(j.frontier);
  const raf = useRef<number | null>(null);

  // Park the dot on your frontier when the road first appears (centre it in the viewport).
  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollLeft = Math.max(0, frontierX - el.clientWidth / 2);
    setPlayX(el.scrollLeft + el.clientWidth / 2);
  }, [frontierX]);

  const onScroll = useCallback(() => {
    if (raf.current != null) return;
    raf.current = requestAnimationFrame(() => {
      raf.current = null;
      const el = scrollRef.current;
      if (!el) return;
      const x = el.scrollLeft + el.clientWidth / 2;
      setPlayX(x);
      const idx = clampIndex(Math.round((x - PAD) / STEP), n);
      if (idx !== lastBuzzed.current) {
        lastBuzzed.current = idx;
        buzz(j.nodes[idx]?.reached ? 18 : 7); // a firmer tap for a landmark you've earned
      }
    });
  }, [n, j.nodes]);

  useEffect(() => () => void (raf.current != null && cancelAnimationFrame(raf.current)), []);

  const dotY = roadY(playX);
  const here = j.nodes[focused];

  return (
    <div className="glass rounded-tile p-5">
      <div className="mb-1 flex items-baseline justify-between gap-3">
        <p className="label text-faint">Your journey</p>
        <span className="text-xs text-faint">
          {j.exploredFamilies > 0 ? `${j.exploredFamilies} explored` : "not begun"}
        </span>
      </div>

      <div
        ref={scrollRef}
        onScroll={onScroll}
        className="scrollbar-none -mx-5 overflow-x-auto px-5"
        style={{
          // fade the road out at both edges so it reads as a trail continuing off-screen
          maskImage: "linear-gradient(to right, transparent, #000 8%, #000 92%, transparent)",
          WebkitMaskImage: "linear-gradient(to right, transparent, #000 8%, #000 92%, transparent)",
        }}
      >
        <svg width={width} height={HEIGHT} className="block" role="img" aria-label="Your exploration journey">
          {/* the road ahead — dim, dashed, an invitation */}
          <path d={fullD} fill="none" stroke="var(--color-line-strong)" strokeWidth={3} strokeLinecap="round" strokeDasharray="1 9" opacity={0.7} />
          {/* the road behind — solid gold */}
          {travelledD && <path d={travelledD} fill="none" stroke="var(--color-accent)" strokeWidth={3.5} strokeLinecap="round" />}

          {/* landmarks */}
          {j.nodes.map((node, i) => {
            const x = nodeX[i];
            const y = roadY(x);
            return (
              <g key={node.id}>
                {node.reached && <circle cx={x} cy={y} r={R + 6} fill="var(--color-accent)" opacity={0.16} />}
                <circle
                  cx={x}
                  cy={y}
                  r={R}
                  fill={node.reached ? "var(--color-accent)" : "var(--color-canvas)"}
                  stroke={node.reached ? "var(--color-accent)" : "var(--color-line-strong)"}
                  strokeWidth={2}
                />
                {node.reached && <circle cx={x} cy={y} r={3} fill="var(--color-canvas)" opacity={0.9} />}
              </g>
            );
          })}

          {/* "you are here" — a soft amber halo + a solid dot, riding the road at the viewport centre */}
          <g style={{ transform: `translate(${playX}px, ${dotY}px)` }}>
            <circle r={13} fill="var(--color-accent)" opacity={0.18} className="motion-safe:animate-pulse" />
            <circle r={6} fill="var(--color-accent)" />
            <circle r={2.5} fill="var(--color-canvas)" />
          </g>
        </svg>
      </div>

      {/* the readout — what the dot is resting on (Duolingo highlights the current node,
          rather than labelling all of them, so the road stays clean). */}
      {here && (
        <div className="mt-1 flex items-baseline gap-2">
          <span className={clsx("text-sm", here.reached ? "text-ink" : "text-muted")}>{here.label}</span>
          {!here.reached && <span className="label text-faint">ahead</span>}
          <span className="ml-auto truncate text-xs text-faint">{here.hint}</span>
        </div>
      )}
    </div>
  );
}

// Sample the sine road between two x's into an SVG path. 6px steps are smooth at this scale.
function buildRoad(fromX: number, toX: number): string {
  let d = "";
  for (let x = fromX; x <= toX; x += 6) {
    d += `${x === fromX ? "M" : "L"}${x.toFixed(1)} ${roadY(x).toFixed(1)} `;
  }
  // make sure the exact end point lands on the road
  d += `L${toX.toFixed(1)} ${roadY(toX).toFixed(1)}`;
  return d.trim();
}

function clampIndex(i: number, n: number): number {
  return Math.max(0, Math.min(n - 1, i));
}
