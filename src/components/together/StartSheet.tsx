"use client";

// "+ Start" — one button for everything you can begin in Together.
//
// Creating things used to mean knowing which of five rooms held the form: "Plan a
// night" in Plans, "Host one" in Parties, "New cup" in Cups, "New circle" in
// Circles, "Write a recipe" in Recipes. Five verbs, five places, none of them where
// you were. This is the one door.
//
// It does not duplicate any of those forms. A night opens the real composer inline
// (the common case, so it's one tap from anywhere); the rest hand you to their room
// with a note about what you'll find — one screen further, but findable at all,
// which they weren't.
import { useEffect } from "react";
import { useRouter } from "next/navigation";

const ELSEWHERE = [
  { href: "/together/cups", label: "A cup", blurb: "A small exploration contest with friends, over a window you set." },
  { href: "/together/circles", label: "A circle", blurb: "A private room for a few people and one shared mosaic." },
  { href: "/together/recipes", label: "A recipe", blurb: "Invent a drink — by hand, or drafted with Ninkasi." },
];

export function StartSheet({ onClose, onStartNight }: { onClose: () => void; onStartNight: () => void }) {
  const router = useRouter();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Start something"
      className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
    >
      <button aria-label="Close" onClick={onClose} className="animate-fade absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div className="glass-strong animate-sheet relative w-full max-w-md rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4 sm:rounded-tile">
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong sm:hidden" />
        <p className="label text-faint">Start</p>
        <p className="mt-1 font-display text-3xl leading-none text-ink">What are we doing?</p>

        <ul className="mt-5 space-y-2">
          <li>
            <button
              onClick={() => {
                onClose();
                onStartNight();
              }}
              className="glass glass-press flex w-full items-center justify-between gap-3 rounded-tile px-4 py-3.5 text-left"
            >
              <span className="min-w-0">
                <span className="block text-[15px] text-ink">A night</span>
                <span className="mt-0.5 block text-xs leading-relaxed text-faint">
                  Yours alone, a few friends, or a link for the group chat. It becomes the room on the day.
                </span>
              </span>
              <span aria-hidden className="shrink-0 text-sm text-accent">
                →
              </span>
            </button>
          </li>
          {ELSEWHERE.map((r) => (
            <li key={r.href}>
              <button
                onClick={() => {
                  onClose();
                  router.push(r.href);
                }}
                className="glass glass-press flex w-full items-center justify-between gap-3 rounded-tile px-4 py-3.5 text-left"
              >
                <span className="min-w-0">
                  <span className="block text-[15px] text-ink">{r.label}</span>
                  <span className="mt-0.5 block text-xs leading-relaxed text-faint">{r.blurb}</span>
                </span>
                <span aria-hidden className="shrink-0 text-sm text-accent">
                  →
                </span>
              </button>
            </li>
          ))}
        </ul>

        <button
          onClick={onClose}
          className="mt-3 flex h-11 w-full items-center justify-center rounded-ctl text-sm text-faint transition-colors hover:text-ink"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
