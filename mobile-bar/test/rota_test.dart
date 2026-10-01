// The rota, time off, breaks, timesheets and payroll (supabase/054): the words and rules
// (held against the migration's own text where the database decides), then the flows on the
// demo venues with the real screens — an owner planning and approving, a server at Café
// Nilgiri asking for a shift and giving one away, a break, a correction, and payroll.
import 'dart:io';

import 'package:brewdiary_bar/data/models.dart';
import 'package:brewdiary_bar/data/session.dart';
import 'package:brewdiary_bar/logic/roles.dart';
import 'package:brewdiary_bar/logic/rota.dart';
import 'package:brewdiary_bar/logic/staff.dart' show weekStart;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final sql = File('../supabase/054_rota_payroll.sql').readAsStringSync();

  group('the rules the database keeps (parity with 054)', () {
    test('who may ask for which shift: their own role, or a shift lead, manager or owner', () {
      final m = RegExp(r"coalesce\(mine, ''\) not in \(([^)]+)\)").firstMatch(sql)!;
      final seniors = m[1]!.split(',').map((x) => StaffRole.parse(x.trim().replaceAll("'", ''))).toSet();
      for (final mine in StaffRole.values) {
        for (final shift in StaffRole.values) {
          expect(canTakeRole(mine, shift), mine == shift || seniors.contains(mine), reason: '${mine.db} → ${shift.db}');
        }
      }
    });

    test('weekdays are stored 0 = Sunday … 6 = Saturday, like quiet nights', () {
      expect(sql, contains('array[0, 1, 2, 3, 4, 5, 6]::smallint[]'));
      expect(dbWeekday(DateTime(2026, 10, 4)), 0); // a Sunday
      expect(dbWeekday(DateTime(2026, 9, 28)), 1); // a Monday
      expect(dbWeekday(DateTime(2026, 10, 3)), 6); // a Saturday
      expect([for (final d in [1, 2, 3, 4, 5, 6, 0]) weekdayShort(d)], ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
    });

    test('a break someone takes is never theirs to call paid', () {
      expect(sql, contains('create or replace function public.start_break(vid uuid)'));
      expect(sql, contains('values (sid, vid, me, false)'));
      expect(sql, contains('nobody decides their own pay'));
    });
  });

  group('the words for a week', () {
    final mon = DateTime(2026, 9, 28);
    RotaShift shift({String? user, String? name, int day = 0, int from = 18, int hours = 8, bool published = true, RotaSwap? swap, bool active = true, int brk = 0}) {
      final s = DateTime(mon.year, mon.month, mon.day + day, from);
      return RotaShift(id: '$user-$day-$from', userId: user, name: name, role: StaffRole.bartender, startsAt: s, endsAt: s.add(Duration(hours: hours)), published: published, swap: swap, active: active, breakMinutes: brk);
    }

    test('labels', () {
      expect(weekLabel(mon), '28 Sep – 4 Oct');
      expect(dayLabel(mon), 'Mon 28');
      expect(dateLabel(DateTime(2026, 10, 4)), '4 Oct');
      expect(shiftTimes(DateTime(2026, 9, 28, 18), DateTime(2026, 9, 29, 2)), '18:00–02:00 (+1)');
      expect(shiftTimes(DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 16, 30)), '08:00–16:30');
      expect(weekDays(mon).last, DateTime(2026, 10, 4));
      expect(weekStart(DateTime(2026, 10, 4, 23)), mon);
    });

    test('a night past midnight belongs to the day it started', () {
      final days = byDay([shift(user: 'u1', name: 'Sam', day: 0, from: 22), shift(user: 'u2', name: 'Ira', day: 0, from: 16)]);
      expect(days.keys, [mon]);
      expect([for (final s in days[mon]!) s.name], ['Ira', 'Sam'], reason: 'by start time');
    });

    test('a clash says what it is — booked, off, or a day they can\'t work', () {
      const sam = RotaMember(userId: 'u1', name: 'Sam', role: StaffRole.bartender, cannotWork: [1]);
      final on = shift(user: 'u1', name: 'Sam', day: 2);
      final s = DateTime(2026, 9, 30, 20);
      expect(clashFor(sam, s, s.add(const Duration(hours: 4)), [on], const []), 'Sam is already on 18:00–02:00 (+1)');
      expect(clashFor(sam, s, s.add(const Duration(hours: 4)), [on], const [], exceptShiftId: on.id), isNull, reason: 'moving the same shift');
      final off = TimeOff(id: 'o', userId: 'u1', startsAt: DateTime(2026, 10, 2), endsAt: DateTime(2026, 10, 3), status: 'approved');
      expect(clashFor(sam, DateTime(2026, 10, 2, 18), DateTime(2026, 10, 3, 2), const [], [off]), 'Sam is off then');
      final asked = TimeOff(id: 'o', userId: 'u1', startsAt: DateTime(2026, 10, 2), endsAt: DateTime(2026, 10, 3), status: 'requested');
      expect(clashFor(sam, DateTime(2026, 10, 2, 18), DateTime(2026, 10, 3, 2), const [], [asked]), isNull, reason: 'only APPROVED time off blocks');
      expect(clashFor(sam, DateTime(2026, 10, 5, 18), DateTime(2026, 10, 6, 2), const [], const []), 'Sam can\'t work Mondays');
    });

    test('tags: draft, open, on offer, asked, needs cover', () {
      expect(shiftTag(shift(user: 'u1', published: false), me: 'u1'), 'draft');
      expect(shiftTag(shift(), me: 'u1'), 'open');
      expect(shiftTag(shift(user: 'u2', active: false), me: 'u1'), 'needs cover');
      expect(shiftTag(shift(user: 'u1', swap: const RotaSwap(id: 'w', status: 'offered', fromUser: 'u1')), me: 'u1'), 'you offered it');
      expect(shiftTag(shift(user: 'u2', swap: const RotaSwap(id: 'w', status: 'offered', fromUser: 'u2')), me: 'u1'), 'on offer');
      expect(shiftTag(shift(user: 'u2', swap: const RotaSwap(id: 'w', status: 'taken', fromUser: 'u2', toUser: 'u1')), me: 'u1'), 'you asked');
      expect(shiftTag(shift(swap: const RotaSwap(id: 'w', status: 'taken', toUser: 'u3', toName: 'Noor')), me: 'u1'), 'asked: Noor');
      expect(shiftTag(shift(user: 'u1'), me: 'u1'), isNull);
    });

    test('planned hours per person: by name, less the planned break, open shifts left out', () {
      final rows = plannedByPerson([
        shift(user: 'u2', name: 'sam', brk: 30),
        shift(user: 'u1', name: 'Ira', day: 1),
        shift(),
        shift(user: 'u2', name: 'sam', day: 2),
      ]);
      expect([for (final r in rows) r.name], ['Ira', 'sam']);
      expect(rows.last.minutes, 8 * 60 - 30 + 8 * 60);
    });

    test('time off shows on each day it covers', () {
      final off = TimeOff(id: 'o', userId: 'u1', startsAt: DateTime(2026, 10, 2), endsAt: DateTime(2026, 10, 4), status: 'approved');
      expect(offOn([off], DateTime(2026, 10, 1)), isEmpty);
      expect(offOn([off], DateTime(2026, 10, 2)), [off]);
      expect(offOn([off], DateTime(2026, 10, 3)), [off]);
      expect(offOn([off], DateTime(2026, 10, 4)), isEmpty);
      expect(off.lastDay, DateTime(2026, 10, 3));
    });
  });

  group('walk-throughs', () {
    setUpAll(loadFonts);

    Future<void> openMore(WidgetTester t, String venue) async {
      await bootApp(t);
      await tapText(t, venue);
      await tapText(t, 'MORE');
    }

    testWidgets('an owner approves an ask, publishes next week, copies it on, and answers time off', (t) async {
      await openMore(t, 'The Amber Room');
      await tapInView(t, 'Rota');
      expect(find.text('Everything this week is published.'), findsOneWidget);
      expect(find.text('A party of 12 at 21:00'), findsNothing, reason: 'the note is part of the line');
      expect(find.textContaining('A party of 12 at 21:00'), findsOneWidget);

      await t.tap(find.byTooltip('The week after'));
      await t.pumpAndSettle();
      expect(find.text('2 shifts are drafts only planners can see.'), findsOneWidget);
      expect(find.text('WAITING FOR YOUR YES'), findsOneWidget);
      await tapText(t, 'Noor asked to take an open shift');
      await tapText(t, 'Approve');
      expect(find.text('WAITING FOR YOUR YES'), findsNothing);
      expect(find.text('Noor'), findsWidgets, reason: 'the lunch shift is hers now');
      expect(find.text('Open shift'), findsNothing);

      await tapText(t, 'Publish this week');
      expect(find.text('Everything this week is published.'), findsOneWidget);
      expect(find.text('draft'), findsNothing);

      await t.tap(find.byTooltip('The week after'));
      await t.pumpAndSettle();
      expect(find.text('Everything this week is published.'), findsOneWidget, reason: 'nothing planned yet');
      await tapText(t, 'Copy last week here');
      expect(find.textContaining('drafts only planners can see'), findsOneWidget);
      expect(find.text('draft'), findsWidgets);

      await t.tap(find.byTooltip('Time off'));
      await t.pumpAndSettle();
      expect(find.text('WAITING FOR YOUR YES'), findsOneWidget);
      await tapText(t, 'Noor');
      expect(find.text('My cousin\'s wedding'), findsWidgets);
      await tapText(t, 'Approve');
      expect(find.text('WAITING FOR YOUR YES'), findsNothing);
      expect(find.text('COMING UP'), findsOneWidget);
    });

    testWidgets('a server asks for an open shift, gives one away, and asks for a day off', (t) async {
      await bootApp(t);
      await tapText(t, 'Café Nilgiri');
      await t.enterText(find.byType(TextField).first, '482913');
      await tapText(t, 'Join Café Nilgiri');
      expect(Session.instance.venue?.myRole, StaffRole.server);
      await tapText(t, 'MORE');
      await tapInView(t, 'Rota');
      expect(find.textContaining('drafts only planners'), findsNothing, reason: 'a server doesn\'t plan');
      await t.tap(find.byTooltip('The week after'));
      await t.pumpAndSettle();
      expect(find.text('Open shift'), findsOneWidget);
      expect(find.text('on offer'), findsOneWidget, reason: 'Arun\'s Friday');

      await tapText(t, 'Open shift');
      await tapText(t, 'Ask to take this shift');
      expect(find.text('you asked'), findsOneWidget);

      await tapText(t, 'You (demo)');
      await tapText(t, 'Give this shift away');
      expect(find.text('you offered it'), findsOneWidget);

      await t.tap(find.byTooltip('Time off'));
      await t.pumpAndSettle();
      expect(find.text('Nothing asked for yet.'), findsOneWidget);
      await tapText(t, 'Ask for time off');
      await tapText(t, 'Send');
      expect(find.text('Nothing asked for yet.'), findsNothing);
      expect(find.text('asked'), findsOneWidget);
      await tapText(t, 'Sat');
      await t.pumpAndSettle();
      expect(find.text('WAITING FOR YOUR YES'), findsNothing, reason: 'a server answers nobody\'s time off');
    });

    testWidgets('a break comes off the hours, and ends before clocking out', (t) async {
      await openMore(t, 'The Amber Room');
      await tapInView(t, 'Clock in');
      await tapInView(t, 'Start a break');
      expect(find.textContaining('On a break since'), findsOneWidget);
      expect(find.text('Clock out'), findsNothing, reason: 'end the break first');
      await tapInView(t, 'End my break');
      expect(find.textContaining('On since'), findsOneWidget);
      expect(find.text('Start a break'), findsOneWidget);
      await tapInView(t, 'Clock out');
      expect(find.text('Off the clock'), findsOneWidget);
    });

    testWidgets('a timesheet: the changes behind a corrected night, a correction, a paid break', (t) async {
      await openMore(t, 'The Amber Room');
      await tapText(t, 'Team');
      await t.scrollUntilVisible(find.text('Hours'), 200, scrollable: find.byType(Scrollable).first);
      await tapText(t, 'Hours');
      expect(find.text('Kabir'), findsNothing, reason: 'waiting for a yes: not on the team yet');
      await t.tap(find.text('30 DAYS'));
      await t.pumpAndSettle();
      await tapInView(t, 'Noor');
      await tapText(t, 'Their timesheet');
      expect(find.text('Timesheet'), findsOneWidget);

      await t.tap(find.text('30 DAYS'));
      await t.pumpAndSettle();
      expect(find.text('corrected'), findsOneWidget);
      await tapInView(t, 'corrected');
      await tapText(t, 'See the changes');
      expect(find.textContaining('Forgot to clock out — we closed at 01:00'), findsOneWidget);
      await t.tapAt(const Offset(20, 60)); // close the sheet
      await t.pumpAndSettle();

      // Noor's nights carry a 15-minute break a manager marked paid; make one unpaid.
      final night = find.textContaining('15 min paid break').first;
      await t.ensureVisible(night);
      await t.pumpAndSettle();
      await t.tap(night);
      await t.pumpAndSettle();
      await tapText(t, 'The break');
      expect(find.text('paid'), findsOneWidget);
      await tapText(t, 'paid');
      await tapText(t, 'Make it unpaid');

      // …and correct another night's end (one not corrected yet), with a reason.
      await t.tap(find.textContaining('15 min paid break').first);
      await t.pumpAndSettle();
      await tapText(t, 'Correct the times');
      await tapText(t, 'End +30 min');
      await tapText(t, 'Save the correction');
      expect(find.text('Say why, so the change can be traced.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'Stayed to close');
      await tapText(t, 'Save the correction');
      expect(find.text('Save the correction'), findsNothing, reason: 'the sheet closed');
      // the night just corrected is tagged; the one corrected earlier sits further up
      expect(find.text('corrected'), findsNWidgets(2));
    });

    testWidgets('payroll: by name, pay per person, a rate set by the owner', (t) async {
      await openMore(t, 'The Amber Room');
      await tapInView(t, 'Payroll');
      await tapText(t, 'Last week');
      final names = [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? ''].where((s) => ['Ira', 'Leo', 'Noor', 'Sam', 'You (demo)'].contains(s)).toList();
      expect(names, isNotEmpty);
      expect(names, [...names]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())), reason: 'listed by name, never by pay');
      expect(find.text('Share as CSV'), findsOneWidget);
      expect(find.textContaining('No rate for'), findsNothing, reason: 'everyone paid by the hour has a rate; the owner isn\'t');

      await tapInView(t, 'Noor');
      await tapText(t, 'Change their pay');
      expect(find.textContaining('never the amount'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, 'lots');
      await tapText(t, 'Save');
      expect(find.text('A number from 0 to 1,00,000.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, '260');
      await tapText(t, 'Save');
      expect(find.text('Save'), findsNothing, reason: 'the sheet closed');
      await tapInView(t, 'Noor');
      await tapText(t, 'Change their pay');
      expect(t.widget<TextField>(find.byType(TextField).last).controller!.text, '260');
    });

    testWidgets('a manager can\'t set their own pay, or the owner\'s', (t) async {
      await openMore(t, 'Mithai Mahal');
      expect(Session.instance.venue?.myRole, StaffRole.manager);
      await tapInView(t, 'Clock in');
      await tapInView(t, 'Clock out');
      await tapInView(t, 'Payroll');
      await tapInView(t, 'You (demo)');
      expect(find.text('My timesheet'), findsOneWidget);
      expect(find.text('Set their pay'), findsNothing);
      expect(find.text('Change their pay'), findsNothing);
      await tapText(t, 'Cancel');
      await t.pageBack();
      await t.pumpAndSettle();
      await tapText(t, 'Team');
      await tapInView(t, 'Ira');
      expect(find.text('Their pay'), findsNothing, reason: 'the owner\'s pay is nobody\'s to set from an app');
    });
  });
}
