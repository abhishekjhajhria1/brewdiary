"use client";

// Per-day tallies — the counts behind the optional Extras (cigarettes, water…).
//
// Shape: { [dateKey]: { [extraKey]: number } }. A day with no count simply isn't
// in the map. Counts never go below zero. Stored per-device in localStorage —
// deliberately kept simple and offline for now (these are private, low-stakes
// tallies); it can be promoted to Supabase later using the lib/store.ts pattern
// if cross-device sync is wanted.
import { useSyncExternalStore } from "react";
import type { ExtraKey } from "./features";

type DayTallies = Partial<Record<ExtraKey, number>>;
type AllTallies = Record<string, DayTallies>;

const LKEY = "brewdiary.tallies.v1";
const EMPTY: AllTallies = {};

let cache: AllTallies = EMPTY;
let loaded = false;
const listeners = new Set<() => void>();

function read(): AllTallies {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as AllTallies) : EMPTY;
  } catch {
    return EMPTY;
  }
}
function ensure() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  cache = read();
}
function persist() {
  try {
    window.localStorage.setItem(LKEY, JSON.stringify(cache));
  } catch {
    /* quota / private mode — keep in-memory */
  }
}
function emit() {
  listeners.forEach((l) => l());
}

function subscribe(cb: () => void): () => void {
  ensure();
  listeners.add(cb);
  return () => listeners.delete(cb);
}

/** The count for one extra on one day (reactive). */
export function useTally(dateKey: string, key: ExtraKey): number {
  return useSyncExternalStore(
    subscribe,
    () => cache[dateKey]?.[key] ?? 0,
    () => 0,
  );
}

/** Nudge a day's count by ±1 (clamped at 0). Empty days/counts are pruned. */
export function bumpTally(dateKey: string, key: ExtraKey, delta: number) {
  ensure();
  const day = { ...(cache[dateKey] ?? {}) };
  const next = Math.max(0, (day[key] ?? 0) + delta);
  if (next === 0) delete day[key];
  else day[key] = next;

  const all = { ...cache };
  if (Object.keys(day).length === 0) delete all[dateKey];
  else all[dateKey] = day;

  cache = all;
  persist();
  emit();
}
