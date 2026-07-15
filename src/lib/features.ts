"use client";

// Extras — optional trackers that stay HIDDEN until you switch them on.
//
// The app stays clean by default: a cigarette counter, a water tally, and
// anything we add next only appear once you enable them from You › Extras. This
// is the one place to register such a feature — add an entry to EXTRAS and it
// shows up as a toggle in the profile and (if it's a per-day counter) as a
// stepper in the log window. No other wiring needed.
//
// Preferences are per-device (localStorage), SSR-safe via useSyncExternalStore.
import { useSyncExternalStore } from "react";
import type { DrinkType } from "./types";

export type ExtraKey = "cigarettes" | "water";

export interface ExtraDef {
  key: ExtraKey;
  /** Shown on the toggle and above the counter. */
  label: string;
  /** One calm line under the toggle explaining what it does. */
  hint: string;
  /** Singular unit, for the counter aria-labels ("1 cigarette"). */
  unit: string;
  /** Is this a per-day +/- counter shown in the log window? */
  counter: boolean;
  /** Each +1 writes a REAL diary entry with this name + kind, so it lands on the
   *  calendar/mosaic and syncs to the DB — not a separate local-only tally. */
  entryDrink: string;
  entryType: DrinkType;
}

// The registry. Everything off by default — the app reveals nothing uninvited.
export const EXTRAS: ExtraDef[] = [
  {
    key: "cigarettes",
    label: "Cigarettes",
    hint: "A small +/- counter on each day, to keep an honest tally.",
    unit: "cigarette",
    counter: true,
    entryDrink: "Cigarette",
    entryType: "other",
  },
  {
    key: "water",
    label: "Water",
    hint: "Count glasses of water alongside the day — a gentle nudge to hydrate.",
    unit: "glass",
    counter: true,
    entryDrink: "Water",
    entryType: "soft",
  },
];

type Flags = Partial<Record<ExtraKey, boolean>>;

const LKEY = "brewdiary.extras.v1";
const EMPTY: Flags = {};

let cache: Flags = EMPTY;
let loaded = false;
const listeners = new Set<() => void>();

function read(): Flags {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as Flags) : EMPTY;
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

export function setExtra(key: ExtraKey, on: boolean) {
  ensure();
  cache = { ...cache, [key]: on };
  try {
    window.localStorage.setItem(LKEY, JSON.stringify(cache));
  } catch {
    /* quota / private mode — keep in-memory */
  }
  emit();
}

function subscribe(cb: () => void): () => void {
  ensure();
  listeners.add(cb);
  return () => listeners.delete(cb);
}

/** The whole flag map (reactive). */
export function useExtras(): Flags {
  return useSyncExternalStore(subscribe, () => cache, () => EMPTY);
}

/** One flag (reactive). Defaults OFF. */
export function useExtra(key: ExtraKey): boolean {
  return useExtras()[key] ?? false;
}

/** The enabled counter-style extras — what the log window should render. */
export function enabledCounters(flags: Flags): ExtraDef[] {
  return EXTRAS.filter((e) => e.counter && flags[e.key]);
}
