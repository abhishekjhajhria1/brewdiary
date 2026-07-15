"use client";

// "To try" list — drinks you want to get to. Two modes, one API (mirrors lib/store.ts):
// local when logged out, Supabase (wishlist_items) when signed in, with optimistic
// writes and local→remote migration on sign-in. Component API is unchanged.
import { useSyncExternalStore } from "react";
import { supabase } from "./supabase";
import { getAuthState, subscribeAuth, type AuthState } from "./profile";

export interface WishItem {
  id: string;
  drink: string;
  createdAt: string;
  done?: boolean;
}

const LKEY = "brewdiary.wishlist.v1";
const EMPTY: WishItem[] = [];

let cache: WishItem[] = EMPTY;
let mode: "local" | "remote" = "local";
let currentUser: string | null = null;
let wired = false;
const listeners = new Set<() => void>();

function emit() {
  listeners.forEach((l) => l());
}
function setCache(next: WishItem[]) {
  cache = next;
  emit();
}

// ── local persistence ────────────────────────────────────────────────────────
function readLocal(): WishItem[] {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as WishItem[]) : EMPTY;
  } catch {
    return EMPTY;
  }
}
function writeLocal(items: WishItem[]) {
  try {
    window.localStorage.setItem(LKEY, JSON.stringify(items));
  } catch {
    /* quota / private mode */
  }
}

// ── DB mapping ───────────────────────────────────────────────────────────────
interface WishRow {
  id: string;
  drink_name: string;
  created_at: string;
  fulfilled: boolean;
}
function rowToWish(r: WishRow): WishItem {
  return { id: r.id, drink: r.drink_name, createdAt: r.created_at, done: r.fulfilled };
}
function wishToRow(w: WishItem, userId: string) {
  return { id: w.id, user_id: userId, drink_name: w.drink, fulfilled: w.done ?? false };
}

function newId(): string {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `w_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}

// ── remote + auth wiring ─────────────────────────────────────────────────────
async function loadRemote() {
  if (!supabase) return;
  const { data, error } = await supabase
    .from("wishlist_items")
    .select("id, drink_name, created_at, fulfilled")
    .order("created_at", { ascending: false });
  if (!error && data) setCache((data as WishRow[]).map(rowToWish));
}

async function applyAuth(s: AuthState) {
  if (s.status === "loading") return;
  if (s.status === "authed" && s.profile && supabase) {
    if (mode === "remote" && currentUser === s.profile.id) return;
    currentUser = s.profile.id;
    mode = "remote";
    const local = readLocal();
    if (local.length) {
      await supabase.from("wishlist_items").insert(local.map((w) => wishToRow(w, currentUser!)));
      writeLocal([]);
    }
    await loadRemote();
  } else {
    mode = "local";
    currentUser = null;
    setCache(readLocal());
  }
}

function wire() {
  if (wired || typeof window === "undefined") return;
  wired = true;
  void applyAuth(getAuthState());
  subscribeAuth(() => void applyAuth(getAuthState()));
}

export function useWishlist(): WishItem[] {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      wire();
      return () => listeners.delete(cb);
    },
    () => cache,
    () => EMPTY,
  );
}

export function addWish(drink: string) {
  const d = drink.trim();
  if (!d) return;
  // Avoid obvious duplicates (case-insensitive, not yet done).
  if (cache.some((w) => !w.done && w.drink.toLowerCase() === d.toLowerCase())) return;
  const item: WishItem = { id: newId(), drink: d, createdAt: new Date().toISOString() };
  setCache([item, ...cache]); // optimistic
  if (mode === "remote" && currentUser && supabase) {
    const userId = currentUser;
    void supabase
      .from("wishlist_items")
      .insert(wishToRow(item, userId))
      .then(({ error }) => {
        if (error) setCache(cache.filter((w) => w.id !== item.id)); // rollback
      });
  } else {
    writeLocal(cache);
  }
}

export async function removeWish(id: string) {
  const prev = cache;
  setCache(cache.filter((w) => w.id !== id)); // optimistic
  if (mode === "remote" && currentUser && supabase) {
    // Await + roll back on failure so a delete that doesn't take shows up honestly
    // instead of silently reappearing on the next refresh. Scoped to my own rows.
    const { error } = await supabase.from("wishlist_items").delete().eq("id", id).eq("user_id", currentUser);
    if (error) setCache(prev);
  } else {
    writeLocal(cache);
  }
}

export function toggleWish(id: string) {
  const target = cache.find((w) => w.id === id);
  if (!target) return;
  const done = !target.done;
  setCache(cache.map((w) => (w.id === id ? { ...w, done } : w))); // optimistic
  if (mode === "remote" && currentUser && supabase) {
    void supabase.from("wishlist_items").update({ fulfilled: done }).eq("id", id);
  } else {
    writeLocal(cache);
  }
}
