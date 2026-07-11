// Two themes only — light & dark. No "system" mode (one deliberate choice, two looks).
// The `.dark` class is applied to <html> before paint by an inline script (see layout.tsx)
// to avoid a flash; this module handles runtime changes. Default is dark — the liquid-glass
// material + ambient blobs read strongest there.
export type Theme = "light" | "dark";

const KEY = "brewdiary.theme";
export const DEFAULT_THEME: Theme = "dark";

export function getStoredTheme(): Theme {
  if (typeof window === "undefined") return DEFAULT_THEME;
  const t = window.localStorage.getItem(KEY);
  return t === "light" || t === "dark" ? t : DEFAULT_THEME;
}

export function applyTheme(theme: Theme) {
  if (typeof document === "undefined") return;
  document.documentElement.classList.toggle("dark", theme === "dark");
}

export function setTheme(theme: Theme) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(KEY, theme);
  applyTheme(theme);
}

/** Inline-able string that sets the class before first paint (no FOUC). Dark unless explicitly light. */
export const NO_FLASH_SCRIPT = `(function(){try{var t=localStorage.getItem('${KEY}');document.documentElement.classList.toggle('dark',t!=='light');}catch(e){document.documentElement.classList.add('dark');}})();`;
