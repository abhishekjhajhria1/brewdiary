# 08 — Founder playbook

This is **your** checklist — the founder's, not a developer's. It turns Ninkasi on, starts her learning,
and walks all the way to **our own trained model**. Do the phases in order; each one works on its own, so
you can stop after any of them and still have a better app.

Terms you'll meet are in the [glossary](02-glossary.md); the "why" behind all this is in
[05 — The Ninkasi AI](05-the-ninkasi-ai-explained.md).

---

## Phase A — Turn Ninkasi's real brain on (≈ 10 minutes)
Right now Ninkasi answers with built-in scripted lines. To give her a real AI brain, plug in a provider.
We use **Groq** (cheap, fast, generous free tier to start).

1. **Get a Groq key.** Go to **https://console.groq.com**, sign up, open **API Keys**, create one, and
   copy it (it looks like `gsk_...`). Treat it like a password.
2. **Put it in the app's secret file.** Open `e:\shit\brewdiary\.env.local` in a text editor and set:
   ```
   AI_API_KEY=gsk_your_key_here
   AI_BASE_URL=https://api.groq.com/openai/v1
   AI_MODEL=llama-3.3-70b-versatile
   ```
   (The last two are already the defaults; you mainly need to fill in `AI_API_KEY`.)
3. **Restart the app** so it reads the new setting: stop it (`Ctrl + C`) and run `npm run dev` again.
4. **Test it.** Open `http://localhost:3000/bartender` and ask "what should I pour tonight?" You should
   get a fresh, personalized reply (not the same scripted line every time). If the little "add an AI
   key" note is gone, she's live.

**Safety is already handled for you:** the code caps chats at ~20 per minute per person and rejects
oversized messages, so this key can't be abused into a giant bill (see
[06 — Security](06-security-and-privacy.md)). Still, set a **spending limit** in the Groq console for
peace of mind.

✅ **After Phase A:** users get a genuinely smart Ninkasi, and — for everyone who leaves the "Help train
Ninkasi" switch on — their conversations quietly start collecting for training.

---

## Phase A2 — Set up the separate AI database (do this to start collecting centrally)
The AI's training data lives in its **own** database, separate from user data (a second Supabase
project). This is a one-time setup. Full plain-English steps are in `ai-db/README.md`; the short version:

1. **Create a second Supabase project** (name it something like `brewdiary-ai`). Keep it separate from
   your main app project.
2. **Apply the AI database blueprint:** open that new project → **SQL Editor** → paste the contents of
   `ai-db/schema.sql` → run. (This creates the `exchanges` and `trend_snapshots` tables, locked down.)
3. **Add its keys to `.env.local`** (these are server-only — never `NEXT_PUBLIC`):
   ```
   AI_SUPABASE_URL=https://<new-project-ref>.supabase.co
   AI_SUPABASE_SERVICE_KEY=<the new project's service_role key, from its API settings>
   AI_DB_SALT=<a long random string — set it once and NEVER change it>
   ```
   (`AI_DB_SALT` scrambles user ids so the corpus is pseudonymous. If you ever change it, old rows can't
   be matched to a user anymore — so pick one and leave it.)
4. **Restart the app.** From now on, every consented, live Ninkasi conversation is safely recorded in
   this separate database, pseudonymized. Until you do this, the app works fine — it just keeps chats
   locally on each device instead of collecting them centrally.

## Phase B — Watch the training data grow
Every consented conversation is saved to the `exchanges` table in your **AI database** (the second
project from Phase A2). To see how many you've gathered:

1. Go to your **AI** Supabase project (not the app one) → **SQL Editor**.
2. Run:
   ```sql
   select count(*) from exchanges;
   ```
3. That number is your corpus size. **You want roughly 500+ before the first training run**, and
   2,000–5,000 for a really good one. (Quality matters more than raw count — see Phase C.)

You don't have to babysit this — just check back every so often as people use the app.

> **You can also skip the wait.** We hand-wrote 41 example conversations (`ninkasi-ai/data/
> persona_seed.jsonl`) so you can train a working Ninkasi *before* collecting anything. Great for a first
> proof-of-concept; fold real conversations in later for a Ninkasi that sounds like *your* community.

---

## Phase C — Train our own model
This is the "build our own AI" step. It happens in the **`ninkasi-ai/`** folder and needs **Python** and
a **graphics card (GPU)** — or a hosted service that provides one. You don't need to understand the
training code; you run three commands and read the exam results.

