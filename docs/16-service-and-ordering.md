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
- **Nothing rewards drinking more.** No happy hours, no discounts, no "another round?" prompt, no
  per-guest drink counts, no staff league table.

## 6. Setting it up

1. Run migration **051** (`node scripts/db.mjs supabase/051_service.sql`), then `npm run db:audit` and
   `npm run db:verify`. `npm run db:local` proves it on a throwaway copy first.
2. In the venue app: **More › Floor setup**. Add areas (Bar, Floor, Patio) and tables (label and
   seats). Open each table to print its QR or write it to an NFC tag (NTAG213 or better).
3. Optional: switch on **Guests can order from the table**.
4. Menu: give each item its station (bar, kitchen, or none), its mark (veg / non-veg / egg / vegan) and
   its allergens.
5. App links: `/t/*` is claimed by the guest app on Android and iOS (see
   [doc 14 §6](14-supabase-cloudflare-connect.md#6-app-links-a-tap-on-a-link-opens-the-right-app)).

## 7. Where it lives

| Piece | Where |
| --- | --- |
| Database | `supabase/051_service.sql` |
| Checks | `scripts/db-audit.mjs` (service section), `scripts/verify-flow.mjs` (scene 21) |
| Venue app screens | `mobile-bar/lib/ui/screens/` `floor_screen.dart`, `tab_screen.dart`, `station_screen.dart`, `inbox_screen.dart`, `waitlist_screen.dart`, `floor_setup_screen.dart`; the live board is in `numbers_screen.dart` |
| Venue app sums (splits, table states, tickets, the shared bill) | `mobile-bar/lib/logic/service.dart` |
| Website table link | `src/app/t/[code]/page.tsx`, `src/components/menu/TableMenu.tsx`, `src/components/menu/MenuView.tsx`, `src/lib/tableOrder.ts` |
| Guest app table link | `test_m_app/lib/data/table_order.dart`, `test_m_app/lib/ui/screens/menu_screen.dart` (`TableMenuScreen`), routed in `test_m_app/lib/app.dart`; parsing in `packages/brewdiary_core/lib/menus.dart` |
| Demo | The Amber Room's floor has seeded tabs, tickets, an order from T3, "bill please" from T2 and a waitlist |

Next (PLAN M3–M6, M11, M13): table moves and merges, courses and hold/fire, sizes and modifiers, the
tax profile, printed receipts, a cash drawer and the day close, bookings, push when food is ready, and
working offline.
