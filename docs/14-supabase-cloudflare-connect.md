# 14 — Connecting everything: Supabase, Cloudflare, the guest app and the venue app

brewdiary is four windows onto **one** database:

- the **website** (bwdy.site);
- the **venue dashboard** (bar.bwdy.site, which is the same website);
- the **guest app** (`test_m_app/`, iOS and Android);
- the **venue app** (`mobile-bar/`, iOS and Android, phones and tablets).

This chapter explains how they connect, what to set up in **Supabase** (the database and sign-in) and in
**Cloudflare** (the domain, the front door and, if you want, the hosting), and how to check it all works.

1. [The picture](#1-the-picture)
2. [What each piece needs](#2-what-each-piece-needs)
3. [Supabase: the one database](#3-supabase-the-one-database)
4. [Cloudflare: the domain and the front door](#4-cloudflare-the-domain-and-the-front-door)
5. [Hosting the website: Vercel or Cloudflare Workers](#5-hosting-the-website-vercel-or-cloudflare-workers)
6. [App links: a tap on a link opens the right app](#6-app-links-a-tap-on-a-link-opens-the-right-app)
7. [How a night flows between the two apps](#7-how-a-night-flows-between-the-two-apps)
8. [Checklist and troubleshooting](#8-checklist-and-troubleshooting)

Words you might not know are in the [glossary](02-glossary.md). Deploying to Vercel step by step is
[doc 10](10-deploy.md); connecting the guest app is [doc 12](12-mobile-server-and-venues.md).

---

## 1. The picture

```
                        ┌──────────────────────────────────────────────┐
                        │ Supabase: the database, sign-in, photos       │
                        │ row-level security + server functions decide  │
                        │ what each person may read and write           │
                        └───▲──────────────▲──────────────▲────────────┘
                            │ anon key + the person's own login (RLS)   │
      ┌─────────────────────┴───┐  ┌───────┴────────┐  ┌──┴─────────────────────┐
      │ Guest app (Flutter)     │  │ Website         │  │ Venue app (Flutter)     │
      │ iOS + Android           │  │ bwdy.site       │  │ iOS + Android           │
      │ site.bwdy.brewdiary     │  │ bar.bwdy.site   │  │ phones + tablets        │
      └───────────┬─────────────┘  └───────▲────────┘  │ site.bwdy.bar           │
                  │                        │           └──────────┬─────────────┘
                  └─── HTTPS: /api/… ──────┴────── HTTPS: /api/… ─┘
                       (Ninkasi, account deletion, app links)
                                   │
                   Cloudflare in front of bwdy.site: DNS, TLS, firewall, rate limits
                   (and, optionally, the hosting itself: Workers via OpenNext)
```

The rules that make this safe:

- **Every app talks to Supabase directly**, with the public **anon key** and the person's own login.
  Row-level security (RLS) and the server functions decide what each person may see and do, so the
  apps don't have to be trusted.
- **Secrets live only on the website's server**: the AI key, the service-role key, the import token.
  The apps reach them through `/api/…` routes, sending their login token so the server knows who's
  asking.
- **One account works everywhere.** A person signs in with the same email in any app. The same person
  can be a guest at one bar and a server at another; the database knows which is which.

## 2. What each piece needs

| Piece | Setting | Where it goes | Secret? |
| --- | --- | --- | --- |
| Website | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` | hosting env | no (public by design) |
| Website | `AI_API_KEY`, `AI_BASE_URL`, `AI_MODEL` | hosting env | **yes** |
| Website | `SUPABASE_SERVICE_ROLE_KEY`, `SIGNALS_IMPORT_TOKEN` (outside signals, [doc 13](13-area-heat-map.md)) | hosting env | **yes** |
| Website | `ANDROID_CERT_SHA256_GUEST`, `ANDROID_CERT_SHA256_BAR`, `APPLE_TEAM_ID` (app links, §6) | hosting env | no |
| Website | `AI_SUPABASE_*`, `AI_DB_SALT` (the separate AI database, [doc 05](05-the-ninkasi-ai-explained.md)) | hosting env | **yes** |
| Guest app | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SITE_URL` | `test_m_app/env.json` (git-ignored) | no |
| Venue app | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SITE_URL` | `mobile-bar/env.json` (git-ignored) | no |
| Your laptop | `SUPABASE_DB_URL` (runs migrations and checks) | `.env.local` | **yes** |

Both apps build with `flutter build … --dart-define-from-file=env.json`. With no `env.json`, the guest
app runs on the device alone and the venue app runs a labelled demo venue. **Never** put a service-role
key or an AI key in an app: anything shipped in an app can be read out of it.

`SITE_URL` is the website's address (`https://bwdy.site`). Both apps call its `/api/…` routes: the
guest app for Ninkasi and account deletion; the venue app for the manager's advisor (`/api/venue-ai`)
and Ninkasi for hosts (`/api/host-ai`).

## 3. Supabase: the one database

1. **One project** for everything the apps share. (The AI's training data lives in a second, separate
   project; see [doc 05](05-the-ninkasi-ai-explained.md).)
2. **Build the schema:** run `supabase/schema.sql`, then every numbered migration in order, with
   `node scripts/db.mjs <file.sql>`. Each file lands whole or not at all. Before touching the live
   database, `npm run db:local` applies all of them to a throwaway copy and runs both checks.
3. **Check it:** `npm run db:audit` (the shape and every safety rule) and `npm run db:verify` (plays a
   whole night in a transaction it rolls back). Both must be green.
4. **Sign-in** (Authentication):
   - Turn on email codes ([doc 12 §4](12-mobile-server-and-venues.md#4-email-code-sign-in--sign-up)).
     Both apps sign in with a 6-digit code, so nobody has to leave the app to click a link.
   - URL Configuration: Site URL `https://bwdy.site`; Redirect URLs `https://bwdy.site/**`,
     `https://bar.bwdy.site/**`, `http://localhost:3000/**`.
5. **Keys:** Project Settings → API. The **anon** key goes in the website env and both `env.json`
   files. The **service_role** key goes only in the website's server env
   (`SUPABASE_SERVICE_ROLE_KEY`), never in an app and never in a `NEXT_PUBLIC_` variable.
6. **Optional: a custom domain for the API** (for example `api.bwdy.site` instead of
   `<ref>.supabase.co`). It's a paid add-on (about $10 a month per project at the time of writing).
   - Add a CNAME from `api` to `<ref>.supabase.co`, plus the two TXT records Supabase gives you.
   - In Cloudflare, set that CNAME to **DNS only (grey cloud)**. Supabase issues the certificate
     itself, and Cloudflare's proxy gets in the way.
   - Once it's active, update `SUPABASE_URL` everywhere, and add the new `…/auth/v1/callback` next
     to the old one wherever an OAuth provider lists callback URLs.
   - It's cosmetic: nothing in brewdiary needs it.

## 4. Cloudflare: the domain and the front door

Cloudflare sits in front of bwdy.site whichever host runs the website.

1. **Add the domain** to Cloudflare and switch the registrar's nameservers to the two Cloudflare gives
   you. From then on DNS is managed in Cloudflare.
2. **DNS records:** `bwdy.site` (apex), `www` and `bar` all point at the website's host (§5).
   - `bar.bwdy.site` must reach the **same** website: its middleware turns `bar.*` into the venue
     dashboard.
   - If you set up §3.6, `api` points at Supabase (grey cloud).
3. **SSL/TLS:** set mode **Full (strict)**. Turn on "Always use HTTPS". The site already sends HSTS
   (`next.config.mjs`).
4. **Caching:** add a Cache Rule to **bypass cache** for `/api/*` and for signed-in pages. Answers
   there are personal or streamed. Static files (`/_next/static/*`, icons) can be cached.
5. **Rate limits** (Security → WAF → Rate limiting rules). The website has its own in-memory limiter,
   but on a platform with many server instances each one counts separately. Add an edge rule as the
   real limit:
   - `/api/bartender`, `/api/venue-ai`, `/api/host-ai`: about 30 requests a minute per IP;
   - `/api/signals/import`: about 10 a minute per IP;
   - `/api/account/*`: about 5 a minute per IP.
6. **Bots:** turn on Bot Fight Mode, but **skip** `/.well-known/*` and `/api/signals/import`. Apple's
   and Google's link checkers, and your own import tool, must get through.

## 5. Hosting the website: Vercel or Cloudflare Workers

**Option A: keep Vercel** ([doc 10](10-deploy.md)). Point the DNS records from §4 at Vercel, and leave
them **DNS only (grey cloud)**, as Vercel recommends when Cloudflare is the DNS. You still get
Cloudflare's DNS, and the WAF rules apply only to proxied records. So if you want the §4.5 rate limits,
either proxy the records (orange cloud; test the Vercel certificate renewal) or use option B.

**Option B: host on Cloudflare Workers** with the OpenNext adapter (`@opennextjs/cloudflare`). The
Next.js app runs in Cloudflare's Node.js-compatible runtime; every route here already uses the Node.js
runtime, which is what the adapter supports. The outline below follows the adapter's guide; check the
[OpenNext Cloudflare docs](https://opennext.js.org/cloudflare) for the current versions before you
start.

1. Install: `npm install @opennextjs/cloudflare` and `npm install -D wrangler`.
2. Add `wrangler.jsonc` at the repo root:
   ```jsonc
   {
     "$schema": "node_modules/wrangler/config-schema.json",
     "name": "brewdiary",
     "main": ".open-next/worker.js",
     "compatibility_date": "2025-04-01",          // any date on or after 2024-09-23
     "compatibility_flags": ["nodejs_compat", "global_fetch_strictly_public"],
     "assets": { "directory": ".open-next/assets", "binding": "ASSETS" }
   }
   ```
3. Add `open-next.config.ts`:
   ```ts
   import { defineCloudflareConfig } from "@opennextjs/cloudflare";
   export default defineCloudflareConfig();
   ```
   (Add it in the same commit as the install. The website's typecheck reads every `.ts` file, so this
   file breaks the build until the package is installed.)
4. Scripts in `package.json`:
   ```json
   "preview": "opennextjs-cloudflare build && opennextjs-cloudflare preview",
   "deploy": "opennextjs-cloudflare build && opennextjs-cloudflare deploy"
   ```
5. Settings:
   - `NEXT_PUBLIC_*` values are baked in **at build time**, so set them where the build runs.
   - Put secrets on the Worker with `npx wrangler secret put AI_API_KEY` (and the others in §2).
   - For local preview, put them in `.dev.vars` (git-ignored).
6. Domains: in the Worker's settings, add **Custom Domains** for both `bwdy.site` and `bar.bwdy.site`,
   on the same Worker. The middleware tells them apart by host, exactly as on Vercel.
7. Things to know:
   - The in-memory rate limiter counts per Worker instance, so rely on the §4.5 WAF rules.
   - The on-device embedding runtime the bartender route can load (`@huggingface/transformers`) is
     heavy. If the Worker bundle is too big, turn that feature off on Workers (it's optional).
   - Run the doc 10 click-test on the Worker URL before switching DNS.

**Which to pick?** If the site already runs on Vercel, start with option A and grey-cloud DNS.
Everything connects and works the same. Move to option B when you want Cloudflare's firewall and
rate limits in front of every request, or one bill for the domain and the hosting.

## 6. App links: a tap on a link opens the right app

A link like `https://bwdy.site/m/amber-room` (a table's NFC tag or QR) should open the **guest app**
when it's installed, and the browser when it isn't. Staff invite links on `bar.bwdy.site/join/…` belong
to the **venue app**. Android and iOS check this with two small files, which the website now serves for
both hosts (`src/lib/appLinks.ts`, via rewrites in `next.config.mjs`):

| File | Served at | Says |
| --- | --- | --- |
| Android | `/.well-known/assetlinks.json` | bwdy.site → `site.bwdy.brewdiary`; bar.bwdy.site → `site.bwdy.bar`, with each app's signing fingerprints |
| Apple | `/.well-known/apple-app-site-association` | bwdy.site → `/p/*`, `/u/*`, `/party/*`, `/m/*` for the guest app; bar.bwdy.site → `/join/*` for the venue app |

To switch them on, set on the website:

- `ANDROID_CERT_SHA256_GUEST` and `ANDROID_CERT_SHA256_BAR`: each app's SHA-256 signing fingerprint
  (`AB:CD:…`, 32 pairs). Use the **Play Console's App signing** key, and add your upload key too,
  comma-separated, if you install your own builds.
- `APPLE_TEAM_ID`: your 10-character Apple Developer team id.

Until they're set, both files answer 404 and links open in the browser, which is today's behaviour, so
nothing breaks. Both files must load over HTTPS **without a redirect**. If `bwdy.site` redirects to
`www`, or the reverse, the checks fail, so keep the apex serving directly.

The guest app already asks Android to verify `bwdy.site` (`test_m_app/android/…/AndroidManifest.xml`).
On iOS, each app needs the Associated Domains capability (`applinks:bwdy.site` for the guest app,
`applinks:bar.bwdy.site` for the venue app). Invite links in the venue app are planned (PLAN M1.9);
until then staff type the 10-character code, which works the same.

## 7. How a night flows between the two apps

```
 Venue app (staff)                 Supabase                          Guest app / website
 ─────────────────                 ────────                          ───────────────────
 Open tonight's room ───────────►  parties (venue room)
                                                         ◄──────────  tap the table tag / scan QR
                                                                      bwdy.site/m/<slug> → the menu,
                                                                      "join tonight's room"
                                   party_members  ◄─────────────────  joins (their own tap)
 Tonight: sees who joined ◄──────  room_guests()
 Punch a visit / record a tab ───► record_visit() / record_spend()
                                   (staff-only: a guest can never
                                    write their own reward)
                                   perk_status() ──────────────────►  their card fills up
 Hand over the reward ───────────► redeem_perk()  ─────────────────►  "claimed", the clock restarts
 Area map / Ninkasi for hosts ◄──  area_heat_map(), venue_area_signals()
                                   (groups of 5+ who said yes; public facts about places)
```

Each app reads fresh data when a screen opens or is pulled down, and after every action. The shared
database means nothing has to be copied between apps. Live push (a guest joins → staff phone buzzes)
is planned with Supabase Realtime and notifications (PLAN M13).

## 8. Checklist and troubleshooting

**Go-live checklist**

- [ ] Schema plus every migration applied; `db:audit` and `db:verify` green.
- [ ] Email codes on; Site URL and all three redirect URLs set.
- [ ] Website env complete (§2); the doc 10 click-test passes on `bwdy.site` **and** `bar.bwdy.site`.
- [ ] Cloudflare: nameservers switched; SSL Full (strict); cache bypass for `/api/*`; rate-limit rules;
      `/.well-known/*` and the import route excluded from bot checks.
- [ ] Both apps built with a real `env.json`; sign in on each with the same account.
- [ ] Venue app: create a venue → verify it (`node scripts/verify-venue.mjs <slug>`) → open a room.
- [ ] Guest app: tap the table link → join the room → the venue app's Tonight shows them.
- [ ] Punch or record, then hand over a reward: the guest's card updates.
- [ ] App links: the two `/.well-known` URLs return JSON (not 404, not a redirect) on both hosts.

**If something doesn't connect**

| Symptom | Likely cause |
| --- | --- |
| An app says "couldn't reach brewdiary" | Wrong `SUPABASE_URL` or anon key in `env.json`, or the app was built without `--dart-define-from-file`. |
| Ninkasi for hosts falls back to the script | `SITE_URL` is wrong, or the website has no `AI_API_KEY` (the fallback is expected then). A 401 means the app's login expired: sign in again. |
| The venue dashboard shows the diary | `bar.bwdy.site` points somewhere other than the same website, or the host header is being rewritten by a proxy. |
| Sign-in email links go to the wrong place | Redirect URLs are missing `bar.bwdy.site/**`. |
| Links open the browser, not the app | The `/.well-known` files 404 (settings not set), redirect (apex ↔ www), or the fingerprint is the upload key instead of the Play signing key. |
| The import route answers 503 | `SUPABASE_SERVICE_ROLE_KEY` isn't set on the server. |
| A migration "succeeded" but something's off | Run `npm run db:audit`: it checks the rules that tests can't see. |
