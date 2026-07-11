// Tiny migration runner: executes a .sql file against a Postgres connection string.
// Usage: node scripts/db.mjs <file.sql> [ENV_VAR_WITH_CONN_STRING]
//   node scripts/db.mjs supabase/schema.sql              # uses SUPABASE_DB_URL (the app DB)
//   node scripts/db.mjs ai-db/schema.sql AI_SUPABASE_DB_URL   # the SEPARATE AI DB
// Reads env from .env.local (so the connection string / password never hits the shell history).
import { readFileSync } from "node:fs";
import { Client } from "pg";

// --- load .env.local (minimal parser; values may contain '=') ---
function loadEnv(path = ".env.local") {
  try {
    for (const line of readFileSync(path, "utf8").split("\n")) {
      const t = line.trim();
      if (!t || t.startsWith("#")) continue;
      const i = t.indexOf("=");
      if (i === -1) continue;
      const k = t.slice(0, i).trim();
      const v = t.slice(i + 1).trim();
      if (!(k in process.env)) process.env[k] = v;
    }
  } catch {
    /* no .env.local — rely on real env */
  }
}
loadEnv();

const file = process.argv[2];
if (!file) {
  console.error("usage: node scripts/db.mjs <file.sql>");
  process.exit(1);
}
const connVar = process.argv[3] || "SUPABASE_DB_URL";
const conn = process.env[connVar];
if (!conn) {
  console.error(`${connVar} is empty — paste the Session-mode connection string into .env.local first.`);
  process.exit(1);
}

const sql = readFileSync(file, "utf8");
const client = new Client({ connectionString: conn, ssl: { rejectUnauthorized: false } });

try {
  await client.connect();
  await client.query(sql);
  console.log(`✓ ran ${file}`);
} catch (e) {
  console.error(`✗ ${file} failed:\n`, e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