Full instructions live in **`ninkasi-ai/README.md`**. The short version:

1. **Export the collected conversations** (from inside the app project):
   ```
   node scripts/ninkasi/export-dataset.mjs
   ```
   This writes a clean training file (it reads Ninkasi's personality live from the app, so nothing drifts
   out of sync).
2. **Build the final dataset** (in `ninkasi-ai/`): mixes your starter examples + the exported real ones:
   ```
   cd ninkasi-ai
   pip install pyyaml
   python data/build_dataset.py
   ```
3. **Train** (needs a GPU — a rented cloud GPU or Google Colab is fine):
   ```
   pip install -r requirements.txt
   python train/finetune.py
   ```
   This produces our own model in `ninkasi-ai/out/`.
   - **No GPU? Easiest path:** upload the training file (`ninkasi-ai/out/train.jsonl`) to a **managed
     fine-tuning service** (Together AI, Fireworks, or OpenAI). They train it for you and hand back a
     ready-to-use model — no hardware needed. Same result.
4. **Run the exam** — make sure she stayed in character *and* safe:
   ```
   python eval/eval.py --base-url <where the model is served> --model ninkasi-7b --api-key x
   ```
   This checks the safety rules automatically (it *fails* if the model would serve a minor or produce
   explicit content). Then read the transcript against `ninkasi-ai/eval/rubric.md` — does she sound
   right? Ship only if the exam passes and she reads like Ninkasi.

---

## Phase D — Switch the app to our own model
Once the model is hosted (either you run it with the provided `serve/` scripts on a GPU box, or a managed
service gives you a web address for it):

1. In `.env.local`, point the app at *our* model instead of Groq:
   ```
   AI_BASE_URL=https://<your-model-host>/v1
   AI_MODEL=ninkasi-7b
   AI_API_KEY=<whatever your host requires>
   ```
2. Restart the app. **Nothing else changes** — the app doesn't know or care whether Ninkasi's brain is
   Groq or ours. That's the whole point of the design.

✅ **After Phase D:** you're running *your own* AI bartender. No more per-message fees to a big provider,
and you can market "Ninkasi, our own AI." Collection keeps running, so the *next* version of the model is
always brewing — re-run Phase C every so often to improve her.

---

## Phase E — The other "turn it on" items (later, optional)
When you're ready to grow beyond the AI:
- **Discover — already functional, no key.** The compass (real device heading) and **"Find places near
  me"** (geolocation → opens the user's maps app to search bars/bottle shops/clubs nearby) work today
  with free browser APIs — no Google Places bill. The only deferred piece is **rich in-app listings**
  (names, live ratings, distance) shown right in the app; that needs a venue-data source (Google Places,
  or a free alternative like OpenStreetMap/Overpass) and is left for when budget/approach is chosen.
- **Monetization.** Two revenue ideas are designed in: promoting bars/shops in Discover (label them
  "sponsored"), and selling **anonymous** taste trends to brands (the k-anonymous `taste_trends` feature
  is the template — only aggregate, opt-in data ever leaves). To build a *history* of those trends,
  schedule the batch job: `node scripts/ninkasi/sync-trends.mjs` (see `ai-db/README.md` → "Fill the
  trend snapshots"). It captures point-in-time snapshots into the AI database, safely and anonymously.
- **Payments.** Not built yet; needs a payment provider (e.g. Stripe) when you decide on pricing.
- **A public launch.** Before going wide, run `/security-review` on the latest changes and set up
  spending alerts.

---

## Your quick reference
| I want to… | Do this |
|---|---|
| Make Ninkasi smart | Phase A: add `AI_API_KEY` from Groq to `.env.local`, restart. |
| Start collecting training data | Phase A2: create the 2nd Supabase project, run `ai-db/schema.sql`, set `AI_SUPABASE_*`. |
| See how much training data I have | Phase B: `select count(*) from exchanges;` in the **AI** project. |
| Train a Ninkasi *today* (no real data) | Phase C on the starter set alone (`ninkasi-ai/README.md`). |
| Build & own the model | Phase C, then Phase D to switch the app to it. |
| Understand *why* any of this works | [05 — The Ninkasi AI](05-the-ninkasi-ai-explained.md). |
| Check we're secure | [06 — Security & privacy](06-security-and-privacy.md). |

You've got this. Start with **Phase A** — it's ten minutes and instantly makes the app feel alive.
