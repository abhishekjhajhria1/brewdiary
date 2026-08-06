"use client";

// To-try — the drinks you mean to get to, and the ones friends put in front of you.
//
// The two halves feed each other, which is why they share a room: a friend pours
// something (FriendPicks, derived from the feed), you save it, it lands on your list,
// and tapping it writes it into the diary — because the calendar is the home, and
// trying something new belongs on a day.
//
// This was buried at the bottom of the old Feed tab, under two other sections. It
// now has its own route, reachable from the hub.
import { useEffect, useMemo, useState } from "react";
import clsx from "clsx";
import { useFeed } from "@/lib/friends";
import { useEntries, addEntry } from "@/lib/store";
import { useWishlist, addWish, removeWish, type WishItem } from "@/lib/wishlist";
import { DRINKS, canonicalize, normalize } from "@/lib/drinks";
import { friendPicks } from "@/lib/derive";
import { todayKey } from "@/lib/date";

export function ToTryRoom() {
  return (
    <>
      <FriendPicks />
      <YourList />
    </>
  );
}

// The regulars half of the recommendation spec — drinks friends pour that you
// haven't logged, most-shared first, one tap to save.
function FriendPicks() {
  const { feed } = useFeed();
  const myEntries = useEntries();
  const wishlist = useWishlist();
  const [added, setAdded] = useState<Set<string>>(new Set());

  const picks = friendPicks(
    feed.map((f) => ({ drink: f.drink, author: f.author.id })),
    myEntries.map((e) => e.drink),
    wishlist.map((w) => w.drink),
    6,
  );
  if (picks.length === 0) return null;

  return (
    <section className="mt-6">
      <p className="label mb-3 text-faint">From friends</p>
      <div className="flex flex-wrap gap-2">
        {picks.map((drink) => {
          const key = drink.toLowerCase();
          const isAdded = added.has(key);
          return (
            <button
              key={key}
              onClick={() => {
                addWish(drink);
                setAdded((s) => new Set(s).add(key));
              }}
              disabled={isAdded}
              className={clsx(
                "glass glass-press min-h-11 rounded-ctl px-3.5 py-2 text-sm transition-colors",
                isAdded ? "text-faint" : "text-ink hover:text-accent",
              )}
            >
              {drink} <span className={isAdded ? "text-faint" : "text-accent"}>{isAdded ? "✓" : "+"}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

function YourList() {
  const items = useWishlist();
  const entries = useEntries();
  const [draft, setDraft] = useState("");
  const [logging, setLogging] = useState<WishItem | null>(null);

  // Suggestions: every dictionary drink you haven't logged and haven't listed yet.
  // A stand-in for the personalised pick Ninkasi will make once the app matures — for
  // now a shuffle of what's known, and it never repeats something already yours.
  const suggestions = useMemo(() => {
    const seen = new Set<string>();
    for (const e of entries) seen.add(normalize(e.drink));
    for (const w of items) seen.add(normalize(w.drink));
    return DRINKS.map((d) => d.canonical).filter((name) => !seen.has(normalize(name)));
  }, [entries, items]);

  const [pick, setPick] = useState<string | null>(null);
  useEffect(() => {
    // Keep a valid pick: choose one initially, and re-choose if the current pick just
    // left the pool (you logged it or added it to the list).
    if (suggestions.length === 0) {
      setPick(null);
      return;
    }
    setPick((cur) =>
      cur && suggestions.includes(cur) ? cur : suggestions[Math.floor(Math.random() * suggestions.length)],
    );
  }, [suggestions]);

  function another() {
    if (suggestions.length === 0) return;
    setPick((cur) => {
      if (suggestions.length === 1) return suggestions[0];
      let n = cur;
      while (n === cur) n = suggestions[Math.floor(Math.random() * suggestions.length)];
      return n;
    });
  }

  return (
    <section className="mt-10">
      <p className="label mb-3 text-faint">Your list</p>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          addWish(draft);
          setDraft("");
        }}
        className="mb-3 flex items-center gap-2"
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Add a drink you're curious about…"
          aria-label="Add a drink to your to-try list"
          className="flex-1 border-b border-line-strong bg-transparent pb-2 text-sm outline-none placeholder:text-faint focus:border-ink"
        />
        <button
          type="submit"
          disabled={!draft.trim()}
          className={clsx(
            "min-h-11 rounded-ctl px-3 py-1.5 text-xs uppercase tracking-[0.12em] transition-colors",
            draft.trim() ? "bg-ink text-paper hover:bg-ink/90" : "cursor-not-allowed bg-ink/10 text-faint",
          )}
        >
          Add
        </button>
      </form>

      {!pick && items.length === 0 ? (
        <p className="py-2 text-sm text-faint">
          Nothing to try yet — add a drink above, or save one from a friend&apos;s pour.
        </p>
      ) : (
        <ul className="glass max-h-80 divide-y divide-line overflow-y-auto rounded-tile px-5">
          {pick && (
            <li className="flex items-center justify-between gap-3 py-2.5">
              <div className="min-w-0">
                <p className="label text-faint">suggested</p>
                <p className="truncate text-[15px] text-ink">{pick}</p>
              </div>
              <div className="flex shrink-0 items-center gap-3">
                <button type="button" onClick={another} className="min-h-11 text-xs text-faint transition-colors hover:text-ink">
                  Another
                </button>
                <button
                  type="button"
                  onClick={() => addWish(pick)}
                  className="min-h-11 rounded-ctl bg-ink px-3 py-1.5 text-xs uppercase tracking-[0.12em] text-paper transition-colors hover:bg-ink/90"
                >
                  Add
                </button>
              </div>
            </li>
          )}
          {items.map((w) => (
            <li key={w.id} className="flex items-center justify-between gap-3 py-2.5">
              <button
                onClick={() => setLogging(w)}
                className="flex min-h-11 min-w-0 flex-1 items-center gap-2.5 text-left"
                aria-label={`Log ${w.drink} to your diary`}
              >
                <span
                  aria-hidden
                  className="flex h-4 w-4 shrink-0 items-center justify-center rounded-[3px] border border-line-strong text-[10px] leading-none text-transparent"
                >
                  ✓
                </span>
                <span className="truncate text-[15px] text-ink">{w.drink}</span>
              </button>
              <button
                onClick={() => removeWish(w.id)}
                aria-label={`Remove ${w.drink}`}
                className="min-h-11 shrink-0 text-sm text-faint transition-colors hover:text-ink"
              >
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}

      {logging && <LogWishPopup item={logging} onClose={() => setLogging(null)} />}
    </section>
  );
}

// Tapping a "to try" drink offers to write it into the diary. Pick the day (today by
// default); it logs the entry and takes the drink OFF the list. Kind is pre-derived
// from the name. Styled to match the log sheet so it feels like the rest of the app.
function LogWishPopup({ item, onClose }: { item: WishItem; onClose: () => void }) {
  const [date, setDate] = useState(todayKey());

  function log() {
    const canon = canonicalize(item.drink);
    addEntry({ date, drink: item.drink, type: canon.type });
    void removeWish(item.id); // logged → off the to-try list
    onClose();
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Log ${item.drink}`}
      className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
    >
      <button aria-label="Close" onClick={onClose} className="animate-fade absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div className="glass-strong animate-sheet relative w-full max-w-md rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4 sm:rounded-tile">
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong sm:hidden" />
        <p className="label text-faint">Log to your diary</p>
        <p className="mt-1 font-display text-3xl leading-none text-ink">{item.drink}</p>
        <label className="mt-5 block">
          <span className="mb-1.5 block text-xs text-muted">Which day</span>
          <input
            type="date"
            value={date}
            max={todayKey()}
            onChange={(e) => setDate(e.target.value)}
            className="glass w-full rounded-ctl px-4 py-3 text-[15px] text-ink"
          />
        </label>
        <button
          onClick={log}
          className="mt-5 flex h-12 w-full items-center justify-center rounded-ctl bg-ink text-base font-medium text-paper transition-opacity hover:opacity-90"
        >
          Log it
        </button>
        <button
          onClick={onClose}
          className="mt-2 flex h-11 w-full items-center justify-center rounded-ctl text-sm text-faint transition-colors hover:text-ink"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
