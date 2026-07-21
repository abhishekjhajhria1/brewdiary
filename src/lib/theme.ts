// The theme registry — four deliberate looks, not a free-for-all.
//   light / dark   — the liquid-glass pair (dark is the default; glass reads strongest there).
//   sketch         — "Sketchbook": warm paper, hand-drawn tile borders, handwritten type.
//   espresso       — a warm coffee-dark; same glass material in caramel light.
// The <html> element carries BOTH a `data-theme` attribute (drives the CSS variable
// overrides in globals.css) and the `.dark` class for dark-family themes (so every
// existing `dark:` Tailwind style keeps working untouched). Both are applied before
// first paint by NO_FLASH_SCRIPT (see layout.tsx); this module handles runtime changes.
export type Theme = "light" | "dark" | "sketch" | "espresso";

export interface ThemeDef {
  value: Theme;
  label: string;
  /** Typographic glyph for the picker — no icon lib (on-brand). */
  glyph: string;
  /** Dark-family themes get the `.dark` class (keeps `dark:` variants working). */
  isDark: boolean;
}

export const THEMES: ThemeDef[] = [
  { value: "light", label: "Light", glyph: "○", isDark: false },
  { value: "dark", label: "Dark", glyph: "●", isDark: true },
  { value: "sketch", label: "Sketchbook", glyph: "✎", isDark: false },
  { value: "espresso", label: "Espresso", glyph: "◐", isDark: true },
];

const KEY = "brewdiary.theme";
export const DEFAULT_THEME: Theme = "dark";

function isTheme(t: unknown): t is Theme {
  return THEMES.some((d) => d.value === t);
}

export function getStoredTheme(): Theme {
  if (typeof window === "undefined") return DEFAULT_THEME;
  const t = window.localStorage.getItem(KEY);
  return isTheme(t) ? t : DEFAULT_THEME;
}

export function applyTheme(theme: Theme) {
  if (typeof document === "undefined") return;
  const def = THEMES.find((d) => d.value === theme) ?? THEMES[1];
  document.documentElement.dataset.theme = def.value;
  document.documentElement.classList.toggle("dark", def.isDark);
}

export function setTheme(theme: Theme) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(KEY, theme);
  applyTheme(theme);
}

/** Inline-able string that sets attribute + class before first paint (no FOUC).
 *  Mirrors applyTheme: unknown/absent value falls back to dark. */
export const NO_FLASH_SCRIPT = `(function(){try{var t=localStorage.getItem('${KEY}');var ok={light:0,dark:1,sketch:0,espresso:1};if(!(t in ok))t='dark';var e=document.documentElement;e.dataset.theme=t;e.classList.toggle('dark',!!ok[t]);}catch(e){var d=document.documentElement;d.dataset.theme='dark';d.classList.add('dark');}})();`;
