# brewdiary — the plain-English handbook

Welcome. This folder explains the **entire brewdiary project in plain English**, for someone who has
**never written code before**. No jargon is assumed. Every technical word is defined the first time it
appears, and there's a full glossary you can jump to anytime.

If you can read a recipe, you can read this.

## Read in this order
1. **[01 — What brewdiary is](01-what-is-brewdiary.md)** — the product, in one sitting. No code at all.
2. **[02 — Plain-English glossary](02-glossary.md)** — what every technical word means. Skim it, then
   keep it open in a tab. Whenever a word confuses you, it's defined here.
3. **[03 — How the code is organized](03-how-the-code-is-organized.md)** — a tour of the folders and
   files, like a map of a building: what each room is for.
4. **[04 — How it all works](04-how-it-all-works.md)** — we follow real actions (logging a drink,
   signing in, the calendar filling up, chatting with the bartender) step by step through the code.
5. **[05 — The Ninkasi AI, explained](05-the-ninkasi-ai-explained.md)** — the AI bartender: what it is,
   how it answers, and the plan to build and own our own AI model. Plain English.
6. **[06 — Security & privacy](06-security-and-privacy.md)** — how we keep the secret keys secret and
   users' data safe. Written so a non-engineer can check we did it right.
7. **[07 — Run it yourself](07-run-it-yourself.md)** — from a fresh computer to the app open in your
   browser, one command at a time, assuming nothing.
8. **[08 — Founder playbook](08-founder-playbook.md)** — the checklist for *you*: how to switch the AI
   on, watch it learn, and train our own model. This is your day-to-day guide.
9. **[09 — Going mobile: Android](09-going-mobile-android.md)** — yes, this becomes a real phone app.
   The three paths (PWA, Play-Store TWA, native Capacitor), what each needs, and which to pick.
10. **[10 — Deploy the web app](10-deploy.md)** — put brewdiary live on Vercel: GitHub, the exact 8
    environment variables, Supabase URL config, and the post-deploy click-test.
11. **[11 — Rooms, points & venues](11-rooms-points-venues.md)** — the bar layer: sparks, vibe, house
    perks, the venue dashboard, the wall screen, the leaderboard, and every privacy switch. Diagrams
    of each workflow, a map of where all of it lives, and the rules that must not be broken.

## The one-paragraph version
brewdiary is a **drink diary**. You open it, tap tonight's date on a calendar, and jot down what you
drank (a coffee, a beer, a cocktail, a mocktail — anything). Over time the calendar fills in like a
mosaic and shows your streak. You can share entries with friends, host parties, split the bill, and ask
**Ninkasi** — an AI bartender — what to pour. Bars can join in too: they open a **room** for the night,
their staff hand out good-vibe points, a screen on the wall shows the board, and regulars earn a free
drink — all of it off until you switch it on ([doc 11](11-rooms-points-venues.md)). It runs on modern
web technology (Next.js + React) with a cloud database (Supabase) that safely stores everyone's data.
We're now building **our own AI model** so Ninkasi is something we own and can market, not a service we
rent forever.

## The other guides (and who they're for)
- **`docs/`** (this one) → **for anyone learning the project**, especially non-coders. Start here.
- **`internal/`** → the maintainer's **local-only working notes** (planning + full decision history).
  It's *git-ignored*, so it isn't in a fresh clone — these docs stand on their own without it.

Before calling any change done, run the three checks: `npm test`, `npm run lint`, `npm run build`.

If you only read one file, read [01 — What brewdiary is](01-what-is-brewdiary.md).
