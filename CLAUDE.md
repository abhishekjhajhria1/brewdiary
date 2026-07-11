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

## The two verification gates — run both before you call anything done

```bash
npm test          # vitest — the pure logic (date math, streak/derive, expenses, drinks, ratelimit, aidb)
npm run build     # next build — the real gate: typecheck + lint + compile all routes
```

If either is red, the task is not finished. `npm test` is fast; run it whenever you touch `src/lib`.

---

## How the code is organized

All application code lives under **`src/`** (standard Next.js `src/` layout). Imports use the `@/*`
alias → `./src/*` (e.g. `@/lib/derive`, `@/components/ui/Chip`).

| Path | What's there |
| --- | --- |
| `src/app/` | Routes (`/`, `/you`, `/together`, `/split`, `/discover`, `/bartender`, `/party/[id]`, `/p/[code]`) + `layout.tsx` + `globals.css` + `middleware.ts` + `api/`. |
| `src/components/` | Feature-grouped UI: `calendar/`, `log/`, `you/`, `together/`, `discover/`, `bartender/`, `share/`, `onboarding/`, `ui/`. |
| `src/lib/` | Framework-free logic — the "brains". See the table below. |
| `public/` | Static assets: PWA `manifest.webmanifest`, `sw.js`, app icons. |
| `supabase/` | App-database SQL (`schema.sql` + numbered migrations `002`–`007`). Run with `node scripts/db.mjs <file.sql>`. |
| `ai-db/` | The **separate** AI database schema (pseudonymous Ninkasi corpus; deny-all RLS). |
| `scripts/` | Dev/ops tooling: `db.mjs` (migration runner), `gen-icons.mjs`, `ninkasi/` (dataset export, trend sync, AI-DB verify). |
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
| `friends.ts` / `circles.ts` / `parties.ts` | Together social: friends+feed, private circles, parties/events (+ host-approval). |
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
drink canonicalization + log autocomplete + Extras.

**Blocked on keys/resources (not code):** live Discover venues (Google Places), payments (Stripe), the
actual model fine-tune (GPU/managed + ~500 corpus). See `docs/08-founder-playbook.md`.

**Next milestone:** deploy to Vercel (`docs/10-deploy.md`) → then Android via Capacitor (`docs/09-…`).
