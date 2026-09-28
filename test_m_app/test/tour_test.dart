// A screenshot tour for design review — NOT part of the normal suite (skipped
// unless TOUR is defined). Renders the screens a local-mode user sees, in the
// states that break layouts: scrolled, keyboard up, small phone, large text.
//   flutter test test/tour_test.dart --dart-define=TOUR=true --update-goldens
// Output: test/tour/*.png (git-ignored).
import 'dart:math';

import 'package:brewdiary/app.dart';
import 'package:brewdiary/core/date.dart';
import 'package:brewdiary/ui/screens/you_screen.dart';
import 'package:brewdiary/ui/widgets/log_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tour = bool.fromEnvironment('TOUR');

Future<void> _shot(WidgetTester t, String name) => expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('tour/$name.png'));

Future<void> _scroll(WidgetTester t, double dy) async {
  await t.drag(find.byType(Scrollable).hitTestable().first, Offset(0, -dy), warnIfMissed: false);
  await t.pumpAndSettle();
}

Future<void> _tab(WidgetTester t, String name) async {
  await t.tap(find.byKey(ValueKey('tab-$name')));
  await t.pumpAndSettle();
}

void _tourTest(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, body, skip: !_tour);

Future<void> _boot(WidgetTester t, {Size size = const Size(390, 844), double text = 1, bool signedIn = true, bool age = true, bool dark = true, double keyboard = 0}) =>
    bootApp(t, size: size, dpr: 2, text: text, insets: true, keyboard: keyboard, dark: dark, age: age, signedIn: signedIn);

void main() {
  setUpAll(() async {
    configureForTests();
    YouScreen.random = Random(3);
    await loadFonts();
  });

  _tourTest('age gate + pickers', (t) async {
    await _boot(t, signedIn: false, age: false);
    await _shot(t, 'a1_age_gate');
    await t.tap(find.text('India'));
    await t.pumpAndSettle();
    await _shot(t, 'a2_country_picker');
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose a date'));
    await t.pumpAndSettle();
    await _shot(t, 'a3_date_picker');
  });

  _tourTest('landing scroll + auth sheet', (t) async {
    await _boot(t, signedIn: false);
    await _shot(t, 'b1_landing');
    for (var i = 0; i < 5; i++) {
      await _scroll(t, 640);
      await _shot(t, 'b${i + 2}_landing');
    }
    await t.tap(find.text('Sign in').first, warnIfMissed: false);
    await t.pumpAndSettle();
    await _shot(t, 'b7_auth_sheet');
  });

  _tourTest('auth sheet with keyboard', (t) async {
    await _boot(t, signedIn: false, keyboard: 336);
    await t.tap(find.text('Sign in').first, warnIfMissed: false);
    await t.pumpAndSettle();
    await _shot(t, 'b8_auth_keyboard');
  });

  _tourTest('calendar + log sheet', (t) async {
    await _boot(t);
    await _shot(t, 'c1_calendar');
    await _scroll(t, 600);
    await _shot(t, 'c2_calendar_scrolled');
    await t.tap(find.text('Year'));
    await t.pumpAndSettle();
    await _shot(t, 'c3_year');
    await t.tap(find.text('Month'));
    await t.pumpAndSettle();
    showLogSheet(navigatorKey.currentContext!, dateKey: todayKey(), recentDrinks: const ['Negroni', 'Flat white', 'Riesling'], recentMoods: const ['cozy', 'bright']);
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    await _shot(t, 'c4_log_sheet');
    await t.tap(find.byTooltip('More for Flat white'));
    await t.pumpAndSettle();
    await _shot(t, 'c5_entry_actions');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add a note, photo, place, who, kind'));
    await t.pumpAndSettle();
    await _scroll(t, 400);
    await _shot(t, 'c6_log_sheet_more');
  });

  _tourTest('empty day log sheet', (t) async {
    await _boot(t);
    showLogSheet(navigatorKey.currentContext!, dateKey: '2026-09-02', recentDrinks: const ['Negroni', 'Flat white', 'Riesling'], recentMoods: const ['cozy', 'bright']);
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    await _shot(t, 'c7_log_empty_day');
  });

  _tourTest('log sheet with keyboard', (t) async {
    await _boot(t, keyboard: 336);
    showLogSheet(navigatorKey.currentContext!, dateKey: todayKey(), recentDrinks: const ['Negroni'], recentMoods: const []);
    await t.pumpAndSettle(const Duration(milliseconds: 500));
    await _shot(t, 'd1_log_keyboard');
  });

  _tourTest('you tab scroll', (t) async {
    await _boot(t);
    await _tab(t, 'you');
    for (var i = 0; i < 8; i++) {
      await _shot(t, 'e${i + 1}_you');
      await _scroll(t, 640);
    }
  });

  _tourTest('settings', (t) async {
    await _boot(t);
    await _tab(t, 'you');
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await _shot(t, 'e${i + 11}_settings');
      await _scroll(t, 640);
    }
  });

  _tourTest('ninkasi + keyboard', (t) async {
    await _boot(t);
    await _tab(t, 'ninkasi');
    await _shot(t, 'f1_ninkasi');
    await t.tap(find.text('Something cozy and low-effort.'));
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle(const Duration(seconds: 1));
    await _shot(t, 'f3_ninkasi_chat');
  });

  _tourTest('ninkasi with keyboard', (t) async {
    await _boot(t);
    await _tab(t, 'ninkasi');
    t.view.viewInsets = const FakeViewPadding(bottom: 336 * 2);
    await t.pumpAndSettle();
    await _shot(t, 'f2_ninkasi_keyboard');
  });

  _tourTest('discover', (t) async {
    await _boot(t);
    await t.tap(find.byTooltip('Discover'));
    await t.pumpAndSettle();
    await _shot(t, 'g1_discover');
    await _scroll(t, 640);
    await _shot(t, 'g2_discover');
  });

  _tourTest('small phone + large text', (t) async {
    await _boot(t, size: const Size(360, 640), text: 1.3);
    await _shot(t, 'h1_small_large_calendar');
    await _scroll(t, 500);
    await _shot(t, 'h2_small_large_calendar');
    await _tab(t, 'you');
    await _shot(t, 'h3_small_large_you');
    await _tab(t, 'ninkasi');
    await _shot(t, 'h4_small_large_ninkasi');
  });

  _tourTest('small phone landing', (t) async {
    await _boot(t, size: const Size(360, 640), text: 1.3, signedIn: false);
    await _shot(t, 'h5_small_large_landing');
  });

  _tourTest('light theme', (t) async {
    await _boot(t, dark: false);
    await _shot(t, 'i1_light_calendar');
    await _tab(t, 'you');
    await _shot(t, 'i2_light_you');
  });
}
