// A motion tour for design review — NOT part of the normal suite (skipped unless
// TOUR is defined). It films the app's moving moments frame by frame, so motion can
// be reviewed like a screenshot: the month turning under a finger, a log landing,
// the year filling in, the passport opening, a cheers, the table's basket, a new rank.
//   flutter test test/motion_tour_test.dart --dart-define=TOUR=true --update-goldens
// Output: test/tour/motion/<clip>_<frame>.png (git-ignored); stitch into GIFs to share.
import 'package:brewdiary/app.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/game.dart';
import 'package:brewdiary/data/friends.dart';
import 'package:brewdiary/data/table_order.dart';
import 'package:brewdiary/ui/screens/menu_screen.dart';
import 'package:brewdiary/ui/screens/taste_card.dart';
import 'package:brewdiary/ui/screens/together_screen.dart';
import 'package:brewdiary/ui/widgets/common.dart';
import 'package:brewdiary/ui/widgets/game.dart';
import 'package:brewdiary/ui/widgets/moments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tour = bool.fromEnvironment('TOUR');

void _tourTest(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, body, skip: !_tour);

Future<void> _boot(WidgetTester t) => bootApp(t, dpr: 2, insets: true, signedIn: true);

/// Film [frames] frames, [every] apart, as `tour/motion/<clip>_<n>.png`, starting at
/// frame [from].
Future<int> _film(WidgetTester t, String clip, {int frames = 12, Duration every = const Duration(milliseconds: 50), int from = 0}) async {
  for (var i = 0; i < frames; i++) {
    await expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('tour/motion/${clip}_${(from + i).toString().padLeft(2, '0')}.png'));
    await t.pump(every);
  }
  return from + frames;
}

String _iso(int hour) => DateTime(testNow.year, testNow.month, testNow.day, hour).toUtc().toIso8601String();

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  _tourTest('the month turns under a finger', (t) async {
    await _boot(t);
    final grid = t.getCenter(find.byType(DayRings));
    final g = await t.startGesture(grid);
    var n = 0;
    for (var i = 0; i < 7; i++) {
      await g.moveBy(const Offset(26, 0));
      await t.pump(const Duration(milliseconds: 16));
      n = await _film(t, 'm1_month_swipe', frames: 1, from: n);
    }
    await g.up();
    await t.pump();
    n = await _film(t, 'm1_month_swipe', frames: 10, every: const Duration(milliseconds: 40), from: n);
    await t.pumpAndSettle();
    await _film(t, 'm1_month_swipe', frames: 1, from: n);
  });

  _tourTest('a log lands: the button, the row, the passport, the square', (t) async {
    await _boot(t);
    openLog(navigatorKey.currentContext!, toKey(addDays(testNow, -2)));
    await t.pumpAndSettle(const Duration(milliseconds: 600));
    await t.enterText(find.byType(TextField).first, 'Paloma');
    await t.pump();
    await t.pumpAndSettle();
    await t.tap(find.text('Log'));
    await t.pump();
    var n = await _film(t, 'm2_log', frames: 14, every: const Duration(milliseconds: 45));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    navigatorKey.currentState!.pop();
    await t.pump();
    n = await _film(t, 'm2_log', frames: 16, every: const Duration(milliseconds: 50), from: n);
    await t.pumpAndSettle();
  });

  _tourTest('the year fills in', (t) async {
    await _boot(t);
    await t.tap(find.byTooltip('Show the year'));
    await t.pump();
    await _film(t, 'm3_year', frames: 16, every: const Duration(milliseconds: 60));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Show the month'));
    await t.pumpAndSettle();
  });

  _tourTest('the passport opens and fills', (t) async {
    await _boot(t);
    showTasteCard(navigatorKey.currentContext!);
    await t.pump();
    await _film(t, 'm4_passport', frames: 20, every: const Duration(milliseconds: 60));
    await t.pumpAndSettle();
  });

  _tourTest('a new rank lands', (t) async {
    await _boot(t);
    showRankUp(navigatorKey.currentContext!, rankFor(500));
    await t.pump();
    await _film(t, 'm5_rank_up', frames: 18, every: const Duration(milliseconds: 60));
    await t.pumpAndSettle();
  });

  _tourTest('a cheers, before the server answers', (t) async {
    await _boot(t);
    const mira = SocialProfile(id: 'u2', handle: 'mira', name: 'Mira');
    final feed = [
      FeedEntry(id: 'f1', userId: 'u2', author: mira, date: todayKey(), createdAt: _iso(21), drink: 'Mezcal Negroni', mood: 'smoky', venue: 'Soka, Bandra', cheers: 2, cheered: false, comments: const []),
    ];
    navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (_) => Ambient(child: Scaffold(backgroundColor: Colors.transparent, body: TogetherScreen(preview: TogetherPreview(friends: const [mira], feed: feed)))),
    ));
    await t.pumpAndSettle();
    await t.ensureVisible(find.bySemanticsLabel('Cheers, 2'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Cheers, 2'));
    await t.pump();
    await _film(t, 'm6_cheers', frames: 12, every: const Duration(milliseconds: 45));
    await t.pumpAndSettle();
  });

  _tourTest("the table's basket rises", (t) async {
    await _boot(t);
    navigatorKey.currentState!.push(MaterialPageRoute(
      builder: (_) => MenuView(
        menu: sampleMenu(),
        table: const TableInfo(code: 'T4X9', venueSlug: 'soka', venueName: 'Soka', tableLabel: '4', tableService: true),
        previewOrdering: true,
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Add Negroni').first);
    await t.pump();
    var n = await _film(t, 'm7_basket', frames: 10, every: const Duration(milliseconds: 45));
    await t.tap(find.byTooltip('Add Negroni').first);
    await t.pump();
    n = await _film(t, 'm7_basket', frames: 6, every: const Duration(milliseconds: 45), from: n);
    await t.pumpAndSettle();
  });
}
