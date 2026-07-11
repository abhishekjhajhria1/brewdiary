# 06 — Security & privacy

How brewdiary keeps **secret keys secret** and **users' data safe** — written so a non-engineer can
check we did it right. Each item says *what the risk is* and *how we handle it*.

## 1. The secret AI key never reaches users
- **Risk:** the key that lets us use the paid AI is like a credit card. If it leaked into the browser,
  anyone could copy it and spend our money.
- **How we handle it:** the key (`AI_API_KEY`) lives in a private file on the **server** (`.env.local`)
  and is only ever read by server code (`src/app/api/bartender/route.ts`). The browser **never** sees
  it. The browser only talks to *our* back-end; *our* back-end talks to the AI. You can verify this:
  search the whole project for `AI_API_KEY` — it appears only in server files and docs, never in a
  component that ships to the browser.
- **The rule of thumb:** anything named `NEXT_PUBLIC_...` is safe to be public; anything else must stay
  on the server. The AI key is deliberately *not* public.

## 2. Nobody can run up our AI bill (rate limiting + size caps)
- **Risk:** once the paid AI is on, a bad actor (or a buggy loop) could hammer the chat endpoint
  thousands of times and cost us a fortune in AI fees.
- **How we handle it (`src/lib/ratelimit.ts` + the chat route):**
  - **Rate limit:** each person gets ~20 chats per minute. Beyond that, the server politely refuses
    (HTTP 429) until the minute resets.
  - **Size caps:** an over-large message is trimmed, and a huge payload is rejected outright *before* we
    even process it. This caps the cost of any single request.
- **Verified working:** we tested it live — normal requests succeed, an empty request is rejected, an
  oversized one is rejected, and the 21st request in a minute gets the "slow down" response.
- **Honest limitation:** this guard lives in the server's memory, which is perfect on a single
  always-on server but softer on "serverless" hosting (where many short-lived copies run). For a hard
  limit at large scale, we'd back it with a shared store (like Upstash Redis) — the code is written so
  that's a drop-in upgrade. Documented, not forgotten.

## 3. Each user can only see their own data (Row-Level Security)
- **Risk:** everyone's diary entries live in the *same* database table. Without protection, a clever
  user could ask the database for someone else's private entries.
- **How we handle it:** every table has **RLS (Row-Level Security)** — rules enforced by the database
  itself (not just our app) that say *which rows each person may read or change*. Your diary is readable
  only by you; a friend's entry is readable only if they actually shared it with you; a circle's
  contents only by its members. Even if our app code had a bug and asked for too much, **the database
  refuses**. These rules are written in the `supabase/*.sql` files and were tested end-to-end (we
  confirmed a stranger gets *zero* rows for a private entry, and that attempts to insert data as someone
  else are blocked).
- **Why this is strong:** the security lives at the deepest layer (the data), so it protects users even
  against mistakes higher up.

## 4. Passwords and logins are handled by Supabase, not by us
- **Risk:** storing passwords yourself is easy to get dangerously wrong.
- **How we handle it:** we use **Supabase Auth**, a dedicated, audited service, for sign-up and login.
  We never see or store raw passwords. After login, a **session cookie** keeps the user signed in
  securely.

## 5. Private-by-default, and consent for anything shared
- **Every diary entry is private** the moment it's created. Sharing is a *separate, deliberate* action.
- **AI training data is opt-in:** we only keep a conversation to train the model if the user left the
  "Help train Ninkasi" switch on, and they can delete that data anytime (it clears from the cloud too).
- **"Taste trends" are anonymous and consented:** the popularity feature only counts a drink when **3+
  different people** logged it, never attaches names, and only includes people who opted in. It reports
  numbers, never individuals.
- **Age gate:** first-time users confirm they're 18+ before using an alcohol-related app.

## 6. Secrets stay out of version control
- **Risk:** accidentally publishing secret keys to a shared code repository.
- **How we handle it:** the `.gitignore` file lists `.env*.local` and the AI training exports, so those
  secret/private files are **never** committed or shared. `.env.example` is a *blank template* that
  shows which settings exist without revealing any real values.

## 7. The AI's data lives in a separate, sealed database
- **Risk:** an AI that could freely read everyone's private diaries would destroy the privacy model —
  and create legal (GDPR/CCPA), app-store, and trust problems.
- **How we handle it:** the AI's training data lives in a **completely separate database** (its own
  Supabase project, its own credentials) — see `ai-db/`. The AI model itself never connects to any
  database; our server hands it only a small, allowed context at chat time. What gets *saved* for
  training is:
  - **Pseudonymous** — a salted hash stands in for the user, never their real id/name/email/photos, and
    it can't be reversed without a secret salt kept only on the server.
  - **Consented + real-only** — saved only when "Help train Ninkasi" is on, and never for scripted
    fallback replies.
  - **Server-only** — the browser has no key for this database; only our server writes to it.
  - **Deletable** — "clear Ninkasi data" calls an authenticated server route that erases that user's
    rows from the AI database too.
- **Why this is strong:** even a total compromise of the AI database exposes only pseudonymous chat
  snippets — not user identities, and not the app's user data (which is a different database behind a
  different key).

## 8. Honest list of what's *not* done yet (so it's tracked, not hidden)
Security is never "finished." These are known, documented next steps — not surprises:
- The rate limiter should be backed by a shared store for large-scale serverless hosting (see item 2).
- When live AI and payments are added, add server-side logging/alerting for unusual usage spikes.
- A formal security review before a big public launch (there's a `/security-review` helper for the
  pending changes).

## The one-sentence summary
**Secrets live only on the server; the database itself enforces who can see what; everything personal is
private-by-default and opt-in to share; and the AI endpoint is guarded against abuse.**

Next: **[07 — Run it yourself](07-run-it-yourself.md)**.
