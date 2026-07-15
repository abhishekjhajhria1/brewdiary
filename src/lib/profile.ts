"use client";

// Auth + profile — backed by Supabase (email + password). The component API
// (useProfile / signUp / signIn / signOut) is the seam the rest of the app uses;
// when Supabase isn't configured it degrades to a local profile so the app still runs.
//
// A single module-level store holds the session so we subscribe to Supabase auth ONCE
// (not once per component). Everything reads it via useSyncExternalStore.
import { useSyncExternalStore } from "react";
import { supabase } from "./supabase";
import { coolHandle, HANDLE_TRIES } from "./handles";

export interface Profile {
  id: string;
  name: string;
  handle: string;
  createdAt: string;
  /** Passed the on-device live-camera check — an anti-bot trust signal, NOT identity
   *  verification (see lib/verify.ts). Absent in local/offline mode. */
  presenceChecked?: boolean;
}

export type AuthStatus = "loading" | "authed" | "anon";
export interface AuthState {
  status: AuthStatus;
  profile: Profile | null;
}

const LOADING: AuthState = { status: "loading", profile: null };
const ANON: AuthState = { status: "anon", profile: null };

let state: AuthState = LOADING;
const listeners = new Set<() => void>();
let initialized = false;

function emit() {
  listeners.forEach((l) => l());
}
function setState(next: AuthState) {
  state = next;
  emit();
}

// ---- local fallback (only when Supabase env is absent) ---------------------
const LKEY = "brewdiary.profile.v1";
function readLocal(): Profile | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as Profile) : null;
  } catch {
    return null;
  }
}
function writeLocal(p: Profile | null) {
  try {
    if (p) window.localStorage.setItem(LKEY, JSON.stringify(p));
    else window.localStorage.removeItem(LKEY);
  } catch {
    /* ignore */
  }
}

// ---- helpers ---------------------------------------------------------------
interface ProfileRow {
  id: string;
  display_name: string | null;
  handle: string | null;
  created_at: string;
  presence_checked?: boolean | null;
}
function toProfile(row: ProfileRow): Profile {
  return {
    id: row.id,
    name: row.display_name ?? "you",
    handle: row.handle ?? "",
    createdAt: row.created_at,
    presenceChecked: Boolean(row.presence_checked),
  };
}

/** Read the user's profile row, creating it on first sight (handles the email-confirm path). */
async function ensureProfile(user: { id: string; email?: string; user_metadata?: Record<string, unknown> }): Promise<Profile> {
  const db = supabase!;
  const { data } = await db.from("profiles").select("id, display_name, handle, created_at, presence_checked").eq("id", user.id).maybeSingle();
  if (data) return toProfile(data as ProfileRow);

  const name = ((user.user_metadata?.name as string) || user.email?.split("@")[0] || "you").trim();

  // `handle` is UNIQUE, and a curated word pool WILL occasionally collide (the old
  // 6-random-char tail never did) — so allocation is a short retry loop, not a single
  // shot. An insert can fail two ways, and they need opposite responses:
  //   • the row for THIS id already exists (a concurrent creation raced us) → adopt it;
  //   • the HANDLE is taken by someone else → pick another word and try again.
  // We tell them apart by re-reading our own id: present means the race, absent means
  // the clash. coolHandle() widens its random tail as `attempt` climbs, so the loop
  // always terminates well within HANDLE_TRIES.
  for (let attempt = 0; attempt < HANDLE_TRIES; attempt++) {
    const { data: inserted } = await db
      .from("profiles")
      .insert({ id: user.id, handle: coolHandle(name, attempt), display_name: name })
      .select("id, display_name, handle, created_at, presence_checked")
      .single();
    if (inserted) return toProfile(inserted as ProfileRow);

    const { data: mine } = await db
      .from("profiles")
      .select("id, display_name, handle, created_at, presence_checked")
      .eq("id", user.id)
      .maybeSingle();
    if (mine) return toProfile(mine as ProfileRow); // the race: our row exists, use it
    // otherwise it was a handle clash — loop and try a different word
  }
  throw new Error("could not allocate a unique handle");
}

async function applySession(session: { user?: { id: string; email?: string; user_metadata?: Record<string, unknown> } } | null) {
  if (!session?.user) {
    setState(ANON);
    return;
  }
  try {
    const profile = await ensureProfile(session.user);
    setState({ status: "authed", profile });
  } catch {
    // Profile row couldn't be ensured (e.g. tables not created yet) — treat as signed out.
    setState(ANON);
  }
}

