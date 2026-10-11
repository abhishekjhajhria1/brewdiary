// A LIVE screenshot tour: the real app, signed in to a real (throwaway, local) Supabase,
// showing data that really went through the server — a friend, their shared night with
// a photo, cheers and comments, a circle, a party, a Split balance. Not part of the
// normal suite: skipped unless built with SUPABASE_URL and TOUR.
//   (with `LIVE_KEEP=1 npm run live:local` running)
//   flutter test test/live/live_tour_test.dart --dart-define=TOUR=true --update-goldens \
//     --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
// Output: test/live/tour/*.png (git-ignored).
@Tags(['live'])
library;

import 'dart:io';

import 'package:brewdiary/app.dart';
import 'package:brewdiary/config.dart';
import 'package:brewdiary/data/auth.dart';
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/circles.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/data/friends.dart';
import 'package:brewdiary/data/parties.dart';
import 'package:brewdiary/data/split.dart';
import 'package:brewdiary/data/wishlist.dart';
import 'package:brewdiary/ui/screens/discover_screen.dart';
import 'package:brewdiary/ui/screens/split_screen.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers.dart' show loadFonts;

const _tour = bool.fromEnvironment('TOUR');

String _stamp() => DateTime.now().millisecondsSinceEpoch.toRadixString(36);

Future<void> _wait(bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Let real network calls finish and the screens rebuild with what came back.
Future<void> _live(WidgetTester t, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pump(const Duration(seconds: 1));
}

Future<void> _shot(WidgetTester t, String name) => expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('tour/$name.png'));

void main() {
  final run = _tour && Config.cloud;
  final pass = 'night-out-2026';
  final miraEmail = 'mira.${_stamp()}@example.com';
  final arjunEmail = 'arjun.${_stamp()}@example.com';

  setUpAll(() async {
    if (!run) return;
    await loadFonts();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'brewdiary.theme': 'dark', 'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'});
    await Prefs.init();
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey, authOptions: const FlutterAuthClientOptions(detectSessionInUri: false));
    auth.init();
    entryStore.wire();
    wishlist.wire();

    // Arjun: a night out, shared with friends, with a photo.
    await auth.signUp(arjunEmail, pass, 'Arjun');
    await _wait(() => auth.isAuthed);
    final arjun = auth.meId!;
    final night = entryStore.addEntry(
      date: todayKey(),
      drink: 'Mezcal Negroni',
      type: DrinkType.cocktail,
      mood: 'smoky',
      venue: 'Soka, Bandra',
      note: 'The house one beats mine, sadly.',
      photos: [Photo(id: newId(), url: File('test/fixtures/night.jpg').absolute.path)],
    );
    await _wait(() => entryStore.entries.any((e) => e.id == night.id && (e.photos?.first.url.startsWith('http') ?? false)));
    entryStore.setVisibility(night.id, EntryVisibility.friends);
    final coffee = entryStore.addEntry(date: toKey(addDays(appNow(), -1)), drink: 'Pour-over', type: DrinkType.coffee, mood: 'slow');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    entryStore.setVisibility(coffee.id, EntryVisibility.friends);

    // Mira: her own diary, then Arjun as a friend, a circle, a party, a Split.
    await auth.signOut();
    await _wait(() => !auth.isAuthed);
    await auth.signUp(miraEmail, pass, 'Mira');
    await _wait(() => auth.isAuthed && auth.meId != arjun);
    final mira = auth.meId!;
    entryStore.addEntry(date: todayKey(), drink: 'Paloma', type: DrinkType.cocktail, mood: 'bright', venue: 'Soka, Bandra');
    entryStore.addEntry(date: toKey(addDays(appNow(), -2)), drink: 'Lime soda', type: DrinkType.none);
    await FriendsApi.sendRequest(arjun);
    await CirclesApi.create('Thursday regulars');
    final party = await PartiesApi.create(name: "Mira's birthday", date: toKey(addDays(appNow(), 2)), venue: 'Soka, Bandra');
    await SplitApi.addExpense(payerId: mira, description: 'Soka round', amount: 1800, participantIds: [mira, arjun]);

    await auth.signOut();
    await _wait(() => !auth.isAuthed);
    await auth.signIn(arjunEmail, pass);
    await _wait(() => auth.isAuthed);
    await FriendsApi.accept((await FriendsApi.requests()).single.friendshipId);
    await FriendsApi.toggleCheers(night.id, false);
    final circle = (await CirclesApi.mine());
    if (circle.isEmpty) {
      final code = (await db!.from('circles').select('invite_code').limit(1)).firstOrNull;
      if (code != null) await CirclesApi.join(code['invite_code'] as String);
    }
    final p = (await db!.from('parties').select('invite_code').eq('id', party.id!)).firstOrNull;
    if (p != null) await PartiesApi.join(p['invite_code'] as String);

    // The tour is Mira's phone.
    await auth.signOut();
    await _wait(() => !auth.isAuthed);
    await auth.signIn(miraEmail, pass);
    await _wait(() => auth.isAuthed);
    await FriendsApi.addComment(night.id, 'Save me one next time.');
    await entryStore.reload();
  });

  testWidgets('the real app on a real server: calendar, Together, a friend\'s night, Split', (t) async {
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    t.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
    addTearDown(t.view.reset);
    Shell.deepLinks = false;
    DiscoverScreen.sensors = false;

    await t.pumpWidget(const BrewdiaryApp());
    await _live(t);
    await _shot(t, 'live1_calendar');

    await t.tap(find.byKey(const ValueKey('tab-together')));
    await _live(t, rounds: 20);
    await _shot(t, 'live2_together');
    await t.drag(find.byType(Scrollable).hitTestable().first, const Offset(0, -600), warnIfMissed: false);
    await _live(t);
    await _shot(t, 'live3_together_feed');

    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const SplitScreen()));
    await _live(t, rounds: 16);
    await _shot(t, 'live4_split');

    // Leave cleanly: Supabase's token refresher started when the app "came to the
    // foreground" inside the test; stop it, unmount, and let the app's timers run out.
    db!.auth.stopAutoRefresh();
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
  }, skip: !run);
}
