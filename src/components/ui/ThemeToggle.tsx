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
export function ThemeToggle() {
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
    <div role="radiogroup" aria-label="Theme" className="grid w-full max-w-xs grid-cols-2 gap-2">
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
              "glass glass-press flex min-h-11 items-center gap-2 rounded-ctl px-3 py-2 text-left text-xs font-medium uppercase tracking-widest transition-colors",
              active ? "border-accent text-ink" : "text-faint hover:text-ink",
            )}
            style={active ? { borderColor: "var(--accent)" } : undefined}
          >
            <span aria-hidden className={clsx("text-sm", active ? "text-accent" : "text-faint")}>
              {o.glyph}
            </span>
            {o.label}
            {active && (
              <span aria-hidden className="ml-auto text-accent">
                ✓
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}
