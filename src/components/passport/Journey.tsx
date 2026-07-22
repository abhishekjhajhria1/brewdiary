"use client";

// The Passport journey — your exploration as ONE winding road you scroll along, the
// Duolingo/level-map pattern made literal. Reached landmarks glow amber; ahead ones are
// dim invitations. A "you are here" dot glides along the squiggle as you scroll, and a
// callout above the road grows in to name whatever landmark the dot is resting on, each
// pass giving a little haptic buzz. Data is derived (lib/journey.ts).
//
// This turn added, from the maintainer's notes:
//  • A CALLOUT that pops above the dot and swells when you land on a landmark — the node
//    under it scales up too ("a little popup that grows bigger when the dot is at its spot").
//  • The NEXT landmark ahead is singled out with a soft pulse, so "what's next" always reads.
//  • JUST-EARNED celebration — a milestone you crossed since you last looked is brought to
//    YOU: the road parks the dot on it and the callout says "just earned", rather than leaving
//    it sitting far down the track. (Seen-set in localStorage; first ever view seeds silently.)
//  • An EXPAND toggle — the horizontal road folds open into a vertical, tappable list-map
//    that shows every landmark's hint at once (more legible, more interactable).
//
// Researched principles kept: one path not a grid; distinctive landmarks; golden-vs-dim so
// "how far / what's ahead" is legible at a glance; and "juice" (visual + haptic at reward moments).
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { journey, type JourneyNode } from "@/lib/journey";
import { useMyRecipeGlory } from "@/lib/cookbook";

// ── road geometry ────────────────────────────────────────────────────────────
const PAD = 84; // lead-in / lead-out before the first & after the last landmark
const STEP = 132; // horizontal gap between landmarks
const CY = 66; // centre-line
const AMP = 26; // squiggle height
const R = 9; // landmark radius
const HEIGHT = 156;

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

const SEEN_KEY = "brewdiary.journey.seen.v1";

/** Which reached landmarks are NEW since the last visit. First ever view seeds the store
 *  silently (so a long-time user isn't shown every past milestone as "just earned"). */
function useFreshlyEarned(reachedIds: string[]): Set<string> {
  const sig = reachedIds.join(",");
  const [fresh, setFresh] = useState<Set<string>>(new Set());
  useEffect(() => {
    if (typeof window === "undefined") return;
    let seen: string[] | null = null;
    try {
      const raw = window.localStorage.getItem(SEEN_KEY);
      seen = raw === null ? null : (JSON.parse(raw) as string[]);
    } catch {
      seen = [];
    }
    const persist = () => {
      try {
        window.localStorage.setItem(SEEN_KEY, JSON.stringify(reachedIds));
      } catch {
        /* quota / private mode */
      }
    };
    if (seen === null) {
      // first run of this feature — remember where they are, celebrate nothing retroactively
      persist();
      setFresh(new Set());
      return;
    }
    const seenSet = new Set(seen);
    setFresh(new Set(reachedIds.filter((id) => !seenSet.has(id))));
    persist();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sig]);
  return fresh;
}

export function Journey() {
  const entries = useEntries();
  // The two creative side-landmarks (a shared recipe, a medalled one) come from the DB,
  // not the diary — so they ride in as extras; the road itself stays pure and derived.
  const glory = useMyRecipeGlory();
  const j = journey(entries, undefined, { sharedRecipe: glory.shared, medalledRecipe: glory.medalled });
  const [mode, setMode] = useState<"road" | "list">("road");

  const reachedIds = useMemo(() => j.nodes.filter((n) => n.reached).map((n) => n.id), [j.nodes]);
  const freshly = useFreshlyEarned(reachedIds);
  // The newest just-earned landmark — the one we bring the dot to.
  const celebrateIndex = useMemo(() => {
    let idx = -1;
    j.nodes.forEach((n, i) => {
      if (n.reached && freshly.has(n.id)) idx = i;
    });
    return idx;
  }, [j.nodes, freshly]);

  return (
    <div className="relative">
      <div className="mb-1 flex items-center justify-between gap-3">
        <p className="label text-faint">The route</p>
        <div className="flex items-center gap-3">
          <span className="text-xs text-faint">
            {j.exploredFamilies > 0 ? `${j.exploredFamilies} explored` : "not begun"}
          </span>
          <button
            onClick={() => setMode((m) => (m === "road" ? "list" : "road"))}
            aria-pressed={mode === "list"}
            aria-label={mode === "road" ? "Open the full journey" : "Back to the road"}
            className="glass glass-press flex h-7 items-center gap-1 rounded-ctl px-2.5 text-xs text-muted transition-colors hover:text-ink"
          >
            {mode === "road" ? "Expand ↕" : "Road ↔"}
          </button>
        </div>
      </div>

      {mode === "road" ? (
        <RoadView nodes={j.nodes} frontier={j.frontier} freshly={freshly} celebrateIndex={celebrateIndex} />
      ) : (
        <ListView nodes={j.nodes} frontier={j.frontier} freshly={freshly} />
      )}
    </div>
  );
}

