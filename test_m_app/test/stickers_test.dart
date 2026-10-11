// Sharing a night: the sticker rules (when, where, what was new — never a drink
// count), and that sharing is one tap from the night itself.
import 'package:brewdiary/app.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/ui/screens/photo_studio.dart';
import 'package:brewdiary/ui/screens/stickers.dart';
import 'package:brewdiary/ui/widgets/log_sheet.dart';
import 'package:brewdiary_core/date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('the stickers say', () {
    test('when, where and what was new — never how many', () {
      final cells = statCells(sampleNight());
      expect(cells.map((c) => '${c.label}: ${c.value}'), ['Since: 9:40 pm', 'At: Soka', 'New to me: 2']);
      expect(cells.any((c) => RegExp(r'drink|round|count', caseSensitive: false).hasMatch(c.label)), isFalse);
    });

    test('a dry night says Dry; nothing new falls back to who and the mood', () {
      expect(statCells(const NightStory(dateKey: '2026-09-27', dry: true, time: '20:10')).map((c) => c.value), ['8:10 pm', 'Dry']);
      final quiet = statCells(const NightStory(dateKey: '2026-09-26', withPeople: 1, mood: 'slow'));
      expect(quiet.map((c) => '${c.label}: ${c.value}'), ['Night: Sat', 'With: 1 friend', 'Mood: slow']);
    });

    test('times read like people say them; a place reads short', () {
      expect(twelveHour('21:40'), '9:40 pm');
      expect(twelveHour('00:05'), '12:05 am');
      expect(twelveHour('12:30'), '12:30 pm');
      expect(shortPlace('Soka, Bandra'), 'Soka');
    });
  });

  group('sharing is one tap from the night', () {
    setUpAll(loadFonts);

    testWidgets('a day with drinks: "Share this night" opens the studio; every sticker draws', (t) async {
      await bootApp(t, size: const Size(390, 900), signedIn: true);
      showLogSheet(navigatorKey.currentContext!, dateKey: todayKey(), recentDrinks: const [], recentMoods: const []);
      await t.pumpAndSettle(const Duration(milliseconds: 600));
      expect(entryStore.entries.any((e) => e.date == todayKey()), isTrue, reason: 'the seed diary has tonight');
      expect(find.byTooltip('Share this night'), findsOneWidget, reason: 'in the sheet header too');

      await t.tap(find.text('Share this night'));
      await t.pumpAndSettle();
      expect(find.text('Share the night'), findsOneWidget);
      expect(find.text('Sticker only'), findsOneWidget);
      expect(find.byType(Sticker), findsWidgets);

      for (final k in StickerKind.values) {
        final thumb = find.bySemanticsLabel('${stickerNames[k]} sticker');
        await t.scrollUntilVisible(thumb, 90, scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right));
        await t.pumpAndSettle();
        await t.tap(thumb);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '${stickerNames[k]} draws without overflowing');
      }
    });

    testWidgets('the sticker moves with a drag and resets with a double-tap', (t) async {
      await bootApp(t, size: const Size(390, 900), signedIn: true);
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => PhotoStudio(story: sampleNight())));
      await t.pumpAndSettle();
      final canvas = find.bySemanticsLabel(RegExp('Stats sticker on'));
      final before = t.getCenter(find.byType(Sticker).first);
      await t.drag(canvas, const Offset(0, -160));
      await t.pumpAndSettle();
      final after = t.getCenter(find.byType(Sticker).first);
      expect(after.dy, lessThan(before.dy - 60), reason: 'dragged up');
      await t.tap(canvas);
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(canvas);
      await t.pumpAndSettle();
      expect(t.getCenter(find.byType(Sticker).first).dy, closeTo(before.dy, 1), reason: 'double-tap puts it back');
    });
  });
}
