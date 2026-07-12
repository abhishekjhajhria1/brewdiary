"use client";

// Entry store. Two modes, one API (so components never change):
//   • logged OUT  → local mode: entries live in localStorage (the onboarding demo).
//   • logged IN   → remote mode: entries live in Supabase, scoped to the user.
// On sign-in, any local entries are migrated up (preserving the first-logged drink).
// Writes are OPTIMISTIC: the in-memory cache updates immediately (snappy darken),
// then the DB write happens in the background and rolls back on failure.
//
// Everything visual (mosaic, streaks, lexicon…) stays DERIVED from these Entry rows.
import { useSyncExternalStore } from "react";
import type { Entry } from "./types";
import { addDays, toKey } from "./date";
import { seedEntries } from "./seed";
import { supabase } from "./supabase";
import { getAuthState, subscribeAuth, type AuthState } from "./profile";

const LKEY = "brewdiary.entries.v1";
const EMPTY: Entry[] = [];

let cache: Entry[] = EMPTY;
let mode: "local" | "remote" = "local";
let currentUser: string | null = null;
let wired = false;
const listeners = new Set<() => void>();

function emit() {
  listeners.forEach((l) => l());
}
function setCache(next: Entry[]) {
  cache = next;
  emit();
}

// ── local persistence ───────────────────────────────────────────────────────
function readLocal(): Entry[] {
  if (typeof window === "undefined") return EMPTY;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as Entry[]) : EMPTY;
  } catch {
    return EMPTY;
  }
}
function writeLocal(entries: Entry[]) {
  try {
    window.localStorage.setItem(LKEY, JSON.stringify(entries));
  } catch {
    /* quota / private mode — keep in-memory */
  }
}

// ── DB <-> app mapping ──────────────────────────────────────────────────────
interface EntryRow {
  id: string;
  date: string;
  drink: string;
  type: string | null;
  mood: string | null;
  note: string | null;
  venue: string | null;
  who_with: string[] | null;
  visibility: string | null;
  created_at: string;
  entry_photos?: { id: string; url: string; sort_order: number }[];
}

function publicUrl(path: string): string {
  return supabase!.storage.from("photos").getPublicUrl(path).data.publicUrl;
}

function rowToEntry(r: EntryRow): Entry {
  const photos = (r.entry_photos ?? [])
    .sort((a, b) => a.sort_order - b.sort_order)
    .map((p) => ({ id: p.id, url: publicUrl(p.url) }));
  return {
    id: r.id,
    date: r.date,
    createdAt: r.created_at,
    drink: r.drink,
    type: (r.type as Entry["type"]) ?? undefined,
    mood: r.mood ?? undefined,
    note: r.note ?? undefined,
    venue: r.venue ?? undefined,
    whoWith: r.who_with ?? undefined,
    visibility: (r.visibility as Entry["visibility"]) ?? "private",
    photos: photos.length ? photos : undefined,
  };
}

function entryToRow(e: Entry, userId: string) {
  return {
    id: e.id,
    user_id: userId,
    date: e.date,
    drink: e.drink,
    type: e.type ?? null,
    mood: e.mood ?? null,
    note: e.note ?? null,
    venue: e.venue ?? null,
    who_with: e.whoWith ?? null,
    visibility: e.visibility ?? "private",
  };
}

// ── photo storage ───────────────────────────────────────────────────────────
async function dataUrlToBlob(dataUrl: string): Promise<Blob> {
  const res = await fetch(dataUrl);
  return res.blob();
}

