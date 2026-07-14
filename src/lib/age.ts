"use client";

// Age gate. brewdiary is an all-drinks diary but it includes alcohol, so a first-run
// age check is a responsible-build + app-store requirement. This is a client-side gate
// (localStorage) — it deters minors; it isn't identity verification.
//
// The threshold is NOT one number. 18 covers most of the world, but it's 21 in the
// US (and much of India), 20 in Japan and Thailand, 19 in Korea and most of Canada.
// A single hardcoded 18 was quietly wrong — and letting a 19-year-old into a US
// build is exactly the kind of thing an app-store reviewer looks for. So we ask
// where you are and apply that country's real age. An UNKNOWN country gets 21 —
// deny by default (see jurisdiction.ts).
import { minDrinkingAge } from "./jurisdiction";
import { currencyForCountry, saveCurrency } from "./money";

/** The safe fallback when we don't know where someone is. */
export const LEGAL_AGE = 21;

// v2, deliberately: everyone who passed the OLD gate passed a flat 18+ check with
// no country. In the US the real bar is 21 — so those confirmations are not worth
// anything and must be re-taken. Bumping the key re-asks once, with the country.
// Never reuse a version after loosening→tightening a check; the stale "ok" wins.
const KEY = "brewdiary.age.v2";
const COUNTRY_KEY = "brewdiary.country.v1";

/** The legal drinking age where this person says they are. */
export function legalAgeFor(country?: string | null): number {
  return minDrinkingAge(country);
}

/** Where the person told us they are. Used for the age bar and to default a venue's
 *  country. Never sent anywhere — it's a device preference, like the theme. */
export function savedCountry(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage.getItem(COUNTRY_KEY);
  } catch {
    return null;
  }
}

export function saveCountry(code: string) {
  try {
    window.localStorage.setItem(COUNTRY_KEY, code.toUpperCase());
    // Their money follows from where they are — so Split doesn't greet a Berliner
    // with rupees. Changeable later in You → settings.
    saveCurrency(currencyForCountry(code));
  } catch {
    /* private mode — we'll just ask again */
  }
}

export function ageFrom(dob: Date, now: Date = new Date()): number {
  let age = now.getFullYear() - dob.getFullYear();
  const m = now.getMonth() - dob.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < dob.getDate())) age--;
  return age;
}

export function isAgeConfirmed(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return window.localStorage.getItem(KEY) === "ok";
  } catch {
    return false;
  }
}

/** Verify a date of birth against the legal age WHERE THEY ARE. Persists only on
 *  success. An unknown country means 21 — the strict fallback, never 18. */
export function confirmAge(dob: Date, country?: string | null): boolean {
  const ok = !Number.isNaN(dob.getTime()) && ageFrom(dob) >= legalAgeFor(country);
  if (ok) {
    try {
      window.localStorage.setItem(KEY, "ok");
      if (country) saveCountry(country);
    } catch {
      /* private mode — gate will re-ask next visit */
    }
  }
  return ok;
}

/** Inline no-flash: mark <html> so the gate can cover content before React mounts. */
export const AGE_FLAG_SCRIPT = `(function(){try{if(localStorage.getItem('${KEY}')!=='ok')document.documentElement.classList.add('needs-age');}catch(e){document.documentElement.classList.add('needs-age');}})();`;

/**
 * Raw CSS injected in <head> (NOT through Tailwind) so the gate's show/hide is
 * guaranteed present and cascade-order-independent (via !important). Paired with
 * AGE_FLAG_SCRIPT: when unconfirmed, <html> gets `needs-age` before paint → the
 * gate shows and the rest of the app is hidden, with no flash.
 */
// `.age-exempt` marks a page that must be readable WITHOUT passing the gate — the
// privacy policy and terms. An app-store reviewer or a regulator has to be able to
// read them without asserting they're of drinking age, and a policy you can only
// see after clearing a gate is not a published policy.
//
// The exempt page is NOT a direct child of <body> (it sits inside the layout's
// wrapper), so `body > *:not(.age-exempt)` would still hide its parent. We instead
// hide body's children only when the page does NOT contain an exempt element —
// `:has()` looks down the tree, so the wrapper survives when it holds the policy.
export const AGE_GATE_STYLE = `.age-gate{display:none!important}html.needs-age .age-gate{display:flex!important}html.needs-age body>*:not(.age-gate):not(:has(.age-exempt)){visibility:hidden}`;
