# 11 — Rooms, points & venues (the bar layer)

This is the newest and largest layer of brewdiary, and the one with the most moving parts. It's where
the app stops being only a private diary and becomes something a **bar** takes part in too.

Read [01](01-what-is-brewdiary.md) and [04](04-how-it-all-works.md) first — this chapter assumes you
know what an *entry*, a *party* and *RLS* are. (Unclear word? [Glossary](02-glossary.md).)

---

## 1. The idea in one paragraph

You go out. The bar has opened a **room** for tonight (it's just a party with the venue's name on it).
You join it, and you get a **spark** for showing up. Your friends can hand you **vibe** for being good
company; so can the **waiters and bartenders**. A screen on the wall — the **kiosk** — shows tonight's
board, but only for people who chose to be on it. The bar can log what you spent, and after enough
visits (or enough rupees) you earn a **house perk**: a free drink next time. You can share your score
to social media like any other card. Everything loud is **off until you switch it on**.

**The thing that makes this not a "spend more, win more" app:** the public score is *never* money.

---

## 2. The three currencies (learn these; everything else follows)

| Currency | What earns it | Who can see it | Where it lives |
| --- | --- | --- | --- |
| **Spark** | **Trying something new** — a new venue, a new drink, or a logged **dry day**. Going back to your local *again* earns nothing. | The room's board, the kiosk wall, your friends' leaderboard (if you opted in). | `point_events`, `currency = 'spark'` |
| **Vibe** | Positive recognition, given by **your table** *and* **the bar's staff** — "great vibe", "kept it classy". | Same places as sparks, always as a plain count. | `point_events`, `currency = 'vibe'` |
| **House perk** | Visits or spend at **one** venue. The reward defaults to something **non-alcoholic**, and in some countries it must be. | **Only you and that venue.** Never public, never on a leaderboard. | `venue_perks` + derived from `venue_visits()` / `venue_spend()` |

And one number that is **not** a currency:

| **Spend** | Recorded by the bar when you close a tab. | You + that venue's staff. On the wall **only** if you switch on *two* separate consents. | `spend_events` |

**Vibe is positive-only, everywhere, forever.** There is no thumbs-down, no rating, no complaint, no
blacklist. A bar can praise a guest; it can never mark one. This isn't a preference — it's the reason
the feature was allowed to exist at all. Don't "balance" it later.

**And sparks pay for variety, never for frequency.** This is subtle and it matters more than anything
else on this page. We originally gave a spark for *checking in* — which meant the public score, the one
on a TV in a bar, was a count of **how often you went out drinking**. We had a rule saying "nobody is
ranked by what they spent" and we kept it, and still built a scoreboard that rewarded going out more.

So: a **new** venue pays, a **new** drink pays, a **dry day** pays. Coming back to your local pays
*nothing publicly* — the bar rewards that privately, with its own perk. The public board rewards
**trying things**; the private perk rewards **coming back**. Different jobs, different currencies.
If you ever find yourself adding a spark for "showing up again," stop.

---

## 3. Where everything lives

