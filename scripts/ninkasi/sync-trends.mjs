// Trend-snapshot batch job — the second half of the AI data plane.
//
// Reads the app database's k-anonymous taste_trends() (drinks/moods logged by ≥3
// consenting users, counts only) and writes point-in-time snapshots into the SEPARATE
// AI database's trend_snapshots table. Nothing personal ever crosses: the source
// function already aggregates and enforces the k-threshold, and only opt-in users
// (profiles.share_trends) are included.
//
// Run it periodically (cron / Task Scheduler / a scheduled cloud agent) to build a
// history of what the community's been pouring — the raw material for the Discover
// "what's trending" surface and, later, anonymized B2B trend reports.
//
//   node scripts/ninkasi/sync-trends.mjs [--windows 7,14,30]
//
// Env (from .env.local):
//   NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY   (app DB — source)
//   AI_SUPABASE_URL          + AI_SUPABASE_SERVICE_KEY      (AI DB — destination)
import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";

for (const line of readFileSync(".env.local", "utf8").split("\n")) {
  const t = line.trim();
  if (!t || t.startsWith("#")) continue;
  const i = t.indexOf("=");
  if (i === -1) continue;
  const k = t.slice(0, i).trim();
  if (!(k in process.env)) process.env[k] = t.slice(i + 1).trim();
}

const args = process.argv.slice(2);
function arg(name, dflt) {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : dflt;
}
const WINDOWS = arg("windows", "7,14,30")
  .split(",")
  .map((n) => parseInt(n.trim(), 10))
  .filter((n) => Number.isFinite(n) && n > 0);

const appUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const appKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const aiUrl = process.env.AI_SUPABASE_URL;
const aiKey = process.env.AI_SUPABASE_SERVICE_KEY;
if (!appUrl || !appKey) {
  console.error("✗ app DB env missing (NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)");
  process.exit(1);
}
if (!aiUrl || !aiKey) {
  console.error("✗ AI DB env missing (AI_SUPABASE_URL / AI_SUPABASE_SERVICE_KEY) — set up ai-db/ first");
  process.exit(1);
}

const app = createClient(appUrl, appKey, { auth: { autoRefreshToken: false, persistSession: false } });
const ai = createClient(aiUrl, aiKey, { auth: { autoRefreshToken: false, persistSession: false } });

const capturedAt = new Date().toISOString();
let totalRows = 0;

for (const days of WINDOWS) {
  const { data, error } = await app.rpc("taste_trends", { days_back: days });
  if (error) {
    console.error(`✗ taste_trends(${days}) failed: ${error.message}`);
    process.exit(1);
  }
  const rows = (data ?? []).map((r) => ({
    captured_at: capturedAt,
    days_back: days,
    kind: r.kind,
    name: r.name,
    users: r.users,
    logs: r.logs,
  }));
  if (rows.length === 0) {
    console.log(`· ${days}d window: no k-anonymous trends yet (needs ≥3 consenting users on a drink/mood)`);
    continue;
  }
  const { error: insErr } = await ai.from("trend_snapshots").insert(rows);
  if (insErr) {
    console.error(`✗ writing ${days}d snapshot failed: ${insErr.message}`);
    process.exit(1);
  }
  totalRows += rows.length;
  const top = rows.filter((r) => r.kind === "drink").slice(0, 3).map((r) => `${r.name}(${r.users}u)`).join(", ");
  console.log(`✓ ${days}d window: ${rows.length} rows${top ? ` — top drinks: ${top}` : ""}`);
}

console.log(
  totalRows > 0
    ? `\n✅ captured ${totalRows} snapshot rows at ${capturedAt}`
    : `\n✅ ran clean — nothing to capture yet (opt-in trends need ≥3 users sharing the same drink/mood). Re-run once you have data.`,
);
