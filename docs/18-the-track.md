# 18 — The track: from here to a real night at a real venue

**Decided 1 October 2026:** the guest website will be retired once both apps work — only the bar portal
(`bar.bwdy.site`) stays. Website-only items below drop away; the apps carry them.

Written 30 September 2026, right after the venue app (PR #2) was merged into `main`. This is the one list
everyone works from — the maintainer, Pankaj, and any AI session. Work top to bottom; each phase ends
with a **gate**, a thing you can do by hand that proves the phase is done. Don't start a phase's code
before the one above it passes its gate unless the item says it can run in parallel.

Tick items here as they land (and in the app's own `CHANGELOG.md`).

---

## Where we actually are (checked, not guessed)

| Part | State on `main` |
| --- | --- |
| Website | lint + 227 tests + build green |
| Database | every migration (`schema.sql` → `054`) applies to a fresh Postgres; `db:audit` + `db:verify` pass (485 checks) |
| App ↔ schema | `db:contract`: all 459 database calls fit — website 198, users app 136, venue app 125 |
| Users app (`test_m_app`) | analyze clean, tests green; runs fully offline-first when signed out; **not yet pointed at the real server** |
| Venue app (`mobile-bar`) | analyze clean, 89 tests green; runs as a demo venue with no env; 56 of 232 plan items done, 30 partly |
| Shared core (`packages/brewdiary_core`) | 67 tests green |
| Live database | **migrations 042–054 not run yet** — the apps' newer features fail against it until they are |

What's missing is not "more screens". It is: (1) the real server switched on, (2) a handful of privacy
bugs that would embarrass us on day one, (3) a diary that survives no signal, and (4) the guest and the
venue actually meeting — today they share a database but never see each other live.

---

## Pankaj's review of the users app — the verdict on each item

`test_m_app/IMPROVEMENTS.md` lists 17 changes. Every claim was checked against the code; all 17 are
real. Not all of them should be done now.

| # | Change | Verdict | Why / how |
| --- | --- | --- | --- |
| 1 | Offline launch looks signed out, empty diary | **Do — Phase 2** | Confirmed (`auth.dart` `_applySession` catch → anon). Cache profile + entries per user; never "signed out" because a read failed. |
| 2 | A drink logged with no signal vanishes | **Do — Phase 2** | Confirmed (insert fails → rolled back silently). Outbox on the phone, sent in order. Ids are already client-made, so retries are safe. |
| 3 | Diary photos are public | **Parked by the maintainer** | The guest website is being retired once both apps work (only the bar portal stays). Note: the bucket itself is `public: true`, so a photo's URL opens without signing in from any app — retiring the site doesn't change that. Revisit before the public launch: private bucket + signed links. |
| 4 | Photos keep GPS in EXIF | **Not doing — maintainer's call** | Photo metadata stays: it's needed to validate a person's profile. Shared overlay images are re-drawn as new PNGs, so they carry none. |
| 5 | Deleted photos stay online | **Do — Phase 1** | Confirmed twice: deleting an entry leaves the files, and account deletion lists only `user/` while files live at `user/entry/photo`. Legal gap (GDPR Art. 17, DPDP). |
| 6 | Import can wipe the cloud diary | **Do — Phase 1** | Confirmed (delete-then-insert). Upsert first, then delete what's not in the import. Same fix on the website. |
| 7 | "Help train Ninkasi" on by default, wrong label | **Done (label) — stays on** | The maintainer keeps it on by default. The label now says what happens: kept on the phone for your book, and sent without your name to the training set. |
| 8 | Export leaves most things out | **Done — as a book** | "Your diary, as a book": a minimal PDF of every entry, the numbers, places, Together, Split, to-try, what venues keep on you and the Ninkasi chats (`lib/data/export.dart`, `lib/ui/export/diary_book.dart`). A machine-readable JSON copy stays as a quiet second option (data portability). |
| 9 | iPhone ignores bwdy.site links | **Do — Phase 4** | Needs the Apple team id and a paid developer account from the maintainer; the entitlements file can be added now. |
| 10 | No iPhone widgets | **Later — Phase 4, on a Mac** | A WidgetKit extension can't be built or tested without Xcode. Written and tested on the maintainer's Mac. |
| 11 | Optional app lock | **Do — Phase 4** | Small (`local_auth`). Blurring in the app switcher only when the lock is on, so screenshots of the mosaic still work for everyone else. |
| 12 | Code sign-in by default, 8-char passwords | **Wait — after SMTP** | Supabase's built-in mailer allows only a few emails an hour; making codes the default before Resend SMTP is set would break sign-up. 8-char minimum: do it on web + app **and** in the Supabase Auth setting, or it's cosmetic. |
| 13 | Thumbnails slow and heavy | **Do — Phase 2, with #3** | Decode at thumbnail size and cache on disk. With signed links the cache key must be the storage path, not the URL — so it lands with #3. |
| 14 | English only | **Later — Phase 6** | Right idea, big change across three apps; do it once the words stop moving (after the pilot). Hindi first. |
| 15 | Sync logic untested | **Do — Phase 2, first** | The venue app's `Backend` / `SupabaseBackend` / `DemoBackend` pattern. It's what makes #1 and #2 testable. |
| 16 | Stricter lints | **Do — Phase 2** | With #2 — they point straight at the unchecked writes. |
| 17 | Small things | **Do — Phase 2** | Picker search box disposal; "load more" in the feed; orphaned local photo files. |

Nothing was rejected. Two are timed by outside things (#10 needs a Mac, #12 needs SMTP) and one is
timed by stability (#14).

---

## Phase 0 — Switch the real server on (the maintainer; ~1 evening)

Nothing below can be tried for real until this is done. None of it is code.

- [ ] Run migrations `042` → `054` in order with `node scripts/db.mjs supabase/0NN_*.sql`, then
      `npm run db:audit` and `npm run db:verify` against the live database.
- [ ] Supabase Auth: email templates carry `{{ .Token }}`; custom SMTP (Resend); OTP expiry 10 min
      (`docs/12` §4).
- [ ] Vercel: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
      (server only), `AI_API_KEY`; deploy (`docs/10`).
- [ ] Cloudflare: DNS for `bwdy.site` and `bar.bwdy.site` (`docs/14`).
- [ ] `env.json` in `test_m_app/` and `mobile-bar/` with the URL + anon key (never the service key).

**Gate:** one person signs up with an emailed code on the website, logs a drink, and sees it on the users
app; a venue created on the venue app shows on `bar.bwdy.site`.

## Phase 1 — Trust: fix what would embarrass us on day one (code; ~1 week)

Can start now, in parallel with Phase 0 — it's proven on the local database first.

- [ ] ~~**Private photos** (review #3)~~ — parked by the maintainer (the guest website is being retired);
      revisit before the public launch, because the bucket is public to any URL holder.
- [ ] **Photos leave with their entry** (#5): delete files with the entry and on reset; account deletion
      walks every folder.
- [x] ~~No location in photos (#4)~~ — not doing: metadata validates profiles (maintainer's call).
- [ ] **Import can't wipe** (#6): upsert-then-prune on both.
- [x] **Ninkasi training** (#7): stays on by default (maintainer's call); the label now says what happens.
- [x] **Export everything** (#8): "Your diary, as a book" — a minimal PDF in the users app; JSON kept as
      a second option.
- [x] **A diary is never deleted** (maintainer, 1 Oct): put away instead (055); clearing it takes an
      emailed code checked by the database; import adds and never overwrites.
- [x] **Photos a year at most** (057): a daily cron removes older files; account deletion finds every
      file, however deep.
- [x] **Photo overlays**: twelve share designs (receipt, lineup, stats, menu, the haul, ticket, cheers,
      polaroid, film, postcard, stamp, mosaic) built from the night's logs and accepted table orders,
      with optional prices and a bill total the person types.
- [ ] **Stop searching everyone at the till** (venue plan 1.4 #4): the venue app's punch/visit flow
      identifies a guest by a short-lived code the guest shows (see Phase 3 "my card"); until that lands,
      `search_users` from the venue app is limited to people who have been in this venue's rooms.

**Gate:** `npm run db:local` green; the book opens on a phone with every section filled from a real
account; an imported diary can't be wiped by a failed upload.

## Phase 2 — Never lose a diary (users app; ~1–2 weeks)

- [ ] `EntryBackend` interface + Supabase and local implementations (review #15), with tests for add,
      rollback, sign-in migration and import.
- [ ] Launch from the phone's cache; a quiet "offline" line; never "signed out" because a read failed (#1).
- [ ] Outbox: writes kept on the phone and sent in order; "2 waiting to sync" (#2); lints on (#16).
- [ ] Thumbnails at thumbnail size, cached by storage path (#13); small things (#17).
- [ ] Same behaviour on the website's `store.ts` where it applies (a failed write says so).

**Gate:** in airplane mode, open the app signed in, log three drinks, delete one, kill the app, turn the
network on — the diary on the website matches exactly.

## Phase 3 — The guest and the venue meet (both apps + website; ~2–3 weeks)

This is the part that makes brewdiary feel like magic instead of two apps: tap a table, and the venue
and the guest are in the same night, live — with the guest in control of what's shared.

- [x] **My card** (M7.2 / M17.5): a 6-letter guest code (10 minutes) the staff type at the till or in the
      guest book (056). Searching everyone is gone from the venue app.
- [x] **Taste at the table** (maintainer, 1 Oct): opening a venue's table or menu link shares the taste
      card with its drink-makers for 8 hours, after a one-time yes; bar tickets show the table's taste;
      the venue sees who's in tonight (056).
- [ ] **Join this table** (M7.1 / M17.2): the table link asks "Join table 7 at <venue>?"; yes joins
      tonight's room and the table session; "Leave" any time.
- [x] **Taste for tonight** (M7.5 / M17.4): hide any line on the passport; "nothing with alcohol tonight"
      goes first; 8 hours; stop any time. (Diet and allergies fields: the database takes them; the
      passport's inputs for them are still to add.)
- [ ] **My tab and receipts** (M17.7): the guest sees only their own lines; a receipt offers "add these to
      my diary" — the guest writes their own entries; "send to Split".
- [ ] **Live, not polled** (M4.9): Supabase Realtime for new tickets, table requests and "ready", with
      the current 15-second polling kept as the fallback.
- [ ] **Push** (M5.6, M7.6): "your order was accepted", "food's ready" to the server, a table request to
      staff. Needs FCM (Android) and APNs (iOS) keys from the maintainer.
- [ ] Guest-side parity on the website for each of the above (M17.10).

**Gate:** two phones and one tablet. A guest taps a table tag, joins, shares "alcohol-free tonight",
orders a lime soda; the bar tablet shows the ticket within 2 seconds; staff mark it ready; the guest's
phone buzzes; the bill closes; the guest adds it to their diary; the venue's guest book shows a visit and
no diary.

## Phase 4 — iPhone parity and first-run polish (~1 week, partly on a Mac)

- [x] Associated Domains entitlements in both apps (#9). Still needed: APPLE_TEAM_ID on the website and
      the capability on the App IDs; then build both apps on an iPhone.
- [ ] iPhone widgets — mosaic, quick log, lock screen (#10, on the Mac).
- [x] Optional app lock (#11).
- [x] Code sign-in as the default; 8-character new passwords in the apps (#12). Set the same in Supabase.
- [x] Venue next-step cards (M1.14).
- [ ] Crash reporting with no personal data, both apps (M0.10).

**Gate:** a person who has never seen brewdiary installs both apps from TestFlight / Play internal
testing and is logging (or serving) in under two minutes, without help.

## Phase 5 — The pilot (M21)

- [ ] Store accounts, signing keys, listings, age rating, review notes (the venue app is a business tool).
- [ ] One pilot venue: set up, train the team, watch a real night, fix, repeat — three nights minimum.
- [ ] Feature switches per venue; the web dashboard keeps working beside the app.

**Gate:** the pilot venue runs a full night on brewdiary and asks to keep it.

## Phase 6 — After the pilot (in the order the pilot asks for)

- Hindi and translations (#14, M0.9).
- Bill tax lines, service charge, cash drawer, X/Z reports (M6 — confirm with a CA first; a Z report is
  a legal record).
- Inventory and recipes (M9), bookings (M11), printing (M5.7), shared-device mode (M1.11).
- India's state drinking ages (venue plan 1.4 #7) before any ID-check feature ships widely.
- **The July branch** `phase-ab-passport-cartographer`: keep what doesn't overlap (cartography,
  expeditions, recipes, cups, palate neighbours, nights) renumbered after the newest migration; drop what
  PR #2 replaced (roles/staff insights, orders & bills); audit `dining_offers` against "a menu is not an
  offer" before keeping any of it. Five files conflict today.

---

## Blocked on things only the maintainer can give

| Needed for | What |
| --- | --- |
| Phase 0 | Supabase URL + anon key (apps), service-role key (Vercel only), Resend SMTP, Groq `AI_API_KEY` |
| Phase 3 push | Firebase project (FCM) and an APNs key |
| Phase 4 | Apple developer account + team id; a Mac with Xcode for widgets and iOS builds |
| Phase 5 | Play Console + App Store Connect accounts; a pilot venue |
| Later | Google Places key (live Discover), Stripe (payments), funding for photo-ID verification |

## House rules every item is checked against

Nothing rewards drinking more · a guest never writes their own reward · no diary ever reaches a venue ·
no cross-venue read · legality lives in the database, deny-by-default · derived, never stored · private
means private · consent is a real yes.
