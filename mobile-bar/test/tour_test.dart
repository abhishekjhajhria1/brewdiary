// A screenshot tour for design review — NOT part of the normal suite (skipped unless
// TOUR is defined). Renders the staff-access and rota/payroll screens on the demo venue,
// dark (the default):
//   flutter test test/tour_test.dart --dart-define=TOUR=true --update-goldens
// Output: test/tour/*.png (git-ignored).
import 'package:brewdiary_bar/app.dart';
import 'package:brewdiary_bar/data/session.dart';
import 'package:brewdiary_bar/ui/screens/guests_screen.dart';
import 'package:brewdiary_bar/ui/screens/station_screen.dart';
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

  _tourTest('the rota, breaks, timesheets and payroll', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'MORE');
    await _shot(t, 'r0_more');
    await tapInView(t, 'Rota');
    await _shot(t, 'r1_rota_week');
    await t.tap(find.byTooltip('The week after'));
    await t.pumpAndSettle();
    await _shot(t, 'r2_rota_next_week_planner');
    await tapText(t, 'Add a shift');
    await _shot(t, 'r3_add_shift');
    await t.tap(find.byTooltip('Close').last);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Time off'));
    await t.pumpAndSettle();
    await _shot(t, 'r4_time_off');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await tapInView(t, 'Clock in');
    await tapInView(t, 'Start a break');
    await _shot(t, 'r5_on_a_break');
    await t.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await t.pumpAndSettle();
    await tapInView(t, 'Payroll');
    await tapText(t, 'Last week');
    await _shot(t, 'r6_payroll');
    await tapInView(t, 'Noor');
    await tapText(t, 'Their timesheet');
    await t.tap(find.text('30 DAYS'));
    await t.pumpAndSettle();
    await _shot(t, 'r7_timesheet');
    await tapInView(t, 'corrected');
    await tapText(t, 'Correct the times');
    await _shot(t, 'r8_correct_sheet');
  });

  _tourTest('the rota as a server sees it', (t) async {
    await bootApp(t);
    await tapText(t, 'Café Nilgiri');
    await t.enterText(find.byType(TextField).first, '482913');
    await tapText(t, 'Join Café Nilgiri');
    await tapText(t, 'MORE');
    await tapInView(t, 'Rota');
    await t.tap(find.byTooltip('The week after'));
    await t.pumpAndSettle();
    await _shot(t, 'w1_rota_mine');
    await tapText(t, 'Open shift');
    await _shot(t, 'w2_ask_for_it');
  });

  _tourTest('guests tonight, the code, the taste on the ticket, next steps', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await _shot(t, 'g1_tonight_next_steps');
    final v = Session.instance.venue!;
    final nav = Navigator.of(t.element(find.byType(Scaffold).first));
    nav.push(MaterialPageRoute(builder: (_) => Scaffold(body: GuestsScreen(venue: v))));
    await t.pumpAndSettle();
    await _shot(t, 'g2_guests_in_tonight');
    nav.push(MaterialPageRoute(builder: (_) => StationScreen(venue: v, station: 'bar')));
    await t.pumpAndSettle();
    await _shot(t, 'g3_bar_ticket_taste');
  });
}
