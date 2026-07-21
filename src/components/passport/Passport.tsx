"use client";

// The Taste Passport — a map of the palate you're building, shown under the YEAR view
// (a companion to the year mosaic). Everything is DERIVED from entries + drinks.ts
// (see lib/passport.ts): a family is a binary stamp, so logging the same drink again never
// advances it — the map rewards breadth, never volume, and coffee/tea fill it like spirits.
// It reuses the year mosaic's amber-by-count language so it reads as the same collectible.
import { useState } from "react";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { addWish, useWishlist } from "@/lib/wishlist";
import { useFeed } from "@/lib/friends";
import { intensityLevel } from "@/lib/derive";
import { adjacentStamps, palateNeighbours, passport, type Stamp, type World } from "@/lib/passport";
import { chartedBy, commons } from "@/lib/cartography";
import { useChartedFamilies, useMyProposals, type ChartedFamily } from "@/lib/charts";
import { Journey } from "./Journey";
import { ChartThis } from "./ChartThis";
import type { DrinkType } from "@/lib/types";
import { MONTH_NAMES, parseKey } from "@/lib/date";

// Same dramatic ramp the year mosaic uses — brighter square = more logged in that family.
const FILL = ["transparent", "var(--ycell-1)", "var(--ycell-2)", "var(--ycell-3)", "var(--ycell-4)"] as const;

const WORLD: Record<DrinkType, string> = {
  coffee: "Coffee",
  tea: "Tea",
  beer: "Beer",
  wine: "Wine",
  cocktail: "Cocktails",
  spirit: "Spirits",
  soft: "Soft & sober",
  other: "Other",
  none: "—",
};

export function Passport() {
  const entries = useEntries();
  const charted = useChartedFamilies();
  const p = passport(entries);
  const [stamp, setStamp] = useState<Stamp | null>(null);
  const c = commons(charted);

  return (
    <section className="mt-10">
      {/* Section header matches every other section in You (label-scale) — the page already
          has one h1, and the map shouldn't compete with it. */}
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <h2 className="label">Passport</h2>
        <span className="text-xs text-faint">
          {p.exploredFamilies > 0
            ? `${p.exploredFamilies} famil${p.exploredFamilies === 1 ? "y" : "ies"} & counting`
            : "your taste passport"}
        </span>
      </div>

      {/* The hero: your exploration as one winding road you scroll along (see Journey.tsx).
          Shown even before your first stamp — a whole trail of landmarks lying ahead. */}
      <Journey />

      {p.exploredFamilies === 0 ? (
        <p className="mt-3 text-center text-xs text-faint">
          Log a drink and its family lights the first landmark — the road fills in as you wander.
        </p>
      ) : (
        <div className="mt-6 space-y-6">
          {/* The silhouette of a taste — the ownable identity. */}
          <PaletteSilhouette worlds={p.worlds} />

          {/* One or two doors out of the map you have. Widens, never deepens. */}
          <WanderHere />

          {/* The worlds — stamps you've lit, and the ones still to wander. */}
          {p.worlds.map((w) => (
            <div key={w.type}>
              <p className="label mb-2 text-faint">{WORLD[w.type]}</p>
              <div className="flex flex-wrap gap-1.5">
                {w.stamps.map((s) => (
                  <StampChip key={s.family} stamp={s} onOpen={() => setStamp(s)} />
                ))}
              </div>
            </div>
          ))}

          {/* Off the map — novel drinks that are regions all your own, and the ones
              you can offer to the shared dictionary (see ChartThis in the sheet). */}
          {p.offMap.length > 0 && (
            <div>
              <p className="label mb-2 text-faint">Off the map</p>
              <div className="flex flex-wrap gap-1.5">
                {p.offMap.map((s) => (
                  <StampChip key={s.family} stamp={s} onOpen={() => setStamp(s)} />
                ))}
              </div>
            </div>
          )}

          {/* The commons: how big the shared map is, and how much of it drinkers drew.
              A count of FAMILIES — there is deliberately no per-person figure anywhere. */}
          {c.charted > 0 && (
            <p className="text-xs text-faint">
              The map holds {c.families} families · {c.charted} charted by drinkers.
            </p>
          )}
        </div>
      )}

      {stamp && <StampSheet stamp={stamp} charted={charted} onClose={() => setStamp(null)} />}
    </section>
  );
}

