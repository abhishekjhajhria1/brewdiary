"use client";

// Gentle limits — the balance side of the app, and the counterweight to the loud
// Together layer (points, kiosk, perks). Deliberately SMALL: this is not a units
// or sobriety tracker. You set an optional ceiling and/or a dry-day target; the
// standing is DERIVED from entries (see derive.weekBalance) and never stored.
//
// Both goals are OFF by default — the app reveals nothing uninvited. Kept as a
// per-device preference (localStorage, same pattern as features.ts) so it works
// signed out too, and so a private intention never leaves the device.
import { useSyncExternalStore } from "react";

export interface Goals {
  /** Ceiling on alcoholic drinks in a rolling 7 days. undefined = off. */
  weeklyLimit?: number;
  /** Target alcohol-free days in a rolling 7 days. undefined = off. */
  dryDays?: number;
}

export type GoalKey = keyof Goals;

/** Sane bounds so a stray keypress can't set a limit of 900. */
export const GOAL_MAX: Record<GoalKey, number> = { weeklyLimit: 50, dryDays: 7 };

const LKEY = "brewdiary.goals.v1";
const EMPTY: Goals = {};

let cache: Goals = EMPTY;
let loaded = false;
const listeners = new Set<() => void>();

function read(): Goals {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as Goals) : EMPTY;
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

/** Set a goal, or pass undefined to switch it off. Clamped to sane bounds. */
export function setGoal(key: GoalKey, value: number | undefined) {
  ensure();
  const next: Goals = { ...cache };
  if (value === undefined || !Number.isFinite(value) || value <= 0) {
    delete next[key];
  } else {
    next[key] = Math.min(Math.round(value), GOAL_MAX[key]);
  }
  cache = next;
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

export function useGoals(): Goals {
  return useSyncExternalStore(subscribe, () => cache, () => EMPTY);
}

/** Has the person asked for any of this at all? Nothing shows until they have. */
export function anyGoalSet(g: Goals): boolean {
  return g.weeklyLimit !== undefined || g.dryDays !== undefined;
}
