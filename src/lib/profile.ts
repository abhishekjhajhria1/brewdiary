"use client";

// Auth + profile — backed by Supabase (email + password). The component API
// (useProfile / signUp / signIn / signOut) is the seam the rest of the app uses;
// when Supabase isn't configured it degrades to a local profile so the app still runs.
//
// A single module-level store holds the session so we subscribe to Supabase auth ONCE
// (not once per component). Everything reads it via useSyncExternalStore.
import { useSyncExternalStore } from "react";
import { supabase } from "./supabase";

export interface Profile {
  id: string;
  name: string;
  handle: string;
  createdAt: string;
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
function makeHandle(seed: string): string {
  const slug = seed.toLowerCase().replace(/[^a-z0-9]+/g, "").slice(0, 16) || "guest";
  return `${slug}_${Math.random().toString(36).slice(2, 8)}`;
}

interface ProfileRow {
  id: string;
  display_name: string | null;
  handle: string | null;
  created_at: string;
}
function toProfile(row: ProfileRow): Profile {
  return {
    id: row.id,
    name: row.display_name ?? "you",
    handle: row.handle ?? "",
    createdAt: row.created_at,
  };
}

/** Read the user's profile row, creating it on first sight (handles the email-confirm path). */
async function ensureProfile(user: { id: string; email?: string; user_metadata?: Record<string, unknown> }): Promise<Profile> {
  const db = supabase!;
  const { data } = await db.from("profiles").select("id, display_name, handle, created_at").eq("id", user.id).maybeSingle();
  if (data) return toProfile(data as ProfileRow);

  const name = ((user.user_metadata?.name as string) || user.email?.split("@")[0] || "you").trim();
  const { data: inserted, error } = await db
    .from("profiles")
    .insert({ id: user.id, handle: makeHandle(name), display_name: name })
    .select("id, display_name, handle, created_at")
    .single();
  if (error) {
    // Lost a race (row created concurrently) — re-read.
    const { data: again } = await db.from("profiles").select("id, display_name, handle, created_at").eq("id", user.id).maybeSingle();
    if (again) return toProfile(again as ProfileRow);
    throw error;
  }
  return toProfile(inserted as ProfileRow);
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

/** Set a new password for the current (recovery) session — used by the /reset page. */
export async function updatePassword(password: string): Promise<AuthResult> {
  if (!supabase) return { ok: false, error: "offline" };
  const { error } = await supabase.auth.updateUser({ password });
  return error ? { ok: false, error: error.message } : { ok: true };
}
