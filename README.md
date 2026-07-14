# brewdiary

An all-inclusive **drink diary**. The home is a calendar — tap a day, log a drink in a tiny sheet, and the
day's square darkens. Over time the year fills into a quiet **streak mosaic**. Calm, minimal, collectible;
social ("Together") is a deliberate second layer. Log *anything* — coffee, wine, beer, a homebrew, a can.

## Run

```bash
npm install
npm run dev      # http://localhost:3000
npm test         # vitest — the pure logic
npm run build    # production build — the verification gate (typecheck + lint + compile)
```

New sign-ups start empty; the **You** tab has quiet *reseed / reset* controls (reseed drops ~20 realistic
demo entries so the mosaic is alive). Copy `.env.example` → `.env.local` and fill it in to enable the
Supabase backend and the Ninkasi AI; without it the app runs local-only (localStorage).

## Stack

Next.js 15 (App Router) · React 19 · TypeScript · Tailwind v4 · Supabase (auth, Postgres + RLS, storage) ·
an OpenAI-compatible AI client (Ninkasi). PWA-ready (installable, offline shell, maskable icons).

## Where things live

All application code is under **`src/`** (standard Next.js `src/` layout); the root holds config + docs.
Imports use the `@/*` alias → `./src/*` (e.g. `@/lib/derive`, `@/components/ui/Chip`).

- `src/app/` — routes + `layout.tsx` + `globals.css` + `middleware.ts` + `api/`
- `src/components/` — feature-grouped UI (`calendar/`, `log/`, `you/`, `together/`, `discover/`, `bartender/`, `share/`, `onboarding/`, `venue/`, `kiosk/`, `profile/`, `ui/`)
- `src/lib/` — framework-free logic. **All visual state is derived from `Entry` rows — never stored.**
- `public/` — PWA manifest, service worker, app icons
- `supabase/` · `ai-db/` — database SQL (app DB + the separate AI DB)
- `scripts/` · `tests/` — dev tooling + unit tests
- `docs/` — the plain-English handbook (start at [`docs/README.md`](docs/README.md))

## 👉 New here? Start at [`docs/`](docs/)

[`docs/README.md`](docs/README.md) is the front door: a zero-assumptions tour of the product, the folder
map, the `src/lib` responsibilities, the conventions, and what's built vs. blocked. Before calling any
change done, run the three checks: `npm test`, `npm run lint`, `npm run build`.

> A local-only `internal/` folder (git-ignored, not in a fresh clone) holds the maintainer's dense working
> notes. `docs/` is self-sufficient without it.
