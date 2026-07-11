// Right-to-be-forgotten for the AI corpus. When a user hits "clear Ninkasi data"
// (You → Settings), the browser can't reach the separate AI database (it has no
// credentials there — by design). So it calls this authenticated server route, which
// resolves who they are from the session cookie and deletes their pseudonymous rows
// from the AI data plane.
import { getServerUser } from "@/lib/supabase-server";
import { forgetUser, aiDbEnabled } from "@/lib/aidb";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST() {
  const user = await getServerUser();
  if (!user) return new Response("Unauthorized", { status: 401 });
  if (aiDbEnabled) await forgetUser(user.id);
  return new Response(JSON.stringify({ ok: true }), {
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
