"use client";

import { useEffect, useState } from "react";
import clsx from "clsx";
import { getStoredTheme, setTheme, type Theme } from "@/lib/theme";

// The theme control — a two-option SEGMENTED switch (Light | Dark) rather than a lone
// glyph button, so both states are visible and the current one is plainly selected.
// It lives in You › Settings ONLY (the maintainer's call): one obvious home beats a
// mystery icon on every page. Typographic glyphs, no icon lib (on-brand).
const OPTIONS: { value: Theme; glyph: string; label: string }[] = [
  { value: "light", glyph: "○", label: "Light" },
  { value: "dark", glyph: "●", label: "Dark" },
];

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
    <div role="radiogroup" aria-label="Theme" className="glass inline-flex rounded-ctl p-1">
      {OPTIONS.map((o) => {
        const active = shown === o.value;
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => pick(o.value)}
            className={clsx(
              "flex min-h-9 items-center gap-1.5 rounded-[7px] px-3 text-xs font-medium uppercase tracking-widest transition-colors",
              active ? "bg-ink text-paper" : "text-faint hover:text-ink",
            )}
          >
            <span aria-hidden>{o.glyph}</span>
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
