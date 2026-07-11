"use client";

// Age gate. brewdiary is an all-drinks diary but it includes alcohol, so a first-run
// age check is a responsible-build + app-store requirement. This is a client-side gate
// (localStorage) — it deters minors; it isn't identity verification.
//
// LEGAL_AGE is the floor: 18 is the legal drinking age across most of the world
// (incl. much of India). Change this one constant to adjust the threshold.
export const LEGAL_AGE = 18;

const KEY = "brewdiary.age.v1";

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

/** Verify a date of birth. Persists confirmation only on success. Returns whether it passed. */
export function confirmAge(dob: Date): boolean {
  const ok = !Number.isNaN(dob.getTime()) && ageFrom(dob) >= LEGAL_AGE;
  if (ok) {
    try {
      window.localStorage.setItem(KEY, "ok");
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
export const AGE_GATE_STYLE = `.age-gate{display:none!important}html.needs-age .age-gate{display:flex!important}html.needs-age body>*:not(.age-gate){visibility:hidden}`;
