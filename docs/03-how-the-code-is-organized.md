# 03 — How the code is organized

Think of the project as a building. This is the floor plan. You don't need to understand the code inside
each file yet — just *what each room is for*. (Unfamiliar words? See the
[glossary](02-glossary.md).)

## The top level (the repo root)
When you open the project folder, the important things are:

| Name | What it is |
|---|---|
| `src/` | **All the app's own code.** 90% of your time is here. Detailed below. |
| `supabase/` | The **app database blueprints** (`.sql` files). Defines every user-data table and its security rules. |
| `ai-db/` | The **separate AI database blueprint** — a *second*, dedicated database just for the AI's data (training corpus + anonymized trends). Server-only. See [doc 05](05-the-ninkasi-ai-explained.md) + [doc 06](06-security-and-privacy.md). |
| `scripts/` | Helper programs run by hand — including `scripts/ninkasi/`, the **AI data exporter**. |
| `ninkasi-ai/` | The **workshop for building our own AI model** (dataset, training, serving). See [doc 05](05-the-ninkasi-ai-explained.md). |
| `tests/` | **Automated checks** for the logic in `src/lib`. Run with `npm test`. |
| `public/` | Files served as-is: the app icon, the offline "service worker," the install manifest. |
| `docs/` | **These plain-English docs.** |
| `CLAUDE.md` | The **developer & AI front door** — folder map, conventions, and the two checks to run before finishing. Read it first. |
| `README.md` | The short front-page readme. |
| `internal/` | **Local-only working notes** (planning + decision history). *Git-ignored* — it is deliberately **not** in a fresh clone. If you have it, read it before starting; if you don't, `CLAUDE.md` + these docs are enough. |
| `.env.local` | **Secret settings** (API keys, database URL). Never shared. Not in version control. |
| `.env.example` | A safe, blank template showing which secrets are needed. |
| `package.json` | The project's ID card: its name, its commands (`dev`, `build`, `test`), and its dependencies. |
| config files | `next.config.mjs`, `tsconfig.json`, `postcss.config.mjs`, `vitest.config.ts` — settings for the tools. You rarely touch these. |

## Inside `src/` — the three main rooms
Everything the app *is* lives in three folders: **`app/`**, **`components/`**, and **`lib/`**.
The simplest way to remember them:

- **`app/`** = the **pages** (web addresses / screens) and the back-end **API**.
- **`components/`** = the **visual building blocks** the pages are made of.
- **`lib/`** = the **brains** — data, logic, and talking to the database. No visuals here.

### `src/app/` — pages & the back-end
In Next.js, **each folder here becomes a web address.** A `page.tsx` file is the screen at that address.

| File | The screen / job |
|---|---|
| `app/page.tsx` | The **home page** (`/`). Shows the marketing landing to logged-out visitors, or the calendar to logged-in users. |
| `app/layout.tsx` | The **frame around every page** — loads fonts, the theme, the age-gate, the top bar and tab bar. |
| `app/globals.css` | The **global styling** and the "liquid glass" design tokens (colors, blur, spacing). |
| `app/you/page.tsx` | The **You** screen (`/you`). |
| `app/together/page.tsx` | The **Together** social hub (`/together`). |
| `app/split/page.tsx` | The **Split** bill-splitter (`/split`). |
| `app/discover/page.tsx` | The **Discover** screen (`/discover`). |
| `app/bartender/page.tsx` | The **Ninkasi** chat screen (`/bartender`). |
| `app/party/[id]/page.tsx` | A **party page** — `[id]` means the address has a changing part, e.g. `/party/abc123`. |
| `app/p/[code]/page.tsx` | A **public party invite** link (works for people without accounts). |
| `app/api/bartender/route.ts` | **The AI back-end.** Not a screen — a doorway the chat calls. It talks to the AI provider using the secret key, and streams the reply back. This is where the security guards (rate limit, size caps) live. |

### `src/components/` — the visual building blocks
Grouped by feature. Each `.tsx` file is one reusable piece of UI.

- **`calendar/`** — the core diary experience.
  - `CalendarHome.tsx` — the whole home screen assembly.
  - `MonthCalendar.tsx` — the month grid.
  - `DayCell.tsx` — a single day's square (brightens with how much you logged).
  - `YearMosaic.tsx` — the zoomed-out year grid.
  - `StreakStrip.tsx` — the quiet streak counter.
