# 12 — The phone app, the server, and the bars

This is the guide for connecting everything together:

1. [The map](#1-the-map) — what talks to what.
2. [Connect the phone app to the server](#2-connect-the-phone-app-to-the-server) — step by step.
3. [Switch Ninkasi on for the phone](#3-switch-ninkasi-on-for-the-phone).
4. [Email-code sign in / sign up](#4-email-code-sign-in--sign-up) — turning it on in Supabase, and
   adding it to the website.
5. [How a bar connects to its guests](#5-how-a-bar-connects-to-its-guests) — what exists today.
6. [How the data is linked — and where it must never go](#6-how-the-data-is-linked--and-where-it-must-never-go).
7. [Making the bar side more interactive, fun and useful](#7-making-the-bar-side-more-interactive-fun-and-useful)
   — a roadmap, with how to build each piece.
8. [Go-live checklist](#8-go-live-checklist).

Words you might not know are in the [glossary](02-glossary.md). The phone app's own README is
[`test_m_app/README.md`](../test_m_app/README.md).

---

## 1. The map

There is **one** database and **one** website. The phone app, the website and the bar dashboard are
three windows onto the same thing.

```
                         ┌─────────────────────────────────────────────┐
                         │  Supabase (the database + sign-in)          │
                         │  tables · row-level security · RPCs         │
                         └──────▲──────────────▲───────────────▲───────┘
                                │              │               │
                  anon key + the person's login (RLS decides what each may see)
                                │              │               │
  ┌──────────────────────┐   ┌──┴───────────┐  │   ┌───────────┴─────────┐
  │ Phone app (Flutter)  │   │ Website      │  │   │ Bar dashboard       │
  │ test_m_app/          │   │ bwdy.site    │  │   │ bar.bwdy.site       │
  └──────────┬───────────┘   └──┬───────────┘  │   │ (same Next.js app)  │
             │                  │              │   └─────────────────────┘
             │  HTTPS           │ server routes│
             └──────────────────►  /api/bartender (Ninkasi)  ── AI provider (key lives HERE only)
                                   /api/account/delete
                                   /api/ninkasi/forget

  NFC sticker / QR on a table ──► https://bwdy.site/m/<venue>  ── opens the app if installed,
                                                                  the website if not
```

Three rules make this safe, and they don't change for the phone:

- **The phone only ever holds the public "anon" key.** It is public by design: what anyone can read
  or write is decided by row-level security (RLS) in the database, per signed-in person.
- **Secrets stay on the server.** The AI key, the service-role key and database passwords are never in
  the app. Anything that needs them is a website route the app calls over HTTPS.
- **The database is the authority** on what's lawful and private (perk rules, the guest book, menus,
  challenges). The app only explains the rule; it never enforces it on its own.

---

## 2. Connect the phone app to the server

Without these values the app runs in **local mode**: the diary lives on the phone, Together shows an
introduction, and menus say "not connected". That's safe, but it's not the real product.

### Step 1 — Get the two public values from Supabase

In the Supabase dashboard, open your project, then **Project Settings → API**:

| Value | Where it is | Also known as |
| --- | --- | --- |
| Project URL | "Project URL" | the website's `NEXT_PUBLIC_SUPABASE_URL` |
| anon public key | "Project API keys → anon / public" | the website's `NEXT_PUBLIC_SUPABASE_ANON_KEY` |

They are exactly the values the website already uses. **Never** use the `service_role` key in the app.

### Step 2 — Put them in `test_m_app/env.json`

```bash
cd test_m_app
cp env.example.json env.json
```

```json
{
  "SUPABASE_URL": "https://<your-project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<the anon public key>",
  "SITE_URL": "https://bwdy.site"
}
```

`env.json` is git-ignored, so it never gets committed. `SITE_URL` is where the phone finds Ninkasi and
the account-deletion route — point it at a preview deploy to test against that instead.

### Step 3 — Run or build with it

```bash
flutter run --dart-define-from-file=env.json                 # on a connected phone
flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=env.json
flutter build ipa --release --dart-define-from-file=env.json # on a Mac
```

The values are baked in at build time ([`lib/config.dart`](../test_m_app/lib/config.dart)); the app
switches to cloud mode on its own when both are present.

### Step 4 — Things on the server side the phone relies on

1. **Deploy the website change in this branch.** `src/lib/supabase-server.ts` accepts
   `Authorization: Bearer <token>` so the phone (which has no cookies) can delete an account and have a
   consented Ninkasi exchange attributed to it.
2. **Run the migrations** the app uses: `042_menus.sql` and `043_challenge_kinds.sql` (the maintainer
   runs these with `node scripts/db.mjs supabase/<file>.sql`), then **`npm run db:audit`**.
3. **Supabase → Authentication → URL Configuration:** keep `https://bwdy.site/reset` in the redirect
   allow-list (password-reset emails open the website's reset page).
4. **App links** (optional, so links open the app instead of the browser): host
   `https://bwdy.site/.well-known/assetlinks.json` (Android) and
   `https://bwdy.site/.well-known/apple-app-site-association` (iOS), covering `/p/*`, `/u/*`,
   `/party/*` and `/m/*`. The steps are in the app README.

### How to check it worked

- Sign up in the app → the new person appears in Supabase **Authentication → Users** and in
  `public.profiles`.
- Log a drink → a row appears in `public.entries` with that person's `user_id`.
- The Together tab shows the real feed instead of the introduction.

---

## 3. Switch Ninkasi on for the phone

The phone never talks to an AI provider. It sends the chat to the website, which holds the key:

```
phone  ──POST {SITE_URL}/api/bartender──►  website  ──►  AI provider
       ◄──── streamed text ────────────── (rate-limited, size-capped)
```

What the phone sends (see [`bartender_api.dart`](../test_m_app/lib/data/bartender_api.dart)):

```json
{
  "messages": [{ "role": "user", "content": "Something cozy and low-effort." }],
  "context":  { "recentDrinks": ["Negroni"], "moods": ["cozy"], "total": 20,
                "friendsPouring": [], "trending": [] },
  "collect":  false
}
```

plus `Authorization: Bearer <session token>` when signed in. The reply streams back as plain text,
and the `x-bartender-mode` header says `live` or `fallback`.

To switch her on, set these on the **website's** server (Vercel → Project → Settings → Environment
Variables), never in the app:

| Variable | What |
| --- | --- |
| `AI_API_KEY` | the provider key (required to go live) |
| `AI_BASE_URL` | an OpenAI-compatible endpoint (default: Groq) |
| `AI_MODEL` | e.g. `llama-3.3-70b-versatile` |

No redeploy of the app is needed: the same app starts getting live replies. Without a key, or when
the phone is offline, Ninkasi answers from her scripted fallback and the app says she's "pouring from
memory". Test the route from a terminal:

```bash
curl -N -X POST https://bwdy.site/api/bartender \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"What should I pour tonight?"}],"context":{},"collect":false}'
```

"Help train Ninkasi" (`collect: true`) is opt-in, and only then is a pseudonymized copy of the
exchange kept in the separate AI database ([doc 05](05-the-ninkasi-ai-explained.md)).

---

## 4. Email-code sign in / sign up

The app now offers **"Email me a code"** next to the password: the person types their email, gets a
6-digit code, types it in, and they're in. No password to forget. New people can start a diary the same
way. It's in [`auth.dart`](../test_m_app/lib/data/auth.dart) (`sendEmailCode` / `verifyEmailCode`) and
the sign-in sheet in [`landing_screen.dart`](../test_m_app/lib/ui/screens/landing_screen.dart).

### Turn it on in Supabase (one time)

1. **Authentication → Providers → Email:** make sure Email is enabled. Set **Email OTP expiration** to
   something short, like `600` seconds (10 minutes), and keep the OTP length at 6.
2. **Authentication → Email Templates:** by default Supabase emails a *link*. To send a *code*, put
   `{{ .Token }}` in the email body of both the **Magic Link** template (existing people) and the
   **Confirm signup** template (new people). For example:

   ```html
   <h2>Your brewdiary code</h2>
   <p>Type this into the app: <strong style="font-size:24px;letter-spacing:4px">{{ .Token }}</strong></p>
   <p>It works for 10 minutes. If you didn't ask for it, ignore this email.</p>
   ```

3. **Custom SMTP (before real users):** Supabase's built-in sender only sends a handful of emails an hour
   and is meant for testing. Under **Project Settings → Authentication → SMTP**, connect a real sender
   (Resend, Amazon SES, Postmark, SendGrid…) with your own domain, e.g. `hello@bwdy.site`.
4. **Rate limits:** Authentication → Rate Limits → keep the email limit sensible (the default protects
   you from someone spamming an inbox with codes).

How the app behaves:

- **Sign in** sends a code only to an email that already has a diary (`shouldCreateUser: false`). A new
  email gets a gentle "New here? Create a diary instead".
- **Create a diary** sends a code and creates the account on the first successful code, carrying the
  name they typed (`shouldCreateUser: true`).
- A wrong or expired code says so plainly; "Send a new code" is right there.
- The session arrives through the same listener as a password sign-in, so everything after (the local
  diary moving to the cloud, the profile row, the handle) is unchanged.

### Add it to the website too

The website uses the same Supabase project, so it's a small change in `src/lib/profile.ts` plus the
sign-in form:

```ts
// src/lib/profile.ts
export async function sendEmailCode(email: string, create: boolean, name?: string) {
  if (!supabase) return { error: "Not connected." };
  const { error } = await supabase.auth.signInWithOtp({
    email: email.trim(),
    options: { shouldCreateUser: create, data: create && name ? { name: name.trim() } : undefined },
  });
  return error ? { error: error.message } : {};
}

export async function verifyEmailCode(email: string, token: string) {
  if (!supabase) return { error: "Not connected." };
  const { error } = await supabase.auth.verifyOtp({ email: email.trim(), token: token.trim(), type: "email" });
  return error ? { error: "That code didn't work — check it and try again." } : {};
}
```

In the form, add a "Password / Email me a code" switch; in code mode show email (+ name when creating),
a "Email me a code" button, then a code box with `autoComplete="one-time-code"` and `inputMode="numeric"`,
and a "Send a new code" link. `useAuth()` picks up the new session automatically.

---

## 5. How a bar connects to its guests

Everything here already exists (migrations 010–043; [doc 11](11-rooms-points-venues.md) has the
diagrams). A bar signs up on **bar.bwdy.site**, creates its venue, and is **verified by us**
(`scripts/verify-venue.mjs`) before anything real-world (perks, menus) switches on.

| Touch point | How a guest reaches it | What happens |
| --- | --- | --- |
| **Table menu** (042) | Tap the NFC sticker or scan the QR on the table → `bwdy.site/m/<venue>` | The menu opens in the app (or the website). "You'd probably like" is worked out on the guest's phone. "Log it" writes the drink into their diary with the venue filled in. |
| **Tonight's room** | Scan the room QR / type the code → `bwdy.site/p/<code>` | The guest joins the night: sparks, positive-only vibe, the wall board (if they opt in), the party recap. |
| **House perks** | Staff record visits / spend | A punch-card with up to 3 tiers. Staff-recorded only — a guest can never punch their own card. Lawful only where the jurisdiction row says so. |
| **Guest book** (040) | The guest has actually been there | Staff keep notes/tags on guests they served. The guest can see and delete every note. |
| **Thank the bar** | From the party room | Kudos to staff; the manager sees one team total. |
| **Taste passport** | The guest holds up their phone | Their tastes, shown on screen by them. Nothing is transmitted. |
| **Insights** | Bar dashboard | Counts over the bar's own guests, hidden below 5 people. |
| **Area trends** (039/041) | Bar dashboard | What consenting drinkers in the bar's ~40 km cell are into, 5+ people per trend. |

To set a bar up for tap-to-open menus:

1. Bar dashboard → the venue → **Menu** tab → add items (section, name, price, kind, "no alcohol").
2. Buy NFC stickers (NTAG213 or better). On an Android phone in Chrome, tap **Write an NFC tag** and hold
   a sticker to the phone. Or copy the link and use any NFC-writer app.
3. Print the **QR** from the same tab and put it next to the sticker for phones without NFC.

---

## 6. How the data is linked — and where it must never go

The question for every connection between a guest and a bar is: **who created this data, and did the
guest agree to this bar seeing it?**

| Data | Who creates it | Can the bar see it? |
| --- | --- | --- |
| The guest's diary (`entries`) | the guest | **Never.** No bar-facing function joins `entries` (db:audit checks). |
| That they joined tonight's room | the guest (they chose to join) | Yes — their name, in that room, that night. |
| Visits, tabs, perk claims | the bar's staff | Yes — it's the bar's own record (first-party). |
| Guest-book notes | the bar's staff | Yes, for that bar only. The guest sees and can delete them. |
| What they did at *another* bar | — | **Never.** There is no function that takes two venues. |
| Their tastes | the guest | Only on the guest's screen, when they hold it up. |
| That they opened the menu | — | **No.** The menu read records nothing. |
| Area trends | many consenting guests | Counts only, 5+ people, no names. |
| Insights | the bar's own records | Counts only, splits hidden below 5. |

Why so strict? Because the diary only works if people log honestly, and because India's DPDP Act (and
GDPR) require a specific, informed consent for each purpose. "Your diary is private" and "we sell your
habits to bars" cannot both be true. It's also the product rule: **nothing rewards drinking more** — a
bar that knows your pattern will use it to sell you another round.

The good news: almost everything a bar actually wants can be done **with** consent, as the next section
shows.

---

## 7. Making the bar side more interactive, fun and useful

Ideas in rough order of value, each with how to build it and the line it must respect. None are built
yet unless marked.

### 7.1 One tap at the table: menu + room together
**What:** the table sticker opens the menu *and* offers "Join tonight's room" when one is open.
**How:** add `open_room_code` to `venue_menu()` (a room with `venue_id = v.id` running tonight); the
menu page and `MenuScreen` show a "Join tonight" button → `/p/<code>`.
**Line:** joining stays a separate, explicit tap.

### 7.2 "Share my taste with the bar, for tonight"
**What:** the consented version of "tell the bar what I like". The guest taps a button and the bartender
sees their taste passport on the bar dashboard until closing, then it's gone.
**How:** a `taste_shares` table `(venue_id, guest_id, summary jsonb, expires_at)`; the guest inserts
their own row (the summary is computed on the phone from `tasteProfile()`, the diary itself never
leaves); staff read rows for their venue where `expires_at > now()`; the guest can delete it any time.
Add a db:audit check that nothing joins `entries`.
**Line:** opt-in per visit, time-limited, revocable, one venue, a summary not the diary.

### 7.3 Order from the table (after payments)
**What:** pick from the menu, send the order to the bar's screen, pay in the app.
**How:** needs Stripe (blocked on keys) or a POS integration; orders are a new table the bar confirms.
**Line:** staff confirm and serve; no "order again?" nudges, no "you usually have three".

### 7.4 Menu insights for bars, without tracking anyone
**What:** "Your menu was opened 140 times this week; most taps between 9 and 10pm."
**How:** a counts-only `menu_opens(venue_id, hour_bucket, n)` incremented by `venue_menu()`, shown only
when n ≥ 5 per bucket.
**Line:** a count per hour, never who.

### 7.5 A warmer wall board
**What:** the kiosk celebrates the room, not the spend: "Welcome, first-timers", "Six new drinks tried
tonight", "Dry nights welcome".
**How:** derived from the room's existing sparks (variety, new place, dry day), not from tabs.
**Line:** never a spend figure or a drink count on the wall.

### 7.6 Bar challenges people actually want
**What:** a bar can host a circle-style challenge for its regulars: "Try every cocktail on the new menu
this month", "Five alcohol-free nights with us in October".
**How:** reuse circle challenges (043 kinds: new drinks, new places, dry nights) scoped to a venue room.
**Line:** variety or consistency kinds only; never "most logged".

### 7.7 Events and plans at the bar
**What:** a bar posts a quiz night or a tasting; guests "plan a night" around it and friends join.
**How:** plans (031+) already support venues; add a venue-hosted plan type listed only to people who
follow the bar.
**Line:** an event listing, never an offer (Discover lists the bar, never the deal — 027).

### 7.8 Safer nights, together
**What:** the room offers "Getting home" (rides, share your location with a friend) at closing time, and
the bar can show a "free water here" note on its menu.
**How:** the app's Tonight sheet already exists; surface it in the party room after 11pm.
**Line:** helpful, never preachy; nothing that counts drinks.

---

## 8. Go-live checklist

**Server**
- [ ] Website deployed with this branch (bearer-token support in `supabase-server.ts`).
- [ ] `AI_API_KEY` / `AI_BASE_URL` / `AI_MODEL` set on the website (Ninkasi live).
- [ ] Migrations `042_menus.sql` and `043_challenge_kinds.sql` applied; `npm run db:audit` green;
      `npm run db:verify` green.
- [ ] Supabase: Email provider on, OTP expiry ~10 min, `{{ .Token }}` in the Magic Link and Confirm
      signup templates, custom SMTP connected, `/reset` in the redirect allow-list.
- [ ] `.well-known/assetlinks.json` and `apple-app-site-association` hosted (paths `/p/*`, `/u/*`,
      `/party/*`, `/m/*`).

**App**
- [ ] `test_m_app/env.json` with the project URL, anon key and site URL.
- [ ] Android: a release keystore and `android/key.properties`; build the `.aab` for Play.
- [ ] iOS: Team set in Xcode, Associated Domains (`applinks:bwdy.site`), then `flutter build ipa`.
- [ ] Sign up with an email code on a real phone; log a drink; see it in Supabase.

**Bars**
- [ ] A test venue created on bar.bwdy.site and verified with `scripts/verify-venue.mjs`.
- [ ] Its menu built, an NFC sticker written, the QR printed — tap it with and without the app.
