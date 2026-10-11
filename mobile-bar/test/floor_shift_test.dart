// The floor in motion, the stations' tools, the shift's notes, the cash drawer and
// bookings (058): walked through on the stand-in venues with the real screens, plus the
// pure arithmetic behind them.
import 'package:brewdiary_bar/data/models.dart';
import 'package:brewdiary_bar/logic/service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('the arithmetic', () {
    OrderLine l(String name, int qty, String status) => OrderLine(id: '$name$qty$status', tabId: 't', name: name, unitPrice: 100, qty: qty, status: status, createdAt: DateTime(2026, 10, 1, 20));

    test('what\'s still to make: new and making, summed by name, most first — ready is done', () {
      final out = allDay([l('Negroni', 2, 'sent'), l('Negroni', 1, 'preparing'), l('Fries', 1, 'sent'), l('Gimlet', 3, 'ready'), l('Amaro', 1, 'sent')]);
      expect(out.map((x) => '${x.qty}× ${x.name}'), ['3× Negroni', '1× Amaro', '1× Fries']);
    });

    test('a count by notes adds up to the paisa', () {
      expect(countTotal({500: 3, 100: 3, 10: 7}), 1870);
      expect(countTotal({.5: 3, 1: 0}), 1.5);
      expect(denominations('INR').first, 500);
      expect(denominations('XYZ'), isEmpty, reason: 'unknown notes: count as one number');
    });

    test('a close is square within one unit, a little off up to 100, otherwise off', () {
      expect(countResult(0.4), CountResult.square);
      expect(countResult(-10), CountResult.slightlyOff);
      expect(countResult(250), CountResult.off);
      expect(countWord(-10, (x) => '₹${x.toStringAsFixed(0)}'), '₹10 short');
      expect(countWord(25, (x) => '₹${x.toStringAsFixed(0)}'), '₹25 over');
    });

    test('a free table shows its next booking within three hours; two bookings at once clash', () {
      final now = DateTime(2026, 10, 1, 19);
      final a = Booking(id: 'a', name: 'Mehta', party: 4, startsAt: DateTime(2026, 10, 1, 20), tableId: 't4');
      final b = Booking(id: 'b', name: 'Rao', party: 2, startsAt: DateTime(2026, 10, 1, 21), tableId: 't4');
      final late = Booking(id: 'c', name: 'Late', party: 2, startsAt: DateTime(2026, 10, 1, 23), tableId: 't4');
      final gone = Booking(id: 'd', name: 'Gone', party: 2, startsAt: DateTime(2026, 10, 1, 19, 30), tableId: 't4', status: 'cancelled');
      expect(nextBookingAt('t4', [late, b, a, gone], now)?.name, 'Mehta');
      expect(nextBookingAt('t4', [late], now), isNull, reason: 'more than three hours out');
      expect(bookingsClash(a, b), isTrue, reason: '8–9:30 and 9–10:30 overlap');
      expect(bookingsClash(a, late), isFalse);
      expect(bookingsClash(a, gone), isFalse, reason: 'a cancelled booking clashes with nothing');
    });
  });

  group('walk-throughs', () {
    setUpAll(loadFonts);

    testWidgets('the bar: what\'s still to make, a spec card, a recall, an 86 and back', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1600));
      await backend.addLines('tab-t5', [
        {'item': 'm1', 'qty': 1},
      ]);
      await tapText(t, 'The Amber Room');
      await tapInView(t, 'Bar tickets');
      expect(find.text('TO MAKE'), findsOneWidget);
      expect(find.text('2× Kokum Cooler', findRichText: true), findsOneWidget);

      // The spec card, from the line's ⋯.
      await t.tap(find.byTooltip('More for Negroni'));
      await t.pumpAndSettle();
      await tapInSheet(t, 'Spec card');
      expect(find.textContaining('30 ml gin'), findsOneWidget);
      Navigator.of(t.element(find.text('SPEC'))).pop();
      await t.pumpAndSettle();

      // Marked ready by mistake → back to making.
      final negroni = (await backend.stationLines('demo-bar', 'bar')).firstWhere((l) => l.name == 'Negroni');
      await backend.setLineStatus(negroni.id, 'ready');
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('More for Negroni'));
      await t.pumpAndSettle();
      await tapInSheet(t, 'Back to making');
      expect((await backend.stationLines('demo-bar', 'bar')).firstWhere((l) => l.id == negroni.id).status, 'preparing');

      // The espresso martini runs out: 86 it from the line, then bring it back.
      await t.tap(find.byTooltip('More for Espresso Martini'));
      await t.pumpAndSettle();
      await tapInSheet(t, '86 Espresso Martini — it\'s run out');
      expect(find.text('OFF TONIGHT'), findsOneWidget);
      expect((await backend.menu('demo-bar')).firstWhere((m) => m.id == 'm2').available, isFalse);
      await tapText(t, 'Espresso Martini'); // the chip under OFF TONIGHT is the first
      await tapInSheet(t, 'Bring it back');
      expect((await backend.menu('demo-bar')).firstWhere((m) => m.id == 'm2').available, isTrue);
    });

    testWidgets('a table: split by item, handed over, another tab brought in, then moved', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1600));
      await tapText(t, 'The Amber Room');
      await tapText(t, 'T2');
      expect(find.text('Noor\'s table'), findsOneWidget);

      // Split by item: the Kokum Coolers go on their own check.
      await tapInView(t, 'Split by item');
      await tapInSheet(t, '2 × Kokum Cooler');
      await tapInSheet(t, 'Move 1 · ₹440');
      final atT2 = (await backend.openTabs('demo-bar')).where((x) => x.tableId == 'tb-t2').toList();
      expect(atT2.length, 2, reason: 'a second check at T2');
      final check2 = atT2.firstWhere((x) => x.id != 'tab-t2');
      expect((await backend.tabLines(check2.id)).single.name, 'Kokum Cooler');

      // Hand the table to Sam (paused Leo and not-yet-in Kabir aren't offered).
      await tapInView(t, 'Hand over');
      expect(find.text('Leo'), findsNothing);
      expect(find.text('Kabir'), findsNothing);
      await tapInSheet(t, 'Sam');
      expect((await backend.openTabs('demo-bar')).firstWhere((x) => x.id == 'tab-t2').serverId, 's-sam');

      // Bring the bar tab in: its lines join this bill, it's kept as merged.
      await tapInView(t, 'Bring a tab in');
      await tapInSheet(t, 'B1');
      expect((await backend.openTabs('demo-bar')).any((x) => x.id == 'tab-b1'), isFalse);
      expect((await backend.tabLines('tab-t2')).any((l) => l.name == 'Hazy IPA (pint)'), isTrue);

      // Move the party to T6: back to the floor, and the tab is at T6.
      await tapInView(t, 'Move');
      await tapInSheet(t, 'T6');
      expect(find.text('Floor'), findsWidgets, reason: 'back on the floor');
      expect((await backend.openTabs('demo-bar')).firstWhere((x) => x.id == 'tab-t2').tableId, 'tb-t6');
    });

    testWidgets('the pre-shift note: on top of the floor, "Got it", who has seen it; the log', (t) async {
      await bootApp(t, size: const Size(390, 1400));
      await tapText(t, 'The Amber Room');
      expect(find.textContaining('Big party of 12 at 9'), findsOneWidget);
      expect(find.text('Seen by Sam.'), findsOneWidget, reason: 'an owner sees who has, by name');
      await tapInView(t, 'Got it');
      expect(find.text('Got it'), findsNothing);
      expect(find.text('Seen by Sam.'), findsNothing, reason: 'once seen, the note folds to one line');
      await tapInView(t, 'Big party of 12 at 9 — T4 to T6 go together. Kokum Cooler is the alcohol-free pick tonight.');
      expect(find.text('Seen by Sam and You (demo).'), findsOneWidget, reason: 'opened again: who has seen it, in name order, never ranked');

      await tapText(t, 'MORE');
      await tapInView(t, 'Shift notes');
      expect(find.textContaining('Ice machine dripping'), findsOneWidget);
      await tapInView(t, 'Add a log entry');
      await t.enterText(find.byType(TextField).last, 'Keg of IPA kicked at 11 — order two Monday.');
      await tapInSheet(t, 'Add to the log');
      expect(find.textContaining('Keg of IPA kicked'), findsOneWidget);
    });

    testWidgets('the cash drawer: a float, a safe drop, a blind count by notes, the close kept', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1800));
      await tapText(t, 'The Amber Room');
      await tapText(t, 'MORE');
      await tapInView(t, 'Cash drawer');
      expect(find.text('No drawer open'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '2000');
      await t.pumpAndSettle();
      await tapText(t, 'Open the drawer');
      expect(find.text('Should hold now'), findsOneWidget, reason: 'an owner sees the expected figure');

      await backend.closeTab('tab-b1', [
        {'method': 'Cash', 'amount': 380},
      ]);
      await tapInView(t, 'Safe drop');
      await t.enterText(find.byType(TextField).first, '500');
      await tapInSheet(t, 'safe drop');
      await tapInSheet(t, 'Record it');
      expect((await backend.drawerState('demo-bar')).open!.expected, 1880, reason: '2000 float + 380 cash − 500 dropped');

      await tapInView(t, 'Count and close');
      expect(find.textContaining('Count what\'s in it first'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), '3'); // 3 × ₹500
      await t.enterText(find.byType(TextField).at(2), '3'); // 3 × ₹100
      await t.enterText(find.byType(TextField).at(5), '7'); // 7 × ₹10
      await t.pumpAndSettle();
      await tapInSheet(t, 'Close the drawer');
      expect(find.text('Drawer closed'), findsOneWidget);
      expect(find.text('₹10 short'), findsWidgets);
      expect((await backend.drawerState('demo-bar')).open, isNull);
    });

    testWidgets('bookings: tonight\'s count on the floor, a new one, one seated at its table', (t) async {
      final backend = await bootApp(t, size: const Size(390, 1600));
      await tapText(t, 'The Amber Room');
      expect(find.text('Bookings · 2'), findsOneWidget);
      await tapInView(t, 'Bookings · 2');
      expect(find.text('Mehta · 4'), findsOneWidget);
      expect(find.text('Rao · 2'), findsOneWidget);

      await tapText(t, 'New booking');
      await t.enterText(find.byType(TextField).first, 'Kapoor');
      await tapInSheet(t, '6');
      await tapInSheet(t, 'Book it');
      expect(find.text('Kapoor · 6'), findsOneWidget, reason: 'the new booking is in the book');

      await tapText(t, 'Mehta · 4');
      await tapInSheet(t, 'Seat them now');
      expect(find.text('Add to the order'), findsOneWidget, reason: 'straight into T4\'s tab');
      final tab = (await backend.openTabs('demo-bar')).firstWhere((x) => x.tableId == 'tb-t4');
      expect(tab.covers, 4);
      final mehta = (await backend.bookings('demo-bar', DateTime.now().subtract(const Duration(days: 1)), DateTime.now().add(const Duration(days: 2)))).firstWhere((b) => b.id == 'bk-mehta');
      expect(mehta.status, 'seated');
      expect(mehta.tabId, tab.id);
    });
  });
}
