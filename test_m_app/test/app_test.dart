// Widget tests — boot the real app in LOCAL mode (no Supabase env) and walk the
// core journey: age gate → landing → log a drink → the day darkens → sign up
// locally → calendar / You / Ninkasi. Goldens double as screenshots for review
// (regenerate with `flutter test --update-goldens`).
import 'dart:math';

import 'package:brewdiary/app.dart';
import 'package:brewdiary/core/date.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/data/settings.dart';
import 'package:brewdiary/ui/screens/together_intro.dart';
import 'package:brewdiary/ui/screens/you_screen.dart';
import 'package:brewdiary/ui/widgets/log_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _placed = {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'};

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  testWidgets('age gate blocks until a legal date of birth is confirmed', (tester) async {
    await bootApp(tester, age: false);
    expect(find.text('A quick check.'), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/01_age_gate.png'));

    // Entering without a date asks for one.
    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();
    expect(find.text('Please choose your date of birth.'), findsOneWidget);

    // Confirming programmatically (the wheel picker is exercised in the tour).
    PlaceStore.instance.confirmAge(DateTime(1995, 1, 1), 'IN');
    await tester.pumpAndSettle();
    expect(find.text('Every night\ngets a square.'), findsOneWidget);
  });

  testWidgets('guest can log a drink on the landing calendar without an account', (tester) async {
    await bootApp(tester, prefs: _placed);
    expect(find.text('Every night\ngets a square.'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-together')), findsOneWidget, reason: 'Together is in the bar for guests too');
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
    await bootApp(tester, prefs: _placed, signedIn: true);

    expect(find.text('night streak'.toUpperCase()), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/04_calendar.png'));

    await tester.tap(find.byTooltip('Show the year'));
    await tester.pumpAndSettle();
    expect(CalendarViewStore.instance.view, CalendarView.year);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/05_year.png'));
    await tester.tap(find.byTooltip('Show the month'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab-you')));
    await tester.pumpAndSettle();
    expect(find.text('YOUR YEAR'), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/06_you.png'));

    // Together is always in the bar; without the cloud it's the introduction.
    await tester.tap(find.byKey(const ValueKey('tab-together')));
    await tester.pumpAndSettle();
    expect(find.text('WHAT LIVES HERE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text("This build isn't connected yet"), 300,
        scrollable: find.descendant(of: find.byType(TogetherIntro), matching: find.byType(Scrollable)).first);
    expect(find.text("This build isn't connected yet"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab-ninkasi')));
    await tester.pumpAndSettle();
    expect(find.text('TRY ASKING'), findsOneWidget);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/07_ninkasi.png'));
  });

  testWidgets('light theme renders the same shell', (tester) async {
    await bootApp(tester, prefs: _placed, signedIn: true, dark: false);
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('goldens/08_calendar_light.png'));
  });
}
