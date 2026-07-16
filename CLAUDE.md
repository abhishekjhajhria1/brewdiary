# brewdiary — developer & AI guide (read this first)

**What this is:** an all-inclusive **drink diary**. The home is a calendar — tap a day, log a
drink in a tiny sheet, the day's square darkens, and over a year the grid fills into a quiet
**streak mosaic**. Calm and minimal; social ("Together") is a deliberate second layer. Built for
everyone who drinks *anything* — coffee, wine, beer, a homebrew, a kombucha.

This file is the front door for any human developer or AI assistant. Read it before touching code.

---

## Before you start any task

1. **Read the docs.** [`docs/`](docs/) is the plain-English handbook (start at [`docs/README.md`](docs/README.md)).
   Every term is defined; you don't need prior context to understand the codebase.
2. **Check the internal working folder — if it exists.** [`internal/`](internal/) holds the local-only
   planning, decision history, and hand-off notes (see "Internal working folder" below). It is
   **git-ignored**, so a fresh clone won't have it — that's intentional. When it *is* present
   (the maintainer's machine), **consult it before starting** so you don't re-litigate settled decisions.
3. **Use the design skill for any UI work.** The `taste-engine` skill in `.claude/skills/` carries the
   locked product spec and anti-slop rules. Its `reference/brewdiary-north-star.md` is the design
   constitution. Do not introduce a look that fights it (see "House style" below).

## The verification gates — run all before you call anything done

```bash
npm run gates     # lint + test + build, in one word
#   npm test      — vitest: the pure logic (dates, derive, balance, drinks, venues, perk policy, money, ratelimit, aidb)
#   npm run lint  — eslint (next/core-web-vitals + TS; config: eslint.config.mjs)
#   npm run build — next build: typecheck + compile every route
```

If any is red, the task is not finished. `npm test` is fast; run it whenever you touch `src/lib`.

**The three gates above cannot see the database.** A migration can succeed, the build can be
green, every test can pass, and the app can still be *unsafe* — a policy that was supposed to be
absent, an RLS flag that never got enabled, a `SECURITY DEFINER` function silently returning the
wrong jurisdiction's rules. That has happened here. So after ANY migration:

```bash
npm run db:audit   # READ-ONLY. Asserts the SHAPE of the live schema + every security invariant.
npm run db:verify  # Plays a whole night against the real schema IN A TRANSACTION IT ROLLS BACK.
```

`db:audit` is what caught `perk_policy()` judging every venue on earth by Massachusetts law —
a bug no unit test could see, because every caller was a trigger and nothing ever threw.
Both run in CI (`.github/workflows/ci.yml`) on every push to `main`.

---

## How the code is organized

All application code lives under **`src/`** (standard Next.js `src/` layout). Imports use the `@/*`
alias → `./src/*` (e.g. `@/lib/derive`, `@/components/ui/Chip`).

| Path | What's there |
| --- | --- |
| `src/app/` | Routes (`/`, `/you`, `/together`, `/split`, `/discover`, `/bartender`, `/party/[id]`, `/p/[code]`, `/u/[handle]` public profile, `/kiosk/[code]` venue wall board, `/venue` the bar dashboard) + `layout.tsx` + `globals.css` + `middleware.ts` + `api/`. The middleware also rewrites any `bar.*` host (bar.bwdy.site) onto `/venue/*` — the venue dashboard is the same app, not a second deploy. |
| `src/components/` | Feature-grouped UI: `calendar/`, `log/`, `you/`, `together/`, `discover/`, `bartender/`, `share/`, `onboarding/`, `venue/`, `kiosk/`, `profile/`, `ui/`. |
| `src/lib/` | Framework-free logic — the "brains". See the table below. |
| `public/` | Static assets: PWA `manifest.webmanifest`, `sw.js`, app icons. |
| `supabase/` | App-database SQL (`schema.sql` + numbered migrations `002`–`030`). Run with `node scripts/db.mjs <file.sql>` — **the maintainer runs these, not the agent.** Each file is one implicit transaction: it lands whole or not at all. |
| `ai-db/` | The **separate** AI database schema (pseudonymous Ninkasi corpus; deny-all RLS). |
| `scripts/` | Dev/ops tooling: `db.mjs` (migration runner), `gen-icons.mjs`, `verify-venue.mjs` (the only path that approves a venue), `ninkasi/` (dataset export, trend sync, AI-DB verify). |
| `tests/` | Vitest unit tests for `src/lib` (excluded from `next build`). |
| `docs/` | The beginner-proof handbook (committed — for every developer you hire). |
| `.claude/skills/taste-engine/` | The design/product spec + anti-slop engine. Loaded as a Claude Code skill; **keep it here** (moving it breaks the skill). |
| `internal/` | **Git-ignored** local planning/handoff. Not in a fresh clone. |

### `src/lib/` — the brains (all pure/derived where possible)

| File | Responsibility |
| --- | --- |
| `types.ts` | Core `Entry` shape + `DrinkType`. Only `Entry` rows are ever written. |
| `date.ts` | Day-key (`YYYY-MM-DD`) helpers, month grid, time-of-day labels. |
| `derive.ts` | **Everything visual is derived here** — counts, streaks (with grace), milestones, lexicon, recent drinks, friend picks, year review. Never stored. |
| `store.ts` | Entry store. Two modes, one API: localStorage when logged-out, Supabase when authed; optimistic writes; local→remote migration on sign-in. |
| `drinks.ts` | Drink **canonicalization** — dictionary + fuzzy match folds variants/typos into one family; powers log autocomplete + the "≈ tidy name" nudge. Grouping is derived, never stored. |
| `features.ts` | **Extras** — opt-in trackers (cigarettes, water…), off by default. Add one entry to `EXTRAS` → it appears as a profile toggle + a log-window counter. |
| `tallies.ts` | Per-day counts behind the Extras (local-only for now). |
| `profile.ts` | Auth (Supabase) + `useAuth`/`useProfile`. The seam real auth plugs into. |
| `friends.ts` / `circles.ts` / `parties.ts` | Together social: friends+feed, private circles, parties/events (+ host-approval). A party doubles as a venue "room" (`venue_id`). |
| `points.ts` | Sparks/vibe boards over the append-only `point_events` ledger (positive-only, counts-only) + the kiosk board poller + the `kiosk_visible` opt-in. |
| `venues.ts` / `perks.ts` | The bar side: venues (`kind`: **bar** = on-trade, **store** = off-trade), staff roles, verification; up to 3 perk **tiers**, each an independent punch-card with its own claim clock. |
| `jurisdiction.ts` | **Where you are decides what the app may lawfully do.** Deny-by-default: an unresearched country gets the STRICTEST setting, never the most permissive. Mirrors `public.jurisdiction_policy` — **the DATABASE is the authority**; this copy only lets the UI *explain* the rule instead of just failing. |
| `kudos.ts` | Thanking staff. A manager sees ONE total for the team — a per-person league table is impossible, and not just hidden: the RLS policy makes it unreadable even via direct SQL. |
| `guestbook.ts` | The venue **guest book** — a **first-party** CRM (migration 040). A venue keeps notes/tags on guests it has actually served, and sees history IT generated (visits, tabs, perks). Hard rule enforced in the DB: **no join to `entries`** (a guest's diary never reaches a venue) and **no cross-venue read**. Notes are staff-written only; the guest can see every note kept on them and delete it (`my_venue_books`, You → Settings). This is the deliberate first-party revision of the older "never a per-guest list" line — we still refuse a churn list of strangers or anyone's activity elsewhere. |
| `money.ts` | Currency is a property of the PLACE, not the app (Intl-based; ₹1,23,456 vs €1.234,56). Also `spendBand()` — a flexed tab is shown as a **band** ("₹2,500+"), never the figure. |
| `host.ts` | Which app is this? On `bar.*` the middleware rewrites to `/venue` but `usePathname()` still returns `/` — so anything hiding "on the venue app" must ask the HOST, not the path. |
| `dataRights.ts` | Export everything / delete the account (GDPR Arts. 15 & 17, India's DPDP Act). |
| `publicProfile.ts` | Opt-in public profile read (`/u/<handle>`, counts only) + the owner's visibility/social-link settings. |
| `goals.ts` | Gentle limits — optional weekly-limit/dry-days goals, per-device localStorage, off by default (standing derived via `derive.weekBalance`). |
| `expenses.ts` | Split (Splitwise-style) balance math. |
| `wishlist.ts` / `trends.ts` / `training.ts` | To-try list, opt-in taste trends, local Ninkasi training export. |
| `bartender.ts` | Ninkasi persona + system prompt + scripted fallback. |
| `ratelimit.ts` / `aidb.ts` / `supabase-server.ts` | AI-route rate limiting; server-only pseudonymized AI-DB writer; SSR session reader. |

---

## Non-negotiable conventions

- **Derived, never stored.** The mosaic, streaks, milestones, lexicon, recommendations, leaderboards
  are all *computed from `Entry` rows* (see `derive.ts`). Don't add a column that caches a derivable value.
- **Store hooks keep a stable public API.** `store.ts` / `wishlist.ts` / etc. expose the same hook names
  in local and remote mode; swapping backends must not change the component-facing API.
- **Supabase writes:** the app uses the anon key + **RLS** for safety; a `SECURITY DEFINER` read policy
  makes PostgREST `INSERT … RETURNING` fail — insert with a **client-generated id and no `.select()`**,
  then read back separately (see `parties.ts` / `expenses.ts`).
- **Secrets are server-only.** `AI_API_KEY`, service-role keys, DB URLs are never `NEXT_PUBLIC_*` and never
  reach the client. The AI model is a stateless text function — it never touches a database.
- **Nothing rewards drinking more.** This is the product, not a slogan — check every new feature against it.
  Sparks are earned for **variety** (a new place, a new drink, a *dry day*), never for frequency or volume.
  A dry day keeps the streak. A quiet-night boost doubles **perk progress**, never a spark and never a
  discount. A flexed tab shows a **band** ("₹2,500+"), never a figure — an exact number turns a wall board
  into a spending race you win by buying one more drink.
- **A guest can never write their own reward.** Spend, visits and perk claims are **staff-recorded only**,
  enforced server-side (no client write policy on `spend_events` / `venue_checkins` / `perk_redemptions`).
  If a guest could punch their own card, the whole thing is a free-drinks machine.
- **Legality is enforced in the DATABASE, deny-by-default.** Alcohol-promotion law is national and often
  sub-national. A trigger — not a form, not a component — decides whether a perk may exist. An unresearched
  jurisdiction returns **no row**, and no row means NO. Opening a market is a deliberate act: research it,
  add a row, cite the source (`internal/legal-and-compliance.md`). **An off-licence is NOT a quieter bar** —
  at a shop a visit *is* a purchase, so it needs its own permission (`allow_offtrade_perks`), counts visits
  only, and its reward is never alcohol, anywhere.
- **House style = liquid glass, two themes, dark-default.** Layered frosted surfaces (`.glass`/`.glass-strong`),
  one amber accent, mosaic glows amber-by-count, high-contrast text, **no** AI-slop purple/neon, no emoji as
  UI chrome. This supersedes any older "flat monochrome / no-glass" note in the north-star file.
- **Currency is `₹`** (the maintainer is in India).

## Internal working folder (`internal/`, git-ignored)

Local-only, never pushed. Holds the dense dev/AI hand-off:
- `internal/done/README.md` — session prime directives & orientation.
- `internal/done/PROGRESS.md` — the full decision trajectory + status + roadmap.
- `internal/done/ARCHITECTURE.md` — structure, conventions, data seams, recipes.

`docs/` (committed) is for *humans learning the codebase*; `internal/done/` is the *denser working memory*.
If `internal/` is missing (a fresh clone), rely on `docs/` + this file — nothing here blocks you.

## What's built vs. blocked

**Built & working (no keys):** calendar/logging/mosaic, auth + cloud sync (entries, photos, wishlist),
Together (friends/feed/cheers/comments/share), circles, parties + host-approval, split, age-gate, PWA,
Ninkasi (live when `AI_API_KEY` set, scripted fallback otherwise) + the two-database AI data plane,
drink canonicalization + log autocomplete + Extras, and the **Rooms/Points/Venues layer** (Phase 7):
sparks + positive-only vibe inside parties, the venue dashboard on the `bar.` subdomain (staff, rooms,
verification requests, house perks for verified venues), the public kiosk board, opt-in public profiles
(`/u/<handle>`), and gentle limits (weekly limit / dry days, derived, off by default).

**Blocked on keys/resources (not code):** live Discover venues (Google Places), payments (Stripe), the
actual model fine-tune (GPU/managed + ~500 corpus). See `docs/08-founder-playbook.md`.

**Next milestone:** deploy to Vercel (`docs/10-deploy.md`) → then Android via Capacitor (`docs/09-…`).
