# Serving Ninkasi + wiring the app

The whole point of the pipeline: **the app never changes.** `brewdiary`'s `/api/bartender` speaks the
OpenAI chat API to whatever `AI_BASE_URL` names. So "going live on our own model" is three env vars.

## Option A — vLLM (production, a GPU box or a cloud GPU)
```bash
bash serve/serve_vllm.sh                 # serves out/ninkasi-7b on :8000
# optional: VLLM_API_KEY=secret PORT=8000 SERVED_NAME=ninkasi-7b bash serve/serve_vllm.sh
```
Then in `brewdiary/.env.local`:
```
AI_BASE_URL=http://<host>:8000/v1
AI_MODEL=ninkasi-7b
AI_API_KEY=<VLLM_API_KEY or any non-empty value>
```

## Option B — Ollama (cheap, runs on a laptop / small VM)
Convert to GGUF, quantize, then use `serve/Modelfile` (instructions in that file). Ollama serves an
OpenAI-compatible API on `:11434/v1`:
```
AI_BASE_URL=http://localhost:11434/v1
AI_MODEL=ninkasi
AI_API_KEY=ollama
```

## Option C — a managed host (no infra)
Upload `out/train.jsonl` to **Together AI**, **Fireworks**, or **OpenAI** fine-tuning; they hand you a
model id + an OpenAI-compatible base URL. Same three env vars. This is the fastest way to ship if you
don't want to run a GPU.

## Verify before you flip production
```bash
# smoke test the endpoint directly
python eval/eval.py --base-url http://localhost:8000/v1 --model ninkasi-7b --api-key x
# or test the whole app path (npm run dev first)
python eval/eval.py --app http://localhost:3000/api/bartender
```
`eval.py` exits non-zero on any hard guardrail failure — good as a pre-deploy gate. Read the transcript
against `eval/rubric.md`; the automatic checks are only a floor.

## After flipping
Collection keeps running (consented exchanges → `ninkasi_exchanges`), so the *next* fine-tune is always
brewing. Re-export (`node scripts/ninkasi/export-dataset.mjs`), re-run `data/build_dataset.py` to fold
the real exchanges in beside the seed, retrain, re-eval, redeploy. Each round she sounds more like *your*
users' Ninkasi and less like the seed.