// ── the curiosity loop (CD7) ─────────────────────────────────────────────────
// "Wander here" — a few families you HAVEN'T logged, drawn from the worlds you already
// wander, what friends pour, and one deliberate seed from a world you've barely entered.
// It never suggests more of what you already drink, and it never ranks by alcohol: a
// chamomile can outrank a mezcal (see lib/passport.palateNeighbours). One action only —
// save it to your to-try list. No spark, no perk, no discount: exploring is its own reward.
function WanderHere() {
  const entries = useEntries();
  const wishlist = useWishlist();
  const { feed } = useFeed();

  const picks = palateNeighbours(
    entries,
    feed.map((f) => ({ drink: f.drink, author: f.author.id })),
    wishlist.map((w) => w.drink),
    4,
  );
  if (picks.length === 0) return null;

  return (
    <div data-testid="wander-here" className="glass rounded-tile p-5">
      <p className="label mb-1 text-faint">Wander here</p>
      <p className="mb-3 text-xs text-faint">Corners of the map you haven&apos;t been to yet.</p>
      <div className="flex flex-wrap gap-2">
        {/* No "saved" state here on purpose: palateNeighbours excludes anything already on
            your to-try list, so saving one removes it from these suggestions on the next
            render. The confirmation is the chip leaving and the drink appearing in To try
            just below — a "saved" label would be unreachable code pretending otherwise. */}
        {picks.map((s) => (
          <button
            key={s.family}
            onClick={() => addWish(s.family)}
            className="min-h-11 rounded-ctl border border-line px-3 py-2 text-sm text-ink transition-colors hover:border-line-strong"
          >
            {s.family}
            <span className="ml-2 text-xs text-faint">+ to try</span>
          </button>
        ))}
      </div>
    </div>
  );
}

