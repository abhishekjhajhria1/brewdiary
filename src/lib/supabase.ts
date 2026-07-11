// Supabase browser client — the single backend (auth + Postgres + storage).
// Reads NEXT_PUBLIC_* (Next.js inlines these into the client bundle). The anon key
// is public by design; the data is protected by RLS (see supabase/schema.sql).
//
// Cookie-backed (@supabase/ssr createBrowserClient) so the session is visible to
// the server too — middleware.ts guards routes and app/page.tsx picks Landing vs
// the calendar without a client-side flash.
//
// `supabase` is null when the env isn't configured, so the app degrades to the local
// store instead of crashing. Callers should guard: `if (!supabase) { ...local... }`.
import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export const supabaseEnabled = Boolean(url && anon);

export const supabase: SupabaseClient | null = supabaseEnabled
  ? createBrowserClient(url as string, anon as string)
  : null;
