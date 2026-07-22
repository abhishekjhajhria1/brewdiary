"use client";

import { useEffect, useState } from "react";
import clsx from "clsx";
import { getStoredTheme, setTheme, THEMES, type Theme } from "@/lib/theme";

// The theme picker — a 2×2 grid of named looks (Light / Dark / Sketchbook /
// Espresso) rather than a lone glyph button, so every state is visible and the
// current one is plainly selected. It lives in You › Settings ONLY (the
// maintainer's call): one obvious home beats a mystery icon on every page.
// Typographic glyphs, no icon lib (on-brand). Selecting applies instantly —
// the whole app is the preview.
export function ThemeToggle({ className }: { className?: string }) {
  const [theme, setLocal] = useState<Theme>("dark");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setLocal(getStoredTheme());
    setMounted(true);
  }, []);

  function pick(next: Theme) {
    setTheme(next);
    setLocal(next);
  }

  // Avoid hydration mismatch: render a stable state until mounted.
  const shown = mounted ? theme : "dark";

  return (
    <div role="radiogroup" aria-label="Theme" className={clsx("grid w-full grid-cols-2 gap-2", className)}>
      {THEMES.map((o) => {
        const active = shown === o.value;
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => pick(o.value)}
            className={clsx(
              "glass glass-press flex min-h-11 items-center gap-1.5 overflow-hidden rounded-ctl px-2.5 py-2 text-left text-[11px] font-medium uppercase tracking-wide whitespace-nowrap transition-colors",
              active ? "text-ink" : "text-faint hover:text-ink",
            )}
            style={active ? { borderColor: "var(--accent)" } : undefined}
          >
            <span aria-hidden className={clsx("shrink-0 text-sm", active ? "text-accent" : "text-faint")}>
              {o.glyph}
            </span>
            <span className="truncate">{o.label}</span>
            {active && (
              <span aria-hidden className="ml-auto shrink-0 text-accent">
                ✓
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}
