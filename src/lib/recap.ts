"use client";

// The weekly discovery recap preference — "look what you found this week".
//
// OFF by default and per-device (localStorage, same pattern as features.ts / goals.ts), so a
// quiet weekly look-back never arrives uninvited and never leaves the device. The card itself
// is derived (passport.weeklyDiscovery); the only thing stored here is whether you asked for
// it, and when you last waved it away.
//
// It is a return-pull, not a consumption push: it shows stamps you already lit, one memory,
// and one door — never "you're behind", never "drink something".
import { useSyncExternalStore } from "react";
import { addDays, parseKey, toKey, todayKey } from "./date";

interface Recap {
  /** Has the person asked for the weekly card at all? Absent = off. */
  on?: boolean;
  /** Day-key they last dismissed it — it stays gone for a week, then quietly returns. */
  dismissed?: string;
}

const LKEY = "brewdiary.recap.v1";
const EMPTY: Recap = {};

let cache: Recap = EMPTY;
let loaded = false;
const listeners = new Set<() => void>();

function read(): Recap {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as Recap) : EMPTY;
  } catch {
    return EMPTY;
  }
}
function ensure() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  cache = read();
}
function emit() {
  listeners.forEach((l) => l());
}
function write(next: Recap) {
  ensure();
  cache = next;
  try {
    window.localStorage.setItem(LKEY, JSON.stringify(cache));
  } catch {
    /* quota / private mode — keep in-memory */
  }
  emit();
}

/** Turn the weekly card on or off. Turning it on clears any old dismissal. */
export function setRecap(on: boolean) {
  ensure();
  write(on ? { on: true } : { ...cache, on: false });
}

/** Wave this week's card away. It comes back in seven days, not sooner. */
export function dismissRecap(today = todayKey()) {
  ensure();
  write({ ...cache, dismissed: today });
}

function subscribe(cb: () => void): () => void {
  ensure();
  listeners.add(cb);
  return () => listeners.delete(cb);
}

function snapshot(): Recap {
  return cache;
}

/** The raw preference (reactive). */
export function useRecap(): Recap {
  return useSyncExternalStore(subscribe, snapshot, () => EMPTY);
}

/** Pure: should the card render today? Off unless asked for, and hidden a week after a dismissal. */
export function recapVisible(r: Recap, today = todayKey()): boolean {
  if (!r.on) return false;
  if (!r.dismissed) return true;
  return r.dismissed < toKey(addDays(parseKey(today), -6));
}

/** Should the card render today, for this device? */
export function useRecapVisible(): boolean {
  return recapVisible(useRecap());
}
