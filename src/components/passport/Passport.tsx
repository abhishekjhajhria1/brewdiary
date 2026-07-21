"use client";

// The Taste Passport — a map of the palate you're building, shown under the YEAR view
// (a companion to the year mosaic). Everything is DERIVED from entries + drinks.ts
// (see lib/passport.ts): a family is a binary stamp, so logging the same drink again never
// advances it — the map rewards breadth, never volume, and coffee/tea fill it like spirits.
// It reuses the year mosaic's amber-by-count language so it reads as the same collectible.
import { useState } from "react";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { addWish } from "@/lib/wishlist";
import { intensityLevel } from "@/lib/derive";
import { adjacentStamps, passport, type Stamp, type World } from "@/lib/passport";
import { chartedBy, commons } from "@/lib/cartography";
import { useChartedFamilies, useMyProposals, type ChartedFamily } from "@/lib/charts";
import { Journey } from "./Journey";
import { Expeditions } from "../expeditions/Expeditions";
import { trophies } from "@/lib/expeditions";
import { scoreFromEntries } from "@/lib/score";
import { ScoreBanner } from "../ui/ScoreBanner";
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

      {/* The Palate Score — the exploration metric, front and centre (breadth + consistency,
          never volume; lib/score). The same banner the profile leads with. */}
      {entries.length > 0 && (
        <div className="glass mb-4 rounded-tile p-5">
          <ScoreBanner ps={scoreFromEntries(entries)} size={84} />
        </div>
      )}

      {/* The hero: your exploration as one winding road you scroll along (see Journey.tsx).
          Shown even before your first stamp — a whole trail of landmarks lying ahead. */}
      <Journey />

      {/* Tonight — the one actionable thing, right under the road (a new user has quests too). */}
      <div className="mt-8">
        <Expeditions />
      </div>

      {p.exploredFamilies === 0 ? (
        <p className="mt-6 text-center text-xs text-faint">
          Log a drink and its family lights the first landmark — the road fills in as you wander.
        </p>
      ) : (
        <div className="mt-10 space-y-8">
          {/* The silhouette of a taste — the ownable identity. */}
          <PaletteSilhouette worlds={p.worlds} />

          {/* What you've collected — only the lit stamps, celebrated (no wall of empty boxes). */}
          <Collected worlds={p.worlds} onOpen={setStamp} />

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

      {/* Achievements — the trophy shelf. Every badge is breadth or a gentle behaviour
          (a dry day in the week), never volume or difficulty (lib/expeditions trophies). */}
      <div className="mt-10">
        <Trophies />
      </div>

      {stamp && <StampSheet stamp={stamp} charted={charted} onClose={() => setStamp(null)} />}
    </section>
  );
}

// ── Collected — the lit stamps, celebrated ───────────────────────────────────
// Only the families you've ACTUALLY explored, grouped by the worlds you've entered.
// This is the gallery of what you have (Untappd-style collection) — the wall of every
// unexplored family lives behind "See the whole map" instead, so this reads as a
// keepsake, not a to-do list. Tapping a stamp opens its sheet (keepsake + next door).
function Collected({ worlds, onOpen }: { worlds: World[]; onOpen: (s: Stamp) => void }) {
  const entered = worlds.filter((w) => w.exploredCount > 0);
  if (entered.length === 0) return null;
  return (
    <div>
      <p className="label mb-3 text-faint">Collected</p>
      <div className="space-y-4">
        {entered.map((w) => (
          <div key={w.type}>
            <p className="mb-1.5 flex items-baseline gap-1.5 text-xs text-muted">
              {WORLD[w.type]}
              <span className="tnum text-faint">{w.exploredCount}</span>
            </p>
            <div className="flex flex-wrap gap-1.5">
              {w.stamps
                .filter((s) => s.explored)
                .map((s) => (
                  <StampChip key={s.family} stamp={s} onOpen={() => onOpen(s)} />
                ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Achievements — the trophy shelf ──────────────────────────────────────────
// A calm collection you fill by EXPLORING (breadth) or a gentle behaviour signal, never by
// drinking more (lib/expeditions.trophies enforces that). Earned badges glow amber; the rest
// are dim invitations that read as "here's what's out there", never a scolding checklist —
// so no "X of N to finish" figure, only how many you've earned. Freshly-earned ones are
// separately celebrated on the journey road (see Journey.tsx), so this stays a quiet cabinet.
function Trophies() {
  const entries = useEntries();
  const all = trophies(entries);
  const earned = all.filter((t) => t.earned).length;
  return (
    <div>
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <p className="label text-faint">Achievements</p>
        <span className="tnum text-xs text-faint">{earned > 0 ? `${earned} earned` : "none yet"}</span>
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {all.map((t) => (
          <div
            key={t.id}
            className={clsx("rounded-tile border p-3", t.earned ? "border-transparent bg-accent/8" : "border-line")}
          >
            <div className="flex items-center gap-2">
              <span
                aria-hidden
                className={clsx(
                  "grid h-6 w-6 shrink-0 place-items-center rounded-full text-xs",
                  t.earned ? "bg-accent text-accent-contrast" : "bg-ink/5 text-faint",
                )}
              >
                {t.earned ? "✦" : "○"}
              </span>
              <p className={clsx("text-sm leading-tight", t.earned ? "text-ink" : "text-faint")}>{t.title}</p>
            </div>
            <p className="mt-1.5 text-xs leading-snug text-faint">{t.note}</p>
          </div>
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
