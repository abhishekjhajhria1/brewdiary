// Backfill embeddings for exchanges collected BEFORE RAG existed (or any row whose
// embedding is null). Run occasionally: node scripts/ninkasi/embed-backfill.mjs
//
// Uses the SAME open-source model as the app (Supabase/gte-small, 384-dim), the service
// key, and updates rows in place. Safe to re-run — it only touches rows missing a vector.
import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";
import { pipeline, env } from "@huggingface/transformers";

// --- load .env.local ---
for (const line of readFileSync(".env.local", "utf8").split("\n")) {
  const t = line.trim();
  if (!t || t.startsWith("#")) continue;
  const i = t.indexOf("=");
  if (i === -1) continue;
  const k = t.slice(0, i).trim();
  if (!(k in process.env)) process.env[k] = t.slice(i + 1).trim();
}

const URL = process.env.AI_SUPABASE_URL;
const KEY = process.env.AI_SUPABASE_SERVICE_KEY;
if (!URL || !KEY) {
  console.error("AI_SUPABASE_URL / AI_SUPABASE_SERVICE_KEY missing in .env.local");
  process.exit(1);
}

console.log("loading gte-small…");
env.allowLocalModels = false;
const extractor = await pipeline("feature-extraction", "Supabase/gte-small");
const embed = async (t) => {
  const o = await extractor(String(t).replace(/\s+/g, " ").trim().slice(0, 2000), { pooling: "mean", normalize: true });
  return Array.from(o.data);
};

const supa = createClient(URL, KEY, { auth: { autoRefreshToken: false, persistSession: false } });

let done = 0;
for (;;) {
  const { data, error } = await supa.from("exchanges").select("id, prompt").is("embedding", null).limit(50);
  if (error) {
    console.error("\nquery failed:", error.message);
    process.exit(1);
  }
  if (!data || data.length === 0) break;
  for (const row of data) {
    const vec = await embed(row.prompt);
    await supa.from("exchanges").update({ embedding: vec }).eq("id", row.id);
    done++;
  }
  process.stdout.write(`\rembedded ${done}…`);
}
console.log(`\n✓ backfilled ${done} exchange${done === 1 ? "" : "s"}`);
