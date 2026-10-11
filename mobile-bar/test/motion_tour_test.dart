// A motion tour for design review — NOT part of the normal suite (skipped unless
// TOUR is defined). Films the venue app's moving moments frame by frame on the demo
// venue: the floor with a table asking, the door clicker, a ticket line moving on, a
// wrong code.
//   flutter test test/motion_tour_test.dart --dart-define=TOUR=true --update-goldens
// Output: test/tour/motion/<clip>_<frame>.png (git-ignored).
import 'package:brewdiary_bar/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tour = bool.fromEnvironment('TOUR');

void _tourTest(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, body, skip: !_tour);

Future<int> _film(WidgetTester t, String clip, {int frames = 12, Duration every = const Duration(milliseconds: 50), int from = 0}) async {
  for (var i = 0; i < frames; i++) {
    await expectLater(find.byType(BarApp), matchesGoldenFile('tour/motion/${clip}_${(from + i).toString().padLeft(2, '0')}.png'));
    await t.pump(every);
  }
  return from + frames;
}

void main() {
  setUpAll(loadFonts);

  _tourTest('the floor: tiles and a table asking', (t) async {
    await bootApp(t);
    await t.tap(find.text('The Amber Room').first);
    await t.pump();
    await _film(t, 'v1_floor', frames: 20, every: const Duration(milliseconds: 80));
    await t.pumpAndSettle();
  });

  _tourTest('the door clicker', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'Door');
    var n = 0;
    for (var i = 0; i < 3; i++) {
      await t.tap(find.bySemanticsLabel('1 In'));
      await t.pump();
      n = await _film(t, 'v2_door', frames: 5, every: const Duration(milliseconds: 45), from: n);
    }
    await t.pumpAndSettle();
  });

  _tourTest('a ticket line moves on', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'Bar tickets');
    final line = find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true && (w.properties.label ?? '').endsWith(', sent'));
    if (line.evaluate().isEmpty) return;
    await t.ensureVisible(line.first);
    await t.pumpAndSettle();
    await t.tap(line.first);
    await t.pump();
    await _film(t, 'v3_ticket', frames: 10, every: const Duration(milliseconds: 40));
    await t.pumpAndSettle();
  });

  _tourTest('a wrong code shakes', (t) async {
    await bootApp(t);
    await tapText(t, 'Café Nilgiri');
    await t.enterText(find.byType(TextField).first, '111111');
    await t.tap(find.text('Join Café Nilgiri').first);
    await t.pump();
    await _film(t, 'v4_wrong_code', frames: 12, every: const Duration(milliseconds: 40));
    await t.pumpAndSettle();
  });
}
