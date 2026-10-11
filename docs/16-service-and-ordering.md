# 16 — Service: the floor, orders, the bar and kitchen, the bill, and ordering from the table

This chapter covers running a night of service with the venue app (`mobile-bar/`), and what a guest
can do from the table. It all runs on `supabase/051_service.sql`. It works the same for a bar, a club,
a restaurant or a café, anywhere in the world. (Counters such as liquor stores, sweet shops and
bakeries have a till instead: [doc 15](15-the-counter-shops.md).)

1. [A night, start to finish](#1-a-night-start-to-finish)
2. [The screens](#2-the-screens)
3. [The bill: staff decide how it's paid](#3-the-bill-staff-decide-how-its-paid)
4. [Ordering from the table (the guest's side)](#4-ordering-from-the-table-the-guests-side)
5. [The rules the database enforces](#5-the-rules-the-database-enforces)
6. [Setting it up](#6-setting-it-up)
7. [Where it lives](#7-where-it-lives)

---

## 1. A night, start to finish

```
 Host            Server / bartender              Bar & kitchen           Guest (phone)
 ────            ──────────────────              ─────────────           ─────────────
 Waitlist ──► seat T4 (how many?) ──► tab opens
                 add from the menu ─────────────► tickets: new → making → ready
                                                                          scans T4's QR → menu
                                                                          "Send 2 items" ─┐
                 Inbox: accept onto T4's tab ◄─────────────────────────────────────────────┘
                 (alcohol? check ID)  ──────────► more tickets
                 mark served ◄────────────────── ready
                                                                          "Bill please" ─┐
                 Inbox ◄─────────────────────────────────────────────────────────────────┘
                 settle: split, how each part was paid, tip → the tab closes, T4 is free
 Manager: Numbers › Right now — open tabs, covers, sales, tips, bar/kitchen waits, the payment mix
```

## 2. The screens

| Screen | Who | What |
| --- | --- | --- |
| **Floor** (the home for places with tables) | everyone on the floor | Every table: **free**, **seated**, **food ready** or **asking**, shown as a colour, a word and a mark (never colour alone), with guests, minutes and the running total. Tap a free table to seat it; tap a busy one to see its tab. Also a named tab at the bar ("Bar 3"), and shortcuts to tickets, the waitlist, the inbox and tonight's room. It refreshes itself every 20 seconds. |
| **Tab** | servers, bartenders, supervisors, managers | Add from the menu (search, sections, the veg mark, quick notes like "no ice" or "allergy — see me"). Each line shows sent / making / ready / served. Mark served; void with a reason; share the bill; settle and close. On a tablet the order and the bill sit side by side. |
| **Bar tickets / Kitchen tickets** | the bar, the kitchen | Tickets oldest first, one per table. The timer turns amber and then red, with a word, as it runs long: the bar at 7 and 12 minutes, the kitchen at 15 and 25. Tap a line to move it along; "All ready" does the whole ticket. Tablet-first and readable from a step back. A kitchen-only role lands straight here. |
| **Inbox** | the floor | Orders from table QRs (accept onto the table's tab, or decline with a reason the guest sees), and "call staff / bill please / water". It shows **which table**, **never who**. An order with alcohol says "check ID". |
| **Waitlist** | hosts | A first name or "party of 4", the quoted wait, minutes waited, then seat or gone. |
| **Door** | hosts and the floor count; everyone on the floor sees it | How many are inside now, against the licensed capacity: big **In** and **Out** buttons, groups (+2, +4…), and undo. It turns amber at 90% ("nearly full — 10 more") and red at full ("full — hold the door"), with a mark and a word each time. Every phone on the door shares one count. Counts only: no name, face or ID. Tonight starts at 6 in the morning, so a night past midnight is one night. (`supabase/052_door.sql`) |
| **Floor setup** (More) | owners, managers | Areas and tables; each table's QR to print or write to an NFC tag; a new code that retires a lost tag; the switch for ordering from the table. |
| **Right now** (Numbers) | owners, managers, supervisors | Open tabs, guests seated, sales and tips today, what the bar and kitchen have waiting and their average time to ready, voids, requests and calls, the waitlist, and how people paid. Business numbers only: no guest, and no ranking of staff. |

## 3. The bill: staff decide how it's paid

This was the maintainer's call: **brewdiary doesn't interfere with payments.**

- Staff split the bill if they like (1–6 ways, and the shares always add up to the paisa). For each
  part they write how it was paid, in their own words: *Cash, Card, UPI, Other* (or anything 2–20
  characters long, like "voucher").
- An optional tip.
- If what was paid doesn't match the total, the screen says so ("₹50 more than the total — fine if
  that's what happened") and still closes the tab. It never blocks.
- The tab's subtotal is kept as a snapshot, so a later menu edit never changes a settled bill.
- **Share the bill** sends a plain-text bill (items, total, how it was paid) through any app.

brewdiary never takes a payment, never stores card details, and never checks that money arrived.
Taxes, printed receipts and invoice numbers wait for each country's rules (PLAN M6.2, M6.11).

## 4. Ordering from the table (the guest's side)

Each table has its own link, `bwdy.site/t/<code>`, printed as a QR or written to an NFC tag. It opens
the venue's menu **with the table known**: in the guest app if it's installed, otherwise on the
website.

- **Reading the menu** needs nothing: no sign-in, and the venue learns nothing about who looked. Menus
  now show the **veg / non-veg / egg / vegan** mark and **allergens** (the EU's 14).
- **Ordering and calling staff** need the venue to switch it on (Floor setup, off by default) and the
  guest to be signed in.
  - An order is a **request**. Staff accept it onto the table's tab (priced by the server, exactly
    as if they had keyed it) or decline it with a reason the guest sees.
  - A guest can cancel a request that's still waiting.
  - "Call staff", "Bill please" and "Water" reach the floor once, however often they're tapped.
- **Staff never see who asked**, only the table. The guest sees only their own requests and their
  status: *waiting for staff*, *on its way*, or *declined — reason*.

## 5. The rules the database enforces

The screens show each rule, but the database decides (`supabase/051_service.sql`). `npm run db:audit`
checks each rule exists, and `npm run db:verify` (scene 21) plays a whole service through them.

- **Every write is a function checking the person's role.** No client write policy on tabs, lines,
  payments, requests or calls. Servers take orders; the bar and the kitchen move only their own
  tickets, and only forward; only people who can take payments settle a bill.
- **The server prices every line**, copying the item's name, price and station at the moment it's
  ordered. A sold-out (86'd) item can't be ordered.
- **A void needs a reason.** Your own line, not yet started and under 10 minutes old, is yours to void;
  anything else needs a supervisor. A tab can be voided only if nothing on it was served.
- **A guest only asks.** `request_order()` never writes a line. It's signed-in only, the venue must
  have switched it on, it allows one request per 20 seconds and at most 3 waiting per table, and each
  item must be on the menu and available.
- **Nobody learns who asked.** The inbox function never returns the requester; a guest reads only
  their own rows.
- **Retries are safe.** A tab or a request made twice with the same id is made once.
- **The waitlist forgets.** Each new name clears the ones older than 20 hours.
- **Tables are for places with tables.** A counter can't add any. A table's code can only change
  through `rotate_table_code()`, which retires the printed tag.
- **The door counts, never people.** A tap is +1 or −1 (a group up to 12); the ledger has no column
  that could say who. "Inside now" is the sum of tonight's taps (never below zero). The count still
  records people past the capacity; the screen says to hold the door. Only the door roles tap.
- **Nothing rewards drinking more.** No happy hours, no discounts, no "another round?" prompt, no
  per-guest drink counts, no staff league table.

## 6. Setting it up

1. Run migration **051** (`node scripts/db.mjs supabase/051_service.sql`), then `npm run db:audit` and
   `npm run db:verify`. `npm run db:local` proves it on a throwaway copy first.
2. In the venue app: **More › Floor setup**. Add areas (Bar, Floor, Patio) and tables (label and
   seats). Open each table to print its QR or write it to an NFC tag (NTAG213 or better).
3. Optional: switch on **Guests can order from the table**, and set the **Capacity** (the number on your
   licence) for the door counter. Run migration **052** for the door.
4. Menu: give each item its station (bar, kitchen, or none), its mark (veg / non-veg / egg / vegan) and
   its allergens.
5. App links: `/t/*` is claimed by the guest app on Android and iOS (see
   [doc 14 §6](14-supabase-cloudflare-connect.md#6-app-links-a-tap-on-a-link-opens-the-right-app)).

## 7. Where it lives

| Piece | Where |
| --- | --- |
| Database | `supabase/051_service.sql`; the door is `supabase/052_door.sql` |
| Checks | `scripts/db-audit.mjs` (service and door sections), `scripts/verify-flow.mjs` (scenes 21 and 22) |
| Venue app screens | `mobile-bar/lib/ui/screens/` `floor_screen.dart`, `tab_screen.dart`, `station_screen.dart`, `inbox_screen.dart`, `waitlist_screen.dart`, `floor_setup_screen.dart`, `door_screen.dart`; the live board is in `numbers_screen.dart` |
| Venue app sums (splits, table states, tickets, the shared bill) | `mobile-bar/lib/logic/service.dart` |
| Website table link | `src/app/t/[code]/page.tsx`, `src/components/menu/TableMenu.tsx`, `src/components/menu/MenuView.tsx`, `src/lib/tableOrder.ts` |
| Guest app table link | `test_m_app/lib/data/table_order.dart`, `test_m_app/lib/ui/screens/menu_screen.dart` (`TableMenuScreen`), routed in `test_m_app/lib/app.dart`; parsing in `packages/brewdiary_core/lib/menus.dart` |
| Tests | `mobile-bar/test/app_test.dart` walks the floor, tabs, tickets, an order request, "bill please" and the waitlist against an in-memory stand-in |

## 8. During the night: moves, the bar's tools, notes, the drawer, bookings (058)

Migration **058** (`supabase/058_floor_shift_cash.sql`) adds the things every bar and restaurant
system has (Toast, Square, Lightspeed, TouchBistro, Petpooja for the floor and the drawer; SevenRooms,
OpenTable and Resy for bookings; 7shifts for pre-shift notes; the kitchen-screen makers for recall and
all-day counts), each built the brewdiary way: the database decides, staff do it in two taps, and
nothing about it rewards drinking more.

**A table, open on the tab screen.** Under the bill, a caption says whose table it is ("Noor's
table") and four chips do the rest:

| Chip | What happens | Who |
| --- | --- | --- |
| **Move** | The party moves to a free table (or the bar, with a name). The tab keeps everything. | anyone who takes orders |
| **Bring a tab in** | Another open tab's lines join this bill. The other tab is kept, marked *merged*, never deleted. | same |
| **Split by item** | Pick lines (or a whole seat) and move them onto their own check at the same table. "Move 2 · ₹880". Voided lines never move. | same |
| **Hand over** | Give the table to someone else on tonight. Only people who can take orders are offered; a paused person never is. | same |

**The bar and the kitchen screens.**
- **TO MAKE** at the top: everything still to make, summed by name, most first ("3× Negroni") —
  ready lines drop off.
- Each line's **⋯** opens: the **spec card** (recipe, glass, garnish, method — written in the menu
  editor), **Back to making** (marked ready by mistake), and **86 it** ("it's run out").
- **OFF TONIGHT** lists what's 86'd; tap one to bring it back. The guest's menu hides it at once.
- The spec card stays inside the venue: `venue_menu()` (the guest's menu) never returns it.

**The pre-shift note.** A shift lead (supervisor and up) writes tonight's note — "walk-in is off,
push the paneer", "party of 12 at 9". It sits at the top of the floor, the till, tonight and the
stations until the end of the night (18 hours by default). Everyone taps **Got it**, and the note
folds to one line. The lead sees *who* has seen it, by name, in name order — never a ranking, never
a time. **More › Shift notes** also holds **the manager's log**: the hand-over for the next manager
(what broke, who called, what's owed), readable by supervisors and managers only.

**The cash drawer** (**More › Cash drawer**).
1. **Open** it with a float (₹2,000) and a label (Drawer / Bar till / Front till). One open drawer
   per venue.
2. During the night: **Safe drop**, **Pay in**, **Pay out** — each with a reason. A pay-out needs a
   manager (the `cash.close_day` permission).
3. **Count and close** is a **blind count**: whoever counts never sees the expected figure first.
   Count by notes (₹500 × 3, ₹100 × 3 …) or type one number. Then the report: float, expected,
   counted, the difference ("₹10 short"), pay-ins, pay-outs, drops, bills, sales, tips, voids, and
   every payment method. The report is stored as it was at close, and no app can change it afterwards.
4. *Expected* is worked out by the database: float + pay-ins − pay-outs − drops + every cash payment
   on a tab or at the counter since the drawer opened. Leads see it during the night; nobody else does.

**Bookings** (the **Bookings · N** chip on the floor).
- Today / Tomorrow / Another day. A day runs 6 am to 6 am, like the rest of the venue app.
- **New booking**: name, party size, day and time, how long (90 min by default), a table if you want
  one, a phone number and a note. Two bookings on the same table at the same time are flagged.
- On the floor, a free table shows its next booking within three hours ("booked 9:00 pm · 4").
- **Seat them now** opens the table's tab with the party size as covers and marks the booking seated.
  Also: They're here, Edit, No-show, Cancel.
- **Kept short, on purpose.** A booking's phone number is wiped a day after it, and after 30 days the
  name becomes "Party of 4" and the note goes. Bookings are never deleted (a no-show stays a no-show),
  but a stranger's phone number isn't kept for ever.

**The rules (058).**
- Every change goes through a function that checks the caller's permission (`venue_can()`); the
  drawer and notes tables have no write policy at all.
- Bookings can be read with `floor.view`, written with `guests.seat`, never deleted; a booking's
  table and tab must belong to the same venue (a trigger checks).
- A merge keeps the merged tab (status `merged`, `merged_into`); a move never moves a voided line;
  hand-over refuses someone who can't take orders.

**Where it lives.** Database: `supabase/058_floor_shift_cash.sql`. Checks: `scripts/db-audit.mjs`
(the 058 section), `scripts/verify-flow.mjs` (scene 28). Venue app: `tab_tools.dart`,
`station_screen.dart`, `widgets/shift_notes.dart`, `log_book_screen.dart`, `cash_screen.dart`,
`bookings_screen.dart`; the sums (`allDay`, `denominations`, `countResult`, `nextBookingAt`,
`bookingsClash`) are in `mobile-bar/lib/logic/service.dart`. Tests: `mobile-bar/test/floor_shift_test.dart`.

**Setting it up.** Run migration **058** after 057 (`node scripts/db.mjs supabase/058_floor_shift_cash.sql`),
then `npm run db:audit` and `npm run db:verify`. Nothing else: the screens appear for the roles that
may use them.

Next (PLAN M3–M6, M11, M13): sections (servers to areas), courses and hold/fire, sizes and modifiers,
the tax profile, printed receipts, push when food is ready, and working offline.