// The palate silhouette — the "shape of your taste" as one slim spectrum: each world
// you've entered is a segment, widest = most-explored, amber deepening with its share.
// A single family reads as one clean segment, so it never looks like an empty box (the
// old multi-row version did, especially when the only find was off-map). Purely a
// relative SHAPE — never an "X of N" completion figure, which would make the map a set
// to finish, i.e. a reason to drink more. Hidden until at least one world is entered.
function PaletteSilhouette({ worlds }: { worlds: World[] }) {
  const explored = worlds
    .filter((w) => w.exploredCount > 0)
    .sort((a, b) => b.exploredCount - a.exploredCount);
  if (explored.length === 0) return null;

  const total = explored.reduce((n, w) => n + w.exploredCount, 0);
  const max = explored[0].exploredCount;
  // Amber deepens with a world's share of your palate — a gentle single-hue ramp, so
  // adjacent segments read apart without a second colour (LILA: one accent, never a rainbow).
  const amber = (c: number) => 0.4 + 0.6 * (c / max);

  return (
    <div className="glass rounded-tile p-5">
      <p className="label mb-3 text-faint">Your palate</p>
      <div className="flex h-3 gap-0.5">
        {explored.map((w) => (
          <div
            key={w.type}
            className="h-full rounded-full bg-accent"
            style={{ width: `${(w.exploredCount / total) * 100}%`, opacity: amber(w.exploredCount) }}
            title={`${WORLD[w.type]} · ${w.exploredCount}`}
          />
        ))}
      </div>
      <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1.5">
        {explored.map((w) => (
          <span key={w.type} className="inline-flex items-center gap-1.5 text-xs text-muted">
            <span aria-hidden className="h-2 w-2 rounded-full bg-accent" style={{ opacity: amber(w.exploredCount) }} />
            {WORLD[w.type]}
            <span className="tnum text-faint">{w.exploredCount}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

function StampChip({ stamp, onOpen }: { stamp: Stamp; onOpen: () => void }) {
  const level = stamp.explored ? Math.max(1, intensityLevel(stamp.drinks.length)) : 0;
  return (
    <button
      onClick={onOpen}
      className={clsx(
        "inline-flex items-center gap-1.5 rounded-ctl border px-2.5 py-1.5 text-xs transition-colors",
        stamp.explored
          ? "border-transparent bg-accent/8 text-ink"
          : "border-line text-faint hover:border-line-strong hover:text-muted",
      )}
    >
      <span
        aria-hidden
        className={clsx("h-3 w-3 shrink-0 rounded-xs", !stamp.explored && "shadow-[inset_0_0_0_1px_var(--color-line-strong)]")}
        style={{ background: FILL[level] }}
      />
      {stamp.family}
    </button>
  );
}

// Tap a stamp: what it is, when you first poured it, the drinks you've had in it — or, if
// you haven't wandered here yet, one tap to add it to your "to try" list (the wishlist).
function StampSheet({
  stamp,
  charted,
  onClose,
}: {
  stamp: Stamp;
  charted: ChartedFamily[];
  onClose: () => void;
}) {
  const entries = useEntries();
  const mine = useMyProposals();
  const [added, setAdded] = useState(false);
  const [saved, setSaved] = useState<Set<string>>(new Set());
  const since = stamp.firstExplored ? parseKey(stamp.firstExplored) : null;
  // Every stamp is a door to another: the nearest places in this world you haven't been.
  const nextDoor = adjacentStamps(entries, stamp);
  // Who drew this one, if a drinker did. The dictionary's own families credit nobody.
  const drawnBy = chartedBy(stamp.family, charted);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={stamp.family}
      className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
    >
      <button aria-label="Close" onClick={onClose} className="animate-fade absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div className="glass-strong animate-sheet relative w-full max-w-md rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4 sm:rounded-tile">
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong sm:hidden" />
        <p className="label text-faint">{stamp.matched ? "family" : "your own"}</p>
        <p className="mt-1 font-display text-3xl leading-none text-ink">{stamp.family}</p>
        {since && (
          <p className="mt-2 text-xs text-faint">
            First poured {MONTH_NAMES[since.getMonth()].slice(0, 3)} {since.getDate()}, {since.getFullYear()}.
          </p>
        )}
        {/* The entire reward for charting: one quiet line, and no number anywhere near it. */}
        {drawnBy && <p className="mt-1 text-xs text-faint">Charted by {drawnBy}.</p>}

        {stamp.explored ? (
          <div className="mt-5">
            <p className="label mb-2 text-faint">What you&apos;ve had</p>
            <div className="flex flex-wrap gap-1.5">
              {stamp.drinks.map((d) => (
                <span key={d} className="rounded-ctl border border-line px-2.5 py-1 text-sm text-muted">
                  {d}
                </span>
              ))}
            </div>
          </div>
        ) : (
          <div className="mt-5">
            <p className="text-sm text-muted">You haven&apos;t wandered here yet.</p>
            <button
              onClick={() => {
                addWish(stamp.family);
                setAdded(true);
              }}
              disabled={added}
              className="mt-3 min-h-11 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-60"
            >
              {added ? "Added to “to try”" : "Add to “to try”"}
            </button>
          </div>
        )}

        {/* An off-map drink is a gap in the shared dictionary — you can offer to fill it. */}
        {!stamp.matched && <ChartThis rawName={stamp.family} mine={mine} />}

        {stamp.explored && nextDoor.length > 0 && (
          <div className="mt-5 border-t border-line pt-4">
            <p className="label mb-2 text-faint">Next door</p>
            <div className="flex flex-wrap gap-2">
              {nextDoor.map((s) => {
                const isSaved = saved.has(s.family);
                return (
                  <button
                    key={s.family}
                    onClick={() => {
                      addWish(s.family);
                      setSaved((prev) => new Set(prev).add(s.family));
                    }}
                    disabled={isSaved}
                    className={clsx(
                      "min-h-11 rounded-ctl border px-3 py-2 text-sm transition-colors",
                      isSaved
                        ? "border-transparent bg-accent/8 text-muted"
                        : "border-line text-ink hover:border-line-strong",
                    )}
                  >
                    {s.family}
                    <span className="ml-2 text-xs text-faint">{isSaved ? "saved" : "+ to try"}</span>
                  </button>
                );
              })}
            </div>
          </div>
        )}

        <button
          onClick={onClose}
          className="mt-6 flex h-11 w-full items-center justify-center rounded-ctl text-sm text-faint transition-colors hover:text-ink"
        >
          Close
        </button>
      </div>
    </div>
  );
}