### Screens (routes)
| Address | Who opens it | File |
| --- | --- | --- |
| `/party/<id>` | Guests. The room: board, check-in, vibe, your perk progress. | `src/components/together/PartyRoom.tsx` |
| `/together` → **Board** tab | Guests, **only if they opted in**. The friends leaderboard. | `src/components/together/Together.tsx` |
| `/you` → settings | Guests. Every consent switch lives here. | `src/components/you/You.tsx` |
| `/venue` (and **bar.bwdy.site**) | Bar owners & staff. The dashboard. | `src/components/venue/VenueApp.tsx` |
| `/kiosk/<code>` | **Nobody signs in.** The screen on the wall. | `src/components/kiosk/KioskBoard.tsx` |
| `/u/<handle>` | Anyone (subject to the owner's privacy tier). | `src/components/profile/PublicProfile.tsx` |

> **`bar.bwdy.site` is not a second app.** `src/middleware.ts` spots any `bar.*` web address and quietly
> serves `/venue` from the same deployment. Staff sign in there with an ordinary brewdiary account.

### The brains (`src/lib/`)
| File | What it does |
| --- | --- |
| `points.ts` | Sparks & vibe, the room board, the kiosk board, the friends leaderboard, recording spend, and the consent switches (`kiosk_visible`, `compete_visible`, `flex_receipts`). |
| `venues.ts` | Venues, staff & their roles, verification requests. |
| `perks.ts` | The house perk — set it (bar side), and track progress toward it (guest side). |
| `publicProfile.ts` | Reading a `/u/<handle>` profile + the owner's privacy tier and social link. |
| `parties.ts` | Rooms. A room **is** a party that has a `venue_id`. |
| `goals.ts` + `derive.weekBalance` | The quiet counterweight: optional weekly limits and dry days. |

### The database (`supabase/`)
| Migration | Adds |
| --- | --- |
| `009_points.sql` | The `point_events` ledger + the room board. |
| `010_venues.sql` | `venues`, `venue_staff`, and the guard that stops a venue verifying itself. |
| `011_venue_rooms.sql` | The bridge: `parties.venue_id`. |
| `012_kiosk.sql` | `kiosk_visible` + the anonymous `room_board()`. |
| `013_public_profiles.sql` | Privacy tiers + one social link. |
| `014_perks.sql` | House perks. |
| `015_verification.sql` | Verification requests (a venue can never approve its own). |
| `016_staff_awards.sql` | Staff hand out vibe; check-in becomes server-authoritative. |
| `017_spend_and_board.sql` | `spend_events` + spend-based perks + the friends leaderboard. |
| `018_flex_and_fof.sql` | The opt-in tab strip + friends-of-friends profile reads. |
| `019_variety_and_consent.sql` | Sparks pay for **variety, not frequency**; dry-day sparks; per-night kiosk consent. |
| `020_perk_policy.sql` | The perk becomes **jurisdiction-aware** (see §12), and visits count rooms again. |

Run one with `node scripts/db.mjs supabase/<file>.sql`.

---

## 4. The shape of the whole layer

```
                        ┌───────────────────────────┐
   BAR STAFF  ─────────▶│  /venue  (bar.bwdy.site)  │
   (own account)        │  VenueApp.tsx             │
                        └────────────┬──────────────┘
                                     │ opens a room
                                     ▼
                        ┌───────────────────────────┐
                        │  a PARTY with a venue_id  │◀──── GUESTS join with the code
                        │  = "tonight's room"       │
                        └────────────┬──────────────┘
                                     │
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                            │
        ▼                            ▼                            ▼
  ┌───────────┐              ┌──────────────┐            ┌────────────────┐
  │  SPARKS   │              │     VIBE     │            │     SPEND      │
  │ check in  │              │ table + staff│            │ STAFF ONLY     │
  └─────┬─────┘              └───────┬──────┘            └───────┬────────┘
        │                            │                           │
        └──────────┬─────────────────┘                           │
                   ▼                                             ▼
          point_events  (append-only)                    spend_events  (append-only)
                   │                                             │
       ┌───────────┼───────────────┐                    ┌────────┴────────┐
       ▼           ▼               ▼                    ▼                 ▼
  room board   kiosk wall   friends board          house perk       kiosk tab strip
  (members)    (opt-in)     (opt-in ×2)          (you + the bar)   (opt-in ×2, tiny)
```

Nothing in the grey boxes is *stored as a total*. Every board you see is **added up on the spot** from
the ledger — the same "derived, never stored" rule as the streak and the mosaic.

---

## 5. Workflow — a bar gets set up

```
owner signs up (a normal account)
        │
        ▼
opens bar.bwdy.site  →  "Create venue"        …………  venues.ts → createVenue()
        │
        ▼
adds staff by handle: manager / bartender     …………  venues.ts → addStaff()
        │
        ▼
"Request verification"                        …………  venues.ts → requestVerification()
        │                                             (row lands as status='pending';
        │                                              there is NO update policy, so the
        │                                              bar cannot approve itself)
        ▼
YOU, the maintainer, review it and run:
        node scripts/verify-venue.mjs <slug>   …………  the ONLY path to verified = true
        │
        ▼
venue is VERIFIED  →  it may now hand out vibe, record spend, and offer a perk
```

**Why verification gates so much:** an unverified venue could otherwise mint points and rewards for
anyone. So the three things that touch a guest's standing — staff vibe, recorded spend, and perks —
all check `verified` inside the database, not in the app.

---

## 6. Workflow — a night at the bar

```
  BAR                                    GUEST                              WALL SCREEN
   │                                       │                                     │
   │ "Open a room" (VenueApp)              │                                     │
   ├──────────────────────────────────────▶│                                     │
   │   room code: "amber-fox"              │                                     │
   │                                       │  joins the room (/party/<id>)       │
   │                                       │                                     │
   │                                       │  taps "Check in"  ──▶ +1 SPARK      │
   │                                       │   points.ts → awardCheckin()        │
   │                                       │   (server decides; once a day)      │
   │                                       │                                     │
   │                                       │  friends tap "Vibe" on each other   │
   │                                       │   points.ts → awardVibe()           │
   │                                       │   positive-only, one per reason     │
   │                                       │                                     │
   │ waiter opens the guest list,          │                                     │
   │ taps "great vibe"                     │                                     │
   ├──────────────────────────────────────▶│  +1 VIBE                            │
   │   points.ts → staffAwardVibe()        │                                     │
   │                                       │                                     │
   │ guest closes the tab: ₹2,400          │                                     │
   ├──────────────────────────────────────▶│  spend recorded                     │
   │   points.ts → recordSpend()           │   ⚠ ONLY the bar can do this        │
   │                                       │                                     │
   │                                       │  perk card: "₹2,400 / ₹3,000        │
   │                                       │   toward a free pour"               │
   │                                       │   perks.ts → usePerkProgress()      │
   │                                       │                                     │
   │  casts bwdy.site/kiosk/amber-fox ─────┼────────────────────────────────────▶│
   │                                       │                                     │ shows sparks + vibe
   │                                       │                                     │ for opted-in guests
   │                                       │  taps "Share your score" ──▶ a card │ (and, in small print,
   │                                       │   ScoreCard.tsx → a PNG             │  tabs — but only for
   │                                       │                                     │  double-opted-in flexers)
```

---

## 7. Workflow — the consent switches (all default **OFF**)

Every loud thing in this layer is a switch in **You → settings**. Nothing is on until a person turns
it on, and each switch buys exactly one thing:

```
  You → settings
  ┌──────────────────────────────────────────────────────────────────────────┐
  │ ▢ Leaderboard in Together     compete_visible                            │
  │      → adds the Board tab, and puts you on your friends' board.          │
  │      → friends_board() returns ONLY people who also switched this on,    │
  │        so you are never ranked in front of someone without asking.       │
  ├──────────────────────────────────────────────────────────────────────────┤
  │ (venue screens are NOT a setting here — see below)                       │
  ├──────────────────────────────────────────────────────────────────────────┤
  │ ▢ Public profile              profile_visibility: friends | fof | public │
  │      → who may open /u/<your-handle>. Counts only, always.               │
  │ ▢ One social link             social_handle                              │
  │      → a handle you're fine with strangers finding. Never a phone/email. │
  ├──────────────────────────────────────────────────────────────────────────┤
  │ ▢ Weekly limit / dry days     goals.ts                                   │
  │      → the quiet counterweight. On your device only. Never shared,       │
  │        never scored, never shown to a bar.                               │
  └──────────────────────────────────────────────────────────────────────────┘
```

**The bar's screen is consented to IN THE ROOM, for that night only** (`room_consent`, migration 019):

```
  inside a venue's room (/party/<id>)          the bar, when it opens the room
  ┌────────────────────────────────────┐       ┌──────────────────────────────┐
  │ ▢ Show me on the screen            │       │  Screen runs for  4h 6h 8h   │
  │ ▢ …and show my tab   (needs the ▲) │       │  → parties.board_until       │
  └────────────────────────────────────┘       └──────────────────────────────┘
                    └──────────── when the board expires, EVERYONE drops off it ───┘
```

This used to be a permanent global switch on your profile, and that was wrong: flip it on for one fun
night and your name sat on every venue's TV forever. **Consent to be on a screen *tonight* is not
consent to be on screens *always*.** So it's granted per room, and it dies with the night.

**Contact information is not shareable by design.** There is no field for a phone number, an email, or
an address anywhere in this layer. A flexer can show a receipt total; they cannot show a way to reach
them. That was a deliberate product decision, not an oversight.

---

## 8. Workflow — visiting someone's profile

```
   /u/<handle>  →  publicProfile.ts → public_profile() in the database
                                            │
                        the OWNER's tier decides, not the visitor:
                        ┌───────────────────┴───────────────────┐
                        ▼                   ▼                   ▼
                   'friends'              'fof'              'public'
              accepted friends     friends + friends'      anyone at all,
                    only              friends              even signed-out
                        └───────────────────┬───────────────────┘
                                            ▼
                            you always see: a 12-week mosaic,
                            a total, how many kinds of drink,
                            and their one social link — COUNTS ONLY.

                            you never see: notes, moods, photos,
                            spend, or where they were.
```

---

## 9. Who can write what (the security table)

This is the part to check if you ever doubt the app. Each rule is enforced **inside the database**, so
it holds even if someone bypasses our app entirely and calls the API by hand.

| Thing | Who can create it | How it's enforced |
| --- | --- | --- |
| A **spark** | Nobody, directly. Only `award_checkin()`. | The client has **no insert permission** on sparks at all. (It used to, and that was a real hole: you could mint unlimited sparks by inventing a reason. Fixed in `016`.) |
| A **vibe** from your table | A fellow guest in the room. | RLS + a unique index: one per person, per reason, per day. |
| A **vibe** from the bar | Staff of a **verified** venue. | `staff_award()` checks both. |
| **Spend** | **Only** staff of a **verified** venue, via `record_spend()`. | `spend_events` has **no insert policy whatsoever** — a guest cannot write their own tab by any route. |
| A **perk** | A manager of a **verified** venue. | Policy on `venue_perks`. |
| `verified = true` | **Only you**, from a terminal, with the service key. | A trigger blocks any signed-in session from touching the column. `scripts/verify-venue.mjs` is the only door. |

Read that table once more and note the shape of it: **the things that could be abused for money or
status are the things a user cannot write.** That's the whole security design in one sentence.

---

## 10. The function reference

**Guest side** — `src/lib/points.ts`
- `usePointsBoard(partyId)` — tonight's board for a room.
- `awardCheckin(partyId)` / `useHasCheckedIn(...)` — the +1 spark, and whether you've had it.
- `awardVibe(...)` / `undoVibe(...)` — hand a fellow guest a positive word, or take it back.
- `useFriendsBoard(enabled)` — the Together leaderboard (opted-in friends only).
- `useCompeteVisible()` / `setCompeteVisible(...)` — the leaderboard switch.
- `useKioskVisible()` / `setKioskVisible(...)` — the wall-screen switch.
- `useFlexReceipts()` / `setFlexReceipts(...)` — the flex switch.
- `useKioskBoard(code)` / `useRoomTabs(code)` — what the wall screen polls (both anonymous).

**Bar side** — `src/lib/venues.ts`, `src/lib/perks.ts`, `src/lib/points.ts`
- `useMyVenues()`, `createVenue(...)`, `updateVenue(...)`, `deleteVenue(...)`
- `useVenueStaff(...)`, `addStaff(...)`, `removeStaff(...)`
- `useVerification(...)`, `requestVerification(...)`, `withdrawVerification(...)`
- `setVenuePerk(venueId, kind, threshold, reward)` — `kind` is `'visits'` or `'spend'`.
- `useRoomGuests(partyId)`, `staffAwardVibe(...)`, `recordSpend(...)`

**Both** — `src/lib/perks.ts`
- `usePerkProgress(venueId)` — how close *you* are to this venue's reward.

**Sharing** — `src/components/share/`
- `ScoreCard.tsx` — shares a **score** (sparks + vibe + rank). `ShareCard.tsx` shares an **entry**.
  Both paint on the shared scaffold in `canvas.ts` (1080×1350, Minimal/Poster).
- The score card renders **no rupee figure, ever.** Don't add one.

---

## 11. The rules a future developer must not break

1. **The calendar never shows a score.** All of this lives in Together, the venue app, and the wall
   screen. The diary stays a calm, private, score-free place. That is the product.
2. **Vibe is positive-only.** No negatives, no ratings, no blacklist — not now, not "just for staff".
3. **Spend is never the public rank.** Sparks and vibe rank people. Money buys a *private* perk from
   *one* bar, and nothing else. The moment the leaderboard sorts by rupees, this app is a different,
   worse app.
4. **Sparks never pay for frequency.** Not for checking in again, not for a nightly bonus, not for a
   "you visited 5 times this week" badge. A public score that rises the more you go out drinking is the
   thing we most need not to build — and it is very easy to rebuild by accident.
5. **The streak counts days you LOGGED, not days you drank.** A dry day keeps it. Never make a drink
   the only way to hold a streak — that is loss aversion pointed straight at consumption.
6. **A perk is never promoted publicly.** It stays private between one guest and one bar. A public feed
   of drink offers turns the app from a diary into an alcohol advertising channel, which is
   *specifically* illegal in some of our target markets (see `internal/legal-and-compliance.md`).
7. **Never give the client an insert policy on `spend_events` or on sparks.** They are server-written
   for a reason — see the table in §9.
8. **Consents default OFF, stay independent, and the screen consent expires.** Don't collapse switches
   into one "social mode", and never revive a permanent global "put me on bar TVs" flag.
9. **Totals stay derived.** Don't add a `total_sparks` column to speed something up.
10. **No mini-games.** One was built and scrapped. Points come from *people* — your table and the bar's
    staff — and from what you *try*. Never from a quiz, and never from a drinking game (that last one is
    explicitly a banned promotion under UK licensing law).

---

## 12. The perk is shaped by law, not by taste

If you are ever tempted to "simplify" the house perk — to drop the country field, or default the reward
back to a free drink — read this first. **The obvious version of this feature is illegal in several
countries.**

- **Ireland** bans awarding loyalty points on alcohol purchases, outright.
- **The UK** defines an irresponsible promotion as *"the supply of an alcoholic drink free of charge or
  at a reduced price on the purchase of one or more drinks"* — which is, word for word, a spend-based
  free-drink perk. In England and Wales it's a mandatory licensing condition, and **the licensee carries
  the liability**: a bad perk of ours could cost a partner bar its licence.
- **Massachusetts and Utah** still restrict drink deals.
- **India** (home) permits the perk — but restricts alcohol *advertising* severely, which is why a perk
  is always **private between one guest and one bar** and there is no public "offers" feed. Building one
  would turn a diary into an alcohol advertising channel.

**The insight that saves the feature:** *a loyalty scheme whose prize is not alcohol is not an alcohol
loyalty scheme.* So the reward defaults to **non-alcoholic** (a coffee, a dessert, priority entry), and
where the law requires it, that's the only option — the bar still gets its regular back.

How it's enforced:

```
   venues.country / .region  ──▶  perk_policy(country, region)
                                        │
                        ┌───────────────┴───────────────┐
                        ▼                               ▼
              allow_alcohol_reward?             allow_spend_perk?
                        │                               │
                        └──────────┬────────────────────┘
                                   ▼
                    venue_perks_policy  (a BEFORE trigger)
                                   │
              an unlawful perk is REFUSED BY THE DATABASE — a bar in
              Dublin cannot save one even by calling the API directly.
```

`src/lib/perks.ts` mirrors the policy (`perkPolicy`, `perkPolicyNote`) so the dashboard can *explain the
rule* rather than just blocking the button — a licensee needs to understand it. But the **database is the
authority**, and `tests/perkPolicy.test.ts` pins the rules. If one of those tests starts failing, someone
has made a perk unlawful in a live market: fix the code, not the test.

Full research, citations, and the pre-launch legal checklist live in `internal/legal-and-compliance.md`
(git-ignored — maintainer and team only).

Next: **[06 — Security & privacy](06-security-and-privacy.md)** for the wider picture, or
**[10 — Deploy](10-deploy.md)** to put it live.
