"use client";

// Your bar — a private list of what you keep at home (spirits, mixers, ingredients).
// It feeds nothing yet; it's the store Ninkasi will read later to answer "what can I
// make tonight with what I've got?" — the shelf's forward-looking half. Per-device
// localStorage, SSR-safe via useSyncExternalStore, deliberately simple and offline (it's
// low-stakes and private); promotable to Supabase later with the lib/store.ts pattern.
import { useSyncExternalStore } from "react";

const LKEY = "brewdiary.pantry.v1";
const EMPTY: string[] = [];

let cache: string[] = EMPTY;
let loaded = false;
const listeners = new Set<() => void>();

function ensure() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  try {
    const raw = window.localStorage.getItem(LKEY);
    const parsed = raw ? JSON.parse(raw) : null;
    cache = Array.isArray(parsed) ? (parsed as string[]) : EMPTY;
  } catch {
    cache = EMPTY;
  }
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

/** Add an ingredient (case-insensitive de-dupe, most-recent-first, capped). */
export function addIngredient(name: string) {
  ensure();
  const n = name.trim();
  if (!n) return;
  if (cache.some((x) => x.toLowerCase() === n.toLowerCase())) return;
  cache = [n, ...cache].slice(0, 100);
  persist();
  emit();
}

export function removeIngredient(name: string) {
  ensure();
  cache = cache.filter((x) => x !== name);
  persist();
  emit();
}

function subscribe(cb: () => void): () => void {
  ensure();
  listeners.add(cb);
  return () => listeners.delete(cb);
}

/** Everything you've got on hand (reactive). */
export function usePantry(): string[] {
  return useSyncExternalStore(subscribe, () => cache, () => EMPTY);
}
