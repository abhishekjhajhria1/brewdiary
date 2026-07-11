# ai-db — the separate AI database ("Ninkasi Data Plane")

This folder defines a **second, dedicated database** — separate from the app's database — whose only job
is to hold the AI's data: the **consented training corpus** and (optionally) **anonymized trend
snapshots**. It is its own Supabase project, with its own credentials, reached **only from our server**.

## Why a separate database
- **Different security blast-radius.** User data (diaries, friends, photos) lives in the app DB, locked
  by Row-Level Security. The AI corpus lives here, behind a *different* key. A problem in one doesn't
  expose the other.
- **Isolation.** Heavy training/analytics reads never compete with the live app's performance.
- **A clean home for AI growth.** Future retrieval (RAG), a recipe knowledge base, and B2B trend
  aggregates all belong here, not tangled into the transactional app.

## The core safety rule: controlled, minimized — never raw access
This database does **not** mirror user data. The pipeline that fills it is deliberately narrow:
- **Pseudonymous.** Each exchange stores a `user_ref` = a *salted hash* of the app user id (via
  `AI_DB_SALT`), never the real id, name, email, or photos. Same person → same ref (so we can dedup and
  honor "delete my data"), but you cannot reverse it to a person without the server-side salt.
- **Consented + live only.** A row is written only when the user has "Help train Ninkasi" on, and only
  for real (teacher) replies — scripted fallbacks never come here.
- **Server-only.** The browser has no credentials for this database. Every write flows through our
  server (`/api/bartender` records the exchange; `/api/ninkasi/forget` deletes a user's rows). The
  export tool reads it locally with the service key.
- **Aggregates are k-anonymous.** `trend_snapshots` only ever holds counts for drinks logged by ≥3
  people. No individuals.

## How the pieces connect
```
  app (server)                          THIS DATABASE (2nd Supabase project)
  ─────────────                         ───────────────────────────────────
  /api/bartender  ──consented, live──►  exchanges   (user_ref, prompt, reply, context, model)
     (pseudonymizes the user id)              │
  /api/ninkasi/forget ──delete mine──►        │
                                              │  service-key export (local)
  scripts/ninkasi/export-dataset.mjs ◄────────┘   → JSONL → ninkasi-ai/ → train our model
```
Code: `src/lib/aidb.ts` (server-only client + `recordExchange` + `forgetUser` + `pseudonymize`),
`src/lib/supabase-server.ts` (trusts the signed-in user from the session cookie).

## Setup (do this when you're ready to start collecting centrally)
1. Create a **new Supabase project** (this is your AI database). Keep it separate from the app project.
2. Apply the schema — either paste `ai-db/schema.sql` into that project's **SQL Editor**, or:
   ```
   # put its Postgres connection string in .env.local as AI_SUPABASE_DB_URL, then:
   node scripts/db.mjs ai-db/schema.sql AI_SUPABASE_DB_URL
   ```
3. In `.env.local` (server-side, never `NEXT_PUBLIC`):
   ```
   AI_SUPABASE_URL=https://<new-project-ref>.supabase.co
   AI_SUPABASE_SERVICE_KEY=<the new project's service_role key>
   AI_DB_SALT=<a long random string — set once, never change>
   ```
4. Restart the app. From now on, every consented, live Ninkasi exchange is recorded here
   (pseudonymized). Until you set these, the app runs fine and simply doesn't record centrally yet.

## Export for training
```
node scripts/ninkasi/export-dataset.mjs        # reads THIS database when configured
```
Then continue in `ninkasi-ai/` (build dataset → fine-tune → serve → flip `AI_BASE_URL`).

## Fill the trend snapshots (the batch job)
`trend_snapshots` is populated by a periodic job that reads the app DB's k-anonymous
`taste_trends()` (drinks/moods logged by ≥3 opt-in users, counts only) and writes a
point-in-time snapshot here — nothing personal ever crosses.
```
node scripts/ninkasi/sync-trends.mjs [--windows 7,14,30]
```
Run it on a schedule to build a history of what the community's been pouring (the raw
material for Discover's "what's trending" and, later, anonymized B2B trend reports):
- **Linux/Mac cron:** `0 3 * * *  cd /path/to/brewdiary && node scripts/ninkasi/sync-trends.mjs`
- **Windows:** Task Scheduler → daily → action `node scripts/ninkasi/sync-trends.mjs`.
- **Cloud:** the `/schedule` helper can run it as a scheduled agent.

It's safe to run anytime and no-ops cleanly when there aren't ≥3 consenting users on a
drink yet.

## Tables
- **`exchanges`** — the training corpus (pseudonymous). Columns: `user_ref, prompt, reply, context,
  model, created_at`.
- **`trend_snapshots`** — optional anonymized aggregates (`kind, name, users≥3, logs, captured_at`).

RLS is ON with **no policies** on both tables, so the public/anon role can read nothing even if this
project's anon key leaked; only the server's service key (which bypasses RLS) can touch them.
