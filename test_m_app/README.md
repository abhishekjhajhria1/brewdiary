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
the diary lives on the phone, and the Together tab shows an introduction that says
this build isn't connected. With `env.json`, Together switches on once you sign in.

## Devices

Built for phones from roughly the last three years:

- **Android 12+** (API 31, `minSdk` in `android/app/build.gradle.kts`): predictive back,
  the Android 12 splash, a monochrome themed icon, drawing under the camera cutout,
  and the panel's full refresh rate (90/120 Hz) via `flutter_displaymode`.
- **iOS 17+** (deployment target in Xcode): ProMotion 120 Hz is on (`Info.plist`).
- Phones stay portrait. Foldables and tablets (600 dp+ on the short side) rotate
  freely, and pages centre at a comfortable width instead of stretching (content
  640, sheets 600, tab bar 480).

## Build

**Android** (on any machine with the Android SDK):

```bash
flutter build apk --release --dart-define-from-file=env.json        # sideload / test
flutter build appbundle --release --dart-define-from-file=env.json  # Play Store (.aab)

# Smallest APK for a modern phone (every phone in the target range is arm64):
flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=env.json
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
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
flutter test         # 47 logic parity tests, 4 app walk-throughs, 6 tests for the small moments
flutter test test/tour_test.dart --dart-define=TOUR=true --update-goldens         # screenshot tour → test/tour/
flutter test test/social_tour_test.dart --dart-define=TOUR=true --update-goldens  # the social screens
```

`test/core_test.dart` ports the website's vitest suite, so the streaks, dry days,
drink matching, money formatting (₹1,23,456), jurisdiction and split maths are
proven to behave exactly like `src/lib`. `test/app_test.dart` boots the real app and
walks age gate → landing → log a drink → calendar / You / Together / Ninkasi; its
goldens in `test/goldens/` double as screenshots of each screen. `test/moments_test.dart`
covers the streak milestones, the reminder's evenings, the bloom after a log and the
retry state. The tours (skipped unless `TOUR` is set) render every screen in the
states that break layouts: scrolled, keyboard up, small phone, large text, tablet.

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
| **Table menus** (new, web + app) | ✅ tap the venue's NFC tag (or scan its QR) → the menu opens in the app, with picks from your diary worked out on the phone and "Log it" per drink. Venues build the menu and write tags from the bar dashboard (Menu tab). Needs migration `042_menus.sql` |
| **Taste card** (mobile) | ✅ what you're into, worked out on the phone from your diary, to hold up for a bartender; hide any line; "Nothing with alcohol tonight" goes first in big type. Never sent to a venue |
| **Tonight** (mobile) | ✅ opt-in water-break nudges for one night; getting home: Uber (Ola, Rapido in India), directions home, send a friend a map link of where you are, call someone |
| **Home-screen widget** (Android) | ✅ this month's mosaic on the home screen, redrawn when the diary changes. iOS needs a WidgetKit extension added in Xcode (not in this repo yet) |
| **Nightly reminder** | ✅ **real scheduled notifications** (the website's toggle never fired one): skips evenings you've already logged, and tapping one opens today's log sheet |
| Small moments (mobile only) | ✅ the day you log blooms; an empty diary's today beckons; a quiet sheet at 7 / 30 / 100 / 365 nights in a row (dry nights count); Ninkasi's typing dots; a plain "couldn't reach brewdiary" with a retry instead of a misleading empty list |
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
     `site.bwdy.brewdiary`. Include `/m/*` (table menus) with `/p/*`, `/u/*`, `/party/*`.
   - iOS: add the *Associated Domains* capability (`applinks:bwdy.site`) in Xcode and
     host `https://bwdy.site/.well-known/apple-app-site-association` (paths `/p/*`, `/u/*`,
     `/party/*`, `/m/*`). iPhones read NFC tags in the background (XS and newer), so a
     tag opens the menu in the app once this is set up; until then it opens the website.
3. **Supabase Auth → URL configuration:** keep `https://bwdy.site/reset` allow-listed
   (password reset emails open the website's reset page).
4. **Run `supabase/042_menus.sql`** (the maintainer runs migrations), then
   `npm run db:audit` — it checks a menu can never carry an offer or appear in Discover.

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
