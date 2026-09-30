// A screenshot tour for design review — NOT part of the normal suite (skipped unless
// TOUR is defined). Renders the staff-access screens on the demo venue, dark (the
// default) and on a small phone:
//   flutter test test/tour_test.dart --dart-define=TOUR=true --update-goldens
// Output: test/tour/*.png (git-ignored).
import 'package:brewdiary_bar/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tour = bool.fromEnvironment('TOUR');

Future<void> _shot(WidgetTester t, String name) => expectLater(find.byType(BarApp), matchesGoldenFile('tour/$name.png'));

void _tourTest(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, body, skip: !_tour);

void main() {
  setUpAll(loadFonts);

  _tourTest('staff access: the employee\'s side', (t) async {
    await bootApp(t);
    await _shot(t, 's1_venues_code_and_paused');
    await tapText(t, 'Café Nilgiri');
    await t.enterText(find.byType(TextField).first, '111111');
    await tapText(t, 'Join Café Nilgiri');
    await _shot(t, 's2_claim_wrong_code');
    await t.tap(find.byType(ModalBarrier).last, warnIfMissed: false);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('The Tap House'));
    await tapText(t, 'The Tap House');
    await _shot(t, 's3_paused');
  });

  _tourTest('staff access: the manager\'s side', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'MORE');
    await _shot(t, 'm1_more_shift');
    await tapText(t, 'Team');
    await _shot(t, 'm2_team');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await t.pumpAndSettle();
    await _shot(t, 'm3_team_scrolled');
    await t.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await t.pumpAndSettle();
    await tapText(t, 'Add an employee');
    await _shot(t, 'm4_add_employee');
    await t.enterText(find.byType(TextField).at(0), 'Priya Nair');
    await t.enterText(find.byType(TextField).at(1), 'priya@example.com');
    await t.pump();
    await t.ensureVisible(find.text('Make their code'));
    await tapText(t, 'Make their code');
    await _shot(t, 'm5_code_once');
    await tapText(t, 'Done');
    await t.ensureVisible(find.text('Sam'));
    await t.drag(find.byType(Scrollable).first, const Offset(0, 200)); // clear of the top bar
    await t.pumpAndSettle();
    await tapText(t, 'Sam');
    await _shot(t, 'm6_member_actions');
    await tapText(t, 'Pause their access');
    await _shot(t, 'm7_pause_sheet');
  });

  _tourTest('staff access: hours and history', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'MORE');
    await tapText(t, 'Team');
    await t.scrollUntilVisible(find.text('Hours'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(t, 'Hours');
    await _shot(t, 'h1_hours');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Team history'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(t, 'Team history');
    await _shot(t, 'h2_history');
  });
}