- **`log/`**
  - `LogSheet.tsx` — the little form that slides up when you tap a day. Also where you edit, delete, and
    share an entry. Includes the drink **autocomplete** (from `lib/drinks.ts`) and the optional per-day
    **Extras counters** (cigarettes/water, from `lib/features.ts` + `lib/tallies.ts`).
- **`together/`** — the social layer.
  - `Together.tsx` (the feed + friends), `Circles.tsx` (private groups + challenges),
    `Parties.tsx` / `PartyRoom.tsx` (events + recaps), `RecentMosaic.tsx` (a friend's/circle's mini
    mosaic).
- **`split/`** — `Split.tsx`, the Splitwise-style bill tool.
- **`you/`** — `You.tsx`, the whole You screen (stats, photo wall, wishlist, history, settings).
- **`bartender/`** — `Bartender.tsx`, the chat interface for Ninkasi.
- **`discover/`** — `Trends.tsx`, the live "what's pouring" anonymous trends card.
- **`onboarding/`** — `Landing.tsx` (the marketing/first-run page) and `AgeGate.tsx` (the 18+ check).
- **`share/`** — `ShareCard.tsx`, which paints an entry onto an image you can share on social media.
- **`ui/`** — small shared pieces used everywhere: `TopBar.tsx`, `TabBar.tsx`, `ThemeToggle.tsx`,
  `Chip.tsx` (a little tag), `MilestoneMeter.tsx`, `PWA.tsx` (makes the app installable/offline).

### `src/lib/` — the brains (no visuals)
This is where data and logic live. A few important patterns:
- Files named after a feature (`friends.ts`, `circles.ts`, `parties.ts`, `expenses.ts`, `wishlist.ts`,
  `challenges.ts`) each hold that feature's data functions — how to read and write it in the database.
- **The most important files:**

| File | What it does |
|---|---|
| `types.ts` | The **definitions** of our data shapes ("an Entry has a date, a drink, a mood, photos…"). The shared dictionary everything else agrees on. |
| `supabase.ts` | Creates the **connection to the database**. |
| `profile.ts` | **Accounts** — sign up, sign in, sign out, who's logged in. |
| `store.ts` | **Drink entries** — the heart. Add / edit / delete / list your drinks. Works offline for logged-out visitors, syncs to the cloud when logged in. |
| `derive.ts` | **The calculator.** Turns your raw entries into the streak, the mosaic shading, milestones, your mood collection, recent-drink suggestions. Nothing derived is *stored* — it's always recomputed, so it's never wrong. |
| `drinks.ts` | **Drink name intelligence.** A dictionary + fuzzy matching that folds variants and typos ("flatwhite", "cappucino") into one tidy family. Powers the log window's autocomplete and the gentle "≈ Flat White" suggestion. |
| `features.ts` | **Extras** — optional trackers (cigarettes, water…) that stay hidden until switched on in *You › Settings*. Add one line here and it appears as a toggle + a counter in the log. |
| `tallies.ts` | The **per-day counts** behind those Extras (e.g. how many cigarettes that day). |
| `date.ts` | Small date helpers (what week is this, format a date). |
| `bartender.ts` | **Ninkasi's personality** (the system prompt) + the offline scripted replies. |
| `training.ts` | Collects consented chat exchanges to build the AI training set. |
| `trends.ts` | The opt-in, anonymous taste-trends data. |
| `ratelimit.ts` | The **anti-abuse guard** for the AI route (caps requests per minute). |
| `theme.ts` | Light/dark theme handling. |
| `age.ts` | The 18+ age-gate logic. |
| `seed.ts` | Fake demo data, so a fresh install has something to look at. |

## The one rule that explains the whole design
> **Only drink entries are truly stored. Everything else is *calculated* from them.**

The streak, the mosaic, milestones, your mood lexicon, "recent drinks" suggestions, leaderboards — none
of these are saved anywhere. They're recomputed from your entries every time by `derive.ts`. This is why
the app can never show a "wrong" streak: there's nothing to get out of sync. If you remember one thing
about the architecture, remember this.

Next: **[04 — How it all works](04-how-it-all-works.md)**, where we follow real actions through these
files step by step.
