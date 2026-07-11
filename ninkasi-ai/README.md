# ninkasi-ai — build & own the Ninkasi model

This folder is the **model workshop**: everything to fine-tune, evaluate, host, and market
**Ninkasi**, brewdiary's AI bartender, as a model *we own* rather than a rented API.

> **Two folders, one pipeline — don't confuse them:**
> - `scripts/ninkasi/` (in the app) = the **data tap**: mirrors consented user chats into Supabase and
>   exports them as JSONL. It runs *inside* the running product.
> - `ninkasi-ai/` (here) = the **workshop**: takes that JSONL (plus a hand-crafted seed) and turns it
>   into a trained, servable model. It runs *offline*, on a GPU box or a laptop.
>
> The app itself never changes — `/api/bartender` speaks the OpenAI chat API to whatever
> `AI_BASE_URL` names. "Ship our own model" = point that env var at what this folder produces.

## The model we chose
**Base: `Qwen/Qwen2.5-7B-Instruct` — Apache-2.0.** Chosen specifically because we intend to *market and
sell* Ninkasi: Apache-2.0 lets us rebrand it "Ninkasi," charge for it, keep our fine-tune closed, with
no user-count cap and no attribution strings. It's also genuinely strong at short, in-character
conversation and small enough to self-host. Full rationale + alternatives (Mistral-7B, Llama-3.1-8B):
**`LICENSE-NOTES.md`**.

We fine-tune with **QLoRA** — a small adapter that teaches *her* onto the base — so a full training run
fits on one 16–24GB GPU (a Colab T4/L4, a 3090/4090, an A10), or you skip GPUs entirely and upload the
same dataset to a managed fine-tune host.

## The pipeline
```
  data/persona_seed.jsonl  (hand-written: voice + every guardrail)  ─┐
                                                                     ├─►  data/build_dataset.py  ─►  out/train.jsonl + out/val.jsonl
  ../scripts/ninkasi/out/*.jsonl  (optional: real consented chats)  ─┘                                        │
                                                                                                              ▼
                                                          train/finetune.py  (QLoRA over Qwen2.5-7B)  ─►  out/ninkasi-7b/  (merged)
                                                                                                              │
                                                       eval/eval.py + eval/rubric.md  (persona + guardrails)  │
                                                                                                              ▼
                                                    serve/ (vLLM or Ollama)  ─►  set AI_BASE_URL in the app  ─►  live
```

## Quickstart
```bash
cd ninkasi-ai
pip install pyyaml                      # just to build the dataset (no GPU)
python data/build_dataset.py           # -> out/train.jsonl, out/val.jsonl   (works on the seed alone)

# --- on a GPU box ---
pip install -r requirements.txt
python train/finetune.py               # -> out/ninkasi-7b/  (merged, servable)

# --- serve + verify ---
bash serve/serve_vllm.sh               # OpenAI-compatible endpoint on :8000
python eval/eval.py --base-url http://localhost:8000/v1 --model ninkasi-7b --api-key x
```
Then in `brewdiary/.env.local`: `AI_BASE_URL=http://<host>:8000/v1`, `AI_MODEL=ninkasi-7b`. Done — the
app now runs on **our** Ninkasi. Details: `serve/README.md`.

## You can start training TODAY
You don't have to wait for 500 real user chats. `data/persona_seed.jsonl` is 40+ hand-written exchanges
that already establish the voice and every guardrail (underage → non-alcoholic, excess → water,
PG-13 flirtation, tight recipes, all-inclusive drinks). Train on the seed to get a working Ninkasi now;
as real consented exchanges accumulate in the app, re-export and re-run `build_dataset.py` to fold them
in beside the seed and retrain. Each round she sounds more like *your community's* bartender.

## No GPU? Two other paths
1. **Managed fine-tune** — upload `out/train.jsonl` to Together AI / Fireworks / OpenAI fine-tuning; they
   return a model id + OpenAI-compatible URL. Same three env vars, zero infra.
2. **Ollama on a laptop/VM** — convert the merged model to GGUF and use `serve/Modelfile`; Ollama serves
   an OpenAI-compatible API on `:11434/v1`.

## Files
```
ninkasi-ai/
  README.md            ← you are here
  MODEL_CARD.md        ← the release card: intended use, safety, training data, limitations
  LICENSE-NOTES.md     ← why Qwen2.5/Apache-2.0 for a model you'll market; alternatives
  requirements.txt     ← pyyaml (dataset) + the GPU training stack
  config/
    ninkasi.yaml       ← base model, LoRA + training hyperparams, data paths, upsampling
    persona.txt        ← canonical system prompt (kept in sync with src/lib/bartender.ts)
  data/
    persona_seed.jsonl ← bootstrap SFT corpus in Ninkasi's voice (40+ examples)
    build_dataset.py   ← merge seed + app export → normalize → upsample guardrails → split
  train/
    finetune.py        ← QLoRA SFT, completion-only, merge-for-serving
  eval/
    eval_prompts.jsonl ← held-out persona + guardrail probes
    eval.py            ← run probes against any endpoint; CI-gates hard guardrails
    rubric.md          ← what "good" means (the real bar)
  serve/
    serve_vllm.sh      ← vLLM OpenAI-compatible serving
    Modelfile          ← Ollama self-host
    README.md          ← serving + wiring the app (the three env vars)
```

## Responsible-build (non-negotiable, and good marketing)
Ninkasi is a **diary companion**, not a drinking cheerleader. The persona enforces legal drinking age,
always offers a non-alcoholic path, and discourages excess — and `eval.py` fails the build if those
break. Training data is opt-in and k-anonymized (app consent flow + `scripts/ninkasi/README.md`).
"We trained our own AI on our community's consented taste, and it always looks after you" is only a
great line while it stays true — keep it true.
