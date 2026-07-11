// Export the central Ninkasi training corpus as fine-tune-ready JSONL — the
// distillation dataset: cheap-teacher answers our own model learns from.
//
// Usage (from the repo root):
//   node scripts/ninkasi/export-dataset.mjs [--min 50] [--out scripts/ninkasi/out]
//
// Reads from the SEPARATE AI database (the second Supabase project) using
// AI_SUPABASE_URL + AI_SUPABASE_SERVICE_KEY from .env.local — the service key
// bypasses RLS, and this exporter is the ONLY consumer allowed to read the whole
// corpus. Run it locally, never ship it. Rows are pseudonymous (user_ref, a salted
// hash) and were only written with "Help train Ninkasi" consent on.
//
// Back-compat: if the AI DB isn't configured yet, it falls back to the app DB's
// legacy `ninkasi_exchanges` table (NEXT_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY).
//
// Output: <out>/ninkasi-train.jsonl + <out>/ninkasi-val.jsonl (95/5 split), each line
//   {"messages":[{role:system},{role:user},{role:assistant}]}
// — the OpenAI chat fine-tune format, accepted as-is by Together AI, Fireworks,
// OpenAI, and convertible one-liner-style for Unsloth/axolotl (see train_lora.py).
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
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

const args = process.argv.slice(2);
function arg(name, dflt) {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : dflt;
}
const MIN = Number(arg("min", "50"));
const OUT = arg("out", "scripts/ninkasi/out");

// The persona MUST match what the app serves — read it straight out of bartender.ts
// so the dataset and the live system prompt can never drift apart.
const bartenderSrc = readFileSync("src/lib/bartender.ts", "utf8");
const m = bartenderSrc.match(/export const SYSTEM_PROMPT = `([\s\S]*?)`;/);
if (!m) {
  console.error("Could not find SYSTEM_PROMPT in src/lib/bartender.ts — did its shape change?");
  process.exit(1);
}
const SYSTEM_PROMPT = m[1];

// Prefer the SEPARATE AI database; fall back to the legacy app-DB table.
const useAiDb = Boolean(process.env.AI_SUPABASE_URL && process.env.AI_SUPABASE_SERVICE_KEY);
const DB_URL = useAiDb ? process.env.AI_SUPABASE_URL : process.env.NEXT_PUBLIC_SUPABASE_URL;
const DB_KEY = useAiDb ? process.env.AI_SUPABASE_SERVICE_KEY : process.env.SUPABASE_SERVICE_ROLE_KEY;
const TABLE = useAiDb ? "exchanges" : "ninkasi_exchanges";
console.log(`reading from ${useAiDb ? "AI database" : "legacy app-DB table"} (${TABLE})`);

const admin = createClient(DB_URL, DB_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// page through the whole corpus
const rows = [];
for (let from = 0; ; from += 1000) {
  const { data, error } = await admin
    .from(TABLE)
    .select("prompt, reply, context, model, created_at")
    .order("created_at", { ascending: true })
    .range(from, from + 999);
  if (error) {
    console.error("fetch failed:", error.message);
    process.exit(1);
  }
  rows.push(...(data ?? []));
  if (!data || data.length < 1000) break;
}
console.log(`fetched ${rows.length} exchanges`);

// clean: drop empties/tiny replies, near-dupes (same prompt+reply), fallback rows
const seen = new Set();
const clean = rows.filter((r) => {
  if (!r.prompt?.trim() || !r.reply?.trim()) return false;
  if (r.reply.trim().length < 40) return false; // too short to teach anything
  if (r.model === "fallback") return false; // scripted replies aren't teacher signal
  const h = createHash("sha1").update(`${r.prompt.trim().toLowerCase()}\n${r.reply.trim().toLowerCase()}`).digest("hex");
  if (seen.has(h)) return false;
  seen.add(h);
  return true;
});
console.log(`kept ${clean.length} after cleaning`);
if (clean.length < MIN) {
  console.error(
    `Only ${clean.length} usable exchanges (< --min ${MIN}). Keep collecting — a first LoRA wants ~500+, a good one 2–5k.`,
  );
  process.exit(1);
}

const toLine = (r) =>
  JSON.stringify({
    messages: [
      { role: "system", content: SYSTEM_PROMPT + (r.context ?? "") },
      { role: "user", content: r.prompt },
      { role: "assistant", content: r.reply },
    ],
  });

// deterministic-ish shuffle then 95/5 split
const shuffled = clean
  .map((r) => ({ r, k: createHash("sha1").update(r.prompt + r.created_at).digest("hex") }))
  .sort((a, b) => a.k.localeCompare(b.k))
  .map((x) => x.r);
const cut = Math.max(1, Math.floor(shuffled.length * 0.05));
const val = shuffled.slice(0, cut);
const train = shuffled.slice(cut);

mkdirSync(OUT, { recursive: true });
writeFileSync(`${OUT}/ninkasi-train.jsonl`, train.map(toLine).join("\n") + "\n");
writeFileSync(`${OUT}/ninkasi-val.jsonl`, val.map(toLine).join("\n") + "\n");
console.log(`wrote ${OUT}/ninkasi-train.jsonl (${train.length}) and ninkasi-val.jsonl (${val.length})`);
console.log("next: scripts/ninkasi/README.md → fine-tune + host, then point AI_BASE_URL at it.");
