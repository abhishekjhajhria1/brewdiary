// Sharing a night: the sticker rules (when, where, what was new — never a drink
// count), the studio's choices (styles, stickers with their backing and type, frames,
// looks, your own line, what shows), and that sharing is one tap from the night itself.
import 'package:brewdiary/app.dart';
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/ui/screens/photo_frames.dart';
import 'package:brewdiary/ui/screens/photo_studio.dart';
import 'package:brewdiary/ui/screens/stickers.dart';
import 'package:brewdiary/ui/widgets/common.dart';
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

    test('times read like people say them; a place reads short; your line leads', () {
      expect(twelveHour('21:40'), '9:40 pm');
      expect(twelveHour('00:05'), '12:05 am');
      expect(twelveHour('12:30'), '12:30 pm');
      expect(shortPlace('Soka, Bandra'), 'Soka');
      expect(leadLine(sampleNight()), "Mira's birthday");
      expect(leadLine(sampleNight().copyWith(caption: () => 'Mira turns 30')), 'Mira turns 30');
      expect(leadLine(sampleNight().copyWith(caption: () => '   ')), "Mira's birthday", reason: 'a blank line falls back to the night');
    });

    test('a look survives being saved and read back; an unknown value falls back', () {
      for (final (_, l) in studioStyles) {
        expect(StudioLook.fromJson(l.toJson()), l);
      }
      expect(StudioLook.fromJson({'kind': 'nonsense', 'frame': 'zzz', 'look': 'noir'}), const StudioLook(look: PhotoLook.noir));
      expect(StudioLook.fromJson({'kind': null}).kind, isNull, reason: 'no sticker stays no sticker');
    });

    test('a look never paints over the photo it was given: the original is untouched', () {
      expect(lookMatrix(PhotoLook.original), isNull);
      for (final l in PhotoLook.values.where((l) => l != PhotoLook.original)) {
        expect(lookMatrix(l), hasLength(20), reason: lookNames[l]);
      }
      final mono = lookMatrix(PhotoLook.mono)!;
      expect(mono[0], closeTo(mono[5], 1e-9), reason: 'mono: every channel the same mix');
    });
  });

  group('the studio', () {
    setUpAll(loadFonts);

    Finder strip() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right);

    Future<void> tab(WidgetTester t, String name) async {
      await t.tap(find.bySemanticsLabel(name));
      await t.pumpAndSettle();
    }

    Future<void> pick(WidgetTester t, String semantic) async {
      final f = find.bySemanticsLabel(semantic);
      if (f.evaluate().isEmpty) {
        await t.drag(strip(), const Offset(4000, 0)); // back to the start of the row
        await t.pumpAndSettle();
      }
      await t.scrollUntilVisible(f, 90, scrollable: strip());
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$semantic draws without overflowing');
    }

    Future<void> open(WidgetTester t, {NightStory? story}) async {
      await bootApp(t, size: const Size(390, 900), signedIn: true);
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => PhotoStudio(story: story ?? sampleNight())));
      await t.pumpAndSettle();
    }

    testWidgets('"Share this night" opens it from the day; every sticker draws, with every backing and type', (t) async {
      await bootApp(t, size: const Size(390, 900), signedIn: true);
      showLogSheet(navigatorKey.currentContext!, dateKey: todayKey(), recentDrinks: const [], recentMoods: const []);
      await t.pumpAndSettle(const Duration(milliseconds: 600));
      expect(entryStore.entries.any((e) => e.date == todayKey()), isTrue, reason: 'the seed diary has tonight');
      expect(find.byTooltip('Share this night'), findsOneWidget, reason: 'in the sheet header too');

      await t.tap(find.text('Share this night'));
      await t.pumpAndSettle();
      expect(find.text('Share the night'), findsOneWidget);
      for (final name in ['Style', 'Sticker', 'Frame', 'Look', 'Text']) {
        expect(find.bySemanticsLabel(name), findsOneWidget);
      }
      expect(find.text('Share'), findsOneWidget, reason: 'Share is always under the thumb');

      await tab(t, 'Sticker');
      expect(find.text('Sticker only'), findsOneWidget);
      for (final k in StickerKind.values) {
        await pick(t, '${stickerNames[k]} sticker');
        if (takesPlate(k)) {
          for (final p in ['FROST', 'CARD', 'NONE']) {
            await t.tap(find.text(p).last);
            await t.pumpAndSettle();
          }
        }
        if (takesFace(k)) {
          for (final f in ['MONO', 'SANS', 'SERIF']) {
            await t.tap(find.text(f).last);
            await t.pumpAndSettle();
          }
        }
        expect(t.takeException(), isNull, reason: '${stickerNames[k]} in every backing and type');
      }
      await pick(t, 'No sticker');
      expect(find.text('Sticker only'), findsOneWidget, reason: 'still there, but nothing to share alone');
    });

    testWidgets('a style in one tap — and the studio remembers it next time', (t) async {
      await open(t);
      for (final (name, _) in studioStyles) {
        await pick(t, '$name style');
      }
      await pick(t, 'Film style');
      expect(StudioLook.fromJson(Prefs.getJson<Map<String, dynamic>>('brewdiary.studio.look')!).frame, PhotoFrame.film);
      navigatorKey.currentState!.pop();
      await t.pumpAndSettle();
      navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => PhotoStudio(story: sampleNight())));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Datestamp sticker on')), findsOneWidget, reason: 'opens on the last look made');
    });

    testWidgets('every frame in every size, paper and black; every look, grain and vignette', (t) async {
      await open(t);
      await tab(t, 'Frame');
      for (final f in ShareFormat.values.reversed) {
        await t.tap(find.text(switch (f) { ShareFormat.story => 'STORY', ShareFormat.post => 'POST', ShareFormat.square => 'SQUARE' }));
        await t.pumpAndSettle();
        for (final fr in PhotoFrame.values) {
          await pick(t, '${frameNames[fr]} frame');
          if (frameHasTone(fr)) {
            await t.tap(find.text('BLACK'));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }
        }
      }
      await tab(t, 'Look');
      for (final l in PhotoLook.values) {
        await pick(t, '${lookNames[l]} look');
      }
      for (final what in ['Grain', 'Vignette']) {
        final toggle = find.byWidgetPredicate((w) => w is BdToggle && w.label == what);
        await t.ensureVisible(toggle);
        await t.pumpAndSettle();
        await t.tap(toggle);
        await t.pumpAndSettle();
      }
      expect(find.byType(CustomPaint), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('your own line, and what shows', (t) async {
      await open(t);
      await tab(t, 'Sticker');
      await pick(t, 'Line sticker');
      await tab(t, 'Text');
      await t.enterText(find.byType(TextField).first, 'Mira turns 30');
      await t.pumpAndSettle();
      final canvas = find.bySemanticsLabel(RegExp('^Line sticker on'));
      expect(find.descendant(of: canvas, matching: find.text('Mira turns 30')), findsOneWidget, reason: 'your line leads the sticker');

      await tab(t, 'Sticker');
      await pick(t, 'Stats sticker');
      final stats = find.bySemanticsLabel(RegExp('^Stats sticker on'));
      expect(find.descendant(of: stats, matching: find.text('Soka')), findsOneWidget);
      await tab(t, 'Text');
      for (final what in ['The place', 'What you had']) {
        final toggle = find.byWidgetPredicate((w) => w is BdToggle && w.label == what);
        await t.ensureVisible(toggle);
        await t.pumpAndSettle();
        await t.tap(toggle);
        await t.pumpAndSettle();
      }
      expect(find.descendant(of: stats, matching: find.text('Soka')), findsNothing, reason: 'the place is off');
      expect(find.descendant(of: stats, matching: find.textContaining('Mezcal Negroni')), findsNothing, reason: 'the drinks are off');
    });

    testWidgets('the sticker moves with a drag and resets with a double-tap', (t) async {
      await open(t);
      final canvas = find.bySemanticsLabel(RegExp('^Stats sticker on'));
      final sticker = find.descendant(of: canvas, matching: find.byType(Sticker));
      final before = t.getCenter(sticker);
      await t.drag(canvas, const Offset(0, -160));
      await t.pumpAndSettle();
      expect(t.getCenter(sticker).dy, lessThan(before.dy - 60), reason: 'dragged up');
      await t.tap(canvas);
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(canvas);
      await t.pumpAndSettle();
      expect(t.getCenter(sticker).dy, closeTo(before.dy, 1), reason: 'double-tap puts it back');
    });
  });
}
