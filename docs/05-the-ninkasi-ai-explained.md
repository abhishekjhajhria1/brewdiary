# 05 — The Ninkasi AI, explained

This is the plan to give brewdiary **its own AI bartender that we own** — not one we rent forever. It
sounds ambitious; it's actually a well-worn, sensible path. Told in plain English. (Words unclear? See
the [glossary](02-glossary.md).)

## Who Ninkasi is
**Ninkasi** is the app's AI bartender, given a personality: named after the *Sumerian goddess of
brewing*, she's warm, knowing, a little teasing, speaks in a few sentences, gives tight recipes, always
offers a great non-alcoholic option, and looks after her guests (she'll slide you a glass of water if
you've had too much). She's off-limits to under-18s and keeps flirtation playful, never explicit.

Her entire personality is **one carefully written instruction** — a **system prompt** — that lives in
`src/lib/bartender.ts`. That text is invisibly attached to the top of every conversation, which is what
makes any capable AI "become" Ninkasi.

## The problem we're solving
Right now, to make Ninkasi *smart*, we'd pay another company (an AI provider) for every single message,
forever. That's:
- **Expensive** at scale (a popular app = a huge bill).
- **Not ours** — we can't truly market "our AI," and we're at the mercy of their pricing and rules.

We want an AI that is **cheap to run, ours to keep, and ours to brand.**

## The plan: teacher → student (called "distillation")
Here's the clever, standard trick, in three acts:

```
  ACT 1 (now)          ACT 2 (weeks later)         ACT 3 (the payoff)
  ───────────          ───────────────────         ──────────────────
  A big, smart,        We've collected             We train a small model
  rented AI (the       thousands of her            WE OWN (the STUDENT)
  TEACHER = Groq)      best answers, with          to imitate those answers.
  answers users        the users' consent.         Then we host it ourselves
  as Ninkasi.                                       and stop paying per-message.
```

1. **Act 1 — the teacher works the bar.** We plug in **Groq**, an AI provider that hosts big capable
   models *very cheaply and fast*. It answers users as Ninkasi today. (Groq is just the current pick —
   the code can use any provider.)
2. **Act 2 — we quietly keep the good answers.** Every time Ninkasi answers, *if the user has agreed*
   (the "Help train Ninkasi" switch), we save that question-and-answer pair into a table called
   `ninkasi_exchanges`. Over weeks this becomes a **dataset**: thousands of real examples of "someone
   asked X, Ninkasi answered Y."
3. **Act 3 — we train our own model.** We take a free, **open** AI model (one we're allowed to use
   commercially), and **fine-tune** it on that dataset — showing it the examples until it learns to
   answer just like Ninkasi. Now we have a small model that *is* Ninkasi. We host it ourselves (cheap),
   point the app at it, and stop paying per message.

The beauty: **the app never changes.** Whether Ninkasi's brain is the rented Groq model or our own model
is decided by **one setting** (`AI_BASE_URL`). Swapping brains is flipping a switch.

## Which model we'll own, and why (the license matters)
We chose **Qwen2.5-7B-Instruct** as the base to fine-tune. The reason is boringly important:
**its license (Apache-2.0) lets us use it commercially, rename it "Ninkasi," sell access, and keep our
version private — with no user-count limit and no attribution strings.** That's exactly what you want
for a product you intend to market. (Other options and the full reasoning are in
`ninkasi-ai/LICENSE-NOTES.md`.)

"7B" means 7 billion parameters — big enough to hold Ninkasi's personality and drink knowledge, small
enough to run on a single affordable graphics card or a cheap hosted service.

## You don't have to wait to start
Training normally needs lots of examples. To avoid a chicken-and-egg wait, we **hand-wrote 41 example
conversations** in Ninkasi's exact voice, covering every rule (turning away minors kindly, offering
non-alcoholic drinks, handling someone who's had too much, tight recipes, all kinds of drinks). That
starter set lives in `ninkasi-ai/data/persona_seed.jsonl`.

**This means you can train a working Ninkasi *today*, before a single real user chats.** As real
consented conversations pile up, we fold them in beside the starter set and retrain — each round she
sounds more like *your community's* bartender.

## Where the AI's data lives: a SEPARATE database (the "Ninkasi Data Plane")
The AI's data does **not** sit in the same database as users' diaries. It has its own dedicated
database — a second Supabase project — for three reasons: a different security boundary (a problem in
one can't expose the other), performance isolation, and a clean home for future AI features.

The golden rule of how it's filled: **controlled and minimized, never raw access.**
- **Pseudonymous.** Each saved conversation stores a *scrambled* stand-in for the user (a salted hash),
  never their real id, name, email, or photos. We can still tell two conversations came from the same
  person (useful for quality and for honoring "delete my data"), but nobody can work backward to *who*
  without a secret key kept only on our server.
- **Consented + real only.** A conversation is saved only if the user left "Help train Ninkasi" on, and
  only when the real AI answered (scripted fallbacks are never sent).
- **Server-only.** The browser has zero credentials for this database. Our *server* writes to it
  (`/api/bartender` records the exchange; `/api/ninkasi/forget` deletes a user's rows on request).
- **Aggregates are anonymous.** The "what's popular" snapshots only count a drink when 3+ people logged
  it — numbers, never individuals.

The blueprint is in `ai-db/schema.sql`; the plain-English setup is in `ai-db/README.md`. Until you set it
up, the app runs perfectly and simply doesn't record centrally yet.

## The two AI folders (don't mix them up)
- **`scripts/ninkasi/`** — the **data tap.** It runs *inside the app* and its exporter pulls the
  consented conversations out of the database into a training file.
- **`ninkasi-ai/`** — the **workshop.** It runs *offline* and turns that file (plus the starter set)
  into a trained, running model. This is where the real model-building happens:

  | Inside `ninkasi-ai/` | What it's for |
  |---|---|
  | `README.md` | The workshop's own guide (start there when you're ready to train). |
  | `data/persona_seed.jsonl` | The 41 hand-written starter conversations. |
  | `data/build_dataset.py` | Mixes the starter set + real conversations into a training file. |
  | `train/finetune.py` | The actual training program (runs on a graphics card). |
  | `eval/` | The **exam**: tests whether the trained model stayed in character *and* obeyed every safety rule. It fails the build if a safety rule breaks. |
  | `serve/` | How to run the finished model as a service and point the app at it. |
  | `MODEL_CARD.md` | The model's "nutrition label": what it's for, its limits, its safety behavior. |
  | `LICENSE-NOTES.md` | Why Qwen2.5/Apache-2.0, with alternatives. |

## The safety and consent rules (never optional)
These are built in *and* enforced, not just promised:
- **Consent:** we only keep a conversation for training if the user left the "Help train Ninkasi" switch
  on. They can switch it off, and "clear Ninkasi data" deletes their saved conversations from the cloud
  too.
- **Only your own data is yours to see:** RLS means one user can never read another's saved
  conversations. Only the offline exporter (with a special admin key, run by you on your own machine)
  can read the whole set to build the training file.
- **The "taste trends" are anonymous:** the separate feature that shows "what's popular" only ever
  reports a drink if **at least 3 different people** logged it, and never attaches names — and only for
  users who opted in. It's counts, never individuals.
- **The exam blocks unsafe models:** `ninkasi-ai/eval/eval.py` automatically fails if the trained model
  would serve alcohol to a minor or produce explicit content. We don't ship a model that fails.

## Where we are, and what's next
- **Built and ready:** the personality, the secure back-end with its safety guards, the consented
  collection into `ninkasi_exchanges`, the starter dataset, and the whole training/eval/serving
  workshop.
- **Needs you (not more coding):** (1) a **Groq key** to turn the live teacher on and start collecting;
  (2) eventually a **graphics card or a hosted training service** to run the training; (3) somewhere to
  **host** the finished model.

The exact click-by-click steps are in **[08 — Founder playbook](08-founder-playbook.md)**.

Next: **[06 — Security & privacy](06-security-and-privacy.md)**.
