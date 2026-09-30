# mobile-bar — the venue staff app: everything that has to be built

**Status (2026-09-30): R1 built, R1.5 under way.** M0–M2 are in this folder (the app, its demo venue and
tests) and in `supabase/044`–`047` (roles, capability gates, every kind of shop); the area heat map is in
`048` and `docs/13`; outside signals `049`; the counter `050`; service `051`; the door `052`; the team —
adding employees with the owner's code, pausing access, history, the time clock — `053` and `docs/17`.
What changed and why, newest first: [`CHANGELOG.md`](CHANGELOG.md). This is the full list of what a
bar / restaurant / shop staff app needs, written after scanning the whole repo: the docs, every venue
migration, the web bar dashboard, the Ninkasi routes and the Flutter user app.

**Standing requirements from the maintainer (apply to every module):**
- **iOS and Android, phones and tablets.** Every screen works in portrait on a phone and in both
  orientations on a tablet; station screens are tablet-first. Nothing platform-only unless it has a
  fallback on the other platform.
- **Everything connects seamlessly.** The guest app, the website, the bar web dashboard and this app
  are windows onto one Supabase database; a change in one shows in the others without a manual step
  (realtime where it matters, refresh-on-open everywhere else).
- **Onboarding a venue is smooth and minimal.** Sign in with an emailed code → name + kind + country →
  you're in, with a working room or till. Everything else (location, verification, perks, menu, team)
  is offered later, one card at a time, never a long form up front.
- **Every kind of place**: bars, clubs, restaurants, cafés, liquor stores, sweet shops, bakeries and
  other shops (047). Words, tabs and legal rules follow the kind.

How to read it:

- `[ ]` is a unit of work. Items are numbered (M4.3) so a session can say "done through M4.6".
- Modules M0–M21 are the push units: one module is built, checked and pushed before the next.
- **Section 4 lists decisions** that change what gets built. Each has a recommendation; the maintainer
  confirms or overrides it before the module that depends on it starts.
- Database changes are new migrations in `supabase/` (048 onward now). `npm run db:local` proves each
  one on a throwaway Postgres first; the maintainer runs them for real, then `npm run db:audit` and
  `npm run db:verify`.
- "Exists" means it is already in the repo and the app reuses it instead of rebuilding it.

