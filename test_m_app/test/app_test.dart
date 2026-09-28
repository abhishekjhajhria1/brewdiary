// Widget tests — boot the real app in LOCAL mode (no Supabase env) and walk the
// core journey: age gate → landing → log a drink → the day darkens → sign up
// locally → calendar / You / Ninkasi. Goldens double as screenshots for review
// (regenerate with `flutter test --update-goldens`).
import 'dart:io';
import 'dart:math';

import 'package:brewdiary/app.dart';
import 'package:brewdiary/core/date.dart';
import 'package:brewdiary/data/auth.dart';
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/data/settings.dart';
import 'package:brewdiary/data/wishlist.dart';
import 'package:brewdiary/ui/widgets/log_sheet.dart';
import 'package:brewdiary/ui/screens/you_screen.dart';
import 'package:brewdiary/ui/widgets/mosaic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Hanken Grotesk', ['HankenGrotesk.ttf', 'HankenGrotesk-Italic.ttf']);
  await load('Newsreader', ['Newsreader.ttf', 'Newsreader-Italic.ttf']);
}

Future<void> _boot(WidgetTester tester, {Map<String, Object> prefs = const {}, bool dark = true}) async {
  tester.view.physicalSize = const Size(585, 1266); // iPhone 13-sized, rendered at 1.5x to keep goldens small
  tester.view.devicePixelRatio = 1.5;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'brewdiary.theme': dark ? 'dark' : 'light', ...prefs});
  await Prefs.init();
  auth.init();
  entryStore.wire();
  wishlist.wire();
  await tester.pumpWidget(const BrewdiaryApp());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    Shell.deepLinks = false;
    AchievementTile.fixedDesign = 1;
    await _loadFonts();
  });

  testWidgets('age gate blocks until a legal date of birth is confirmed', (tester) async {
    await _boot(tester);
    expect(find.text('A quick check.'), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/01_age_gate.png'));

    // Confirming programmatically (the date picker is platform UI).
    PlaceStore.instance.confirmAge(DateTime(1995, 1, 1), 'IN');
    await tester.pumpAndSettle();
    expect(find.text('Every night\ngets a square.'), findsOneWidget);
  });

  testWidgets('guest can log a drink on the landing calendar without an account', (tester) async {
    await _boot(tester, prefs: {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'});
    expect(find.text('Every night\ngets a square.'), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/02_landing.png'));

    // Open today's log sheet (the same call a tap on the square makes).
    showLogSheet(navigatorKey.currentContext!, dateKey: todayKey(), recentDrinks: const [], recentMoods: const []);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('What did you drink?'.toUpperCase()), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'negroni');
    await tester.pumpAndSettle();
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/03_log_sheet.png'));

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(entryStore.entries.where((e) => e.date == todayKey()).length, 1);
    expect(entryStore.entries.first.drink, 'negroni');
    await tester.pump(const Duration(seconds: 2)); // let the 'Logged ✓' flash finish
  });

  testWidgets('signed-in (local) shell: calendar, year mosaic, You, Ninkasi', (tester) async {
    YouScreen.random = Random(7);
    await _boot(tester, prefs: {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'});
    entryStore.reseed();
    await auth.signUp('a@b.c', 'secret1', 'Sekhi');
    await tester.pumpAndSettle();

    expect(find.text('night streak'.toUpperCase()), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/04_calendar.png'));

    CalendarViewStore.instance.toggle();
    await tester.pumpAndSettle();
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/05_year.png'));
    CalendarViewStore.instance.toggle();

    await tester.tap(find.text('YOU'));
    await tester.pumpAndSettle();
    expect(find.text('Your year'.toUpperCase()), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/06_you.png'));

    await tester.tap(find.text('NINKASI'));
    await tester.pumpAndSettle();
    expect(find.text('Ninkasi'), findsWidgets);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/07_ninkasi.png'));
  });

  testWidgets('light theme renders the same shell', (tester) async {
    await _boot(tester, prefs: {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'}, dark: false);
    entryStore.reseed();
    await auth.signUp('a@b.c', 'secret1', 'Sekhi');
    await tester.pumpAndSettle();
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/08_calendar_light.png'));
  });
}
