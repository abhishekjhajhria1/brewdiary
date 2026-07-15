"use client";

// Water measure — an OPTIONAL glass size in millilitres. When set, the water counter
// shows a running volume next to the glass count; left unset, it simply counts glasses.
// Per-device (localStorage), SSR-safe via useSyncExternalStore — it sits alongside the
// tallies and extras it belongs with (see lib/tallies.ts / lib/features.ts). Off by
// default: the app asks for nothing until you opt in.
import { useSyncExternalStore } from "react";

const LKEY = "brewdiary.water.mlPerGlass.v1";

let cache: number | null = null;
let loaded = false;
const listeners = new Set<() => void>();

function ensure() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  try {
    const raw = window.localStorage.getItem(LKEY);
    const n = raw ? Number(raw) : NaN;
    cache = Number.isFinite(n) && n > 0 ? n : null;
  } catch {
    cache = null;
  }
}
function emit() {
  listeners.forEach((l) => l());
}

/** Set the glass size in ml (null/0 clears it → back to counting glasses only). */
export function setWaterMl(ml: number | null) {
  ensure();
  cache = ml && ml > 0 ? Math.round(ml) : null;
  try {
    if (cache) window.localStorage.setItem(LKEY, String(cache));
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

/** The chosen glass size in ml, or null when counting glasses only (reactive). */
export function useWaterMl(): number | null {
  return useSyncExternalStore(subscribe, () => cache, () => null);
}

/** Tidy a volume for display: 750 → "750 ml", 1500 → "1.5 L". */
export function formatVolume(ml: number): string {
  if (ml >= 1000) return `${(ml / 1000).toFixed(ml % 1000 === 0 ? 0 : 1)} L`;
  return `${ml} ml`;
}