/** Upload any data-URL photos to the bucket + insert entry_photos rows. Returns photos with public URLs. */
async function syncPhotos(entry: Entry, userId: string): Promise<Entry["photos"]> {
  if (!supabase || !entry.photos?.length) return entry.photos;
  const out: NonNullable<Entry["photos"]> = [];
  let order = 0;
  for (const p of entry.photos) {
    if (p.url.startsWith("data:")) {
      const blob = await dataUrlToBlob(p.url);
      const path = `${userId}/${entry.id}/${p.id}`;
      const up = await supabase.storage.from("photos").upload(path, blob, { upsert: true, contentType: blob.type || "image/jpeg" });
      if (!up.error) {
        await supabase.from("entry_photos").insert({ id: p.id, entry_id: entry.id, user_id: userId, url: path, sort_order: order });
        out.push({ id: p.id, url: publicUrl(path) });
      }
    } else {
      out.push(p); // already a stored URL
    }
    order++;
  }
  return out;
}

// ── remote ops ──────────────────────────────────────────────────────────────
async function loadRemote() {
  if (!supabase) return;
  const { data, error } = await supabase
    .from("entries")
    .select("id, date, drink, type, mood, note, venue, who_with, visibility, created_at, entry_photos(id, url, sort_order)")
    .order("date", { ascending: true });
  if (!error && data) setCache((data as EntryRow[]).map(rowToEntry));
}

/** Returns true only if the rows actually landed — the caller must NOT clear the
 *  local diary otherwise (a network blip at sign-in must never lose entries). */
async function migrateLocalToRemote(local: Entry[], userId: string): Promise<boolean> {
  if (!supabase || local.length === 0) return true;
  // Insert rows first, then their photos.
  const { error } = await supabase.from("entries").insert(local.map((e) => entryToRow(e, userId)));
  if (error) return false;
  for (const e of local) await syncPhotos(e, userId);
  return true;
}

