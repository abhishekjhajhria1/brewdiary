// Shared test plumbing: real fonts (so goldens show the real type and icons) and a
// one-call boot of the app in LOCAL mode (no Supabase env).
import 'dart:io';

import 'package:brewdiary/app.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/menus.dart';
import 'package:brewdiary/data/auth.dart';
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/data/wishlist.dart';
import 'package:brewdiary/ui/screens/discover_screen.dart';
import 'package:brewdiary/ui/widgets/mosaic.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The evening every test lives in, so goldens don't drift with the calendar.
final testNow = DateTime(2026, 9, 28, 20, 30);

/// Flags that keep native plugins (links, sensors), randomness and the real
/// clock out of tests.
void configureForTests() {
  appClock = () => testNow;
  Shell.deepLinks = false;
  DiscoverScreen.sensors = false;
  AchievementTile.fixedDesign = 1;
}

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.view(File(p).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await load('Hanken Grotesk', ['assets/fonts/HankenGrotesk.ttf', 'assets/fonts/HankenGrotesk-Italic.ttf']);
  await load('Newsreader', ['assets/fonts/Newsreader.ttf', 'assets/fonts/Newsreader-Italic.ttf']);
  await load('Phosphor', ['assets/fonts/Phosphor.ttf']);
  await load('PhosphorFill', ['assets/fonts/Phosphor-Fill.ttf']);
  await load('PhosphorBold', ['assets/fonts/Phosphor-Bold.ttf']);
}

/// Boot the app. `size` is in logical pixels; `insets` fakes the notch/home
/// indicator; `keyboard` fakes an open keyboard of that height.
Future<void> bootApp(
  WidgetTester t, {
  Size size = const Size(390, 844),
  double dpr = 1.5,
  double text = 1,
  bool insets = false,
  double keyboard = 0,
  bool dark = true,
  bool age = true,
  bool signedIn = false,
  Map<String, Object> prefs = const {},
  bool settle = true,
}) async {
  t.view.physicalSize = size * dpr;
  t.view.devicePixelRatio = dpr;
  t.platformDispatcher.textScaleFactorTestValue = text;
  if (insets) t.view.padding = FakeViewPadding(top: 47 * dpr, bottom: 34 * dpr);
  if (keyboard > 0) t.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({
    'brewdiary.theme': dark ? 'dark' : 'light',
    if (age) 'brewdiary.age.v2': 'ok',
    'brewdiary.country.v1': 'IN',
    ...prefs,
  });
  await Prefs.init();
  auth.init();
  if (auth.isAuthed) await auth.signOut(); // the singleton outlives a test
  entryStore.wire();
  wishlist.wire();
  await t.pumpWidget(const BrewdiaryApp());
  // `settle: false` stops mid-motion (for screenshots of an animation in flight).
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
  if (signedIn) {
    entryStore.reseed();
    await auth.signUp('a@b.c', 'secret1', 'Sekhi');
    await t.pumpAndSettle();
  }
}

/// A sample venue menu (the cloud isn't there in tests).
Menu sampleMenu() => groupMenu([
      for (final r in [
        ('m1', 'Cocktails', 'Negroni', 'Gin, Campari, vermouth.', 450, 'cocktail', false),
        ('m2', 'Cocktails', 'Boulevardier', 'Bourbon in place of gin.', 480, 'cocktail', false),
        ('m3', 'Cocktails', 'Garden Spritz', 'Cucumber, elderflower, soda.', 320, 'soft', true),
        ('m4', 'Beer', 'Hazy IPA', 'Local, on tap.', 380, 'beer', false),
        ('m5', 'Coffee', 'Flat white', null, 220, 'coffee', false),
        ('m6', 'Food', 'Masala fries', null, 260, 'food', false),
      ])
        {
          'venue_name': 'Soka',
          'venue_city': 'Bandra, Mumbai',
          'venue_kind': 'bar',
          'currency': 'INR',
          'item_id': r.$1,
          'section': r.$2,
          'name': r.$3,
          'description': r.$4,
          'price': r.$5,
          'kind': r.$6,
          'no_alcohol': r.$7,
          if (r.$1 == 'm6') 'diet': 'veg',
          if (r.$1 == 'm6') 'allergens': ['gluten'],
        },
    ])!;
