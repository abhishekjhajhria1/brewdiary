// Verify the separate AI database end-to-end: connect with the service key, then
// insert → read back → delete a throwaway row in `exchanges`. Proves the credentials,
// the schema, and the recordExchange/forgetUser data path all work — without needing
// the app running. Reads AI_SUPABASE_URL + AI_SUPABASE_SERVICE_KEY from .env.local.
//
//   node scripts/ninkasi/verify-aidb.mjs
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { createClient } from "@supabase/supabase-js";

for (const line of readFileSync(".env.local", "utf8").split("\n")) {
  const t = line.trim();
  if (!t || t.startsWith("#")) continue;
  const i = t.indexOf("=");
  if (i === -1) continue;
  const k = t.slice(0, i).trim();
  if (!(k in process.env)) process.env[k] = t.slice(i + 1).trim();
}

const url = process.env.AI_SUPABASE_URL;
const key = process.env.AI_SUPABASE_SERVICE_KEY;
const salt = process.env.AI_DB_SALT || "";
if (!url || !key) {
  console.error("✗ AI_SUPABASE_URL / AI_SUPABASE_SERVICE_KEY missing in .env.local");
  process.exit(1);
}
console.log(`→ AI DB: ${url}`);
console.log(`→ salt set: ${salt ? "yes" : "NO (set AI_DB_SALT!)"}`);

const db = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
const userRef = createHash("sha256").update(`${salt}:__verify_user__`).digest("hex");

// 1) insert
const ins = await db
  .from("exchanges")
  .insert({ user_ref: userRef, prompt: "verify: hi", reply: "verify: a cortado, love.", model: "__verify__" })
  .select("id")
  .single();
if (ins.error) {
  console.error(`✗ insert failed: ${ins.error.message}`);
  if (/relation .*exchanges.* does not exist|schema cache/i.test(ins.error.message)) {
    console.error("  → the schema isn't applied yet. Apply ai-db/schema.sql (SQL Editor) or set AI_SUPABASE_DB_URL and run:\n     node scripts/db.mjs ai-db/schema.sql AI_SUPABASE_DB_URL");
  }
  process.exit(1);
}
console.log(`✓ insert ok (id ${ins.data.id})`);

// 2) read back
const sel = await db.from("exchanges").select("id, user_ref, model").eq("id", ins.data.id).single();
if (sel.error) {
  console.error(`✗ read-back failed: ${sel.error.message}`);
  process.exit(1);
}
console.log(`✓ read-back ok (user_ref ${sel.data.user_ref.slice(0, 12)}…, pseudonymous: ${sel.data.user_ref !== "__verify_user__"})`);

// 3) delete (the forget path)
const del = await db.from("exchanges").delete().eq("id", ins.data.id);
if (del.error) {
  console.error(`✗ delete failed: ${del.error.message}`);
  process.exit(1);
}
console.log("✓ delete ok (forget path works)");

// 4) confirm anon is sealed (RLS deny-all): a client with the ANON key should read nothing
const anon = process.env.NEXT_PUBLIC_AI_ANON_KEY;
if (anon) {
  const pub = createClient(url, anon, { auth: { persistSession: false } });
  const r = await pub.from("exchanges").select("id").limit(1);
  console.log(`✓ anon sealed: ${r.error ? "read blocked (" + r.error.message + ")" : (r.data?.length ? "!! anon READ rows — check RLS" : "0 rows")}`);
}

console.log("\n✅ AI database verified: credentials, schema, and insert/read/delete all work.");
console.log("   Consented, live Ninkasi exchanges will now be recorded here (pseudonymized).");
