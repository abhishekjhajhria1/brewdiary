"use client";

import { useEffect, useState } from "react";
import { getStoredTheme, setTheme, type Theme } from "@/lib/theme";

// Two themes — a single toggle, not a cycle. Typographic glyphs (no icon lib, on-brand):
// ○ a light disc, ● a filled one. The glyph shows the CURRENT theme.
const GLYPH: Record<Theme, string> = { light: "○", dark: "●" };
const LABEL: Record<Theme, string> = { light: "Light", dark: "Dark" };

export function ThemeToggle() {
  const [theme, setLocal] = useState<Theme>("dark");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setLocal(getStoredTheme());
    setMounted(true);
  }, []);

  function toggle() {
    const next: Theme = theme === "dark" ? "light" : "dark";
    setTheme(next);
    setLocal(next);
  }

  // Avoid hydration mismatch: render a stable placeholder until mounted.
  const shown = mounted ? theme : "dark";

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={`Theme: ${LABEL[shown]}. Tap to switch.`}
      title={`Theme: ${LABEL[shown]}`}
      className="flex h-9 w-13 items-center justify-center rounded-ctl text-sm text-muted transition-colors hover:bg-ink/5 hover:text-ink"
    >
      <span aria-hidden>{GLYPH[shown]}</span>
    </button>
  );
}
