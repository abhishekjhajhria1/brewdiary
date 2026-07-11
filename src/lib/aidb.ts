// Ninkasi Data Plane — the client for the SEPARATE AI database.
//
// SERVER-ONLY. Never import this from a component or any "use client" file: it reads
// AI_SUPABASE_SERVICE_KEY (a full-access key) and connects to the second Supabase
// project that holds the AI corpus. It's only ever used inside route handlers
// (src/app/api/**), which run on the server.
//
// The design guarantee: the browser has NO credentials for this database. All writes
// flow through our server, carry only a PSEUDONYMOUS user reference (a salted hash),
// and only for consented, live exchanges. See ai-db/schema.sql.

import { createHash } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const AI_URL = process.env.AI_SUPABASE_URL;
const AI_SERVICE_KEY = process.env.AI_SUPABASE_SERVICE_KEY;
const SALT = process.env.AI_DB_SALT || ""; // set a long random value in .env.local

/** True once the second (AI) Supabase project is configured. Until then, everything
 *  here is a graceful no-op so the app runs fine without the AI DB. */
export const aiDbEnabled = Boolean(AI_URL && AI_SERVICE_KEY);

let _client: SupabaseClient | null = null;
function client(): SupabaseClient | null {
  if (!aiDbEnabled) return null;
  if (!_client) {
    _client = createClient(AI_URL as string, AI_SERVICE_KEY as string, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
  }
  return _client;
}

/** Turn a real app user id into a stable, non-reversible reference for the corpus.
 *  Same user → same ref (so we can dedup and honor delete), but you cannot get the
 *  user id back without the server-side salt. */
export function pseudonymize(userId: string): string {
  return createHash("sha256").update(`${SALT}:${userId}`).digest("hex");
}

export interface ExchangeInput {
  userId: string; // real id — hashed here, never stored raw
  prompt: string;
  reply: string;
  context?: string | null;
  model?: string | null;
}

/** Record one consented, live exchange in the AI corpus. Fire-and-forget safe:
 *  it swallows its own errors so a logging hiccup never breaks a chat response. */
export async function recordExchange(x: ExchangeInput): Promise<void> {
  const c = client();
  if (!c) return;
  if (!x.userId || !x.prompt.trim() || !x.reply.trim()) return;
  try {
    await c.from("exchanges").insert({
      user_ref: pseudonymize(x.userId),
      prompt: x.prompt,
      reply: x.reply,
      context: x.context ?? null,
      model: x.model ?? null,
    });
  } catch {
    /* corpus write is best-effort; never surface to the user */
  }
}

/** Right-to-be-forgotten: delete every corpus row for this user. Called by the
 *  authenticated /api/ninkasi/forget route when a user clears their Ninkasi data. */
export async function forgetUser(userId: string): Promise<void> {
  const c = client();
  if (!c || !userId) return;
  try {
    await c.from("exchanges").delete().eq("user_ref", pseudonymize(userId));
  } catch {
    /* best-effort */
  }
}
