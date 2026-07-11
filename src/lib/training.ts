"use client";

// Training-data collection seam — the real path toward "our own Ninkasi".
// Every completed exchange with Ninkasi is appended here (locally, opt-out-able).
// Over time this accumulates a dataset you can EXPORT as JSONL in the OpenAI
// fine-tune chat format, then fine-tune a cheap small model on it so it speaks as
// Ninkasi natively — that is the "AI trained on our own answers" goal, made concrete.
//
// Same useSyncExternalStore pattern as store.ts. When a backend lands, swap the
// localStorage read/write for a POST to a collection endpoint; the public API stays.
//
// PRIVACY: samples are personal chat. Keep collection local + opt-in, and strip/own
// the data before any real training run. This file only stores; it never uploads.

import { useSyncExternalStore } from "react";
import { SYSTEM_PROMPT } from "./bartender";

export interface TrainingSample {
  id: string;
  at: number; // epoch ms
  user: string; // the guest's message
  assistant: string; // Ninkasi's reply
  context?: string; // the personalization block in effect (for faithful replay)
}

const KEY = "brewdiary.training.v1";
const PREF_KEY = "brewdiary.training.enabled"; // opt-in flag

function read(): TrainingSample[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as TrainingSample[]) : [];
  } catch {
    return [];
  }
}

function write(samples: TrainingSample[]) {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(samples));
  } catch {
    /* quota — ignore, this is best-effort collection */
  }
  emit();
}

// --- opt-in preference (default ON; user can stop collection in You → Settings) ---
export function isCollecting(): boolean {
  if (typeof window === "undefined") return false;
  return window.localStorage.getItem(PREF_KEY) !== "off";
}
export function setCollecting(on: boolean) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(PREF_KEY, on ? "on" : "off");
  emit();
}

/** Append one finished exchange. No-op if collection is off or either side is empty. */
export function logExchange(sample: Omit<TrainingSample, "id" | "at">) {
  if (!isCollecting()) return;
  if (!sample.user.trim() || !sample.assistant.trim()) return;
  const next = read();
  next.push({
    id: `${Date.now()}_${Math.random().toString(36).slice(2)}`,
    at: Date.now(),
    ...sample,
  });
  write(next);
}

export function clearTraining() {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(KEY);
  emit();
  // Clear the cloud copy too (same consent, same switch). The central corpus now lives
  // in the SEPARATE AI database, which the browser has no credentials for — so we ask
  // our authenticated server route to delete this user's pseudonymous rows for us.
  void fetch("/api/ninkasi/forget", { method: "POST" }).catch(() => {});
}

// NOTE: the cloud write used to happen here (browser → app DB `ninkasi_exchanges`).
// It now happens SERVER-SIDE, into the separate AI data plane: /api/bartender records
// each consented, live exchange itself (pseudonymized). The client only keeps the LOCAL
// copy below (for the personal JSONL export) and sends its consent flag with each chat.

/**
 * Export the collected exchanges as JSONL in the OpenAI fine-tune chat format —
 * one training example per line: {messages:[system, user, assistant]}. The system
 * line is Ninkasi's persona (+ the context that was live), so a fine-tune learns
 * to BE her with that grounding. Drop this file straight into a fine-tune job.
 */
export function toJSONL(samples: TrainingSample[] = read()): string {
  return samples
    .map((s) =>
      JSON.stringify({
        messages: [
          { role: "system", content: SYSTEM_PROMPT + (s.context ?? "") },
          { role: "user", content: s.user },
          { role: "assistant", content: s.assistant },
        ],
      }),
    )
    .join("\n");
}

// --- store plumbing ---
const listeners = new Set<() => void>();
function emit() {
  listeners.forEach((l) => l());
}
function subscribe(cb: () => void) {
  listeners.add(cb);
  if (typeof window !== "undefined") window.addEventListener("storage", cb);
  return () => {
    listeners.delete(cb);
    if (typeof window !== "undefined") window.removeEventListener("storage", cb);
  };
}

/** Reactive count of collected samples (for the export affordance). */
export function useTrainingCount(): number {
  return useSyncExternalStore(
    subscribe,
    () => read().length,
    () => 0,
  );
}

export function snapshotTraining(): TrainingSample[] {
  return read();
}
