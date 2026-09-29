# 13 — The area heat map

A bar manager asked to see "the kind of people outside": where people go out near them, what they like,
when they come out, and what they spend. This chapter explains how the venue app answers that, using only
information people agreed to share, and never pointing at anyone.

1. [What a manager sees](#1-what-a-manager-sees)
2. [The two yeses (and the venue's yes)](#2-the-two-yeses-and-the-venues-yes)
3. [The rules that keep it from pointing at anyone](#3-the-rules-that-keep-it-from-pointing-at-anyone)
4. [How to read each layer](#4-how-to-read-each-layer)
5. ["What it says": the guide](#5-what-it-says-the-guide)
6. [Switching it on](#6-switching-it-on)
7. [Where it lives in the code](#7-where-it-lives-in-the-code)
8. [What it never does](#8-what-it-never-does)
9. [What comes next](#9-what-comes-next)

Words you might not know (geohash, k-anonymity, persona) are in the [glossary](02-glossary.md).

---

## 1. What a manager sees

In the venue app: **Numbers → Open the area map** (owners and managers only). The map is the ~40 km area
around the venue, cut into a grid of 8 × 4 squares. Each square is a **neighbourhood** of about 5 km.

```
  north
  ┌────┬────┬────┬────┬────┬────┬────┬────┐
  │    │    │    │10+ │25+ │▓45▓│30+ │ 5+ │   ▓ = your neighbourhood (outlined)
  ├────┼────┼────┼────┼────┼────┼────┼────┤   brighter = more people
  │    │    │    │    │10+ │20+ │15+ │    │   blank = not enough to show
  ├────┼────┼────┼────┼────┼────┼────┼────┤
  │    │    │    │ 5+ │15+ │10+ │    │    │
  ├────┼────┼────┼────┼────┼────┼────┼────┤
  │    │    │    │    │    │    │    │    │
  └────┴────┴────┴────┴────┴────┴────┴────┘
  west                                  east
```

Above the map, five layers: **How many · Kinds of people · What they like · When · Spend**. Tap a square to
see everything the map knows about that neighbourhood. Under it, **What it says** puts the map into plain
sentences. On a tablet, the guide sits beside the map.

## 2. The two yeses (and the venue's yes)

A guest is counted only if they switched on **both** of these in their diary (You → Settings, on the
website and in the phone app). Both are **off** until they turn them on.

1. **Anonymous taste trends** (existing): count my logs in trends, counts only.
2. **Neighbourhood maps** (new, shown under the first): also count me where I go out, meaning the venue
   rooms I join, only in groups of 5+ people across 3+ venues.

A **venue** has its own switch: **Share our totals with the area map** (Setup). The spend layer comes from
venues' own records of tabs. A venue sees the area's spend only if it shares its own. This is called
*give to get*, and it is fair: nobody sees a number they didn't help make.

## 3. The rules that keep it from pointing at anyone

The database enforces all of these (`supabase/048_area_map.sql`). The app can't turn any of them off.

| Rule | Why |
| --- | --- |
| A neighbourhood shows only with **5+ people** who said yes **and 3+ venues** in it | Five people so no square is one person; three venues so no square is one competitor's night. |
| Every number is **rounded down to 5s** ("25+") | Two answers can't be subtracted to find one person who joined. |
| The time window is **fixed**: 7, 30 or 90 whole days, ending yesterday | Asking for "8 days" and then "7 days" can't isolate one day's visitor. |
| Spend is a **band** ("₹1,000+"), the median of the neighbourhood's tabs | An exact figure is a receipt; a band is a picture. |
| Only a **verified** venue can open the map | Nobody can create a pretend venue to look at an area. |
| A verified venue can **refine** its location but **not move** to another area | The map is only ever of where the venue really is. |
| A location must be a **real geohash** | No free text (an address, a note) can be hidden in the location. |
| The answer is only **(neighbourhood, layer, label, number)** | No name, no venue, no row per person ever leaves the database. |

`npm run db:audit` checks every rule is present in the live database, and `npm run db:verify` plays a
scene where the rules have to hold (4 people plus one "no" stays dark; the 5th and 6th "yes" light the
square as "5+"; a two-venue square stays dark; a venue that doesn't share sees no spend).

## 4. How to read each layer

- **How many.** People who said yes and went out in that neighbourhood in the window. Brighter means
  more.
- **Kinds of people.** Taste **personas**, each worked out from the person's own diary over the window:
  *Coffee & tea people, Beer people, Wine people, Cocktails & spirits, Zero-proof* (mostly soft drinks
  and dry days), and *Explorers* (four or more kinds of drink). Pick one to see where they are.
- **What they like.** The kinds of drink those people logged, counted in people.
- **When.** When they came out, on the **venue's** clock: mornings (5 am–noon), afternoons (noon–5 pm),
  evenings (5–9 pm), late (after 9 pm).
- **Spend.** A typical night's tab, as a band. It shows only for venues that share, and only where
  3+ sharing venues and 5+ people are behind it.

## 5. "What it says": the guide

The app turns the map into short sentences (`mobile-bar/lib/logic/area.dart`, `areaGuide()`), for
example:

- *Busiest: ~5 km east, 40+ people went out there.*
- *Coffee & tea people lead in 4 of 11 neighbourhoods.*
- *Near you it's mostly cocktails & spirits, out evenings.*
- *Most people go out in the evening (5–9 pm).*
- *A typical night out around here: ₹1,000+.*

Its suggestions are about **fit**, never about getting anyone to drink more: a good alcohol-free list
where zero-proof drinkers are a real crowd, daytime hours where coffee people lead, a changing special
where there are many explorers. A test checks that the guide never says "another round", "drink more",
"upsell" or "happy hour". Ninkasi for hosts will read the same guide.

## 6. Switching it on

1. **Run migration 048** (the maintainer): `node scripts/db.mjs supabase/048_area_map.sql`, then
   `npm run db:audit` and `npm run db:verify`. Before that, `npm run db:local` proves it on a
   throwaway database.
2. **Venues:** verify the venue, then in Setup tap **Set it again** standing in the venue. A location
   saved before 048 was a rough ~40 km area (4 letters), and the map needs at least 5. Optionally switch
   on **Share our totals with the area map**.
3. **Guests:** You → Settings → Anonymous taste trends → Neighbourhood maps. Until 048 is applied the
   switch stays hidden, so nothing breaks.

## 7. Where it lives in the code

| Piece | Where |
| --- | --- |
| The database function, opt-ins and rules | `supabase/048_area_map.sql` (`area_heat_map`, `spend_band_floor`, `venues_guard_geohash`) |
| The grid (which squares, which direction) | `packages/brewdiary_core/lib/geo.dart` and its twin `src/lib/geohash.ts`, with the same tests on both sides |
| Reading the rows and the guide | `mobile-bar/lib/logic/area.dart` |
| The screen | `mobile-bar/lib/ui/screens/area_screen.dart` |
| Guest switches | `src/components/you/You.tsx`, `test_m_app/lib/ui/screens/settings_screen.dart` |
| Venue switch and location | `mobile-bar/lib/ui/screens/setup_screen.dart`, `src/components/venue/VenueApp.tsx` |
| Checks | `scripts/db-audit.mjs` and `scripts/verify-flow.mjs` (section/scene 18) |

## 8. What it never does

- It never shows a person, a name, a handle, or "who's near you now".
- It never uses age, gender, religion, caste, origin or anything like them. None of these exist in the
  database.
- It never shows one venue's own figures to anyone, including that venue.
- It never counts anyone who didn't say yes, and switching "Neighbourhood maps" off removes you from the
  next answer.
- It never rewards drinking more. Spend is a band, and suggestions are about fit.

## 9. What comes next

- **Outside signals.** Public facts about places (events, openings, holidays, opening hours) gathered by
  separate tools, imported through a server-only path that drops anything about a person. They join the
  map and the briefing.
- **Ninkasi for hosts.** The assistant reads this guide, the venue's live state and the outside signals,
  and answers "what should I know tonight?".
- **The web dashboard.** The same map on bar.bwdy.site. The grid code is already shared.
