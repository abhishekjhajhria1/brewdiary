// Server-side Supabase helpers for route handlers — reads the signed-in user from
// the session cookie so the server can trust WHO is calling without believing a
// client-supplied id. Server-only (uses next/headers cookies).
//
// The mobile app has no cookie jar: it sends `Authorization: Bearer <access token>`
// instead. When a request carries one, the token is verified with Supabase Auth
// (getUser(jwt) checks the signature server-side) — it is never trusted blindly.
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import type { User } from "@supabase/supabase-js";

/** The authenticated user for the current request, or null if signed out / unconfigured.
 *  Pass `req` so a bearer token (the mobile app) is honoured as well as the cookie. */
export async function getServerUser(req?: Request): Promise<User | null> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) return null;

  const bearer = req?.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (bearer) {
    const client = createClient(url, anon, { auth: { persistSession: false } });
    const { data } = await client.auth.getUser(bearer);
    return data.user ?? null;
  }

  const cookieStore = await cookies();
  const supabase = createServerClient(url, anon, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: () => {
        /* read-only in a route handler — token refresh is handled by middleware */
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user ?? null;
}
