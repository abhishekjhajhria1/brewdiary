"use client";

// The home calendar's view mode — "month" grid or "year" heat-mosaic.
//
// It lives here, not inside CalendarHome, because two components need it: the home
// renders the chosen view, and the TopBar carries the toggle (the morphing squircle).
// Same tiny module-level pub/sub as theme.ts / features.ts — SSR-safe via
// useSyncExternalStore, defaulting to "month". Not persisted: the view is a per-visit
// glance, and always opening on the month keeps the nightly ritual (tap today → log)
// one step away.
import { useSyncExternalStore } from "react";

export type CalendarView = "month" | "year";

let view: CalendarView = "month";
const listeners = new Set<() => void>();

export function setCalendarView(next: CalendarView) {
  if (next === view) return;
  view = next;
  listeners.forEach((l) => l());
}

export function toggleCalendarView() {
  setCalendarView(view === "month" ? "year" : "month");
}

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function useCalendarView(): CalendarView {
  return useSyncExternalStore(subscribe, () => view, () => "month");
}
