# Our own Ninkasi — the distillation pipeline

The plan, end to end: a **cheap teacher answers users today; its answers become the
dataset; a small model we own learns from it; we host that model and point the app
at it.** The app never changes — `/api/bartender` speaks OpenAI-compatible to
whatever `AI_BASE_URL` names.

```
users chat  ──►  /api/bartender  ──►  TEACHER (Groq llama-3.3-70b)   ← today, needs AI_API_KEY
                     │
                     └─ consented exchanges ──► ninkasi_exchanges (Supabase)
                                                      │
                              export-dataset.mjs ─────┘   → JSONL (train/val)
                                                      │
                                train_lora.py (LoRA over Llama-3.1-8B)
                                                      │
                            vLLM host ("ninkasi-8b") ─┘   ← tomorrow
                                                      │
                     AI_BASE_URL=http://<host>:8000/v1  AI_MODEL=ninkasi-8b
```

## Why these models
- **Teacher: Groq · `llama-3.3-70b-versatile`.** Cheapest capable hosted option,
  OpenAI-compatible, fast. Its answers (wrapped in the Ninkasi persona prompt)
  are what we distill. Swap by env if pricing shifts — nothing in code cares.
- **Student: `Llama-3.1-8B-Instruct` + LoRA.** Small enough to serve on one 24GB
  GPU (or Together/Fireworks serverless), big enough to hold the persona and the
  drink knowledge. The problem is narrow — one persona, one domain — which is
  exactly where a fine-tuned 8B matches a 70B in practice.

## Step by step
1. **Go live with the teacher** — in `.env.local`:
   `AI_API_KEY=<groq key>` (defaults already target Groq). Done: users chat,
   and every consented exchange lands in `ninkasi_exchanges` with its context
   block and the model name.
2. **Collect.** A first LoRA wants **~500+** cleaned exchanges; a good one 2–5k.
   Check progress: `select count(*) from ninkasi_exchanges;`
3. **Export** — `node scripts/ninkasi/export-dataset.mjs` → cleaned, deduped,
   95/5-split JSONL in `scripts/ninkasi/out/`. The system line is read live from
   `src/lib/bartender.ts` so persona and dataset never drift.
4. **Train** — `python scripts/ninkasi/train_lora.py` on any single-GPU box or
   Colab (Unsloth 4-bit). Or skip GPUs entirely: the same JSONL uploads as-is to
   Together AI / Fireworks / OpenAI fine-tuning.
5. **Host** — `vllm serve ./ninkasi-8b-merged --served-model-name ninkasi-8b`
   (or the provider's deployed endpoint).
6. **Switch** — `.env.local`: `AI_BASE_URL=http://<host>:8000/v1`,
   `AI_MODEL=ninkasi-8b`, keep an `AI_API_KEY` if your host wants one. The
   collection keeps running, so the NEXT fine-tune is always brewing.

## Consent & privacy (non-negotiable, already enforced)
- Exchanges are stored **only while "Help train Ninkasi" is on** (You → Settings);
  "clear ninkasi data" deletes the user's cloud rows too (RLS lets them).
- The corpus is readable **only by the service role** — this exporter, run locally.
- The curation signals Ninkasi sees are consent-shaped as well: the guest's own
  diary, their friends' **shared** entries (visible to them anyway), and
  `taste_trends()` — opt-in, k-anonymous (≥3 users), counts only.
