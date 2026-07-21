"use client";

// Expeditions — the exploration game, shown right under the Passport (you play ON the map the
// Passport draws). All DERIVED (lib/expeditions.ts): a small hand of do-able "try this" cards
// plus a collection trophy shelf. See internal/phase-c-expeditions.md for the full design.
//
// House rules made visible here:
//  • Fun-first, not difficulty — `effort` shows only as a quiet tag, never a lock or a level.
//  • Choose Your Path (Pokémon GO) — the four vibe chips bias which cards surface, nothing more.
//  • Breadth, never volume — a card points at a family you HAVEN'T explored; logging it once is
//    the whole ask, and the card then leaves (the hand self-advances). No card counts drinks.
//  • One action only — save the drink to your to-try list. No spark, no perk: exploring is the reward.
import { useEffect, useState } from "react";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { usePantry } from "@/lib/pantry";
import { addWish, useWishlist } from "@/lib/wishlist";
import { useFeed } from "@/lib/friends";
import { expeditionHand, type Quest, type Vibe } from "@/lib/expeditions";
import { useVibe, setVibe } from "@/lib/expeditionPath";
import { todayKey } from "@/lib/date";

const PATHS: { vibe: Vibe; label: string }[] = [
  { vibe: "cozy", label: "Cozy" },
  { vibe: "social", label: "Social" },
  { vibe: "explorer", label: "Explorer" },
  { vibe: "bold", label: "Bold" },
];

const WHERE_LABEL: Record<Quest["where"], string | null> = { home: "at home", out: "out", any: null };

export function Expeditions() {
  const entries = useEntries();
  const pantry = usePantry();
  const wishlist = useWishlist();
  const { feed } = useFeed();
  const vibe = useVibe();

  const hand = expeditionHand(
    {
      entries,
      pantry,
      friendDrinks: feed.map((f) => ({ drink: f.drink, author: f.author.id })),
      wishlist: wishlist.map((w) => w.drink),
    },
    { vibe: vibe ?? undefined },
  );

  return (
    <div>
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <p className="label text-faint">Tonight</p>
        <span className="text-xs text-faint">a few doors to wander</span>
      </div>

      {/* Choose your path — biases the flavour of the hand, never the difficulty. Tapping the
          active one again clears it, back to a balanced mix. */}
      <div className="mb-3 flex flex-wrap gap-1.5">
        {PATHS.map(({ vibe: v, label }) => {
          const active = vibe === v;
          return (
            <button
              key={v}
              onClick={() => setVibe(active ? null : v)}
              aria-pressed={active}
              className={clsx(
                "min-h-11 rounded-ctl border px-3 py-2 text-sm transition-colors",
                active
                  ? "border-transparent bg-accent/8 text-ink"
                  : "border-line text-muted hover:border-line-strong hover:text-ink",
              )}
            >
              {label}
            </button>
          );
        })}
      </div>

      <div className="space-y-2">
        {hand.map((q, i) => (
          // The LAST card of a full hand arrives face-down — a small, honest slot-pull of
          // curiosity (variable reward pointed at EXPLORING, never at drinking). Once looked
          // at it stays open for the day; tomorrow's hand deals a fresh unknown.
          <QuestCard key={q.id} quest={q} mystery={hand.length >= 2 && i === hand.length - 1} />
        ))}
      </div>
    </div>
  );
}

// Which day's mystery has been peeked, kept per-device so the card doesn't re-hide on
// every remount within the same evening. One key, overwritten daily.
const MYSTERY_KEY = "brewdiary.mystery.v1";
function peekedToday(): boolean {
  try {
    return window.localStorage.getItem(MYSTERY_KEY) === todayKey();
  } catch {
    return false;
  }
}
function markPeeked() {
  try {
    window.localStorage.setItem(MYSTERY_KEY, todayKey());
  } catch {
    /* private mode — the card simply re-hides next mount */
  }
}

// One card in tonight's hand. A card with a target family gets a single action — save it to your
// to-try list (like Wander here). An open invitation (chart something / go somewhere new / a quiet
// night) has no family to save, so it's just a prompt — a standing door, not a task to tick.
function QuestCard({ quest, mystery = false }: { quest: Quest; mystery?: boolean }) {
  const [saved, setSaved] = useState(false);
  // Face-down until tapped (or until it was already peeked today). Starts revealed on the
  // server render, then hides after mount if unpeeked — avoids a hydration mismatch.
  const [revealed, setRevealed] = useState(true);
  useEffect(() => {
    if (mystery && !peekedToday()) setRevealed(false);
  }, [mystery]);
  const where = WHERE_LABEL[quest.where];

  if (!revealed) {
    return (
      <button
        type="button"
        onClick={() => {
          markPeeked();
          setRevealed(true);
        }}
        className="glass glass-press w-full rounded-tile border-dashed p-4 text-left"
      >
        <p className="text-sm text-ink">A door you haven&apos;t opened.</p>
        <p className="mt-1 text-xs text-faint">Tonight&apos;s wildcard — tap to look.</p>
      </button>
    );
  }

  return (
    <div className={clsx("glass rounded-tile p-4", mystery && "animate-pop")}>
      <p className="text-sm text-ink">{quest.title}</p>
      {quest.hint && <p className="mt-1 text-xs text-faint">{quest.hint}</p>}
      <div className="mt-2.5 flex items-center gap-2 text-xs text-faint">
        {/* effort is a descriptive tag, never a gate — so it reads as a mood, not a difficulty lock */}
        <span className="rounded-xs bg-ink/5 px-1.5 py-0.5">{quest.effort}</span>
        {where && <span>· {where}</span>}
        {quest.target && (
          <button
            onClick={() => {
              addWish(quest.target!);
              setSaved(true);
            }}
            disabled={saved}
            className={clsx(
              "ml-auto min-h-11 rounded-ctl border px-3 py-2 text-xs transition-colors",
              saved ? "border-transparent bg-accent/8 text-muted" : "border-line text-ink hover:border-line-strong",
            )}
          >
            {saved ? "saved" : "+ to try"}
          </button>
        )}
      </div>
    </div>
  );
}
