"use client";

// Data rights. Not a nice-to-have: GDPR gives an enforceable right of ACCESS
// (Art. 15) and ERASURE (Art. 17); India's DPDP Act 2023 gives correction and
// erasure; Google Play and the App Store both require an in-app route to delete
// your account. We had "forget my AI chats" and nothing else — which would have
// been an app-store rejection and, in the EU, a straightforward breach.
//
// Two operations, both honest:
//   exportEverything() — every row we hold about you, as a JSON file you keep.
//   deleteAccount()    — really deletes. Not a soft flag, not a "deactivate".
//
// Deletion leans on Postgres: every table that references a profile does so with
// ON DELETE CASCADE, so removing the auth user removes the person. That's why the
// server route deletes the AUTH user rather than walking tables by hand — a table
// added next year is covered automatically, whereas a hand-written list rots.
import { supabase } from "./supabase";

/** Everything we hold about you, in one file. */
export async function exportEverything(): Promise<string | null> {
  if (!supabase) return "You're signed out — there's nothing stored in the cloud to export.";
  const { data: auth } = await supabase.auth.getUser();
  const me = auth.user?.id;
  if (!me) return "You're signed out.";

  // Read only what's yours; RLS would refuse anything else anyway.
  const [profile, entries, wishlist, expenses, shares, points, spend, consent] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", me).maybeSingle(),
    supabase.from("entries").select("*").eq("user_id", me),
    supabase.from("wishlist").select("*").eq("user_id", me),
    supabase.from("expenses").select("*").eq("payer_id", me),
    supabase.from("expense_shares").select("*").eq("user_id", me),
    supabase.from("point_events").select("*").eq("subject_user_id", me),
    supabase.from("spend_events").select("*").eq("subject_user_id", me),
    supabase.from("room_consent").select("*").eq("user_id", me),
  ]);

  const payload = {
    exported_at: new Date().toISOString(),
    note:
      "Everything brewdiary holds about you. Points and tabs are included because they're about you, " +
      "even though only a venue could write them.",
    profile: profile.data ?? null,
    entries: entries.data ?? [],
    wishlist: wishlist.data ?? [],
    expenses: expenses.data ?? [],
    expense_shares: shares.data ?? [],
    points: points.data ?? [],
    spend: spend.data ?? [],
    venue_screen_consent: consent.data ?? [],
    on_this_device_only: {
      goals: safeRead("brewdiary.goals.v1"),
      extras: safeRead("brewdiary.features.v1"),
      currency: safeRead("brewdiary.currency.v1"),
      country: safeRead("brewdiary.country.v1"),
    },
  };

  download(JSON.stringify(payload, null, 2), `brewdiary-${new Date().toISOString().slice(0, 10)}.json`);
  return null;
}

/** Delete the account and everything in it. Irreversible, and meant to be. */
export async function deleteAccount(): Promise<string | null> {
  const res = await fetch("/api/account/delete", { method: "POST" });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    return (body as { error?: string }).error ?? "Couldn't delete the account — please try again.";
  }
  try {
    // Clear the device too, so a shared laptop doesn't keep the leftovers.
    for (const k of Object.keys(window.localStorage)) {
      if (k.startsWith("brewdiary.")) window.localStorage.removeItem(k);
    }
  } catch {
    /* private mode — nothing cached anyway */
  }
  await supabase?.auth.signOut();
  return null;
}

function safeRead(key: string): unknown {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function download(text: string, filename: string) {
  const url = URL.createObjectURL(new Blob([text], { type: "application/json" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
