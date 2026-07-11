#!/usr/bin/env bash
# Serve the merged Ninkasi model with vLLM as an OpenAI-compatible endpoint.
# Then point the app at it: in brewdiary/.env.local set
#     AI_BASE_URL=http://<this-host>:8000/v1
#     AI_MODEL=ninkasi-7b
#     AI_API_KEY=<any value if you set --api-key below, else leave the app's existing one>
# The app's /api/bartender already speaks OpenAI-compatible — nothing else changes.
set -euo pipefail

MODEL_DIR="${1:-$(dirname "$0")/../out/ninkasi-7b}"
SERVED_NAME="${SERVED_NAME:-ninkasi-7b}"
PORT="${PORT:-8000}"

if [ ! -d "$MODEL_DIR" ]; then
  echo "Merged model not found at: $MODEL_DIR"
  echo "Run training first (train/finetune.py) or pass the model path as arg 1."
  exit 1
fi

# --api-key gates the endpoint (optional but recommended). --max-model-len keeps VRAM sane.
exec vllm serve "$MODEL_DIR" \
  --served-model-name "$SERVED_NAME" \
  --host 0.0.0.0 --port "$PORT" \
  --max-model-len 4096 \
  --dtype bfloat16 \
  ${VLLM_API_KEY:+--api-key "$VLLM_API_KEY"}
