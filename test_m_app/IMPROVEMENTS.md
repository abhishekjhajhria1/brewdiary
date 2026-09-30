# The users app: changes to make next

A review of `test_m_app/` (about 15,500 lines of Dart), written on 30 September 2026. **None of this
is done yet** — it's the list to work from, most important first. Each item names the file and line
where the problem is, what goes wrong for a person using the app, and the fix.

The goals behind the order:

1. **Never lose a diary.** A drink logged is a drink kept, with or without signal.
2. **Private means private.** What someone marks private, or deletes, stays private or gone.
3. **Consent is a real yes.** Nothing is collected by default, and every switch says what it does.
4. **Works the same on iPhone and Android.**
5. **Easier to change safely** — tests where the risk is.

Tick an item off here when it lands, and add a line to [`CHANGELOG.md`](CHANGELOG.md).

---

## Fix first: bugs and privacy

### 1. Offline, a signed-in person looks signed out with an empty diary
- **Where:** `lib/data/auth.dart:109`, `lib/data/entries.dart:121`
- **What happens:** at launch the app reads the profile over the network. If that fails (a bar with no
  signal, a plane), `_applySession` marks the person signed out. And in cloud mode the diary lives only
  in memory, so an offline launch shows an empty calendar and a 0-day streak.
- **Fix:** cache the profile and the entries on the phone (per user id). Launch from the cache, show a
  quiet "offline" note, and refresh when the connection is back. Never fall back to "signed out"
  because a read failed.

### 2. A drink logged without signal quietly disappears
- **Where:** `lib/data/entries.dart:201–207` (add), `:263` (delete), `:278` (reset)
- **What happens:** the entry shows at once, then is removed without a word if the insert fails. A
  failed delete is ignored, so the entry comes back on the next refresh.
- **Fix:** an outbox — writes saved on the phone first and sent in order when online, with a small
  "2 waiting to sync" note. Ids are already made on the phone, so a retry is safe.

### 3. Diary photos aren't private
- **Where:** `supabase/schema.sql:212–218`
- **What happens:** the `photos` bucket is public, and its read rule lets any signed-in person list and
  open every file in it — including photos on private entries.
- **Fix:** a private bucket; read allowed to the owner, and to friends only for friends-visible entries
  (a join through `entry_photos` → `entries.visibility`); photos served through short-lived signed
  links. Add storage checks to `scripts/db-audit.mjs`, which has none today.

### 4. Photos can carry where they were taken
- **Where:** `lib/ui/widgets/log_sheet.dart:221`, `lib/ui/screens/photo_studio.dart:62`
- **What happens:** neither picker removes the photo's metadata (EXIF), which can include GPS
  coordinates. With item 3, a shared photo can reveal where someone lives.
- **Fix:** strip metadata before saving (re-encode without EXIF; `requestFullMetadata: false` on iOS).

### 5. Deleted photos stay online
- **Where:** `lib/data/entries.dart:263–282`; `src/app/api/account/delete/route.ts:55`
- **What happens:** deleting an entry, or resetting the diary, removes the photo rows but not the files.
  Account deletion lists only the person's top folder, but photos are stored one level deeper
  (`user/entry/photo`) and listing isn't recursive, so none are removed. That's an erasure gap under
  GDPR Art. 17 and India's DPDP Act.
- **Fix:** delete the files with the entry; make account deletion walk every folder (or delete by
  prefix). Also remove the phone's own copies of photos from deleted signed-out entries.

### 6. Import can wipe the cloud diary
- **Where:** `lib/data/entries.dart:288` (`replaceAll`)
- **What happens:** import deletes everything, then inserts. If the insert fails, the diary is gone,
  and imported photos aren't carried over.
- **Fix:** insert (upsert by id) first, then remove what isn't in the import — or one database function
  that does both in a transaction.

### 7. "Help train Ninkasi" is on by default, and its label is wrong
- **Where:** `lib/data/settings.dart:207`, `lib/ui/screens/bartender_screen.dart:104`,
  `lib/ui/screens/settings_screen.dart:607`; the website's `src/lib/training.ts:48` has the same default
- **What happens:** the label says chats are kept "on this phone", but the switch also sends
  `collect: true`, and the server saves the chat to the AI training database.
- **Fix:** off by default on both, a label that says what actually happens, and a one-time question in
  the Ninkasi tab.

### 8. "Export everything" leaves most things out
- **Where:** `lib/data/safety.dart:300`
- **What happens:** it reads 8 tables. Missing: comments, cheers, friends, circles, parties, plans,
  photos, dry days, vouches, blocks, reports, check-ins and table orders.
- **Fix:** one `export_my_data()` database function used by both the website and the app, and an audit
  check that every table holding a person's rows is in it.

---

## Next: iPhone support and everyday use

### 9. On iPhone, bwdy.site links never open the app
- **Where:** `ios/Runner` has no `.entitlements` file
- **Fix:** add the Associated Domains entitlement `applinks:bwdy.site` in Xcode, and set the Apple team
  id on the website so `/.well-known/apple-app-site-association` is served (`src/lib/appLinks.ts`).

### 10. iPhone has no home-screen widgets
- Android has three (quick log, mosaic, split). Add a WidgetKit extension with the mosaic and quick
  log, plus a lock-screen widget.

### 11. An optional app lock
- A drink diary is private. Offer Face ID / fingerprint to open the app (`local_auth`), and hide the
  screen in the app switcher.

### 12. Sign-up
- **Where:** `lib/ui/screens/landing_screen.dart:317`, `:329`
- Make the emailed code the default (the venue app uses only codes) and keep the password as the other
  choice. Raise the password minimum from 6 to 8 characters.

### 13. Photos load slowly and use a lot of memory
- **Where:** `lib/ui/screens/you_screen.dart:129`, `lib/ui/widgets/log_sheet.dart:483`,
  `lib/ui/screens/party_screens.dart:256`
- Thumbnails decode full-size images and download again each time. Decode at thumbnail size
  (`cacheWidth`) and cache on disk — which also shows your own photos offline.

### 14. English only
- Set up Flutter's `gen-l10n` translations, starting with Hindi. Money and dates already follow the
  place through `brewdiary_core`.

---

## When convenient: code health

### 15. The sync logic has no tests
- The data layer calls Supabase directly through the global `db`, so adding, rollback, the sign-in
  migration and import are untested. Put it behind an interface (the venue app's `Backend` /
  `SupabaseBackend` / `DemoBackend` is the pattern) — that also makes item 2 testable.

### 16. Stricter lint rules
- `unawaited_futures`, `discarded_futures` and `cancel_subscriptions` would flag the unchecked
  background writes behind item 2.

### 17. Small things
- `lib/ui/widgets/pickers.dart:76` never disposes its search box.
- The feed shows the 50 newest posts with no "load more" (`lib/data/friends.dart:104`).
- Photos from deleted signed-out entries stay in the app's folder (see item 5).
