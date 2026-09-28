// The small moments: a logged day blooms, a streak milestone is cheered once (dry
// nights count), a failed network load says so and retries, and the reminder
// skips evenings you've already written in.
import 'package:brewdiary/app.dart';
import 'package:brewdiary/core/date.dart';
import 'package:brewdiary/core/derive.dart';
import 'package:brewdiary/core/types.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/data/reminder.dart';
import 'package:brewdiary/ui/theme.dart';
import 'package:brewdiary/ui/widgets/common.dart';
import 'package:brewdiary/ui/widgets/moments.dart';
import 'package:brewdiary/ui/widgets/mosaic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _placed = {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'};

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  group('streak milestones', () {
    test('the highest milestone a log carries the streak across', () {
      expect(crossedMilestone(6, 7), 7);
      expect(crossedMilestone(7, 8), isNull, reason: 'already past it');
      expect(crossedMilestone(5, 6), isNull);
      expect(crossedMilestone(28, 31), 30, reason: 'a backfill can jump the count');
      expect(crossedMilestone(0, 120), 100);
      expect(crossedMilestone(364, 365), 365);
    });
  });

  group('reminder evenings', () {
    const nine = TimeOfDay(hour: 21, minute: 30);
    final evening = DateTime(2026, 9, 28, 20, 30);

    test('tonight and the next evenings, at the chosen time', () {
      final due = ReminderStore.evenings(evening, nine, const {}, days: 3);
      expect(due.map((d) => d.$1), [0, 1, 2]);
      expect(due.first.$2, DateTime(2026, 9, 28, 21, 30));
      expect(due.last.$2, DateTime(2026, 9, 30, 21, 30));
    });

    test('skips an evening already written in, and one already past', () {
      final due = ReminderStore.evenings(evening, nine, {'2026-09-28', '2026-09-30'}, days: 4);
      expect(due.map((d) => d.$1), [1, 3], reason: 'tonight and the 30th are logged');
      final late = ReminderStore.evenings(DateTime(2026, 9, 28, 22), nine, const {}, days: 2);
      expect(late.map((d) => d.$1), [1], reason: "tonight's time has gone");
    });

    test('crosses a month end', () {
      final due = ReminderStore.evenings(DateTime(2026, 9, 30, 8), nine, const {}, days: 2);
      expect(due.last.$2, DateTime(2026, 10, 1, 21, 30));
    });
  });

  testWidgets('logging tonight blooms the square and cheers a week of nights, once', (tester) async {
    await bootApp(tester, prefs: _placed, signedIn: true);
    // Six nights in a row before tonight, one of them dry: the streak counts it.
    entryStore.resetAll();
    final today = parseKey(todayKey());
    for (var d = 1; d <= 6; d++) {
      final dry = d == 3;
      entryStore.addEntry(date: toKey(addDays(today, -d)), drink: dry ? dryDayLabel : 'Flat white', type: dry ? DrinkType.none : null);
    }
    await tester.pumpAndSettle();
    expect(stats(entryStore.entries).current, 6);

    final blooms = <String>[];
    void heard() => blooms.add(LogBloom.signal.value!.key);
    LogBloom.signal.addListener(heard);
    addTearDown(() => LogBloom.signal.removeListener(heard));

    // Tap today's square: the calendar opens the sheet and waits for it.
    await tester.tap(find.byWidgetPredicate((w) => w is DayCell && w.day.isToday));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Negroni');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(entryStore.entries.where((e) => e.date == todayKey()).map((e) => e.drink), ['Negroni']);
    navigatorKey.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(blooms, [todayKey()]);
    expect(find.text('Seven nights in a row.'), findsOneWidget);
    expect(find.textContaining('the dry ones count just the same'), findsOneWidget);
    await tester.tap(find.text('Lovely'));
    await tester.pumpAndSettle();
    expect(find.text('Seven nights in a row.'), findsNothing);

    // The same milestone on the same day doesn't replay.
    showStreakCheer(navigatorKey.currentContext!, 7);
    await tester.pumpAndSettle();
    expect(find.text('Seven nights in a row.'), findsNothing);
  });

  testWidgets('a failed load says so, and trying again loads it', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(BD.darkTokens),
      home: Scaffold(
        body: Loader<List<int>>(
          retry: true,
          load: () async {
            calls++;
            if (calls == 1) throw StateError('offline');
            return [1, 2];
          },
          builder: (context, data, loading) => Text(data == null ? 'waiting' : 'got ${data.length}'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach brewdiary"), findsOneWidget);
    expect(find.text('waiting'), findsNothing, reason: 'an error is not an empty list');

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('got 2'), findsOneWidget);
  });
}
