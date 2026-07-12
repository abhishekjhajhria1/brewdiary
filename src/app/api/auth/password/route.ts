// Set a new password for the signed-in (recovery) session — called by /reset.
// Done SERVER-SIDE on purpose: browser-side `auth.updateUser()` can hang forever
// on supabase-js's internal navigator lock (widely-reported), which left the reset
// form spinning. Here the session comes from cookies, the update runs over plain
// HTTP, and the rotated tokens are written back to the response cookies.
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { rateLimit, clientKey } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  // CSRF defense-in-depth: a state-changing, cookie-authenticated route must only
  // accept same-origin calls. (SameSite=Lax already blocks cross-site POSTs; this
  // holds even if a future cookie config loosens that.)
  const origin = req.headers.get("origin");
  const host = req.headers.get("host");
  if (origin && host) {
    // "Origin: null" (sandboxed iframes) and malformed values must 403, not throw
    let originHost: string | null = null;
    try {
      originHost = new URL(origin).host;
    } catch {}
    if (originHost !== host) {
      return Response.json({ error: "Cross-origin request rejected." }, { status: 403 });
    }
  }

  // A password change is rare — a tight limit costs a real user nothing.
  const gate = rateLimit(`pw:${clientKey(req)}`, 5, 60_000);
  if (!gate.ok) {
    return Response.json(
      { error: "Too many attempts — try again in a moment." },
      { status: 429, headers: { "Retry-After": String(gate.retryAfter) } },
    );
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) return Response.json({ error: "Cloud backend not configured." }, { status: 503 });

  let password: unknown;
  try {
    ({ password } = await req.json());
  } catch {
    return Response.json({ error: "Bad request." }, { status: 400 });
  }
  if (typeof password !== "string" || password.length < 6) {
    return Response.json({ error: "Password must be at least 6 characters." }, { status: 400 });
  }
  if (password.length > 72) {
    return Response.json({ error: "Password is too long (72 characters max)." }, { status: 400 });
  }

  const cookieStore = await cookies();
  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (toSet) => {
        // route handlers may write cookies — persist the rotated session
        toSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Your reset session expired — request a fresh link." }, { status: 401 });

  const { error } = await supabase.auth.updateUser({ password });
  if (error) return Response.json({ error: error.message }, { status: 400 });

  return Response.json({ ok: true }, { headers: { "Cache-Control": "no-store" } });
}
