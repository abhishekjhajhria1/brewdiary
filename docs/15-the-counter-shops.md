# 15 — The counter: liquor stores, sweet shops, bakeries and every shop

Bars have rooms and tabs. **Counters** (a liquor store, a sweet shop, a bakery, any other shop) have a
**till**: people buy and leave. This chapter covers the venue app's counter module
(`supabase/050_shop_counter.sql`):

- the shelf of products, with prices and MRP;
- stock that follows every sale;
- suppliers and deliveries;
- the checkout;
- for a liquor store, the law on a bottle leaving the shop and the excise register the state asks for.

1. [What staff do](#1-what-staff-do)
2. [The rules the database enforces](#2-the-rules-the-database-enforces)
3. [Opening a state for alcohol sales](#3-opening-a-state-for-alcohol-sales)
4. [The excise register](#4-the-excise-register)
5. [Where it lives](#5-where-it-lives)

---

## 1. What staff do

| Task | Where in the venue app | Who (roles, from 045) |
| --- | --- | --- |
| Ring up a sale | Till → **New sale**: tap **Add**, choose how it was paid, **Ring up** | owner, manager, supervisor, bartender, server |
| Sell by weight (mithai by the gram) | Add asks for grams: 100 g, 250 g, 500 g, 1 kg, or type it | same |
| Punch a loyalty card | Till → **Punch a card** (once a day per customer, as before) | anyone who can hand over rewards |
| Receive a delivery | More → **Stock** → a product → Receive (quantity, supplier, invoice no.) | owner, manager, supervisor, bartender, kitchen |
| Fix a count, a breakage, a return | More → Stock → a product → Adjust (a count needs a note) | owner, manager |
| Add or edit products, prices, MRP | More → Stock → Add a product / Edit | owner, manager |
| Read the excise register | More → **Excise register** (liquor stores) → Share as CSV | owner, manager |

On a tablet, the checkout shows the shelf and the sale side by side. On a phone, the sale sits on top
and the shelf below it.

## 2. The rules the database enforces

The app shows each rule before anyone taps, but the **database** decides. A tampered app can't get
round them.

- **The server prices every sale.** The till sends only *what* and *how many*. `ring_sale()` reads each
  product's price at that moment, works out the total (per kg × grams for weight), and moves the stock.
- **Never above MRP.** A price above the printed maximum retail price can't be saved at all.
- **Stock is derived.** On hand is the sum of the stock ledger (deliveries in, sales out, adjustments
  with a reason and who made them). Nothing stores a count that could drift.
- **Ledgers have no client write.** Sales and stock moves are written only by the functions, each
  checking the person's role.
- **A retry can't double-ring.** The phone gives every sale its own id; sending it twice returns the
  first result.
- **A shop that sells no alcohol can't list any.** A sweet shop's shelf refuses whisky. A shop that
  sells alcohol is a liquor store, a kind of its own.
- **Alcohol is deny-by-default.** A bottle rings up only when all of these hold:
  1. brewdiary has researched that state's **retail** rules (a row in `retail_alcohol_rules`, with its
     source);
  2. today isn't a **dry day** listed for the state or the country;
  3. it's inside the state's **legal sale hours**, on the state's own clock;
  4. the sale is under the state's **per-sale limit** (millilitres), where there is one;
  5. staff confirmed they **checked ID**, against the drinking age for the venue's state.
     Only the yes is kept, never the ID.
- **A sale has no customer attached.** The till sells to "a customer". Nothing about who bought what
  reaches a guest profile, and loyalty stays the separate once-a-day punch.

`npm run db:audit` checks each of these exists in the live database. `npm run db:verify` (scene 20) rings
real sales through every rule: a soda anywhere; a bottle refused until the state is researched; refused
without an ID check, over the limit, on a dry day, and outside hours; a retry not double-counted; a sweet
shop refused whisky; kaju katli by the gram.

## 3. Opening a state for alcohol sales

Until a state has a row, liquor stores there can sell everything **except** alcohol, and the till says
why. That is on purpose: the house rule is that an unresearched place gets the strictest setting.
Opening a state is a deliberate act:

1. **Research it.** Find the state's official source for:
   - retail sale hours for off-licences;
   - any per-sale quantity limit;
   - the dry days for the year, national and state.

   Note the source (notification number, excise department page, date).
2. **Add the rows** with the service key (the same way `jurisdiction_policy` is maintained), for
   example:
   ```sql
   insert into public.retail_alcohol_rules (country, region, tz, sale_start, sale_end, max_ml_per_sale, source)
   values ('IN', 'KA', 'Asia/Kolkata', '<opens>', '<closes>', <ml or null>, '<official source and date>');

   insert into public.dry_days (country, region, day, reason, source)
   values ('IN', '', '<yyyy-mm-dd>', '<the occasion>', '<official source>');
   ```
   The hours are local to the `tz` you give. A window that crosses midnight (for example 10:00–01:00)
   works. `region = ''` means the whole country. A state's row beats the country's.
3. **Check it:** `npm run db:audit` fails if any rule or dry day has no source.
4. **Tell the stores.** The till's banner changes from "we haven't researched…" to the hours and
   limits.

Dry days change every year and elections add more, so keep them current. Outside signals
([doc 13](13-area-heat-map.md#9-outside-signals-bringing-in-public-data)) can carry them as `holiday`
signals so the whole team sees them coming in Ninkasi's briefing. The `dry_days` table is still what
stops the till.

## 4. The excise register

States ask liquor stores to keep a daily account of every brand and pack:
- opening stock;
- received;
- sold;
- closing.

The register is read straight from the stock ledger (`excise_register()`), per product per day, with
days on the state's clock. Breakages, returns and count corrections appear in their own column, so
nothing is hidden inside "sold". **Share as CSV** gives a file with one row per bottle per day, ready
to copy into the state's own form. The exact format differs by state, so this is the source for it,
not the form itself.

## 5. Where it lives

| Piece | Where |
| --- | --- |
| Tables, rules, functions | `supabase/050_shop_counter.sql` |
| Checks | `scripts/db-audit.mjs` (the counter section), `scripts/verify-flow.mjs` (scene 20) |
| The till's arithmetic, the pre-checks, the CSV | `mobile-bar/lib/logic/counter.dart` |
| Screens | `mobile-bar/lib/ui/screens/checkout_screen.dart`, `stock_screen.dart`, `excise_screen.dart` |
| Demo | the demo's **Cellar Door Wines** (a liquor store) and **Mithai Mahal** (sweets by weight) |

Next (PLAN M9, M16): purchase orders and par levels, barcode scanning with the camera, receipts, a
day-close (Z) for the counter, and the guest code, so a card is punched only when the customer shows
their own app.