Contents: [0 Rules](#0-the-rules-this-app-inherits) · [1 What exists](#1-what-exists-today-from-the-scan) ·
[2 At a glance](#2-the-app-at-a-glance) · [3 Roles](#3-roles-and-access) · [4 Decisions](#4-decisions-recommendation-first) ·
[5 Modules](#5-modules-the-build-list) · [6 Database](#6-database-work-in-order) · [7 Server](#7-server-routes-and-jobs) ·
[8 Legal](#8-legal-and-compliance-to-research) · [9 Design](#9-design-notes-for-a-staff-app) ·
[10 Order](#10-suggested-order) · [11 Blocked](#11-blocked-on-keys-or-resources-not-code) · [12 Words](#12-words-used-here)

---

## 0. The rules this app inherits

The bar app is a new window onto the same database. The house rules in `CLAUDE.md`, `docs/11` and
`docs/12` apply unchanged. What they mean for a staff app:

| Rule | What it means here |
| --- | --- |
| **Nothing rewards drinking more** | No upsell prompts, no "another round?", no per-guest drink counts shown to staff, no happy-hour engine, no staff sales leaderboard. AI tips suggest what fits a guest's taste and always include an alcohol-free option. |
| **A guest can never write their own reward** | Spend, visits and perk claims stay staff-recorded through server functions. Closing a tab records spend on the server; the guest's phone never does. |
| **A guest's diary never reaches a venue** | No bar-facing function joins `entries`. Staff see first-party history (what the guest had *here*) and a taste summary only if the guest pushes one, for one visit. |
| **No cross-venue reads** | Nothing takes two venue ids for guest data, not even for one owner's group of venues. |
| **Counts, not profiles; k = 5** | Manager stats over guests are counts; any split under 5 people shows "—". No churn list ("who stopped coming"), no per-night new/returning split. |
| **Positive only** | Vibe and kudos stay positive. Refusals and cut-offs are recorded against a tab or anonymously, never as a mark on a guest's profile. |
| **One team number for kudos** | A manager sees the team's total thanks, never a per-person table (GDPR employee monitoring; works councils in seven EU states). The same logic rules out any per-staff performance ranking. |
| **Legality lives in the database, deny by default** | Anything that differs by place (perks, service charge, tax, self-ordering, drinking age) is a row in a policy table. No row means no. |
| **Derived, never stored** | Table state, stock on hand, tab totals and stats are computed from ledgers. The exceptions are legal records that must not change later (a closed day's Z report, a receipt), kept as snapshots the way `perk_redemptions` snapshots a claim. |
| **Secrets stay on the server** | The app holds the anon key only. AI, push, payment and service-role keys live on the website's server. |
| **Client-generated ids** | Inserts use a client uuid and no `.select()` (the RLS/RETURNING gotcha). This also makes offline retries safe to repeat. |
| **House style** | Liquid glass, dark by default, one amber accent, no neon/purple, no emoji as UI chrome. Use the `taste-engine` skill for every screen. |

---

## 1. What exists today (from the scan)

### 1.1 What guests get

| Area | Guest features | Where |
| --- | --- | --- |
| Diary | Calendar + log sheet (autocomplete, mood, photos, place, dry day), year mosaic, streaks where dry days count, milestones, Extras (water, cigarettes), gentle limits | web + Flutter (`test_m_app/`) |
| Together | Friends feed, cheers, comments, circles + challenges (variety and consistency, never volume), plans, parties, Split | web + Flutter |
| At a venue | Table menu from an NFC tag / QR (`/m/<slug>`, migration 042) with "you'd probably like" worked out on the phone and "Log it"; join tonight's **room** (sparks for variety, positive vibe, wall board by per-night consent); house-perk progress; thank the staff (kudos); see and delete notes a venue keeps on you | web + Flutter |
| Phone only | Taste card / passport (held up to a bartender, never sent), Tonight sheet (water nudges, getting home), morning after, reminders, home-screen widgets, photo studio | Flutter |
| Ninkasi | AI bartender (`/api/bartender`), scripted fallback, opt-in training corpus in a separate database | web + Flutter |
| Discover | Venues on brewdiary (a listing, never an offer), area and global trends (k-anonymous) | web + Flutter |
| Rights | Export, account deletion, block/report, profile privacy tiers | web + Flutter |

### 1.2 What venues get today (web only: bar.bwdy.site → `/venue`)

| Tab | What it does | Code |
| --- | --- | --- |
| Tonight | Open a room (wall board runs 4/6/8 h), room code / QR / kiosk link, guests in the room, record a tab (`record_spend`), give vibe (`staff_award`), a guest's perk tiers + claim (`perk_status`, `redeem_perk`), my kudos | `src/components/venue/VenueApp.tsx` (`VenueRooms`, `RoomGuestList`, `GuestPerk`, `MyKudos`) |
| Till (stores) | Find a customer by name/@handle, punch their card once a day (`record_visit`) | `StoreCounter` |
| Menu / Shelf | Items (section, name, price, kind, no-alcohol, available), write an NFC tag (Web NFC), QR | `VenueMenu.tsx`, `src/lib/menus.ts` |
| Perks / Card | Up to 3 tiers, visits or spend, jurisdiction rule explained, quiet nights | `VenuePerkEditor`, `QuietNights`, `src/lib/perks.ts` |
| Insights | `venue_insights` v2 (rooms, guests, new/returning under k-anon, perks, tabs, takings, kudos, weekday visits, trend) + Ninkasi advisor (`/api/venue-ai`, totals only) + area trends | `Insights`, `VenueAdvisor.tsx`, `src/lib/venueAdvisor.ts` |
| Guests | Guest book: first-party card + staff notes/tags | `GuestBook.tsx`, `src/lib/guestbook.ts` |
| Team | Roster, add staff by handle (always as bartender), remove, team kudos total | `AddStaff`, `TeamKudos` |
| Setup | Verification request, edit name/city, venue location (coarse geohash), delete (owner) | `VerificationPanel`, `EditVenue`, `VenueLocation` |

Roles today: `owner`, `manager`, `bartender`. A bartender sees only Tonight / Till.

**Not built anywhere:** tables, orders, bar/kitchen screens, bills, payments, stock, rota, time clock,
bookings, push notifications, and any mobile app for venues (`test_m_app` is the guest app only).

### 1.3 The database the bar side already stands on

| Thing | Migrations | Note for the bar app |
| --- | --- | --- |
| `venues` (kind bar/store, country/region, server-set currency, quiet_nights, geohash, verified) | 010, 020–024, 030, 041 | `verified` changes only through `scripts/verify-venue.mjs` |
| `venue_staff` (role, thankable) + `is_venue_staff()` / `is_venue_manager()` | 010, 025 | roles must grow (M1) |
| Rooms: `parties.venue_id`, `board_until`, `room_consent` | 011, 019 | at a bar, a visit = a room joined |
| `point_events` (sparks, vibe) + `staff_award()` | 009, 016, 019 | four fixed staff vibe reasons |
| `spend_events` + `record_spend(room, guest, amount)` | 017 | the guest must be in a venue room |
| `venue_perks` tiers, `perk_status()`, `redeem_perk()`, `perk_redemptions` | 014, 023, 029, 030 | the server re-checks eligibility |
| `jurisdiction_policy` + `perk_policy()` | 021, 028, 030 | deny by default |
| `venue_checkins` + `record_visit()` (stores) | 030 | one per guest per day |
| `staff_kudos`, `thank_staff()`, `my_kudos()`, `venue_kudos_total()` | 025 | managers get one number |
| `venue_insights()`, `k_anon()` = 5 | 026, 030, 038 | counts only |
| `area_taste_trends(geohash)` | 039, 041 | consenting drinkers, ≥5 people per row |
| `venue_guest_notes`, `venue_guest_card()`, `set_guest_note()`, `my_venue_books()` | 040 | first-party CRM; the guest can delete |
| `venue_menu_items` + `venue_menu(slug)` | 042 | not an offer; never in Discover |
| `discover_venues()` | 027, 030 | never joins perks or menus |

Server routes the app can call today: `/api/venue-ai` (manager advisor), `/api/bartender`,
`/api/account/delete`. The website reads the phone's session from `Authorization: Bearer <token>`
(`src/lib/supabase-server.ts`), since a phone has no cookies.

### 1.4 Found while scanning: fix before (or while) building on it

1. **A manager can change a verified venue's country, region, kind and slug.** The `venues_update`
   policy has no column limits, and the guard trigger only protects `verified` and `created_by`.
   Changing the country can switch on perks the real location forbids. Changing the slug breaks every
   NFC tag and QR already printed. Lock these fields after verification (service role only), or send
   the venue back through verification. *(Fixed in 045: locked once verified, with `serves_alcohol` added in 047.)*
2. **Staff roles have holes.** `venue_staff_insert` doesn't check the role, so a manager can add
   someone as `owner`. `venue_staff_delete` lets a manager remove the owner's row. There is no update
   path, so changing a role means removing and re-adding the person. Fix before adding roles.
   *(Fixed in 045: `can_grant_role`, owner row protected, `set_staff_role`.)*
3. **Every staff member can do everything any staff member can.** Nineteen gates call
   `is_venue_staff()`: nine functions (`record_spend`, `staff_award`, `redeem_perk`, `record_visit`,
   `set_guest_note`, `venue_guest_card`, `perk_status`, `room_guests`, `parties_guard_venue`) and ten
   policies (reads on venues, staff, parties, spend, redemptions, check-ins, verifications, menus and
   guest notes, plus the guest-note delete). New
   roles such as kitchen or host would inherit tab, perk and guest-book powers unless these become
   capability checks. *(Fixed in 046: each gate now asks `venue_can()` for one capability.)*
4. **A store can create a "visit" for anyone.** The till searches every user (`search_users`), and
   `record_visit()` needs no proof the guest is there. A punch counts as an interaction, which then
   allows writing a guest-book note on that person. Identify guests by a code they show from their own
   phone instead (M7.2).
5. **Spend needs a room.** `record_spend()` requires the guest to be a member of a venue room, so a POS
   tab can feed perks only if the guest joined tonight's room (decision D3).
6. **The web data export misses the to-try list.** `src/lib/dataRights.ts:30` reads `wishlist`, but
   the table is `wishlist_items`, and the error is swallowed. The Flutter export uses the right table.
   Both exports also leave out perk claims, store punches, kudos you gave, notes venues keep on you,
   and several social tables.
7. **India has one drinking-age row.** `jurisdiction_policy` has `IN` at 21, but each state sets its
   own age (roughly 18 to 25). The door and ID-check features need state rows.
8. **CI never runs Flutter.** `.github/workflows/ci.yml` runs lint/test/build and the database checks;
   `test_m_app`'s tests don't run anywhere automatically. Add jobs for `test_m_app` and `mobile-bar`.
   *(Fixed: a `flutter` job now runs analyze + test.)*

Found once the database checks could run on a local copy (`npm run db:local`), all fixed:

9. **`db:verify` could not get past its first expected refusal.** A refused statement aborted the
   whole transaction, so every later check crashed; the script had also drifted from the schema (a
   verification request without the required contact, rooms opened by an owner who wasn't on the
   team, checks written before claims and the 030 jurisdiction re-check). It now runs each expected
   refusal inside a savepoint and passes end to end.
10. **The guest card never loaded.** `venue_guest_card()` (040) read a column with the same name as
    one of its outputs (`tags`), so every call failed with "column reference is ambiguous". Fixed in
    `supabase/044_fix_guest_card.sql`.
11. **Reporting a person failed in both apps.** They sent an upsert with a conflict target; Postgres
    then also checks the new row against the table's read policies, and `reports` has none by
    design, so every report was refused. Both apps now send a plain insert and treat the duplicate
    error as success (dedup still silent).

---

## 2. The app at a glance

- **Phones** (each person's own phone, iOS or Android, signed in as themselves): servers, bartenders,
  hosts, managers, shop staff.
- **Tablets** (iPad or Android, shared or mounted): bar screen, kitchen screen, host stand, till. Tablets
  rotate; lists become two panes. The kiosk wall board stays a web URL.
- **One app, many modes.** The role decides the home screen; a tablet can be switched into a station.

```
                 Supabase: one database · RLS · RPCs  ◄── the authority on what's allowed
                        ▲                 ▲                    ▲
            anon key + each person's own login (RLS decides per person)
                        │                 │                    │
  ┌─────────────────────┴───┐  ┌──────────┴──────┐  ┌──────────┴─────────────────┐
  │ mobile-bar (Flutter)    │  │ bar.bwdy.site   │  │ guests: test_m_app + web   │
  │ phones: server, bar,    │  │ web dashboard,  │  │ menu, join a table, taste  │
  │ host, manager           │  │ same RPCs       │  │ share, requests, receipts  │
  │ tablets: bar / kitchen  │  └─────────────────┘  └────────────────────────────┘
  │ screen, host stand, till│
  └───────────┬─────────────┘
              │ HTTPS + bearer token
              ▼
  website server: /api/venue-ai (exists) · /api/staff-ai · push sender · receipts (new)
              │
              ▼ LAN / Bluetooth (keeps working offline)
  receipt + ticket printers · cash drawer · NFC tags
```

---

## 3. Roles and access

### 3.1 Roles

| Role | Who | Today |
| --- | --- | --- |
| `owner` | The licensee: the account that created the venue | exists |
| `manager` | Runs the venue | exists |
| `supervisor` | Shift lead: approves voids and comps within limits, cashes up, reassigns tables | new |
| `bartender` | Makes drinks, runs bar tabs | exists (today it means "any staff") |
| `server` | Waiter: tables, orders, bills | new |
| `host` | Door, bookings, waitlist, seating | new |
| `kitchen` | Food tickets, prep, stock counts | new |

A role is per venue: a manager at one bar can be a server at another. In a store (off-licence) the app
calls `bartender` "counter staff"; server, host and kitchen don't apply.

### 3.2 Capability matrix

The database enforces this (M1.5); the app only hides what a role can't use.
● yes · ◐ limited · "ask" = sends a request a supervisor or manager approves on their phone · — no

| Capability | Owner | Manager | Supervisor | Bartender | Server | Host | Kitchen |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Service** | | | | | | | |
| See the floor and tables | ● | ● | ● | ● | ● | ● | — |
| Seat guests; bookings; waitlist | ● | ● | ● | — | ◐ own section | ● | — |
| Open tabs, take orders | ● | ● | ● | ● | ● | — | — |
| Work the bar screen | ● | ● | ● | ● | — | — | — |
| Work the kitchen screen | ● | ● | ● | — | — | — | ● |
| Void own lines before they're sent | ● | ● | ● | ● | ● | — | — |
| Void after sending; comp | ● | ● | ◐ up to a limit | ask | ask | — | — |
| Take payment, close a tab | ● | ● | ● | ● | ● | — | — |
| Refund; reopen a closed tab | ● | ● | — | — | — | — | — |
| Cash up own bank | ● | ● | ● | ● | ● | — | — |
| Day close (Z report) | ● | ● | ● | — | — | — | — |
| 86 an item (mark sold out) | ● | ● | ● | ● | ask | — | ● |
| Open tonight's room; kiosk link | ● | ● | ● | ● | — | ● | — |
| **Guests** | | | | | | | |
| See guests linked to my tables | ● | ● | ● | ● | ● | ◐ names | — |
| Guest card; "usuals here" | ● | ● | ● | ● | ● | — | — |
| Tonight's taste share; AI tip | ● | ● | ● | ◐ when serving them | ◐ when serving them | — | — |
| Write guest-book notes | ● | ● | ● | ● | ● | — | — |
| Give vibe | ● | ● | ● | ● | ● | ● | — |
| Claim a perk; punch a store card | ● | ● | ● | ● | ● | — | — |
| **Back office** | | | | | | | |
| Menu, prices, recipes | ● | ● | — | — | — | — | — |
| Perks, quiet nights | ● | ● | — | — | — | — | — |
| Stock counts; waste log | ● | ● | ● | ● | — | — | ● |
| Receive deliveries | ● | ● | ● | ◐ | — | — | ◐ |
| Stock adjustments; suppliers; purchase orders | ● | ● | — | — | — | — | — |
| Edit the rota; approve time off, swaps, time fixes | ● | ● | — | — | — | — | — |
| Own rota, clock in/out, own tips, own thanks | ● | ● | ● | ● | ● | ● | ● |
| Tip pools and payouts | ● | ● | — | — | — | — | — |
| Live board | ● | ● | ● | — | — | — | — |
| Reports, insights, area trends, advisor | ● | ● | — | — | — | — | — |
| Audit log | ● | ● | — | — | — | — | — |
| Team: invite, change role, remove | ● | ◐ roles below manager | — | — | — | — | — |
| Settings (tax, printers, floor, stations) | ● | ● | — | — | — | — | — |
| Request verification | ● | ● | — | — | — | — | — |
| Delete the venue; export venue data | ● | — | — | — | — | — | — |

"Owner" means the venue's creator (`venues.created_by`). Ownership transfer stays with brewdiary (service
role), as today.

### 3.3 Each role's home screen

- **Owner / manager** (phone or tablet): the live board (M12.1), then floor, approvals, guests in the
  house, stock alerts, who's on shift. Tabs: Now · Floor · Guests · Stock · Team · Reports · Settings.
- **Supervisor:** today's live board, floor, approvals, cash-up.
- **Server:** my tables with timers and requests → a table → its guests (card, usuals, taste share, AI
  tip), order, bill. My shift: clock, tips, thanks.
- **Bartender:** the bar queue and bar tabs at the counter, spec cards, guests at the bar, 86, waste, my
  shift.
- **Host:** tonight's bookings on a timeline, waitlist, free tables, door count.
- **Kitchen:** kitchen queue (tablet), prep list, 86, stock counts.
- **Store counter:** till (guest code → punch card), shelf, stock.

### 3.4 What nobody sees, managers included

- A guest's diary, moods, notes or photos, or anything they did at another venue.
- A list of guests who stopped coming, or of anyone who hasn't been to this venue.
- Who is near the venue right now, or anyone's age, gender or income.
- A per-night new-vs-returning split, or any guest split under 5 people.
- A per-person ranking of staff (thanks, sales or speed).
- A guest's drink count or pace ("usually has three").
- Card numbers: the app never touches card data.

**"The kind of people outside"** is answered by area taste trends: what consenting drinkers in the
venue's ~40 km cell are logging, with at least 5 people behind every row, plus counts of menu opens.
That is the lawful version of the question (M12.6).

---

## 4. Decisions (recommendation first)

| # | Decision | Recommendation | Why / alternative |
| --- | --- | --- | --- |
| D1 | Sharing logic with the user app | Move `test_m_app/lib/core` into a pure-Dart package `packages/brewdiary_core/`, used by both apps through a path dependency, with its parity tests. | Otherwise the logic exists three times (TypeScript + two Dart copies). Needs a machine with Flutter so `test_m_app` stays green. |
| D2 | Shared tablets | Each person signs in once on the device; their session sits in secure storage, unlocked by a personal PIN that never leaves the device. RLS keeps acting as the real person. | The alternative, one "station account" with server-checked PINs, adds a new login surface to secure. |
| D3 | POS tabs and perks | Opening the service day opens tonight's room automatically. A guest who joins a table also joins that room. Closing a tab records spend per linked guest through the room. | Every existing perk, insight and guest-book function keeps working unchanged. Spend without a room would mean rewriting `perk_status`, `venue_insights` and `venue_guest_card`. |
| D4 | Identifying a guest | The guest links themselves: tap the table tag, or show a short-lived code from their app. Staff never search the whole user base to attach someone. Walk-ins without the app get anonymous tabs. | Fixes 1.4 #4; consent is the guest's own tap. |
| D5 | Guest taste for staff | First-party "usuals here" (drink names from this venue's own tabs, no counts) plus the guest-pushed "share my taste for tonight" (`taste_shares`, docs/12 §7.2): opt-in per visit, a summary not the diary, expires, revocable. | This is what the user asked for, done with consent. docs/11–12 must be updated, since they currently say tastes stay on the guest's screen. |
| D6 | AI tips about a guest | A new route `/api/staff-ai` that sees only the menu, the consented taste summary and the usuals, never a name or id, and never writes the training corpus. The existing advisor stays totals-only. | The advisor's prompt promises it never sees individuals; a separate, consented route keeps that promise true. |
| D7 | Per-staff numbers | Team totals everywhere. Per-person figures only where the job needs them (your own cash-up, tips, hours), visible to that person and managers as statements, never ranked. | Same reasoning as the kudos rule (025). |
| D8 | Payments | v1 records how the bill was paid (cash, card, UPI) on the venue's existing machines. Integrated payments come later, with a provider that supports UPI in India. | Unblocks the whole POS now. The docs name Stripe as a placeholder; confirm the provider. |
| D9 | Phone numbers for bookings | Bookings from the user app need none (push). Phone bookings keep a number on that booking only, deleted automatically N days after the date. | The bar layer has no contact fields by design (docs/11 §7). |
| D10 | Refusals and cut-offs | A "no more alcohol tonight" flag on the **tab** that ends with the tab. Refusal and incident logs have no guest id. | Nothing negative may reach a guest's profile (positive-only rule). |
| D11 | Promotions | No happy-hour or discount engine. Price changes are menu edits; comps need a reason and approval; perks stay the only reward, gated by jurisdiction. | Time-limited drink discounts are banned in several markets and conflict with "nothing rewards drinking more". |
| D12 | Ordering from the table | "Call staff" and "bill please" first. Guests ordering alcohol from their phone waits for payments and a new deny-by-default jurisdiction column. | docs/12 §7.3; responsible-service law varies. |
| D13 | Stores (off-licence) | Full liquor-store module (M16): till punch card (with the guest-code fix), shelf, stock by brand and pack, a checkout with an age check, dry days and legal hours, MRP and per-sale quantity limits (deny-by-default rows), excise registers, suppliers. | A store is not a quieter bar (030). The maintainer asked for full store scope. |
| D19 | Other shops | Sweet shops, bakeries, cafés, restaurants and any shop use the same app (047). A place that sells no alcohol is outside alcohol-promotion law, but still deny-by-default on the country. Counters (store, sweet shop, bakery, shop) run a till and punch cards, not rooms. | One app, many kinds; the words follow the kind ("counter", "shelf", "menu"). |
| D20 | The area heat map | Cells of a coarse geohash with 5+ consenting people each: spend as bands, taste mix, busy hours, taste "personas" (what people like), never age, gender, religion or anyone's identity. | "The kind of people outside" answered with consented, k-anonymous aggregates only. |
| D21 | Outside data (web scraping) | Scraping is done by separate tools. What they produce comes in through a server-only import that keeps business-level public facts (venues, events, prices, opening hours, reviews as counts) and drops anything about a person. It feeds the heat map and Ninkasi for hosts. | No workaround for consent: public facts about places, never profiles of people. |
| D14 | Groups of venues | Owners can roll up sales, stock and labour across their venues; guest data never crosses venues. | The guest consented to one venue. |
| D15 | Offline | A local SQLite outbox (for example `drift`), client ids, idempotent server functions. Order entry and LAN printing work offline; payments, AI and reports need a connection. | Bars have basements and bad signal. |
| D16 | Push | FCM (Android, and iOS through APNs), sent from the website server or a Supabase Edge Function; credentials server-side only. | The user app has local notifications only. |
| D17 | Name and distribution | "brewdiary bar" (matches bar.bwdy.site), app id `site.bwdy.bar`; pilots through Play internal testing and TestFlight. | Final naming is the maintainer's call. |
| D18 | The web dashboard | The database stays the single source. Service screens (orders, stations) are phone/tablet-first; back office (reports, menu, stock, rota) comes to bar.bwdy.site later too. | Managers want reports on a laptop. |

---

## 5. Modules: the build list

### M0 — Foundations

- [x] **M0.1** Scaffold the Flutter app in `mobile-bar/` (Android + iOS) with the same toolchain and lints as `test_m_app`.
- [x] **M0.2** App id, name and icons (D17). Android 12+ / iOS 17+ like the user app; phones portrait, tablets rotate.
- [x] **M0.3** Config like `test_m_app/lib/config.dart`: `--dart-define-from-file=env.json`, anon key only, `SITE_URL` for server routes, `env.example.json`, `env.json` git-ignored.
- [x] **M0.4** Demo mode when there's no env: a seeded, clearly labelled demo venue for screenshots, golden tests and demos. (No offline-only production mode: a venue app without the database isn't useful.)
- [x] **M0.5** Shared core (D1): `packages/brewdiary_core` — dates, money (`₹1,23,456`; currency from the venue), the jurisdiction mirror, drink canonicalisation, menus — used by both apps, with the parity tests.
- [~] **M0.6** Theme: reuse the liquid-glass tokens (`test_m_app/lib/ui/theme.dart`), fonts (Hanken Grotesk, Newsreader), Phosphor icons. Add staff tokens: status colours with shapes and labels, a station type scale, and a reduced-blur mode for cheap tablets. *(Done: tokens, fonts, icons, status tones. Left: station type scale, reduced blur.)*
- [~] **M0.7** Data plumbing like `test_m_app/lib/data/base.dart` (`db`, `Rev`, `rows()`), plus a realtime helper and the outbox (M13.3). *(Done: `Backend` with Supabase and demo implementations, `Rev` signals. Left: realtime, outbox.)*
- [~] **M0.8** Shell: role-based navigation; phone tabs and tablet station layouts; states for loading, empty, offline, "couldn't reach brewdiary" with retry, and "your role can't do this". *(Done: phone tabs by capability, loading/empty/retry. Left: tablet station layouts, offline state.)*
- [ ] **M0.9** Translation scaffolding (English first); number and date formats from the venue's country.
- [ ] **M0.10** Crash reporting with no personal data (choose a provider); off in demo mode.
- [x] **M0.11** CI: `flutter analyze` + `flutter test` jobs for `mobile-bar` and `test_m_app` (fixes 1.4 #8).
- [x] **M0.12** `mobile-bar/README.md`: run, build, test.

### M1 — Sign-in, venues, roles

- [x] **M1.1** Sign in with an email code or password, using the same accounts as the website (the patterns in `test_m_app/lib/data/auth.dart`). Password reset finishes on the website.
- [x] **M1.2** Venue picker from `venue_staff` (like `useMyVenues`); remember the last venue; switch venues.
- [x] **M1.3** Create a venue (name, slug, city, bar/store, country/region), showing the jurisdiction note before saving.
- [x] **M1.4** Verification: request, withdraw, status, and what unlocks once verified.
- [x] **M1.5** DB: extend the role check (supervisor, server, host, kitchen). Add `venue_can(venue, user, capability)`, a definer function backed by a seeded, server-only `role_capabilities` table (data, like `jurisdiction_policy`). db:audit pins the critical rows (kitchen can't record spend, and so on).
- [x] **M1.6** DB: close the staff holes (1.4 #2). Only an owner adds or removes managers; nobody can add an owner from the app; a role-change path that can't grant above your own rank.
- [x] **M1.7** DB: lock country, region, kind and slug after verification (1.4 #1).
- [x] **M1.8** DB: move the `is_venue_staff()` gates to capability checks wherever the role matters (1.4 #3).
- [x] **M1.9** Staff invites: by handle (exists) and by an invite link / QR carrying a role and an expiry; accept it in the app. *(053: an invite now makes the person WAITING until a manager approves; adding by handle is gone — the database refuses a direct roster insert.)*
- [x] **M1.10** Team screen: roster, change role, remove, leave the venue, my "take thanks" switch (`thankable`).
- [x] **M1.15** Add an employee with the owner's code (053): name, email, phone, role → a 6-digit code shown once (hashed, email-bound, 48 h, 5 tries); the employee signs in with that email and types it. Codes not typed yet: new code, cancel.
- [x] **M1.16** Pause access (053): a reason and an owner/manager to report to; every call stops at once (only ACTIVE staff count); the app shows who to report to within a minute (on resume and after any refused call, at once); give access again. Nobody pauses themself or the owner.
- [ ] **M1.17** New-device approval: an employee's first sign-in on a new phone waits for a manager's OK (needs a device id on each call; changes the website's sign-in too).
- [ ] **M1.11** Shared-device mode (D2): add a person to this device, PIN switch, auto-lock when idle, a "signed in as" banner, sign everyone out.
- [x] **M1.12** Removal takes effect at once (RLS checks every call). Test it; the app says "you're no longer on this team" and clears cached data. *(053: removal and pausing; db:verify scene 23 proves a paused person can do nothing; the app re-checks and closes the venue.)*
- [ ] **M1.14** Minimal onboarding: first run is sign in → name, kind, country → in. A short "next steps" card list (location, verify, first perk, menu, invite the team) that disappears as each is done; nothing blocks service on day one.
- [x] **M1.13** Capability-aware UI: screens and buttons appear only for roles that can use them; the server refuses the rest anyway.

### M2 — Everything the web dashboard does, on the phone

- [x] **M2.1** Tonight: open a room (board 4/6/8 h), room code, QR, kiosk link, share link.
- [x] **M2.2** Room guests (`room_guests`), give vibe (four positive staff reasons), record a tab (`record_spend`), perk tiers and claim (`perk_status`, `redeem_perk`).
- [~] **M2.3** Store till: punch a card (`record_visit`) using the guest code (M7.2), not a search of all users. *(Built on the name search for now; the guest-code handshake is next.)*
- [x] **M2.4** Menu / shelf editor (`venue_menu_items`, 400-item cap): availability, order, sections.
- [~] **M2.5** Write NFC tags natively (Android and iOS, e.g. `nfc_manager`); share and print the QR. *(QR and share done; native NFC writing left.)*
- [x] **M2.6** Perks editor: up to 3 tiers, visits or spend, alcoholic reward only where allowed, the jurisdiction note; quiet nights.
- [x] **M2.7** Insights (`venue_insights` v2): hidden values show "—", never 0; weekday chart; trend against the previous window; average tab only when there are 5+ tabs.
- [x] **M2.8** Ninkasi advisor (`/api/venue-ai`) with its scripted fallback when the AI is off.
- [x] **M2.9** Area trends: set the venue location once (device → coarse geohash, precision 4); show `area_taste_trends`.
- [x] **M2.10** Guest book: guest card, notes and tags, only for guests who have been here.
- [x] **M2.11** Kudos: my thanks (`my_kudos`), the team total (`venue_kudos_total`).
- [x] **M2.12** Setup: edit name/city, location, verification, delete the venue (owner only).
- [ ] **M2.13** Parity check: the same fixture gives the same numbers on the web and the phone.

### M3 — Floor and tables

- [x] **M3.1** DB: `venue_areas`, `venue_tables` (label, seats, shape, position, active) and a per-table tag code. *(051: areas, tables, an 8-character code per table.)*
- [~] **M3.2** Floor-plan editor: drag tables on a tablet, a simple list on a phone; bar seats are one-seat tables. *(A list editor on phone and tablet (More › Floor setup); drag-to-place plan next.)*
- [x] **M3.3** Table tags: `bwdy.site/m/<slug>/t/<code>`, written to NFC and printed as QR; rotate a code if a tag is lost or abused. *(bwdy.site/t/<code> (shorter than /m/<slug>/t/<code>); QR + share; rotate_table_code().)*
- [x] **M3.4** Live floor: each table's state derived from sessions, orders and requests (free, seated, waiting, served, bill asked, paying, to clear). *(Free / seated / food ready / asking — colour, word and mark.)*
- [ ] **M3.5** Sections: assign servers to areas or tables per shift; transfer a table; merge and split tables.
- [x] **M3.6** Seat a party: covers, server, optional booking; this opens a table session. *(Seat → how many → the tab opens.)*
- [~] **M3.7** Timers on every table: seated for, since the last order, items waiting. *(Minutes seated and the running total on each table; per-item waits on the stations.)*
- [~] **M3.8** Capacity: seats in use against the total, and the licensed maximum occupancy. *(052: the licensed capacity on the venue; the door counts against it.)*

### M4 — Orders and tabs (the POS core)

- [~] **M4.1** DB: `tabs` (on a table session, a bar tab by name, or walk-up pay-now); `order_lines` with name, price and tax class copied at the time of ordering; `order_line_events`, append-only (sent, started, ready, served, void, comp, remake, return). Status is derived in a view. *(051: tabs and order_lines with name/price/station copied at order time; status on the line (not an event ledger yet).)*
- [~] **M4.2** Menu extensions: sizes with their own prices (30/60 ml pegs, pint/half), modifier groups (required/optional, price changes), allergen and diet tags, ABV and pour size, station routing. Still no discount column. *(Allergens (EU 14), the veg/non-veg/egg/vegan mark and station routing done; sizes and modifiers next.)*
- [~] **M4.3** Order screen: sections, search, quick keys, modifiers, seat, course, notes (allergy notes stand out), quantity. Two taps for a common drink. *(Sections, search, quantity, quick notes; seats in the data, courses next.)*
- [x] **M4.4** Send: drinks to the bar, food to the kitchen; hold and fire by course; rush. *(Drinks to the bar, food to the kitchen, per item; hold/fire next.)*
- [x] **M4.5** Void your own lines before sending. After sending, a void needs a reason and supervisor/manager approval above a threshold; a comp needs a reason and approval. All of it is audited. *(Own fresh lines by the server; anything else a supervisor; always a reason.)*
- [x] **M4.6** Repeat a line only when the guest asks. It is never offered as a prompt. *(There is no repeat prompt anywhere.)*
- [ ] **M4.7** Move lines between seats and tabs, merge tabs, hand a tab to another server.
- [ ] **M4.8** Tab flag "no more alcohol tonight" (D10): blocks alcoholic lines on that tab only; ends with the tab.
- [ ] **M4.9** Realtime: new lines reach the stations within about a second; offline lines queue (M13.3).
- [ ] **M4.10** A linked guest's lines become this venue's first-party history for them (feeds "usuals here", M7.4).

### M5 — Bar screen and kitchen screen

- [x] **M5.1** Station mode on a tablet: pick the station(s); a full-screen ticket queue. *(Bar and Kitchen ticket screens; a kitchen-only role lands on theirs.)*
- [~] **M5.2** Ticket card: table, seat, server, items with modifiers, allergy flags, notes, course, an age timer with thresholds, rush. *(Table, items, seat, notes, an age timer that turns a word and colour as it runs long.)*
- [~] **M5.3** Actions: start, bump, partial bump, recall, remake, 86 from the station. *(Start (making), ready, "All ready"; recall/remake next.)*
- [ ] **M5.4** All-day counts per item (what's still to make), for the station only.
- [ ] **M5.5** Expo view for restaurants: every station, assemble and run.
- [ ] **M5.6** "Ready" pings the server (push and in-app).
- [ ] **M5.7** Printer fallback: bar and kitchen ticket printers where there's no screen.
- [ ] **M5.8** Sound and haptics on a new ticket; brightness settings for a dark bar.
- [ ] **M5.9** Bartender tools: spec cards (recipe, glass, garnish, method), batch recipes, prep lists (syrups, garnish).

### M6 — Bill, pay, close, cash-up

- [~] **M6.1** Bill: items, modifiers, taxes by class, optional service charge, rounding. Print it, or share an e-bill. *(The bill and a shareable e-bill (text); taxes and printing wait for the tax profile (M6.2).)*
- [ ] **M6.2** DB: a tax profile per venue. India: food and soft drinks under GST, alcohol outside GST and taxed by the state, on separate lines (confirm with a CA). Tax-inclusive or exclusive prices by country.
- [ ] **M6.3** Service charge as a jurisdiction column. In India it can't be added by default (CCPA guidelines), so it's off by default, removable on request and clearly labelled.
- [~] **M6.4** Split: evenly, by seat, by item, or custom; each part paid separately; optionally send the split to the guests' Split. *(Split evenly 1–6 ways, each part paid separately; by seat/item next.)*
- [x] **M6.5** Record payments (D8): cash, card, UPI, other; a tip per payment; change due. A UPI QR for the exact amount on the bill (a `upi://pay` link), with staff confirming it arrived. *(The maintainer's call: STAFF DECIDE — any method in their own words, any split, an optional tip; brewdiary records it and never checks it.)*
- [~] **M6.6** DB: `close_tab()` on the server checks paid ≥ total, assigns the invoice number (sequential per financial year), records spend per linked guest (verified venues; D3), frees the table and triggers stock depletion (M9). *(close_tab() snapshots the subtotal and records the payments; it deliberately does NOT enforce paid ≥ total (staff decide).)*
- [ ] **M6.7** Refund, and reopen a closed tab: manager only, with a reason, audited.
- [ ] **M6.8** Receipts: printed (ESC/POS) and in the linked guest's app with "add these to my diary"; the guest writes their own entries. No offers or marketing on receipts.
- [ ] **M6.9** Cash drawer: float, pay-ins and pay-outs, drops, a blind count at close, expected against counted, variance with a reason.
- [ ] **M6.10** X report during service. Z report at day close, stored as a snapshot that can't change (a legal record). Per-server cash-up where servers hold their own bank.
- [ ] **M6.11** What a bill must show in each country (India: GSTIN, FSSAI licence number, invoice numbering; confirm).

### M7 — Guests at the table

- [ ] **M7.1** A guest joins a table (D4): they tap the table tag, the user app or website asks "Join table 7 at <venue>?", and yes joins tonight's room and links them to the table session (`join_table(code)`). They can leave any time.
- [ ] **M7.2** Guest code: the user app shows a short-lived QR ("my card") that staff scan to link a guest at the bar or punch a store card. This replaces searching everyone (1.4 #4).
- [ ] **M7.3** Staff see linked guests at their tables by name and open the guest card (first-party visits, last seen, perk tiers, notes and tags).
- [ ] **M7.4** "Usuals here" (D5): drinks this guest had at this venue, names only, never counts.
- [ ] **M7.5** Taste share for tonight (D5): a summary the guest pushes, "alcohol-free tonight" first, optional allergies and diet. It expires at close or the next morning, and the guest can revoke it. Staff can only read it.
- [ ] **M7.6** Table requests: call staff, bill please, water. Only linked guests can send them; rate-limited; they go to the assigned server (falling back to the area) and staff acknowledge them.
- [ ] **M7.7** Perks at the table: tiers, quiet-night weighting, claim (`redeem_perk`).
- [ ] **M7.8** Vibe and thanks as today (`staff_award`, `thank_staff`).
- [ ] **M7.9** Guest-book reminders when a noted guest links ("celebrating", "likes the corner"). The guest can still see and delete every note.
- [ ] **M7.10** Walk-ins without the app get anonymous tabs; everything except the guest features works.

### M8 — Ninkasi for staff (AI)

- [~] **M8.1** The advisor on mobile for managers (M2.8), plus a pre-shift briefing built from totals, the 86 list, bookings and events. *(Advisor and briefing done (`/api/host-ai`, the "Before your shift" card); bookings wait for M11.)*
- [ ] **M8.2** Guest tip card for servers and bartenders (D6): 1–3 picks from this menu that match the consented taste and usuals, always one alcohol-free option, an optional food pairing.
- [ ] **M8.3** Route `/api/staff-ai` on the website: rate-limited, size-capped, reads the taste share with the staff member's own token (so RLS applies), sends the model no name or id, never writes the training corpus.
- [ ] **M8.4** Offline / no-key fallback: a matcher on the device (like `menuPicks`, driven by the taste summary).
- [ ] **M8.5** Guardrails and evals in `ninkasi-ai/eval`: never "another round", never comments on how much anyone has had, never guesses age, gender or religion, refuses to profile beyond the share, always offers an alcohol-free option.
- [ ] **M8.6** Staff questions about the menu ("what's in it", allergens), answered from the recipes (M9) only.
- [ ] **M8.7** Reorder suggestions from par levels and sales (deterministic first, AI wording optional).
- [ ] **M8.8** An end-of-night summary for managers.
- [ ] **M8.9** Switches: off until `AI_API_KEY` is set, opt-in per venue, a kill switch.
- [x] **M8.10** Ninkasi for hosts: one assistant for every role that knows the venue's live state (open room, 86 list, menu, stock, bookings), the area heat map and the imported outside signals (D21), and answers "what should I know tonight?" — events nearby, what the area is drinking, what's running low. *(A "Before your shift" card on Tonight and the Till, and a question screen. The briefing is built on the phone, so it's instant, free and offline; the AI is asked only for questions. Rules twinned in `src/lib/hostAdvisor.ts`.)*
- [x] **M8.11** A heat-map guide: Ninkasi explains the map in plain words ("the cells east of you lean coffee and dessert on weekday evenings; spend there is mostly ₹500–1,000") and suggests menu or hours changes, never targeting a person. *(`areaGuide()`, under the map and in the manager's shift briefing.)*

### M9 — Inventory

- [ ] **M9.1** DB: `inventory_items` (category; unit and pack such as a 750 ml bottle, 30 L keg or case of 24; cost; supplier; barcode; par; reorder quantity; alcohol flag and ABV) and `inventory_locations` (cellar, bar, kitchen).
- [ ] **M9.2** Recipes: a menu item or size → ingredients and quantities; batch items made from other items (syrups).
- [ ] **M9.3** Stock ledger `stock_movements`, append-only: received, used by sales, waste, comp, staff drink, transfer, count adjustment. Stock on hand is derived from it.
- [ ] **M9.4** Deplete when a line is sent and reverse it on a void (recommended; the alternative is at close).
- [ ] **M9.5** Counts: full and spot counts by location, part bottles (tenths now, weight later), kegs, blind counts, approval.
- [ ] **M9.6** Variance: expected against counted by item and category, pour cost %, shrinkage flags, by period.
- [ ] **M9.7** Receiving: against a purchase order or ad hoc, barcode scan, invoice photo (a storage bucket with RLS), a cost-update rule (last cost or average; decide).
- [ ] **M9.8** Suppliers and purchase orders: suggested from par levels, shared as a PDF or message, partial deliveries, backorders.
- [ ] **M9.9** Alerts: below par → manager. Out of stock → automatically 86 the menu items that need it, and bring them back on delivery.
- [ ] **M9.10** Waste log with reasons (spill, breakage, returned, expired, over-pour).
- [ ] **M9.11** Staff drinks log (the venue's own policy).
- [ ] **M9.12** Costing: item cost from the recipe, margin, menu engineering (popularity against margin). Managers only.
- [ ] **M9.13** Excise stock registers where required (India, state by state; research) and CSV import/export.

### M10 — Staff operations

- [ ] **M10.1** Rota: a weekly grid by role and area, publish, availability, time-off requests and approvals, shift swaps with approval, templates, a labour budget.
- [~] **M10.2** Time clock: in/out and breaks; corrections as append-only events with a reason; timesheet export for payroll. If the venue turns it on, location is checked only at the moment of clocking in, never tracked. *(053: clock in/out; a manager clocks out someone who forgot (logged); hours per person since a date, in name order, never ranked. Breaks, corrections and the export are next.)*
- [ ] **M10.3** Tips: from payments; pooling rules (hours, points or role) and tip-outs to the bar and kitchen. Each person sees their own statement; no ranking.
- [ ] **M10.4** Certificates: responsible-service and food-safety certificates with expiry reminders; an onboarding checklist.
- [ ] **M10.5** Messages: pre-shift notes, announcements with read receipts, handover notes, the 86 list.
- [ ] **M10.6** Kudos as today (M2.11); never per person for managers.
- [x] **M10.7** Offboarding: removing someone ends their access; the records they made stay. *(053: removal or a pause ends access at once; the team's history keeps who did what.)*
- [ ] **M10.8** Minimum age to serve alcohol by jurisdiction (research): warn before putting an under-age staff member on the bar.

### M11 — Bookings, waitlist, door

- [ ] **M11.1** DB: `reservations` (in-app or phone booking; party size, time, duration, area, table, notes; status booked / confirmed / arrived / seated / no-show / cancelled).
- [ ] **M11.2** Host screen: today's bookings on a timeline, clashes, seat from a booking.
- [ ] **M11.3** Contact data (D9): in-app bookings use push; phone numbers live only on the booking and are deleted automatically.
- [~] **M11.4** Waitlist: add, quoted wait, notify (push for app users; SMS/WhatsApp needs a provider), seat. *(Host waitlist: name or "party of 4", quote, seat, gone — forgets names within a day. Notify-by-push next.)*
- [ ] **M11.5** Deposits and no-show fees: blocked on payments.
- [~] **M11.6** Door: a live headcount against the licensed capacity; an ID-check tally (passed/refused counts only, with no photo, date of birth or ID number). *(052: the shared headcount, in/out and groups, amber at 90% and red at full, undo; the ID tally is next.)*
- [ ] **M11.7** Events: tonight's room, venue-hosted plans (docs/12 §7.7), guest lists with host approval (007). A listing, never an offer.
- [ ] **M11.8** Book from the user app (M17.8).

### M12 — Manager: live board, reports, insights

- [~] **M12.1** Live now: covers, occupancy against capacity, open tabs, sales so far, tickets waiting and average ticket time per station, staff on shift and labour cost so far, the 86 list, low stock, bookings in the next 2 hours, waitlist, approvals waiting, unanswered table requests, incidents. *(Live board: open tabs, covers, sales and tips today, bar/kitchen waits and times, voids, requests, calls, waitlist, the payment mix.)*
- [ ] **M12.2** Sales: by day, hour and weekday; by category and item; by area; by payment type; taxes; service charge; comps, voids and refunds; covers; average check per cover (hidden under 5 tabs); table turns; dwell time.
- [ ] **M12.3** Labour: hours, cost %, overtime, rota against actual.
- [ ] **M12.4** Stock: variance, pour cost, waste, shrinkage, stock value, days on hand.
- [ ] **M12.5** Guests: the existing k-anonymous insights, the share of covers from linked guests, perk use, booking no-show rate, the team kudos total.
- [x] **M12.10** The area heat map (D20): cells at geohash precision 5–6 around the venue, each shown only with 5+ consenting people; layers for footfall by hour, spend band, taste mix and taste personas; a plain guide under the map. *(048; `docs/13-area-heat-map.md`. A venue shares spend only if it shares its own; the web dashboard map is still to do.)*
- [x] **M12.11** Outside signals (D21): events, openings, holidays and public venue facts from the import, on the map and in the briefing. *(049, `docs/13` §9: an import route for tools, a CLI for files, one cleaner, a DB guard. Shown under the map; the map overlay and the briefing are next.)*
- [ ] **M12.6** The area ("the kind of people outside"): area taste trends (5+ people per row) and menu opens by hour (docs/12 §7.4, counts of 5+). Never who is nearby, never demographics.
- [ ] **M12.7** Exports: CSV/PDF, an accountant export, a scheduled emailed summary (server-side).
- [ ] **M12.8** A roll-up for owners of several venues (D14).
- [ ] **M12.9** Charts follow the `dataviz` skill; hidden numbers show "—".

### M13 — Notifications, offline, printing, devices

- [ ] **M13.1** DB `staff_devices` (push tokens per person, venue and platform) and a server-side sender (D16).
- [ ] **M13.2** Pushes: order ready → server; table request → assigned server; booking arriving; approval needed → supervisor/manager; low stock → manager; rota published; announcements. Silent when off shift.
- [ ] **M13.3** Offline outbox (D15): local SQLite, client ids, idempotent server functions, a sync indicator, clear conflict rules (the server decides anything about money).
- [ ] **M13.4** Printing: ESC/POS over the LAN (port 9100) and Bluetooth; receipts and bar/kitchen tickets; 58/80 mm paper; a test page; cash-drawer kick. Many printer code pages lack the ₹ sign, so print it as an image or fall back to "Rs.".
- [ ] **M13.5** NFC writing and QR printing (M2.5, M3.3).
- [ ] **M13.6** Shared tablets: register a device as a station; a kiosk / guided-access setup guide; keep stations awake.

### M14 — Responsible service and compliance

- [ ] **M14.1** The tab flag (M4.8), a staff reminder to offer water on long sessions (by time, never by drink count), and a "free water here" note on the menu (docs/12 §7.8).
- [ ] **M14.2** At closing, a prompt for staff to offer help getting home (the user app's Tonight sheet).
- [ ] **M14.3** Refusal log (anonymous: reason category, staff, time) and incident log (venue level); often a licence condition.
- [ ] **M14.4** ID-check tally (M11.6) and the occupancy cap.
- [ ] **M14.5** Licences: numbers and expiry reminders (bar licence, excise, FSSAI), shown where the law says.
- [ ] **M14.6** No promotions engine (D11).
- [ ] **M14.7** New jurisdiction columns, deny by default: service charge by default, guests self-ordering alcohol, minimum age to serve, and state drinking-age rows (1.4 #7).

### M15 — Setup and settings

- [ ] **M15.1** Venue profile; trading hours and the service-day cut-off (a night ending at 4 am belongs to the day before).
- [ ] **M15.2** Jurisdiction shown read-only with its plain-English note; currency is set by the server.
- [ ] **M15.3** Tax profile, service charge, invoice settings (GSTIN, prefix, financial year).
- [ ] **M15.4** Floor plan, stations and routing, printers, table tags.
- [ ] **M15.5** Room defaults (board hours, open with the day), quiet nights, perks.
- [ ] **M15.6** Roles and capabilities (read-only view), devices, notifications.
- [ ] **M15.7** Export the venue's own business records; delete the venue (owner, with a confirmation step).

### M16 — Shops: liquor stores, sweet shops, bakeries, any shop

- [~] **M16.1** Till: guest code → punch card once a day (`record_visit`); perk status and claim (visits only, never an alcoholic reward). *(Till built on name search; guest code next.)*
- [~] **M16.2** Shelf (menu), stock (M9), staff (M10), insights. *(Stock done for counters (050): products, ledger, receive/adjust, suppliers.)*
- [x] **M16.3** No tables, rooms, kiosk, tabs or spend perks. The database refuses rooms for every counter kind (047).
- [x] **M16.4** Every kind of shop (047): sweet shop, bakery, café, restaurant, club, other shop; `serves_alcohol` decides the legal class; the web dashboard and the app both offer them.
- [x] **M16.5** Liquor store checkout: scan or pick by brand and pack size, the bill, how it was paid; stock moves with it.
- [x] **M16.6** Age check at the counter: a prompt when a line is alcohol, "ID checked" recorded on the sale (never the ID itself), refusals logged with no guest id.
- [x] **M16.7** Dry days, legal sale hours and per-sale quantity limits as deny-by-default rows per state; the till refuses outside them. *(The tables ship EMPTY on purpose: a state opens when someone researches it and adds rows with sources — docs/15 §3.)*
- [x] **M16.8** MRP: a sale above the printed maximum retail price is refused (India).
- [x] **M16.9** Excise registers: daily stock and sales by brand and pack, exported in the state's format.
- [~] **M16.10** Suppliers, purchase orders and deliveries (shared with M9). *(Suppliers and deliveries done; purchase orders next.)*
- [~] **M16.11** Sweet shops and bakeries: sale by weight (per kg), made-today batches and waste, festival pre-orders. *(Sale by weight and waste done; batches and pre-orders next.)*

### M17 — Guest side (user app + website) the bar app needs

- [~] **M17.1** Per-table links: website route `/m/<slug>/t/<code>`, user-app deep-link parsing (`menuSlugFrom`), and the `assetlinks.json` / `apple-app-site-association` paths. *(The two app-link files are served for both apps from env (`src/lib/appLinks.ts`, docs/14 §6); per-table routes still to do.)*
- [~] **M17.2** "Join this table" with plain consent wording, and "Leave". *(Ordering from the table: a request the staff accept onto the tab or decline with a reason; signed-in, rate-limited; the venue switches it on.)*
- [x] **M17.3** The menu and tonight's room in one tap (docs/12 §7.1). *(The table link opens the menu with the table known.)*
- [ ] **M17.4** Taste share for tonight from the taste card (M7.5): pick the lines, alcohol-free first, allergies; see and revoke it.
- [ ] **M17.5** Guest code / "my card" QR (M7.2).
- [x] **M17.6** Table requests: call staff, bill please, water. *(Call staff, bill please, water — once however often it's tapped.)*
- [ ] **M17.7** "My tab" (your own lines only), a receipts inbox with "add to diary", send a split to Split.
- [ ] **M17.8** Book a table from the venue's page. Discover stays a directory, never an offer.
- [ ] **M17.9** Data rights: tabs, receipts, bookings, table links and taste shares in export and deletion (and fix 1.4 #6).
- [ ] **M17.10** Parity: each guest-side feature on both the website and the Flutter app.

### M18 — Security and privacy

- [ ] **M18.1** RLS on every new table. Ledgers (order events, payments, stock movements, time-clock corrections, audit log, refusals) get no client write policy; server functions only.
- [ ] **M18.2** Capability checks in every new server function (M1.5, M1.8).
- [~] **M18.3** `venue_audit_log`: voids, comps, refunds, reopened tabs, price changes, role changes, stock adjustments, drawer variances, settings. Append-only; managers read it. *(053: the team's history — every roster change written by a trigger, whichever app made it. The rest is next.)*
- [~] **M18.4** db:audit invariants for everything new (done through 053; plus `db:contract`, which checks every app call against the schema): no client write on ledgers; no bar-facing function joins `entries`; no guest-data function takes two venue ids; k-anon still 5; taste shares expire; refusal and incident tables have no guest id; kudos stay a total; no per-staff ranking function; venue fields locked after verification.
- [ ] **M18.5** db:verify plays a whole service night in a rolled-back transaction (open the day → seat → order → send → bump → serve → split → pay → close → spend → perk → Z → stock → variance), plus the refusals: kitchen can't record spend, a guest can't punch their own card, a server can't approve their own void.
- [ ] **M18.6** Rate limits and abuse: table requests, joining a table, short-lived guest codes, rotated table codes.
- [ ] **M18.7** Device security: PINs local only with lockout, tokens in secure storage, auto-lock, sign out all devices.
- [ ] **M18.8** Retention: booking phone numbers, audit logs, time clock, receipts. A staff privacy notice (employee data) and guest notices (DPDP Act, GDPR).
- [ ] **M18.9** Payments: never touch card numbers (PCI); terminals and the provider do.
- [ ] **M18.10** A security review before the first pilot (`/security-review`) and a short threat-model note.

### M19 — Tests and CI

- [ ] **M19.1** Unit tests for the pure logic: bill maths, taxes, rounding, splits, tip pools, stock depletion, variance, the permission matrix, the perk-policy mirror.
- [ ] **M19.2** Parity tests wherever Dart mirrors `src/lib`.
- [ ] **M19.3** Widget and golden tests: each role's home, the order screen, a station screen, the bill, the floor.
- [ ] **M19.4** Integration tests against a local Supabase (CLI + Docker) with every migration applied.
- [ ] **M19.5** Offline and sync tests (airplane mode mid-order, repeated retries).
- [ ] **M19.6** Load test: a Friday night (hundreds of lines an hour per venue, several stations, realtime).
- [ ] **M19.7** Accessibility: text scaling, contrast, screen readers, colour-blind-safe states.
- [ ] **M19.8** Device matrix: cheap Android tablets (common in bars), older iPads, small phones.
- [ ] **M19.9** CI jobs (M0.11) alongside the existing database checks.

### M20 — Docs

- [ ] **M20.1** `docs/13-bar-app.md` in plain English, with each workflow as a diagram; new glossary terms.
- [ ] **M20.2** Update `CLAUDE.md` (a `mobile-bar/` row, roles, new libs and migrations) and docs/11–12 where rules change (taste shares, AI about a consenting guest, roles).
- [ ] **M20.3** Keep `mobile-bar/README.md` current (run, build, test).
- [ ] **M20.4** A printable one-page quick start per role, and a venue onboarding guide.
- [x] **M20.5** Connecting everything: one Supabase project, Cloudflare in front (DNS, hosting the website and its API routes, secrets, rate limits, app links), and how the guest app, the website and this app reach it. *(`docs/14-supabase-cloudflare-connect.md`.)*
- [~] **M20.6** The heat-map guide and the outside-data import, in plain English. *(Heat map done: docs/13.)*

### M21 — Release and pilot

- [ ] **M21.1** Store accounts, signing keys, listing text, age rating, and review notes explaining it's a business tool.
- [ ] **M21.2** Distribution: Play internal testing and TestFlight for pilots; public or private listing decided later.
- [ ] **M21.3** A pilot venue: set up, train, watch a real night, fix, repeat.
- [ ] **M21.4** Feature switches per venue; the web dashboard keeps working alongside the app.
- [ ] **M21.5** Versioning, crash monitoring, a support channel.

---

## 6. Database work, in order

Numbering continues after `047_all_shops.sql`. Each file lands whole or not at all, and the
maintainer runs it; `npm run db:local` proves it applies to a fresh schema and passes db:audit and
db:verify first. Every migration also gets a db:audit section, a db:verify scene, a `src/lib` mirror
where the website needs one, and Dart parity tests where the app mirrors logic.

| Migration | Adds |
| --- | --- |
| `044_fix_guest_card.sql` | **Done.** Fixes the ambiguous `tags` in `venue_guest_card` (1.4 #10) |
| `045_staff_roles.sql` | **Done.** New roles, `role_capabilities`, `venue_can()`, the staff RLS fixes, venue fields locked after verification, staff invites, `set_thankable` |
| `046_capability_gates.sql` | **Done.** Existing `is_venue_staff()` gates moved to capability checks |
| `047_all_shops.sql` | **Done.** Eight kinds of venue, `serves_alcohol`, legal class, counters |
| `048_area_map.sql` | **Done.** The area heat map: two guest opt-ins + a venue opt-in, cells of 5+ people and 3+ venues, rounded to 5s, fixed windows, spend bands (D20) |
| `049_area_signals.sql` | **Done.** Server-only outside signals: places and happenings, never people; cleaned twice; staff read their own area (D21) |
| `050_shop_counter.sql` | **Done.** The counter: products (MRP), stock ledger, suppliers, `ring_sale()`, retail alcohol rules + dry days (deny-by-default), the excise register |
| `051_service.sql` | **Done.** Areas, tables and table codes; tabs, lines, stations, bills (staff-recorded payments), the table link (requests, calls), the waitlist, the live board, diet marks and allergens |
| `052_door.sql` | **Done.** The licensed capacity and the door's headcount: a ledger of taps (counts, never people), `door_tick()` for the door roles, `door_count()` for tonight |
| `053_staff_access.sql` | **Done.** Staff status (waiting / active / paused); adding an employee with the owner's code; invites wait for a yes; no direct roster inserts; pausing with a reason and who to report to; the team's history (trigger); the time clock; the venue's details for a person |

The rows below are the plan as first written; their numbers shift as files land.

| `052_service_day.sql` | Service days (open/close, auto-opened room), table sessions, `join_table()`, linked guests, guest codes |
| `053_menu_v2.sql` | Sizes, modifiers, allergens, stations and routing (still no discount column) |
| `054_orders.sql` | Tabs, order lines, line events, the status view, the tab flag |
| `055_payments.sql` | Tax profiles, service charge, payments, `close_tab()`, invoice numbers, receipts, refunds |
| `056_cash.sql` | Drawers, cash movements, the day-close snapshot (Z) |
| `057_guest_link.sql` | `taste_shares`, the usuals function, table requests |
| `058_inventory.sql` | Items, locations, recipes, stock movements, counts, suppliers, purchase orders, deliveries |
| `059_labour.sql` | Rota, time clock, availability, time off, swaps, tip pools |
| `060_bookings.sql` | Reservations, waitlist, door tallies |
| `061_compliance.sql` | Refusal log, incidents, licences, new jurisdiction columns and state rows |
| `062_devices_audit.sql` | Staff devices, the audit log |
| `063_reports.sql` | Live board, sales, labour and stock reports (derived), menu opens |

---

## 7. Server routes and jobs

| Route / job | Status |
| --- | --- |
| `/api/venue-ai` (manager advisor, totals only) | exists |
| `/api/host-ai` (Ninkasi for hosts: the shift companion, every role) | **done** (M8.10) |
| `/api/staff-ai` (guest tip from a consented share) | new (M8.3) |
| Outside-data import (scraped public facts → `area_signals`): `/api/signals/import` + `npm run signals:import` | **done** (D21) |
| Push sender | new (M13.1) |
| Receipt PDF / email | new (M6.8) |
| Scheduled reports | new (M12.7) |
| Payment webhooks | later (D8) |
| `/api/account/delete` | exists; extend to staff and venue data |

---

## 8. Legal and compliance to research

Research before building the feature, not after. Each finding becomes a row or column in a policy table
with its source, the way `jurisdiction_policy` works.

**India first**
- [ ] Tax on bills: GST on food and soft drinks (the rate depends on the kind of establishment), state tax on alcohol outside GST, invoice format and numbering. With a CA.
- [ ] Service charge: the CCPA guidelines (2022) say it can't be added by default; confirm the current position after the 2025 court ruling.
- [ ] FSSAI licence number on bills; licence display.
- [ ] State excise: stock registers and sales reports, bar licence conditions, permitted hours.
- [ ] Drinking age by state; minimum age to serve alcohol.
- [ ] Labour: the labour codes and state Shops & Establishments rules (hours, overtime, night work, weekly off).
- [ ] DPDP Act 2023 and its Rules: notices and consent for guests (table link, taste share, bookings) and for staff (time clock, tips).

**Before opening any other market**
- [ ] Happy-hour and price-promotion bans (Scotland, Massachusetts and others).
- [ ] Certified cash-register rules: some countries require certified or fiscal POS software (for example Germany, France, Italy, Austria, Poland). A POS can't launch there without it.
- [ ] Refusal records, tip-pooling law (for example the US FLSA), GDPR employee monitoring and works councils for any per-staff data.
- [ ] Whether guests may order alcohol from their own phone.
- [ ] App-store rules for alcohol-related apps.

---

## 9. Design notes for a staff app

- Dark by default (bars are dark); amber marks the one action that matters.
- Liquid glass on phones; a solid-fill mode for cheap tablets, where blur is expensive.
- Big targets (at least 48 dp; main actions 56 dp), actions at the bottom, one-handed use.
- Status is colour + shape + word, so it's colour-blind safe. Amber stays the accent, never a status.
- Tabular numbers; station timers readable from a metre away.
- Stations in landscape; phones in portrait.
- Sounds and haptics that can be switched off.
- No emoji as UI, no neon or purple, no celebration for selling more.
- Use the `taste-engine` skill for every screen and the `dataviz` skill for every chart.

---

## 10. Suggested order

| Release | Modules | What a venue gets |
| --- | --- | --- |
| R1 ✓ | M0, M1, M2, M16.4 | Everything the web dashboard does, from a phone; roles fixed; every kind of shop |
| R1.5 | M12.10–11, M8.10–11, M20.5–6 | The area heat map, outside signals, Ninkasi for hosts, the connection docs |
| R2 ◐ | M3, M4, M5, M6 (record-only payments), M13 (printing, push, offline) | A real night of service: tables, orders, stations, bills — the core is built (051); printing, push, offline next |
| R3 | M7, M8, M17 | Guests link themselves; usuals, taste shares, AI tips; table requests; receipts |
| R4 | M9 | Stock, recipes, counts, variance |
| R5 | M10, M11 | Rota, time clock, tips; bookings, waitlist, door |
| R6 | M12, M14, M15, M16 | Full manager reports, compliance, settings, store mode |
| R7 | Integrated payments, e-invoicing and excise exports, accounting | Needs provider keys and legal work |
| Always | M18, M19, M20, M21 | Security, tests, docs and pilots alongside every release |

---

## 11. Blocked on keys or resources (not code)

- [x] **A Flutter SDK in the cloud environment.** Available now; CI runs `flutter analyze` and `flutter test` for both apps.
- [ ] A payments provider account and keys (D8).
- [ ] Push: a Firebase project and an Apple Developer account (APNs key).
- [ ] An SMS/WhatsApp provider for waitlist messages to people without the app (optional).
- [ ] `AI_API_KEY` on the website for live AI (the fallbacks work without it).
- [ ] Play Console and Apple Developer accounts; signing keys.
- [ ] Test hardware: an ESC/POS printer (LAN or Bluetooth), NFC stickers (NTAG213 or better), an Android tablet.
- [ ] A pilot venue, and a CA / lawyer for the India tax and excise items.

---

## 12. Words used here

| Word | Meaning |
| --- | --- |
| Tab | The running bill for a table, a seat at the bar, or a named person. |
| Cover | One guest being served (a table of four is four covers). |
| 86 | Sold out: the item disappears from the menu until it's back. |
| Station / BDS / KDS | A screen where drinks (bar) or food (kitchen) tickets queue up and get "bumped" when ready. |
| Expo | The person or screen that assembles a table's food before it goes out. |
| Void / comp | A void removes a line (a mistake); a comp gives it free (making up for a problem). Both need a reason. |
| X / Z report | Mid-shift sales summary (X); end-of-day close (Z) that can't be changed afterwards. |
| Par | The stock level you want on the shelf; below it, you reorder. |
| Variance / pour cost | The gap between what sales say you used and what the count says you have; drink cost as a % of its price. |
| Peg | A measured pour of spirit (30 or 60 ml in India). |
| First-party | Data a venue created itself about its own guests (their tabs and visits there), as opposed to a guest's own diary. |