// ── auth wiring ─────────────────────────────────────────────────────────────
async function applyAuth(s: AuthState) {
  if (s.status === "loading") return;

  if (s.status === "authed" && s.profile && supabase) {
    if (mode === "remote" && currentUser === s.profile.id) return; // already synced
    currentUser = s.profile.id;
    mode = "remote";
    const local = readLocal();
    if (local.length) {
      const moved = await migrateLocalToRemote(local, currentUser);
      if (moved) writeLocal([]); // moved up — don't double-count (kept locally if the upload failed)
    }
    await loadRemote();
  } else {
    // signed out → back to the local (onboarding) diary
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

// ── subscription ────────────────────────────────────────────────────────────
function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  wire();
  return () => listeners.delete(cb);
}

export function useEntries(): Entry[] {
  return useSyncExternalStore(
    subscribe,
    () => cache,
    () => EMPTY,
  );
}

export interface NewEntry {
  date: string;
  drink: string;
  mood?: string;
  note?: string;
  type?: Entry["type"];
  venue?: string;
  whoWith?: string[];
  photos?: Entry["photos"];
}

function uuid(): string {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `e_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}

export function addEntry(input: NewEntry): Entry {
  const entry: Entry = {
    id: uuid(),
    createdAt: new Date().toISOString(),
    ...input,
    drink: input.drink.trim(),
    mood: input.mood?.trim() || undefined,
  };
  setCache([...cache, entry]); // optimistic

  if (mode === "remote" && currentUser && supabase) {
    const userId = currentUser;
    void (async () => {
      const { error } = await supabase!.from("entries").insert(entryToRow(entry, userId));
      if (error) {
        setCache(cache.filter((e) => e.id !== entry.id)); // rollback
        return;
      }
      const photos = await syncPhotos(entry, userId);
      if (photos !== entry.photos) {
        setCache(cache.map((e) => (e.id === entry.id ? { ...e, photos } : e)));
      }
    })();
  } else {
    writeLocal(cache);
  }
  return entry;
}

export function updateEntry(id: string, patch: Partial<Entry>) {
  const prev = cache.find((e) => e.id === id);
  setCache(cache.map((e) => (e.id === id ? { ...e, ...patch } : e))); // optimistic

  if (mode === "remote" && currentUser && supabase) {
    const userId = currentUser;
    void (async () => {
      const row: Record<string, unknown> = {};
      if ("date" in patch) row.date = patch.date;
      if ("drink" in patch) row.drink = patch.drink;
      if ("type" in patch) row.type = patch.type ?? null;
      if ("mood" in patch) row.mood = patch.mood ?? null;
      if ("note" in patch) row.note = patch.note ?? null;
      if ("venue" in patch) row.venue = patch.venue ?? null;
      if ("whoWith" in patch) row.who_with = patch.whoWith ?? null;
      if ("visibility" in patch) row.visibility = patch.visibility ?? "private";
      if (Object.keys(row).length) await supabase!.from("entries").update(row).eq("id", id);
      if ("photos" in patch) {
        const updated = cache.find((e) => e.id === id);
        if (updated) await reconcilePhotos(id, updated.photos ?? [], userId);
      }
    })();
  } else {
    writeLocal(cache);
  }
  return prev;
}

/** Drop removed photos, upload added (data-URL) ones — keeps entry_photos in sync on edit. */
async function reconcilePhotos(entryId: string, photos: NonNullable<Entry["photos"]>, userId: string) {
  if (!supabase) return;
  const keepIds = photos.map((p) => p.id);
  const { data: existing } = await supabase.from("entry_photos").select("id, url").eq("entry_id", entryId);
  for (const row of existing ?? []) {
    if (!keepIds.includes(row.id)) {
      await supabase.storage.from("photos").remove([row.url]);
      await supabase.from("entry_photos").delete().eq("id", row.id);
    }
  }
  await syncPhotos({ id: entryId, photos } as Entry, userId);
}

export function deleteEntry(id: string) {
  setCache(cache.filter((e) => e.id !== id)); // optimistic
  if (mode === "remote" && currentUser && supabase) {
    void supabase.from("entries").delete().eq("id", id); // cascade removes photos rows
  } else {
    writeLocal(cache);
  }
}

export function resetAll() {
  if (mode === "remote" && currentUser && supabase) {
    const userId = currentUser;
    setCache(EMPTY);
    void supabase.from("entries").delete().eq("user_id", userId);
  } else {
    setCache(EMPTY);
    writeLocal(EMPTY);
  }
}

/** Wipe and re-seed the demo history (for the current diary). */
export function reseed() {
  const seeded = seedEntries();
  if (mode === "remote" && currentUser && supabase) {
    const userId = currentUser;
    setCache(seeded);
    void (async () => {
      await supabase!.from("entries").delete().eq("user_id", userId);
      await supabase!.from("entries").insert(seeded.map((e) => entryToRow(e, userId)));
    })();
  } else {
    setCache(seeded);
    writeLocal(seeded);
  }
}

/** Replace the whole diary (used by import). Drops malformed rows — a bad file
 *  must never crash the app later (day sorts call `createdAt.localeCompare`) or
 *  corrupt the mosaic with non-day keys. */
export function replaceAll(entries: Entry[]) {
  const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;
  const clean = entries.filter(
    (e): e is Entry =>
      Boolean(
        e &&
          typeof e.id === "string" &&
          typeof e.date === "string" &&
          DAY_KEY.test(e.date) &&
          typeof e.createdAt === "string" &&
          typeof e.drink === "string" &&
          (e.photos === undefined || Array.isArray(e.photos)) &&
          (e.whoWith === undefined || Array.isArray(e.whoWith)),
      ),
  );
  if (mode === "remote" && currentUser && supabase) {
    const userId = currentUser;
    setCache(clean);
    void (async () => {
      await supabase!.from("entries").delete().eq("user_id", userId);
      if (clean.length) await supabase!.from("entries").insert(clean.map((e) => entryToRow(e, userId)));
    })();
  } else {
    setCache(clean);
    writeLocal(clean);
  }
}

/** Current entries, for export (a stable snapshot). */
export function snapshot(): Entry[] {
  return cache;
}

// Re-export for convenience.
export { toKey, addDays };
