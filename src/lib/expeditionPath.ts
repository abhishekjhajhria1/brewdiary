"use client";

// Which expedition PATH the player has chosen — cozy / social / explorer / bold.
//
// Per-device (localStorage), same pattern as recap.ts / goals.ts / features.ts. It is a UI
// preference, not data: it only biases which do-able cards surface tonight (Pokémon GO "Choose
// Your Path"). Absent = no path picked yet, and the hand simply shows a balanced mix. Nothing
// here is stored server-side and nothing about it touches what you log.
import { useSyncExternalStore } from "react";
import type { Vibe } from "./expeditions";

const LKEY = "brewdiary.expedition.path.v1";

let cache: Vibe | null = null;
let loaded = false;
const listeners = new Set<() => void>();

const VALID: Vibe[] = ["cozy", "social", "explorer", "bold"];
function isVibe(v: unknown): v is Vibe {
  return typeof v === "string" && (VALID as string[]).includes(v);
}

function read(): Vibe | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return isVibe(raw) ? raw : null;
  } catch {
    return null;
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

/** Choose a path (or clear it by re-picking the same one). */
export function setVibe(v: Vibe | null) {
  ensure();
  cache = v;
  try {
    if (v) window.localStorage.setItem(LKEY, v);
    else window.localStorage.removeItem(LKEY);
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
function snapshot(): Vibe | null {
  return cache;
}

/** The chosen path (reactive). null = none picked yet. */
export function useVibe(): Vibe | null {
  return useSyncExternalStore(subscribe, snapshot, () => null);
}
