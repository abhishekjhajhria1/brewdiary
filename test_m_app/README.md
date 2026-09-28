# brewdiary — the mobile app (Flutter, Android + iOS)

The **user app** (not the bar portal), ported from the Next.js website to Flutter.
It uses the **same Supabase backend** as the website — the same tables, row-level
security, RPCs and legal checks — so nothing about the database changes. The four
server routes (Ninkasi, account deletion, …) stay on the website; the app calls them
over HTTPS.

## Run it

```bash
cd test_m_app
flutter pub get
cp env.example.json env.json          # fill in your Supabase URL + anon key
flutter run --dart-define-from-file=env.json
```

With no `env.json` the app runs in **local mode**, like the website without its env:
the diary lives on the phone and Together (the social tab) is hidden.

## Build

**Android** (on any machine with the Android SDK):

```bash
flutter build apk --release --dart-define-from-file=env.json        # sideload / test
flutter build appbundle --release --dart-define-from-file=env.json  # Play Store (.aab)
```

For a Play upload, create a keystore and `android/key.properties`
(`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) — it's git-ignored. Without
it, release builds are signed with the debug key.

**iOS** (on a Mac with Xcode):

```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # set your Team under Signing & Capabilities
flutter build ipa --release --dart-define-from-file=env.json
```

Bundle id: `site.bwdy.brewdiary` (change it in Xcode / `android/app/build.gradle.kts`
if you want another).

## Checks

```bash
flutter analyze      # static analysis — clean
flutter test         # 47 logic parity tests + 4 widget tests (51 total)
```

`test/core_test.dart` ports the website's vitest suite, so the streaks, dry days,
drink matching, money formatting (₹1,23,456), jurisdiction and split maths are
proven to behave exactly like `src/lib`. `test/app_test.dart` boots the real app and
walks age gate → landing → log a drink → calendar / You / Ninkasi; its goldens in
`test/goldens/` double as screenshots of each screen.

## What's in it

| Web | Mobile |
|---|---|
| Age gate (per-country legal age, traveller re-check) | ✅ |
| Landing + sign-up / sign-in / password reset | ✅ (reset finishes on the website) |
| Calendar, month grid, year mosaic, streak strip, milestones, "looking back" | ✅ |
| Log sheet: autocomplete, "≈ tidy name", mood, note, photos, place, who, kind, undoable remove, dry day | ✅ |
| Share an entry to friends / circles / parties; share-as-image cards | ✅ (native share sheet) |
| Extras (cigarettes, water + glass size), gentle limits, balance card | ✅ |
| Together: feed, cheers, comments, friend requests, search, friend picks, friend mosaic, vouch | ✅ |
| Plans (coming up / mine / create / invite / requests / soft signals / block / report) | ✅ |
| Circles + challenges + competitions | ✅ |
| Parties + party room (RSVP, invite, recap, points, vibe, check-in, house perk, thank the bar, screen consent) | ✅ |
| Split (balances, add expense, settle up) | ✅ |
| Discover (compass, near-me, venues on brewdiary, area + global trends) | ✅ |
| Ninkasi (streamed from `/api/bartender`, scripted fallback offline) | ✅ |
| You: stats, year, to-try, words, photos, shelf, pantry, journey, all settings | ✅ |
| Handle re-roll, trust standing, profile privacy, blocks, venue notes | ✅ |
| Data export + real account deletion | ✅ |
| Public profiles (`/u/<handle>`), invite links (`/p/<code>`) | ✅ (opened as deep links) |
| **Nightly reminder** | ✅ **real scheduled notification** (the website's toggle never fired one) |
| Live-camera presence check | ❌ not ported yet (MediaPipe on the web; needs ML Kit on mobile) |
| Moderation queue (moderators only) | ❌ stays on the website |
| Bar portal / kiosk | ❌ out of scope (user app only) |

## One-time setup outside the app

1. **Deploy the website change in this branch.** `src/lib/supabase-server.ts` now also
   accepts `Authorization: Bearer <token>` (the phone has no cookies). Until it's
   deployed, "Delete my account" in the app returns "Not signed in."
2. **Deep links** (optional but nice — invite links open the app):
   - Android: host `https://bwdy.site/.well-known/assetlinks.json` with your release
     key's SHA-256 (`keytool -list -v -keystore upload-keystore.jks`), package
     `site.bwdy.brewdiary`.
   - iOS: add the *Associated Domains* capability (`applinks:bwdy.site`) in Xcode and
     host `https://bwdy.site/.well-known/apple-app-site-association`.
3. **Supabase Auth → URL configuration:** keep `https://bwdy.site/reset` allow-listed
   (password reset emails open the website's reset page).

## Layout

```
lib/
  core/      pure logic, ported 1:1 from src/lib (dates, derive, drinks, money, …)
  data/      Supabase + device storage: auth, entries, wishlist, social, settings,
             the reminder, the Ninkasi stream
  ui/        theme (liquid-glass tokens from globals.css), widgets, screens
assets/      bundled fonts (Hanken Grotesk + Newsreader, OFL) and the app icon
test/        parity tests, widget tests, golden screenshots
```

House rules carry over from the website: everything visual is derived, never stored;
nothing rewards drinking more; the database is the authority on what's legal.