function init() {
  if (initialized || typeof window === "undefined") return;
  initialized = true;

  if (!supabase) {
    const p = readLocal();
    setState(p ? { status: "authed", profile: p } : ANON);
    return;
  }
  supabase.auth.getSession().then(({ data }) => applySession(data.session));
  supabase.auth.onAuthStateChange((_event, session) => applySession(session));
}

// ---- subscription ----------------------------------------------------------
function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  init();
  return () => listeners.delete(cb);
}

export function useAuth(): AuthState {
  return useSyncExternalStore(
    subscribe,
    () => state,
    () => LOADING,
  );
}

/** Non-React access to auth, for the data store (which keys entries to the user). */
export function getAuthState(): AuthState {
  return state;
}
export function subscribeAuth(cb: () => void): () => void {
  listeners.add(cb);
  init();
  return () => listeners.delete(cb);
}

/** Convenience: just the profile (null while loading or signed out). */
export function useProfile(): Profile | null {
  return useAuth().profile;
}

/** Persist that the person passed the on-device live-camera check, and update the
 *  in-memory profile so the trust level re-derives immediately. Soft anti-bot signal,
 *  self-settable by design (the check is client-side) — see lib/verify.ts. */
export async function markPresenceChecked(): Promise<boolean> {
  const profile = state.profile;
  if (!profile) return false;
  if (!supabase) {
    const next = { ...profile, presenceChecked: true };
    writeLocal(next);
    setState({ status: "authed", profile: next });
    return true;
  }
  const { error } = await supabase
    .from("profiles")
    .update({ presence_checked: true, presence_checked_at: new Date().toISOString() })
    .eq("id", profile.id);
  if (error) return false;
  setState({ status: "authed", profile: { ...profile, presenceChecked: true } });
  return true;
}

// ---- imperative actions ----------------------------------------------------
export type AuthResult = { ok: true; needsConfirm?: boolean } | { ok: false; error: string };

export async function signUp(email: string, password: string, name: string): Promise<AuthResult> {
  if (!supabase) {
    const p: Profile = { id: "local", name: name.trim() || "you", handle: "", createdAt: new Date().toISOString() };
    writeLocal(p);
    setState({ status: "authed", profile: p });
    return { ok: true };
  }
  const { data, error } = await supabase.auth.signUp({
    email: email.trim(),
    password,
    options: { data: { name: name.trim() } },
  });
  if (error) return { ok: false, error: error.message };
  if (data.session?.user) {
    await applySession(data.session); // session already → straight into the app
    return { ok: true };
  }
  return { ok: true, needsConfirm: true }; // email confirmation is on for this project
}

export async function signIn(email: string, password: string): Promise<AuthResult> {
  if (!supabase) {
    const p = readLocal() ?? { id: "local", name: "you", handle: "", createdAt: new Date().toISOString() };
    writeLocal(p);
    setState({ status: "authed", profile: p });
    return { ok: true };
  }
  const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

export async function signOut(): Promise<void> {
  if (!supabase) {
    writeLocal(null);
    setState(ANON);
    return;
  }
  await supabase.auth.signOut();
}

/** Email a password-reset link. Redirects to /reset on THIS origin (dev or prod).
 *  Requires the reset redirect URL to be allow-listed in Supabase Auth settings. */
export async function sendPasswordReset(email: string): Promise<AuthResult> {
  if (!supabase) return { ok: false, error: "Password reset needs the cloud backend." };
  const redirectTo = typeof window !== "undefined" ? `${window.location.origin}/reset` : undefined;
  const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo });
  return error ? { ok: false, error: error.message } : { ok: true };
}

/** Claim a new handle. The value is one WE generated (the re-roll button — a user
 *  never types it), so there's nothing to validate; the only failure that matters is
 *  the race where two people grab the same word at once, which the UNIQUE index turns
 *  into a duplicate-key error we report as "taken" so the UI can re-roll. */
export async function updateHandle(handle: string): Promise<AuthResult> {
  const profile = state.profile;
  if (!profile) return { ok: false, error: "Not signed in." };

  if (!supabase) {
    const next = { ...profile, handle };
    writeLocal(next);
    setState({ status: "authed", profile: next });
    return { ok: true };
  }

  const { error } = await supabase.from("profiles").update({ handle }).eq("id", profile.id);
  if (error) {
    if (/duplicate|unique/i.test(error.message)) return { ok: false, error: "taken" };
    return { ok: false, error: error.message };
  }
  setState({ status: "authed", profile: { ...profile, handle } });
  return { ok: true };
}
