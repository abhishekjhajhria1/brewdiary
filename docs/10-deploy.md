# 10 — Deploy the web app (Vercel + bar.bwdy.site)

Putting brewdiary live. Vercel is the natural host for a Next.js app (same company makes Next.js) and has
a free tier. ~30 minutes end to end, including the bar subdomain.

**The venue dashboard is not a second app.** `bar.bwdy.site` is the *same* deployment, the *same* Supabase
project, and the *same* codebase — `src/middleware.ts` sees the `bar.` host and rewrites it onto `/venue`.
So you deploy once and add one domain. No second project, no extra cost.

---

## Step 0 — The database must be current FIRST

Deploying code that expects a column the live database doesn't have is the classic way to take a site
down. Run any migration you haven't yet, in order, and confirm:

```bash
node scripts/db.mjs supabase/022_currency.sql     # if not already applied
node scripts/verify-flow.mjs                      # the end-to-end check (rolls itself back)
```

Migrations `009`–`022` must all be applied. If `verify-flow` is green, the database matches the code.

---

## Step 1 — Push to GitHub

The repo already exists locally. Create an **empty private repo** on GitHub (no README), then:

```bash
git add .
git commit -m "Phase 7: venues, points, jurisdiction policy, data rights"
git remote add origin https://github.com/<you>/brewdiary.git
git branch -M main
git push -u origin main
```

> ✅ **Secrets are safe.** `.env.local` and `internal/` are gitignored — no keys, and your legal research
> stays private. Confirm with `git status`: neither should be listed.
>
> ✅ `CLAUDE.md` and `.claude/skills/` **are** committed now, deliberately — a fresh clone (a new hire, a
> new machine) needs the guide and the design skill.

## Step 2 — Import into Vercel

1. Vercel → **Add New… → Project** → pick the `brewdiary` repo.
2. It auto-detects **Next.js**. Leave the build settings alone.
3. **Don't deploy yet** — add the environment variables first.

## Step 3 — Environment variables

Project → Settings → **Environment Variables**, for **Production**. Copy the values from `.env.local`.

| Variable | What it is | Secret? |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | App Supabase project URL | public (client) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Anon key — RLS is what protects the data | public (client) |
| `NEXT_PUBLIC_SITE_URL` | `https://bwdy.site` — used for canonical/OG links | public |
| **`SUPABASE_SERVICE_ROLE_KEY`** | **Required.** Powers account deletion (`/api/account/delete`). | **SECRET** |
| `AI_API_KEY` | Groq key (Ninkasi's brain) | **SECRET** |
| `AI_BASE_URL` | `https://api.groq.com/openai/v1` | secret |
| `AI_MODEL` | `llama-3.3-70b-versatile` | secret |
| `AI_SUPABASE_URL` | The **AI** Supabase project URL | **SECRET** |
| `AI_SUPABASE_SERVICE_KEY` | AI project service_role key | **SECRET** |
| `AI_DB_SALT` | Your salt (never change it once live) | **SECRET** |

> ⚠️ **`SUPABASE_SERVICE_ROLE_KEY` is new and it is not optional.** Deleting an account has to destroy an
> auth user, which the anon key cannot do. Without this variable, "Delete my account" returns a 500 — and
> an in-app deletion route is a hard requirement of both app stores and of GDPR/DPDP. Ship it or the
> deletion feature is a lie.
>
> Still **not** needed on the server: `SUPABASE_DB_URL` and `AI_SUPABASE_DB_URL` — those are only for
> running migrations from your own machine.

## Step 4 — Deploy

Click **Deploy**. You get `https://brewdiary-xyz.vercel.app`. Every push to `main` auto-deploys from now on.

---

## Step 5 — The domains: bwdy.site AND bar.bwdy.site

Project → Settings → **Domains**. Add **both**:

1. `bwdy.site` (and `www.bwdy.site` if you want it to redirect)
2. `bar.bwdy.site` ← **the venue dashboard**

Then at your DNS provider (wherever you bought the domain), add what Vercel shows you — typically:

| Type | Name | Value |
|---|---|---|
| `A` | `@` | `76.76.21.21` (Vercel gives you the current one) |
| `CNAME` | `bar` | `cname.vercel-dns.com` |

Vercel issues the TLS certificate for both automatically. DNS usually propagates in minutes; it can take
up to an hour.

**Nothing else is needed.** You do *not* configure a rewrite in Vercel — `src/middleware.ts` already does
it in code: any host starting with `bar.` is rewritten onto `/venue/*`, and the browser's address bar
stays on `bar.bwdy.site`. Point the subdomain at the same project and it works.

### Testing the subdomain locally
The same rewrite fires for any `bar.` host, so this works with no config:
```
http://bar.localhost:3000
```
(Chrome and Edge resolve `*.localhost` automatically. If yours doesn't, add
`127.0.0.1 bar.localhost` to your hosts file.)

## Step 6 — Point Supabase at the live URLs

App Supabase project → **Authentication → URL Configuration**:

- **Site URL:** `https://bwdy.site`
- **Redirect URLs** — add **all** of these:
  - `https://bwdy.site/**`
  - `https://bar.bwdy.site/**` ← **easy to forget.** Staff sign in on the subdomain with an ordinary
    brewdiary account; without this, their password-reset and confirmation links break.
  - `http://localhost:3000/**` (keeps local dev working)

---

## Step 7 — The click-test (do all of it)

On `https://bwdy.site`:
1. **Age gate** → pick a country, enter a date of birth → you get in. Reload → it does **not** come back.
2. **Sign up / sign in** → you land on the calendar.
3. **Log a drink** (with a photo) → the square brightens; it survives a refresh.
4. **Log a dry day** → the streak *keeps going*.
5. **Ask Ninkasi** something → a real, live reply.
6. **You → Your data → Download my data** → a JSON file lands. *(Don't test delete on your own account.)*
7. **`/privacy`** loads — and loads **before** you clear the age gate (open it in a private window).

On `https://bar.bwdy.site`:
8. It shows the **venue dashboard**, not the diary. Sign in with a normal account.
9. **Create a venue**, pick a country → the perk editor shows that country's rule.
10. Approve it from your machine: `node scripts/verify-venue.mjs <slug>` → then set a perk.
11. **Open a room** → copy the kiosk link → the wall board loads signed-out.

If all eleven pass, you're live.

---

## Good to know

- **The AI rate limiter is in-memory**, so on serverless it's a *soft* cap per instance
  (`src/lib/ratelimit.ts`). Fine for launch; move to Upstash Redis if you get big.
- **Free tiers** (Vercel + both Supabase projects) comfortably cover an early launch.
- **This unblocks Android:** once the site is live at a stable URL, the Capacitor app wraps it
  ([09](09-going-mobile-android.md)).
- **Before a *public* launch** (not needed to deploy): a `/terms` page, error monitoring, and a named
  grievance officer for DPDP. See `internal/legal-and-compliance.md`.
