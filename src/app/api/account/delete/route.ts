// Delete your account — really delete it.
//
// Required by GDPR Art. 17 (erasure), India's DPDP Act, and the app-store rules
// (both stores demand an in-app account-deletion route). This is not a soft flag
// or a "deactivate": the auth user is destroyed, and every table that references a
// profile does so with ON DELETE CASCADE, so the person goes with it.
//
// Deleting the AUTH USER rather than walking tables by hand is deliberate: a table
// somebody adds next year is covered automatically, whereas a hand-written list of
// DELETEs quietly rots and leaves orphaned personal data behind — which is exactly
// the kind of thing that turns a deletion request into a breach.
//
// WHO is decided by the session cookie (getServerUser), never by the request body:
// a client cannot ask us to delete somebody else.
import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { getServerUser } from "@/lib/supabase-server";
import { sameOrigin } from "@/lib/origin";
import { rateLimit, clientKey } from "@/lib/ratelimit";

export async function POST(req: Request) {
  // The single most destructive route in the app, authenticated by a COOKIE — so it
  // gets the same-origin check and a rate limit BEFORE anything else. (It shipped
  // without either while the password route had both; a forged cross-site POST here
  // would have been an unrecoverable deletion. Any route that destroys something on
  // the strength of a cookie starts with these two guards.)
  if (!sameOrigin(req)) {
    return NextResponse.json({ error: "Cross-origin request rejected." }, { status: 403 });
  }
  const gate = rateLimit(`del:${clientKey(req)}`, 3, 60_000);
  if (!gate.ok) {
    return NextResponse.json(
      { error: "Too many attempts — try again in a moment." },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } },
    );
  }

  const user = await getServerUser();
  if (!user) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY; // server-only, never NEXT_PUBLIC_
  if (!url || !serviceKey) {
    return NextResponse.json({ error: "Account deletion isn't configured on this server." }, { status: 500 });
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Storage isn't covered by a foreign key, so the photos have to go explicitly —
  // they're the one place a deleted person could otherwise linger.
  try {
    const { data: files } = await admin.storage.from("photos").list(user.id);
    if (files?.length) {
      await admin.storage.from("photos").remove(files.map((f) => `${user.id}/${f.name}`));
    }
  } catch {
    /* no bucket / nothing stored — deletion proceeds regardless */
  }

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) {
    return NextResponse.json({ error: "Couldn't delete the account. Please try again." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
