# Changes to the venue app

What changed in `mobile-bar/` (and the database and website work it needed), newest first, with the
goal behind each change. The full build list is [`PLAN.md`](PLAN.md); how the pieces fit is in
[`docs/`](../docs/README.md).

The goals every change is held to:

1. **Works for real, not only in the demo.** Every screen talks to the real database; the demo keeps
   the same rules so it never shows a power the real app wouldn't have.
2. **The database decides.** Who may do what is enforced in Supabase (row-level security and server
   functions), so no app, old or new, can get around it.
3. **Nothing rewards drinking more**, and no staff member is ranked against another.
4. **A guest's diary never reaches a venue.**
5. **Proven before it ships:** `npm run db:local` (audit, a full play-through, and a check that every
   app call fits the schema) and the app's own tests.

---

## 1 October 2026 — guests tonight, the guest's code, the taste on the ticket, next steps

**Goal:** the bartender makes something the guest will like; the till finds a guest without searching
everyone; a new venue sees what's left to set up.

- `056_taste_at_the_table.sql`: guests who opened the menu share their taste card (8 hours, a one-time
  yes); `venue_guests_tonight()` for `guests.taste` roles; `venue_find_guest()` by a 6-letter code.
- The till and the guest book: **In tonight** (each guest, table, taste chips) and **Their code**,
  instead of a name search (`lib/ui/widgets/guest_finder.dart`).
- Bar tickets show the table's taste — "nothing with alcohol tonight" and allergies first.
- **Getting set up** on Tonight / the Till (`lib/ui/widgets/next_steps.dart`, PLAN M1.14).
- iOS: `applinks:bar.bwdy.site` entitlement.

## 30 September 2026 — the team: the owner's code, pausing access, hours

**Goal:** an owner adds employees and decides their role. An employee signs in with their own details
plus a code from the owner (a second factor) and sees the role chosen for them. An owner or manager
can pause anyone's access at any moment and ask them to report to them.
([docs/17](../docs/17-staff-access.md))

**Database — `supabase/053_staff_access.sql`**
- Staff have a status: waiting, active or paused. Every permission check now counts **active** staff
  only, so a pause stops every screen, table and function at once.
- **Adding an employee** (`enrol_staff`): name, email, phone, role, then a 6-digit code shown once. It
  is stored only as a salted hash that nobody can read, works only for that email, and lasts 48 hours
  with 5 tries. A wrong try is counted, not rolled back. `claim_staff_enrolment` joins with the chosen
  role.
- **No more direct adds.** An app can no longer insert a roster row, except the creator's own owner
  row. Before, a manager could put any account found by @handle straight onto the team.
- **Shared invite codes** now make the person *waiting*; a manager approves or declines.
- **Pausing** (`lock_staff` / `unlock_staff`): a reason, and an owner or manager to report to. Nobody
  pauses themself or the owner. Pausing also clocks the person out.
- **The team's history** is written by a trigger on every roster change: joined, asked, approved,
  declined, role changed, paused, unpaused, removed, left, codes made and cancelled.
- **The time clock**: clock in and out; hours per person since a date, in name order.
- **The venue's details** for a person (the name they go by, a phone), seen only by owners, managers
  and the person themself.

**Venue app**
- **Your venues**: *A code to type* for each venue that added your email; waiting and paused venues
  with why. Signing in with a new email offers to create the account.
- **Paused mid-shift**: the app re-checks every minute, on resume and right after any refused call,
  then shows *"Your access is paused · Please report to Arjun (manager)"* with the reason. Given access
  again, the person goes straight back in. A failed check (no signal) keeps the pause on screen; it
  never lifts it (`02cdf3e`).
