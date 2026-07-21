"use client";

// The weekly discovery recap — the calm "come back and look" the app otherwise lacks.
//
// Three quiet things: the stamps you first lit this week, one resurfaced memory, and one
// door you haven't walked through. All DERIVED (lib/passport.weeklyDiscovery) — nothing new
// is stored.
//
// Deliberately NOT a nudge to drink. It never says "you're behind", never counts what you
// didn't do, and a week with no new stamps simply shows nothing rather than scolding. It is
// OFF until you ask for it in You → Settings, and dismissing it buys a week of silence.
import { useState } from "react";
import { useEntries } from "@/lib/store";
import { useWishlist, addWish } from "@/lib/wishlist";
import { useFeed } from "@/lib/friends";
import { weeklyDiscovery } from "@/lib/passport";
import { dismissRecap, useRecapVisible } from "@/lib/recap";
import { MONTH_NAMES, parseKey } from "@/lib/date";

export function WeeklyRecap() {
  const visible = useRecapVisible();
  const entries = useEntries();
  const wishlist = useWishlist();
  const { feed } = useFeed();
  const [saved, setSaved] = useState(false);

  const d = weeklyDiscovery(entries, {
    friendDrinks: feed.map((f) => ({ drink: f.drink, author: f.author.id })),
    wishlist: wishlist.map((w) => w.drink),
  });

  // Nothing to say is a fine outcome — a quiet week is not a failure to report.
  if (!visible || (d.newStamps.length === 0 && !d.memory && !d.nudge)) return null;

  const memoryOn = d.memory ? parseKey(d.memory.date) : null;

  return (
    <section className="animate-rise glass mt-6 rounded-tile p-5">
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <p className="label text-faint">Your week</p>
        <button
          onClick={() => dismissRecap()}
          className="-m-2 min-h-11 p-2 text-xs text-faint transition-colors hover:text-ink"
        >
          dismiss
        </button>
      </div>

      {d.newStamps.length > 0 && (
        <div className="mb-4">
          <p className="text-sm text-ink">
            {d.newStamps.length === 1 ? "One new corner of the map" : `${d.newStamps.length} new corners of the map`}
          </p>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {d.newStamps.map((s) => (
              <span key={s.family} className="rounded-ctl bg-accent/8 px-2.5 py-1 text-sm text-ink">
                {s.family}
              </span>
            ))}
          </div>
        </div>
      )}

      {d.memory && memoryOn && (
        <div className="mb-4 border-t border-line pt-3">
          <p className="label mb-1 text-faint">Looking back</p>
          <p className="text-sm text-muted">
            {d.memory.drink}
            {d.memory.mood && <span className="italic"> · {d.memory.mood}</span>}
            <span className="text-faint">
              {" "}
              — {MONTH_NAMES[memoryOn.getMonth()].slice(0, 3)} {memoryOn.getDate()}, {memoryOn.getFullYear()}
            </span>
          </p>
        </div>
      )}

      {d.nudge && (
        <div className="border-t border-line pt-3">
          <p className="label mb-2 text-faint">A door</p>
          <button
            onClick={() => {
              addWish(d.nudge!.family);
              setSaved(true);
            }}
            disabled={saved}
            className="min-h-11 rounded-ctl border border-line px-3 py-2 text-sm text-ink transition-colors hover:border-line-strong disabled:border-transparent disabled:bg-accent/8 disabled:text-muted"
          >
            {d.nudge.family}
            <span className="ml-2 text-xs text-faint">{saved ? "saved" : "+ to try"}</span>
          </button>
        </div>
      )}
    </section>
  );
}
