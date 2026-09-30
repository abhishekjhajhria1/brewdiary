// Import outside signals (public facts about places) from a file.
//
//   npm run signals:import -- signals.json            check only: what would land, what's refused
//   npm run signals:import -- signals.json --apply    write them (SUPABASE_DB_URL, the maintainer's)
//
// The file is a JSON array, { "signals": [...] }, or JSON Lines. Each record goes
// through cleanSignal() (src/lib/signals.ts) — the same cleaner as /api/signals/import —
// and the table's guard (supabase/049) refuses anything that still looks like a person.
// Runs with Node's type stripping so it can load the TypeScript cleaner directly.
import { readFileSync } from "node:fs";
import { Client } from "pg";
import { cleanBatch } from "../src/lib/signals.ts";
import { encodeGeohash } from "../src/lib/geohash.ts";

try {
  for (const line of readFileSync(".env.local", "utf8").split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i > 0 && !(t.slice(0, i).trim() in process.env)) process.env[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
} catch {
  /* no .env.local */
}

const [file, ...flags] = process.argv.slice(2);
if (!file) {
  console.error("usage: npm run signals:import -- <file.json|file.jsonl> [--apply]");
  process.exit(1);
}
const text = readFileSync(file, "utf8").trim();
let records;
try {
  const parsed = JSON.parse(text);
  records = Array.isArray(parsed) ? parsed : Array.isArray(parsed.signals) ? parsed.signals : [];
} catch {
  records = text.split("\n").filter((l) => l.trim()).map((l, i) => {
    try {
      return JSON.parse(l);
    } catch {
      return `line ${i + 1} isn't JSON`;
    }
  });
}

const { rows, refused } = cleanBatch(records, encodeGeohash);
console.log(`${records.length} records → ${rows.length} to import, ${refused.length} refused`);
for (const r of refused.slice(0, 50)) console.log(`  refused #${r.index}: ${r.reason}`);
if (refused.length > 50) console.log(`  … and ${refused.length - 50} more`);

if (!flags.includes("--apply")) {
  console.log("\n(check only — add --apply to write)");
  process.exit(0);
}
if (!process.env.SUPABASE_DB_URL) {
  console.error("SUPABASE_DB_URL is not set — put it in .env.local.");
  process.exit(1);
}

const db = new Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: process.env.SUPABASE_DB_URL.includes("sslmode=disable") ? false : { rejectUnauthorized: false } });
await db.connect();
const cols = ["area", "cell", "kind", "title", "detail", "starts_on", "ends_on", "facts", "source", "source_url", "dedupe_key", "expires_at"];
let ok = 0;
const failed = [];
for (const r of rows) {
  try {
    await db.query(
      `insert into public.area_signals (${cols.join(",")}) values (${cols.map((_, i) => `$${i + 1}`).join(",")})
       on conflict (dedupe_key) do update set ${cols.filter((c) => c !== "dedupe_key").map((c) => `${c} = excluded.${c}`).join(", ")}, observed_at = now()`,
      cols.map((c) => (c === "facts" ? JSON.stringify(r[c]) : r[c])),
    );
    ok++;
  } catch (e) {
    failed.push(`${r.title}: ${e.message}`);
  }
}
await db.end();
console.log(`\nimported ${ok}${failed.length ? `, the database refused ${failed.length}:` : ""}`);
for (const f of failed.slice(0, 20)) console.log(`  ✗ ${f}`);
process.exitCode = failed.length ? 1 : 0;
