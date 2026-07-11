// Server-side Supabase helpers for route handlers — reads the signed-in user from
// the session cookie so the server can trust WHO is calling without believing a
// client-supplied id. Server-only (uses next/headers cookies).
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { User } from "@supabase/supabase-js";

/** The authenticated user for the current request, or null if signed out / unconfigured. */
export async function getServerUser(): Promise<User | null> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anon) return null;

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