- **Team** (owners and managers): add an employee and show the code once, with a message to share; codes not
  typed yet (new code, cancel); a deliberate *Approve* for invite joiners; per person: role, pause
  (reason + report to), change the message, give access again, details, call, history, clock out,
  remove. **Hours** (who's on now, the week by name) and **Team history**.
- **More → Your shift**: clock in and out.
- The old *add by name or @handle* is gone; the database refuses it now.

**Checks**
- `scripts/check-app-contract.mjs` (`npm run db:contract`, in `db:local` and CI) reads every
  `.from()` / `.rpc()` call in the venue app, the users app and the website, and checks it against the
  migrated schema: tables, columns, embeds and their hints, a row-level-security policy for what the
  call does, grants, and function argument names. It checks itself first on 26 known cases. Today:
  420 calls, all fit.
- `db:audit` 306/0 and `db:verify` 404/0 locally, with about 60 staff-access steps (scene 23).
- App tests: 17 new (the wording, held against 053's own text; six walk-throughs). 65 pass.

**Website (bar.bwdy.site)**
- The team tab: add an employee (code shown once), approve or decline, pause (reason + report to),
  give access again. The venue list shows codes to type, and where you're waiting or paused. The wording
  is twinned in `src/lib/staffAccess.ts` with the same tests.

**Not done yet:** asking the owner again when an employee signs in on a *new phone*; an instant push of
a pause (today: within a minute); rotas, breaks, payroll export.

## 30 September 2026 — installable test builds

**Goal:** a phone build to test without a laptop.
- `.github/workflows/android.yml` builds release APKs of both apps on every app change and keeps them
  for 14 days. Without the repository variables `SUPABASE_URL` and `SUPABASE_ANON_KEY` the build is
  the demo; the run's summary says so.

## 29 September 2026 — the door (052)

**Goal:** clubs and busy bars count people in and out against the licensed capacity.
- A ledger of taps (counts, never people); `door_tick()` for the door roles, `door_count()` for tonight.
- The Door screen: In and Out, groups, undo; amber at 90% and red at full, with a word and a mark.
  Every phone on the door shares one count.

## 29 September 2026 — service: the floor, tabs, bar and kitchen, the bill (051)

**Goal:** run a night of service in any place with tables, and let a guest order from the table
without staff ever seeing who asked.
- **Floor**: every table as free, seated, food ready or asking (colour, word and mark). Seat a table,
  open a tab, a named tab at the bar.
- **Tab**: add from the menu (search, veg mark, quick notes), sent → making → ready → served, void with a
  reason.
- **The bill is the staff's**: split 1–6 ways, how each part was paid in their own words, a tip; a
  mismatch is noted, never blocked.
- **Bar and kitchen tickets**, oldest first, timers that turn a word and a colour.
- **Inbox**: table orders (accept or decline with a reason) and "call staff / bill please / water".
- **Waitlist**, **Floor setup** (areas, tables, each table's QR / NFC link, retire a code), the live
  board for managers, menu allergens and diet marks, "Share the menu".
- Fix: a sheet with a focused text box no longer crashes when it closes.

## 29 September 2026 — the counter: liquor stores, sweet shops and every shop (050)

**Goal:** a real till for counters, with alcohol deny-by-default.
- Products never priced above the printed MRP; a stock ledger (on hand is its sum); deliveries,
  counts, breakages, suppliers.
- `ring_sale()`: the server prices the sale and moves the stock. A bottle rings up only where the state's
  rules are researched and sourced, not on a dry day, inside legal hours, under the per-sale limit,
  after an ID check (only the yes is kept). A sale has no customer column.
- The excise register (opening, in, sold, closing) as CSV.

## 29 September 2026 — Ninkasi for hosts; the area map; outside signals

**Goal:** tell every role what they need to know for the shift, and show a venue its neighbourhood
without pointing at anyone.
- *Before your shift*: dry days, tonight's room, quiet nights, what's 86'd, events nearby, water and
  what to do when someone's had enough. It's built on the phone from what the role can already see,
  and Ninkasi answers questions (`/api/host-ai`).
- The area heat map (048): groups of 5+ people who said yes, across 3+ venues, rounded to 5s.
- Outside signals (049): public facts about places (events, openings, dry days, prices), never people.

## 29 September 2026 — the first release (R1: M0–M2) and every kind of shop

**Goal:** the venue staff app on the same Supabase backend as the website and the guest app, for
iOS and Android, phones and tablets.
- Sign in with an emailed code; create or join a venue; roles with invite codes.
- Tonight's room, or a till for counters; the guest book; the menu with 86 toggles and table-tag QRs;
  the loyalty card; the numbers; area trends; setup and verification.
- **Roles (045, 046)**: seven roles and a capability table the database checks (`venue_can`). This
  fixed three older holes: a manager could crown an owner, remove the owner, and a new role inherited
  tab, perk and guest-book powers.
- **Every kind of shop (047)**: bar, club, restaurant, café, liquor store, sweet shop, bakery, shop —
  what a place sells decides which law shapes its loyalty card.
- Shared pure logic with the users app in `packages/brewdiary_core`.
- A clearly labelled demo venue when no server values are built in.
