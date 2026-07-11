# 10 — Deploy the web app (Vercel)

A short, do-it-yourself guide to putting brewdiary live. Vercel is the natural host for a Next.js app
(same company makes Next.js) and has a free tier. ~20 minutes end to end.

## Before you start (both free)
- A **GitHub** account (to hold the code).
- A **Vercel** account — sign up with your GitHub at https://vercel.com.

## Step 1 — Put the code on GitHub
The project isn't a git repo yet. From the project folder (`e:\shit\brewdiary`):
```bash
git init
git add .
git commit -m "brewdiary"
```
Then create an **empty private repo** on GitHub (github.com → New repository, don't add a README), and:
```bash
git remote add origin https://github.com/<you>/brewdiary.git
git branch -M main
git push -u origin main
```
> ✅ Your secrets are safe: `.env.local` is gitignored, so **no keys get pushed**. The committed
> `.env.example` is just a blank template. (Double-check: `git status` should NOT list `.env.local`.)

*(No-git alternative: `npm i -g vercel`, then run `vercel` in the folder — it deploys directly. But
GitHub is better long-term: every push auto-deploys.)*

## Step 2 — Import the project into Vercel
1. Vercel dashboard → **Add New… → Project** → pick your `brewdiary` repo.
2. Vercel auto-detects **Next.js** — leave Build Command (`next build`) and Output as defaults.
3. **Don't click Deploy yet** — add the environment variables first (next step).

## Step 3 — Add the environment variables
In the import screen (or Project → Settings → Environment Variables), add these **8** for the
**Production** environment. Copy the values from your local `.env.local`.

| Variable | What it is | Public? |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | App Supabase project URL | Public (client) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | App Supabase anon key (RLS protects data) | Public (client) |
| `AI_API_KEY` | Groq key (Ninkasi's brain) | **Secret** |
| `AI_BASE_URL` | `https://api.groq.com/openai/v1` | Secret (fine) |
| `AI_MODEL` | `llama-3.3-70b-versatile` | Secret (fine) |
| `AI_SUPABASE_URL` | The **AI** Supabase project URL (`brewdiary-ai`) | **Secret** |
| `AI_SUPABASE_SERVICE_KEY` | AI project service_role key | **Secret** |
| `AI_DB_SALT` | The salt you set (never change it) | **Secret** |

> **Do NOT add** `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, or `AI_SUPABASE_DB_URL` — those are
> only for running database migrations/scripts from your own machine, and the live app never uses them.
> Keeping them off the server is safer.

## Step 4 — Deploy
Click **Deploy**. Vercel installs, runs `next build`, and gives you a URL like
`https://brewdiary-xyz.vercel.app`. Future `git push`es to `main` auto-deploy.

## Step 5 — Point Supabase at your live URL
In your **app** Supabase project → **Authentication → URL Configuration**:
- Set **Site URL** to your Vercel URL (e.g. `https://brewdiary-xyz.vercel.app`).
- Add the same URL under **Redirect URLs**.

This makes password-reset/confirmation links point to the live site. (Login itself already works without
it, but set it now so nothing breaks later.)

## Step 6 — Verify it's really working (the click-test)
On the live URL:
1. **Sign up / sign in** → you land on the calendar.
2. **Log a drink** (add a photo) → the day's square brightens; it persists on refresh.
3. **Ask Ninkasi** something → you get a real, live reply.
4. In the **brewdiary-ai** Supabase SQL Editor: `select count(*) from exchanges;` → should be ≥ 1 (proves
   the consented, pseudonymized training pipeline works in production).
5. On your **phone**, open the URL in Chrome → "Add to Home Screen" → it installs like an app.

If all five pass, you're live. 🎉

## Good to know
- **Custom domain:** Project → Settings → Domains → add `brewdiary.app` (or whatever you buy) and follow
  the DNS steps. This is also the domain you'll use for the Android app.
- **Rate limiter:** the AI abuse-guard is in-memory, so on Vercel's serverless it's a *soft* cap per
  instance (documented in `src/lib/ratelimit.ts`). Fine for launch; upgrade to Upstash Redis if you get
  big.
- **Free tiers:** Vercel + both Supabase projects on free tiers comfortably handle an early launch.
- **This unblocks Android:** once the site is live at a stable URL, the Android app (Capacitor — see
  [09](09-going-mobile-android.md)) wraps that URL. So: deploy → then we build Android.