// ── the horizontal road ──────────────────────────────────────────────────────
function RoadView({
  nodes,
  frontier,
  freshly,
  celebrateIndex,
}: {
  nodes: JourneyNode[];
  frontier: number;
  freshly: Set<string>;
  celebrateIndex: number;
}) {
  const n = nodes.length;
  const width = PAD * 2 + (n - 1) * STEP;
  const nodeX = useMemo(() => Array.from({ length: n }, (_, i) => PAD + i * STEP), [n]);
  // Where the dot parks on open: the fresh win if there is one, else your frontier.
  const parkIndex = celebrateIndex >= 0 ? celebrateIndex : frontier;
  const parkX = parkIndex >= 0 ? nodeX[parkIndex] : PAD;
  const frontierX = frontier >= 0 ? nodeX[frontier] : PAD;

  const fullD = useMemo(() => buildRoad(0, width), [width]);
  const travelledD = useMemo(() => (frontier >= 0 ? buildRoad(0, frontierX) : ""), [frontier, frontierX]);

  const scrollRef = useRef<HTMLDivElement>(null);
  const [playX, setPlayX] = useState(parkX);
  const focused = clampIndex(Math.round((playX - PAD) / STEP), n);
  const lastBuzzed = useRef<number>(parkIndex);
  const raf = useRef<number | null>(null);

  // Park the dot when the road appears (on the fresh win, or your frontier).
  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollLeft = Math.max(0, parkX - el.clientWidth / 2);
    setPlayX(el.scrollLeft + el.clientWidth / 2);
    lastBuzzed.current = parkIndex;
    if (celebrateIndex >= 0) buzz(28); // a firmer congratulatory tap
  }, [parkX, parkIndex, celebrateIndex]);

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
        buzz(nodes[idx]?.reached ? 18 : 7); // a firmer tap for a landmark you've earned
      }
    });
  }, [n, nodes]);

  useEffect(() => () => void (raf.current != null && cancelAnimationFrame(raf.current)), []);

  const scrollToNode = (i: number) => {
    const el = scrollRef.current;
    if (!el) return;
    el.scrollTo({ left: Math.max(0, nodeX[i] - el.clientWidth / 2), behavior: "smooth" });
  };

  const dotY = roadY(playX);
  const here = nodes[focused];
  const nextIndex = frontier + 1 < n ? frontier + 1 : -1;

  return (
    <div>
      {/* The callout — sits above the centred dot and grows in each time the dot lands on a new
          landmark (keyed re-mount → animate-rise). Points down at the dot with a small notch. */}
      <div className="flex h-14 items-end justify-center">
        {here && (
          <Callout
            key={focused}
            node={here}
            fresh={here.reached && freshly.has(here.id)}
            isNext={!here.reached && focused === nextIndex}
          />
        )}
      </div>

      <div
        ref={scrollRef}
        onScroll={onScroll}
        className="map-grid scrollbar-none -mx-5 overflow-x-auto px-5"
        style={{
          maskImage: "linear-gradient(to right, transparent, #000 8%, #000 92%, transparent)",
          WebkitMaskImage: "linear-gradient(to right, transparent, #000 8%, #000 92%, transparent)",
        }}
      >
        <svg width={width} height={HEIGHT} className="block" role="img" aria-label="Your exploration journey">
          {/* the road ahead — dim, dashed, an invitation */}
          <path d={fullD} fill="none" stroke="var(--color-line-strong)" strokeWidth={3} strokeLinecap="round" strokeDasharray="1 9" opacity={0.7} />
          {/* the road behind — solid gold */}
          {travelledD && <path d={travelledD} fill="none" stroke="var(--color-accent)" strokeWidth={3.5} strokeLinecap="round" />}

          {nodes.map((node, i) => {
            const x = nodeX[i];
            const y = roadY(x);
            const isFocused = i === focused;
            const isFresh = node.reached && freshly.has(node.id);
            const isNext = !node.reached && i === nextIndex;
            const r = isFocused ? R + 4 : R;
            return (
              <g key={node.id} onClick={() => scrollToNode(i)} className="cursor-pointer" aria-label={node.label}>
                {/* a generous invisible hit-target so the small dot is easy to tap */}
                <circle cx={x} cy={y} r={24} fill="transparent" />
                {/* just-earned burst, or the reached halo */}
                {isFresh && <circle cx={x} cy={y} r={r + 10} fill="var(--color-accent)" opacity={0.18} className="motion-safe:animate-ping" />}
                {node.reached && <circle cx={x} cy={y} r={r + 6} fill="var(--color-accent)" opacity={0.16} />}
                {/* the "next up" pulse — a dim ring inviting the step ahead */}
                {isNext && <circle cx={x} cy={y} r={r + 6} fill="none" stroke="var(--color-accent)" strokeWidth={1.5} opacity={0.5} className="motion-safe:animate-pulse" />}
                <circle
                  cx={x}
                  cy={y}
                  r={r}
                  fill={node.reached ? "var(--color-accent)" : "var(--color-canvas)"}
                  stroke={node.reached ? "var(--color-accent)" : "var(--color-line-strong)"}
                  strokeWidth={2}
                  className="transition-all duration-200"
                />
                {node.reached && <circle cx={x} cy={y} r={isFocused ? 4 : 3} fill="var(--color-canvas)" opacity={0.9} />}
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
    </div>
  );
}

// The floating callout above the dot. Amber + "just earned" when it lands on a fresh win,
// a quiet "next" tag when it's resting on the landmark immediately ahead, else just the name.
function Callout({ node, fresh, isNext }: { node: JourneyNode; fresh: boolean; isNext: boolean }) {
  return (
    <div className="motion-safe:animate-rise flex flex-col items-center">
      <div
        className={clsx(
          "max-w-60 rounded-ctl px-3 py-1.5 text-center shadow-[0_2px_10px_rgba(0,0,0,0.12)]",
          fresh ? "bg-accent text-accent-contrast" : "glass-strong",
        )}
      >
        <p className="flex items-center justify-center gap-1.5 text-sm font-medium leading-tight">
          {fresh && <span aria-hidden>✦</span>}
          <span className={clsx(!fresh && (node.reached ? "text-ink" : "text-muted"))}>{node.label}</span>
          {isNext && !fresh && <span className="label text-faint">next</span>}
        </p>
        <p className={clsx("mt-0.5 text-xs leading-snug", fresh ? "text-accent-contrast/80" : "text-faint")}>
          {fresh ? "just earned" : node.hint}
        </p>
      </div>
      {/* little downward notch pointing at the dot */}
      <span
        aria-hidden
        className={clsx("-mt-1 h-2 w-2 rotate-45", fresh ? "bg-accent" : "bg-canvas")}
        style={fresh ? undefined : { boxShadow: "1px 1px 0 var(--color-line)" }}
      />
    </div>
  );
}

// ── the vertical, tappable list-map (the expanded view) ──────────────────────
// The same landmarks, unrolled top-to-bottom. It's meant to feel alive: the rail draws
// itself downward, markers pop in on a stagger, your frontier's NEXT door pulses, and
// tapping any landmark springs open a status line (grid-rows height transition). A slim
// progress track up top shows how far the road is lit — breadth milestones, never volume.
function ListView({ nodes, frontier, freshly }: { nodes: JourneyNode[]; frontier: number; freshly: Set<string> }) {
  const [sel, setSel] = useState<string | null>(null);
  const nextIndex = frontier + 1 < nodes.length ? frontier + 1 : -1;
  const reachedCount = nodes.filter((n) => n.reached).length;
  const pct = Math.round((reachedCount / nodes.length) * 100);

  const scrollRef = useRef<HTMLDivElement>(null);
  const targetIndex = nextIndex >= 0 ? nextIndex : Math.max(0, frontier);
  // The landmark currently under the centre "playhead" — mirrors the road's gliding
  // dot, brought to the vertical view so scrolling feels like a scanner running the
  // route: whichever landmark sits on the centre line lights up, with a haptic tick.
  const [centerIndex, setCenterIndex] = useState(targetIndex);
  const raf = useRef<number | null>(null);
  const lastBuzz = useRef(targetIndex);

  const recenter = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const mid = el.scrollTop + el.clientHeight / 2;
    let best = 0;
    let bestDist = Infinity;
    el.querySelectorAll("li").forEach((li, i) => {
      const c = (li as HTMLElement).offsetTop + (li as HTMLElement).offsetHeight / 2;
      const dist = Math.abs(c - mid);
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    });
    setCenterIndex(best);
    if (best !== lastBuzz.current) {
      lastBuzz.current = best;
      buzz(nodes[best]?.reached ? 12 : 5); // a firmer tick for a landmark you've earned
    }
  }, [nodes]);

  const onScroll = useCallback(() => {
    if (raf.current != null) return;
    raf.current = requestAnimationFrame(() => {
      raf.current = null;
      recenter();
    });
  }, [recenter]);

  // On open: bring the live part of the route to the centre line (next door, else
  // frontier), then sync the playhead to whatever landed there.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const li = el.querySelectorAll("li")[targetIndex] as HTMLElement | undefined;
    if (li) el.scrollTop = Math.max(0, li.offsetTop - el.clientHeight / 2);
    recenter();
  }, [targetIndex, recenter]);

  useEffect(() => () => void (raf.current != null && cancelAnimationFrame(raf.current)), []);

  return (
    <div className="mt-3">
      {/* progress track — fills to your frontier on mount */}
      <div className="mb-4 flex items-center gap-3">
        <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-ink/8">
          <div
            className="h-full rounded-full bg-accent transition-[width] duration-700 ease-out motion-reduce:transition-none"
            style={{ width: `${pct}%` }}
          />
        </div>
        <span className="tnum text-xs text-faint">
          {reachedCount}/{nodes.length}
        </span>
      </div>

      {/* The route as a CONTAINED, vertically-scrolling itinerary — the whole map in a
          fixed window that scrolls in place (top/bottom fade masks), rather than pushing
          the rest of the page down. A centre "playhead" line lights whichever landmark
          scrolls onto it, so the scroll itself is the interaction. */}
      <div className="relative">
        {/* the playhead — a fixed amber scan-line at the viewport centre. Strong over the
            marker rail, faded before the text so it never strikes through a label. */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-1/2 z-10 h-px w-1/2 -translate-y-1/2 bg-linear-to-r from-accent/60 via-accent/20 to-transparent"
        />
        <div
          ref={scrollRef}
          onScroll={onScroll}
          className="scrollbar-none map-grid relative max-h-84 overflow-y-auto rounded-ctl"
          style={{
            maskImage: "linear-gradient(to bottom, transparent, #000 7%, #000 90%, transparent)",
            WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 7%, #000 90%, transparent)",
          }}
        >
      <ol className="py-1">
        {nodes.map((node, i) => {
          const isFresh = node.reached && freshly.has(node.id);
          const isNext = i === nextIndex;
          const passed = !node.reached && i < frontier; // an optional side-stop you've gone past
          const selected = sel === node.id;
          const last = i === nodes.length - 1;
          const isCentered = i === centerIndex; // sitting on the scroll playhead
          return (
            <li key={node.id} className="motion-safe:animate-rise" style={{ animationDelay: `${i * 55}ms` }}>
              <button
                onClick={() => setSel(selected ? null : node.id)}
                aria-expanded={selected}
                className={clsx(
                  "group flex w-full items-stretch gap-3 rounded-ctl py-1 pl-1 pr-2 text-left transition-colors",
                  selected && "bg-accent/5",
                )}
              >
                {/* the rail: a marker + the connector drawing down to the next */}
                <span className="relative flex w-5 shrink-0 flex-col items-center">
                  <span className="relative mt-1.5 grid place-items-center">
                    {isNext && <span aria-hidden className="absolute h-5 w-5 rounded-full bg-accent/25 motion-safe:animate-ping" />}
                    {/* focus halo — a ring that scales in around whichever landmark is on the playhead */}
                    <span
                      aria-hidden
                      className={clsx(
                        "absolute rounded-full border border-accent/45 transition-all duration-300 ease-out",
                        isCentered ? "h-6 w-6 opacity-100" : "h-3.5 w-3.5 opacity-0",
                      )}
                    />
                    <span
                      className={clsx(
                        "relative h-3.5 w-3.5 rounded-full border-2 transition-transform duration-300 group-hover:scale-125",
                        isCentered && "scale-125",
                        node.reached
                          ? "border-accent bg-accent motion-safe:animate-pop"
                          : isNext
                            ? "border-accent bg-canvas motion-safe:animate-pulse"
                            : passed
                              ? "border-accent/45 bg-canvas"
                              : "border-line-strong bg-canvas",
                      )}
                      style={node.reached ? { animationDelay: `${i * 55 + 120}ms` } : undefined}
                    />
                  </span>
                  {!last && (
                    <span
                      className={clsx(
                        "mt-1 w-px flex-1",
                        i < frontier ? "bg-accent/60 motion-safe:animate-grow-down" : "bg-line",
                      )}
                      style={i < frontier ? { animationDelay: `${i * 55}ms` } : undefined}
                    />
                  )}
                </span>

                {/* the content */}
                <span className="min-w-0 flex-1 pb-3">
                  <span className="flex items-center gap-2">
                    <span
                      className={clsx(
                        "text-[15px] leading-tight transition-all duration-300 group-hover:text-ink",
                        node.reached ? "text-ink" : "text-muted",
                        isCentered && "translate-x-0.5 font-medium text-ink",
                      )}
                    >
                      {node.label}
                    </span>
                    {isFresh && (
                      <span className="rounded-xs bg-accent/12 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-widest text-accent">
                        new
                      </span>
                    )}
                    {isNext && !isFresh && <span className="label text-faint">next</span>}
                    <span
                      aria-hidden
                      className={clsx("ml-auto text-sm text-faint transition-transform duration-300", selected && "rotate-90")}
                    >
                      ›
                    </span>
                  </span>
                  <span className="mt-0.5 block text-xs leading-snug text-faint">{node.hint}</span>

                  {/* the detail springs open with a grid-rows height transition (no measuring) */}
                  <span
                    className={clsx(
                      "grid transition-all duration-300 ease-out",
                      selected ? "mt-2 grid-rows-[1fr]" : "grid-rows-[0fr]",
                    )}
                  >
                    <span className="overflow-hidden">
                      <span
                        className={clsx(
                          "block rounded-ctl px-2.5 py-1.5 text-xs",
                          node.reached ? "bg-accent/8 text-accent" : "bg-ink/5 text-muted",
                        )}
                      >
                        {node.reached
                          ? "✦ Reached — lit on your road."
                          : isNext
                            ? "One step away — the next door."
                            : "Ahead — a door still to open."}
                      </span>
                    </span>
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ol>
        </div>
      </div>
    </div>
  );
}

// Sample the sine road between two x's into an SVG path. 6px steps are smooth at this scale.
function buildRoad(fromX: number, toX: number): string {
  let d = "";
  for (let x = fromX; x <= toX; x += 6) {
    d += `${x === fromX ? "M" : "L"}${x.toFixed(1)} ${roadY(x).toFixed(1)} `;
  }
  d += `L${toX.toFixed(1)} ${roadY(toX).toFixed(1)}`;
  return d.trim();
}

function clampIndex(i: number, n: number): number {
  return Math.max(0, Math.min(n - 1, i));
}
