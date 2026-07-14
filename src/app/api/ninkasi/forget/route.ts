// Right-to-be-forgotten for the AI corpus. When a user hits "clear Ninkasi data"
// (You → Settings), the browser can't reach the separate AI database (it has no
// credentials there — by design). So it calls this authenticated server route, which
// resolves who they are from the session cookie and deletes their pseudonymous rows
// from the AI data plane.
import { getServerUser } from "@/lib/supabase-server";
import { forgetUser, aiDbEnabled } from "@/lib/aidb";
import { sameOrigin } from "@/lib/origin";
import { rateLimit, clientKey } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  // Cookie-authenticated and it deletes something → same-origin + rate limit first,
  // like every state-changing route (see lib/origin.ts).
  if (!sameOrigin(req)) return new Response("Cross-origin request rejected.", { status: 403 });
  const gate = rateLimit(`forget:${clientKey(req)}`, 5, 60_000);
  if (!gate.ok) {
    return new Response("Too many attempts — try again in a moment.", {
      status: 429,
      headers: { "Retry-After": String(gate.retryAfter) },
    });
  }

  const user = await getServerUser();
  if (!user) return new Response("Unauthorized", { status: 401 });
  if (aiDbEnabled) await forgetUser(user.id);
  return new Response(JSON.stringify({ ok: true }), {
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
