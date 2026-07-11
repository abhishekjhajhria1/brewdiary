# Model card — Ninkasi 7B

*A drink-diary bartender you can host, brand, and market as your own.*

## Overview
**Ninkasi 7B** is Mistress Ninkasi — the in-app AI bartender of **brewdiary**, a calm all-inclusive
drink diary. She recommends drinks (alcoholic and non-alcoholic), gives tight recipes, and personalizes
to what a guest has been logging. She is a **fine-tune of an open base model** (default
`Qwen/Qwen2.5-7B-Instruct`, Apache-2.0) on a persona + guardrail dataset plus opt-in, k-anonymized real
exchanges from brewdiary users.

- **Task:** short-form conversational drink guidance, in a fixed persona.
- **Serving:** OpenAI-compatible chat endpoint (vLLM / Ollama / a managed fine-tune host).
- **Base:** Qwen2.5-7B-Instruct (Apache-2.0). See `LICENSE-NOTES.md`.
- **Method:** QLoRA SFT, completion-only loss, persona system prompt fixed at train + serve time.

## Intended use
- The bartender surface inside brewdiary (`/bartender`, `/api/bartender`).
- Recipe pop-ups and "what should I pour" style prompts across the product.
- **Not** intended as: a general assistant, a medical/health authority, or an age-verification system.
  Age-gating is enforced by the app (18+ gate) and reinforced by the persona — not by the model alone.

## Persona (the product, not a side effect)
Warm, knowing, unhurried; commands the room gently; economical (2–4 sentences); occasional mythic
flourish; sparing endearments; no emoji, no stage directions. The full persona is `config/persona.txt`,
kept in sync with the app's `src/lib/bartender.ts`.

## Safety & guardrails (evaluated every release via `eval/eval.py` + `eval/rubric.md`)
- **Legal drinking age:** refuses to give alcoholic recommendations to anyone signalling they're
  underage; redirects warmly to non-alcoholic options.
- **Non-alcoholic always available**, offered freely and never as a lesser option.
- **Discourages excess / responds to distress** with care — water, food, rest, or "just the one" —
  never enabling blackout drinking.
- **Flirtation is PG-13 and mythic**, never explicit or crude.
- **No fabricated venues**; points to the app's Discover surface for real places.
- Hard guardrails (underage refusal, no explicit content) are CI-gated: `eval.py` exits non-zero on
  failure.

## Training data
1. **Persona seed** (`data/persona_seed.jsonl`) — hand-written examples establishing voice + every
   guardrail. Ships in this repo; it bootstraps training before any real data exists.
2. **Consented user exchanges** (optional) — exported from `ninkasi_exchanges` by the app's
   `scripts/ninkasi/export-dataset.mjs`. Stored **only** while a user has "Help train Ninkasi" on;
   deletable by the user; **k-anonymized / counts-only** for any aggregate signals. See the app's
   consent flow and `scripts/ninkasi/README.md`.

`data/build_dataset.py` merges these, normalizes to one canonical persona, upsamples guardrail rows,
dedupes, and splits train/val.

## Limitations
- 7B: can occasionally give an imperfect recipe ratio or over-lean on the persona if over-trained. Keep
  epochs low; prefer more real data over more epochs.
- Not a sommelier or a safety system. Pairing suggestions are guidance, not gospel.
- Persona and guardrails are strong but not adversarially unbreakable — keep the app-side age gate and
  monitoring in place.

## Provenance & versioning
Every consented exchange is stored with its model provenance (`x-bartender-model`), so you always know
which teacher/version produced which training row. Bump the model version on each retrain; re-run the
eval suite and record the result before flipping `AI_BASE_URL` in production.

## License
The fine-tune inherits the base model's license (Apache-2.0 for the Qwen default) — you may host it
privately, keep your weights closed, and brand it "Ninkasi". Your persona, guardrails, and fine-tune are
your IP. See `LICENSE-NOTES.md`.
