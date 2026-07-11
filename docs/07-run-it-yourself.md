# 07 — Run it yourself

From a fresh computer to brewdiary open in your browser. We assume you've **never done this before**.
Every command is copy-paste. If something goes wrong, see "When something breaks" at the bottom.

> **What "running the app" means:** you'll start a small web server on *your own computer* and open the
> app at a local web address (`http://localhost:3000`). "localhost" just means "this computer." No one
> else can see it; it's your private sandbox.

## Step 1 — Install Node.js (once per computer)
The project needs **Node.js** (the thing that runs the app) and **npm** (its package downloader, which
comes bundled with Node).

1. Go to **https://nodejs.org** and download the **LTS** version (the stable one).
2. Install it (click through the installer).
3. Confirm it worked: open a terminal (on Windows, "PowerShell" or "Git Bash"; on Mac, "Terminal") and
   type:
   ```
   node --version
   ```
   If it prints a version like `v22.x.x`, you're good. (Node 18.18+ works; the LTS is safest.)

## Step 2 — Open a terminal in the project folder
The project is at `e:\shit\brewdiary`. In your terminal:
```
cd e:\shit\brewdiary
```
`cd` means "change directory" (go into that folder). Everything below is run from here.

## Step 3 — Download the project's building blocks
```
npm install
```
This reads `package.json` and downloads all the code libraries the project depends on into a
`node_modules` folder. It can take a couple of minutes the first time. You only re-run this if the
dependencies change.

## Step 4 — Add the secret settings
The app needs a `.env.local` file with the database connection (and, optionally, the AI key). There's a
template to copy:
```
cp .env.example .env.local
```
Then open `.env.local` in any text editor. For **just looking at the app**, you can leave the AI key
blank — Ninkasi will use her charming built-in scripted replies. To connect the **real database** and
the **real AI**, fill in the values as described in [08 — Founder playbook](08-founder-playbook.md).
(The current project already has a working `.env.local` for its Supabase database.)

> **Never share `.env.local` or paste its contents anywhere public.** It holds secrets.

## Step 5 — Start the app
```
npm run dev
```
Wait a few seconds until it says something like *"Ready on http://localhost:3000"*. Then open a browser
and go to:
```
http://localhost:3000
```
🎉 That's brewdiary running on your computer. Log a drink, poke around. As you edit code and save, the
page refreshes automatically ("hot reload").

To **stop** the app, click in the terminal and press `Ctrl + C`.

## The four commands you'll actually use
| Command | What it does | When |
|---|---|---|
| `npm install` | Download dependencies | First time, or after they change |
| `npm run dev` | Run the app for development (auto-refresh) | Every day, while working |
| `npm run build` | Package the app for release; also checks for errors | **Before calling anything "done"** |
| `npm test` | Run the automated tests (the core logic) | After changing any logic in `src/lib/` |
| `npm start` | Run the packaged (release) version | To test the real production build |

### Tests
The critical "brains" of the app have automated tests (in the `tests/` folder, run with
[Vitest](https://vitest.dev)). They cover the streak/mosaic math, the money-balance netting for Split,
the AI rate limiter, and the pseudonymization of training data. Run them with `npm test` — if they pass,
the core logic still behaves correctly. If you change anything in `src/lib/`, run `npm test` before
`npm run build`. `npm run test:watch` re-runs them automatically as you edit.

> **The golden habit:** run `npm run build` after any change. If it finishes without errors, your code
> at least *compiles* correctly. If it fails, it tells you what's wrong. We never declare work "done"
> without a green build.

## Where the different pieces run
- **The app you see** → your browser, at `localhost:3000`.
- **The database** → Supabase, in the cloud (already set up for this project).
- **The AI** → a provider (Groq) in the cloud, *once you add a key*; otherwise scripted replies run
  locally.
- **The AI training/model workshop** → separate, offline, in the `ninkasi-ai/` folder, and it needs
  Python (not Node). See [08 — Founder playbook](08-founder-playbook.md).

## When something breaks
- **`npm: command not found`** → Node isn't installed or the terminal needs restarting. Redo Step 1 and
  open a fresh terminal.
- **A red error mentioning a port** (`EADDRINUSE`, `port 3000`) → the app is already running in another
  terminal, or a previous run didn't close. Close other terminals, or stop the process, then try again.
- **The page loads but data doesn't save** → the database settings in `.env.local` are missing or wrong.
  For just browsing, that's fine (logged-out mode uses on-device storage).
- **A weird error after changing dependencies** → delete the `node_modules` folder and the `.next`
  folder, then run `npm install` again. (The `.next` folder is a rebuildable cache; deleting it is safe
  and fixes many odd glitches.)
- **Build complains about a type error** → the message names the file and line. TypeScript is catching a
  real inconsistency; fix what it points to.

Next: **[08 — Founder playbook](08-founder-playbook.md)** — your step-by-step for turning the AI on and
training our own model.
