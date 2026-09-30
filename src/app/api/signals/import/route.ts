import { timingSafeEqual } from "node:crypto";
import { createClient } from "@supabase/supabase-js";
import { cleanBatch } from "@/lib/signals";
import { encodeGeohash } from "@/lib/geohash";
import { rateLimit, clientKey } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Where outside tools (a scraper, a feed, a scheduled job) push public facts about
// places — events, openings, hours, prices — for the area map and Ninkasi for hosts.
//
//   POST /api/signals/import            Authorization: Bearer $SIGNALS_IMPORT_TOKEN
//   { "signals": [ { kind, title, geohash | lat+lon, source, starts_on?, ... } ] }
//   ?dry=1 checks and reports without writing.
//
// Everything goes through cleanSignal() (src/lib/signals.ts): places and happenings in,
// people out. The table's guard (049) refuses whatever slips through. The write uses
// the service-role key, which lives here on the server and nowhere else.
const MAX_RECORDS = 500;
const MAX_BYTES = 1_000_000;

function authorized(req: Request): boolean {
  const want = process.env.SIGNALS_IMPORT_TOKEN;
  const got = req.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!want || want.length < 24 || !got) return false;
  const a = Buffer.from(got);
  const b = Buffer.from(want);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function POST(req: Request) {
  const gate = rateLimit(`signals:${clientKey(req)}`, 30, 60_000);
  if (!gate.ok) return Response.json({ error: "slow down" }, { status: 429, headers: { "Retry-After": String(gate.retryAfter) } });
  if (!authorized(req)) return Response.json({ error: "not authorized" }, { status: 401 });
  if (Number(req.headers.get("content-length") || 0) > MAX_BYTES) return Response.json({ error: "too large" }, { status: 413 });

  let records: unknown[];
  try {
    const body = await req.json();
    records = Array.isArray(body) ? body : Array.isArray(body?.signals) ? body.signals : [];
  } catch {
    return Response.json({ error: "send JSON: { signals: [...] }" }, { status: 400 });
  }
  if (records.length === 0) return Response.json({ error: "no signals" }, { status: 400 });
  if (records.length > MAX_RECORDS) return Response.json({ error: `at most ${MAX_RECORDS} per request` }, { status: 413 });

  const { rows, refused } = cleanBatch(records, encodeGeohash);
  const dry = new URL(req.url).searchParams.get("dry") === "1";
  if (dry || rows.length === 0) return Response.json({ dry, accepted: rows.length, refused });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !service) return Response.json({ error: "import isn't configured on this server" }, { status: 503 });

  const db = createClient(url, service, { auth: { persistSession: false } });
  const { error } = await db.from("area_signals").upsert(rows, { onConflict: "dedupe_key" });
  if (error) return Response.json({ error: error.message, refused }, { status: 422 });
  return Response.json({ imported: rows.length, refused });
}
