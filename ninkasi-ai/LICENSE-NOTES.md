# Base-model licensing — why Qwen2.5-7B-Instruct (and what it means for marketing Ninkasi)

You want to **own, brand, and sell** an AI bartender. The base model's license decides whether you can.
This is the one technical choice with real commercial consequences, so it's documented, not buried.

## The decision: **Qwen2.5-7B-Instruct**, license **Apache-2.0**
Apache-2.0 is about as permissive as it gets:
- ✅ **Commercial use, no revenue or user cap.** No "under 700M monthly active users" clause to trip on
  if brewdiary takes off.
- ✅ **Rebrand freely.** You can call the fine-tuned model **"Ninkasi"** and market it as your own AI.
  No obligation to name the base, no "Built with X" badge required in your UI.
- ✅ **Modify + redistribute + keep your fine-tune closed.** Your LoRA weights and the merged model are
  yours; you may host them privately and never publish them.
- ✅ **Patent grant** included (Apache-2.0), which reduces IP risk for a product you're selling.
- Only obligations: keep the base model's `LICENSE`/`NOTICE` files with any copy of the *base weights*
  you redistribute, and note significant changes. Trivial for a hosted product — you're serving an
  endpoint, not shipping the weights.

Qwen2.5-7B-Instruct is also just a strong pick for this job: excellent instruction-following, solid at
short-form conversational style, multilingual (useful for a global drinks app / an India-based team),
long context, and small enough to serve on one 24GB GPU (or Ollama on a good laptop).

## Alternatives (all supported by this repo — change `base_model` in config/ninkasi.yaml)
| Base | License | Marketing implication |
|---|---|---|
| **Qwen2.5-7B-Instruct** (chosen) | Apache-2.0 | Sell/rebrand freely, no caps, no attribution. |
| Mistral-7B-Instruct-v0.3 | Apache-2.0 | Same freedom; a touch weaker at instruction-following than Qwen2.5. |
| Llama-3.1-8B-Instruct | Llama 3.1 Community | Commercial OK **under 700M MAU**; must show "Built with Llama" + can't name your model starting with "Llama". Fine for a startup, but strings attached. This is what `scripts/ninkasi/` originally targeted. |
| Gemma-2-9B-it | Gemma Terms | Commercial OK but Google's use-policy applies; extra restrictions vs Apache. |

The training script auto-detects the chat template from whichever base you pick, so switching is a
one-line change — but **for a product you intend to monetize, Apache-2.0 (Qwen/Mistral) is the clean
choice.** We picked Qwen2.5 for the capability edge.

## What you're actually selling
You are **not** selling the base model — you're selling *Ninkasi*: the persona, the guardrails, the
fine-tune trained on your own users' consented taste, wrapped in brewdiary. That combination is your
moat and your IP. The base is just the clay; Apache-2.0 means the clay comes with no strings.

## Responsible-marketing guardrails (don't skip — they protect the brand and the app-store listing)
- **21+ / legal-drinking-age framing** is baked into the persona and enforced by `eval.py`. Keep it.
- Market Ninkasi as a **diary companion and drinks guide**, never as a drinking *encouragement* — she
  always offers a non-alcoholic path and discourages excess. That framing is also what keeps the app
  out of app-store "promotes excessive alcohol use" rejections.
- Training data is **opt-in and k-anonymized** (see the app's consent flow + `scripts/ninkasi/README.md`).
  "We trained our own AI on our community's taste" is a great marketing line *only* while that stays true.
