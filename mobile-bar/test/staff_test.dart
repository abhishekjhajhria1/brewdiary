// Staff access (supabase/053): the owner's code, approvals, pausing someone, the history
// and the clock — the words (held against the migration's own text), then the flows on
// the demo venue with the real screens.
import 'dart:io';

import 'package:brewdiary_bar/data/session.dart';
import 'package:brewdiary_bar/logic/staff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final sql = File('../supabase/053_staff_access.sql').readAsStringSync();

  group('the rules the database keeps (parity with 053)', () {
    test('every way a code can fail is one the app can word', () {
      final m = RegExp(r"'error', case when e\.attempts \+ 1 >= 5 then '(\w+)' else '(\w+)' end").firstMatch(sql)!;
      final raised = {
        m[1]!,
        m[2]!,
        for (final x in RegExp(r"jsonb_build_object\('ok', false, 'error', '(\w+)'\)").allMatches(sql)) x[1]!,
      };
      expect(raised, {for (final e in ClaimError.values) e.db});
    });

    test('the phone and email shapes are the database\'s', () {
      expect(sql, contains(r"phone ~ '^\+?[0-9 ()-]{6,20}$'"));
      for (final ok in ['+91 98765 43210', '080-2345 6789', '(022) 1234567']) {
        expect(validStaffPhone(ok), isTrue, reason: ok);
      }
      for (final bad in ['12345', 'call me', '+91 98765 43210 ext 5']) {
        expect(validStaffPhone(bad), isFalse, reason: bad);
      }
      expect(validStaffEmail('rahul@gmail.com'), isTrue);
      expect(validStaffEmail(' Rahul@Gmail.com '), isTrue);
      expect(validStaffEmail('rahul@gmail'), isFalse);
      expect(validStaffEmail('rahul gmail.com'), isFalse);
    });

    test('statuses: waiting, working, paused — and anything else reads as working', () {
      expect(sql, contains("check (status in ('pending', 'active', 'locked'))"));
      expect(StaffStatus.parse('locked'), StaffStatus.locked);
      expect(StaffStatus.parse(null), StaffStatus.active, reason: 'a database before 053 has no status column');
    });

    test('a code lives 48 hours and allows 5 tries', () {
      expect(sql, contains("interval '48 hours'"));
      expect(sql, contains('attempts between 0 and 5'));
      expect(enrolShareText(venue: 'The Amber Room', roleWord: 'Server', email: 'r@x.com', code: '482913'), allOf(contains('48 hours'), contains('482913'), contains('r@x.com'), contains('as a server')));
    });
  });

  group('the words', () {
    test('a wrong code says how many tries are left', () {
      expect(claimMessage(ClaimError.wrongCode, left: 4), 'That\'s not the code — 4 tries left.');
      expect(claimMessage(ClaimError.wrongCode, left: 1), 'That\'s not the code — 1 try left.');
      expect(claimMessage(ClaimError.tooMany, addedBy: 'Meenakshi'), 'Too many wrong tries — ask Meenakshi for a new code.');
      expect(claimMessage(ClaimError.notFound), contains('the email your manager added'));
      expect(claimMessage(ClaimError.locked, addedBy: ''), 'Your access here is paused — talk to your manager.');
    });

    test('the code as typed: digits only, six at most', () {
      expect(codeDigits('482 913'), '482913');
      expect(codeDigits(' 48-29-13 '), '482913');
      expect(codeDigits('4829130'), '482913');
      expect(codeDigits('12a'), '12');
    });

    test('roles in a sentence', () {
      expect(roleWithArticle('Server'), 'a server');
      expect(roleWithArticle('Owner'), 'an owner');
      expect(roleWithArticle('Kitchen'), 'kitchen staff');
      expect(roleWithArticle('Shift lead'), 'a shift lead');
    });

    test('who to report to', () {
      expect(reportLine('Arjun', 'manager'), 'Please report to Arjun (manager).');
      expect(reportLine('Arjun', null), 'Please report to Arjun.');
      expect(reportLine(null, null), 'Please talk to the owner or a manager.');
    });

    test('how long a code has left', () {
      final now = DateTime(2026, 9, 30, 20);
      expect(codeLifeLeft(now.add(const Duration(hours: 31, minutes: 20)), now), 'runs out in 31h');
      expect(codeLifeLeft(now.add(const Duration(minutes: 40)), now), 'runs out in 40 min');
      expect(codeLifeLeft(now.subtract(const Duration(minutes: 1)), now), 'ran out');
    });

    test('hours read as hours, and a week starts on Monday', () {
      expect(formatMinutes(0), '0m');
      expect(formatMinutes(45), '45m');
      expect(formatMinutes(180), '3h');
      expect(formatMinutes(425), '7h 05m');
      expect(weekStart(DateTime(2026, 9, 30, 21, 15)), DateTime(2026, 9, 28)); // a Wednesday
      expect(weekStart(DateTime(2026, 9, 28, 0, 5)), DateTime(2026, 9, 28)); // Monday itself
      expect(weekStart(DateTime(2026, 10, 4, 23)), DateTime(2026, 9, 28)); // Sunday
    });

    test('every kind of history line the database writes reads as a sentence', () {
      String word(String db) => db[0].toUpperCase() + db.substring(1);
      final kinds = RegExp(r'kind in \(([^)]+)\)').firstMatch(sql)![1]!.split(',').map((k) => k.trim().replaceAll("'", '')).where((k) => k.isNotEmpty);
      for (final k in kinds) {
        final line = describeStaffEvent(kind: k, actor: 'Ira', subject: 'Sam', detail: const {'role': 'server', 'from': 'server', 'to': 'bartender'}, roleWord: word);
        expect(line, isNot(startsWith('Ira changed something')), reason: k);
      }
      String d(String kind, [Map<String, dynamic> detail = const {}]) => describeStaffEvent(kind: kind, actor: 'Ira', subject: 'Sam', detail: detail, roleWord: word);
      expect(d('enrolled', {'role': 'server', 'name': 'Rahul S.'}), 'Ira added Rahul S. as a server');
      expect(d('joined', {'role': 'server', 'via': 'code'}), 'Sam joined as a server with the owner\'s code');
      expect(d('locked', {'reason': 'See me first'}), 'Ira paused Sam\'s access: \u201cSee me first\u201d');
      expect(d('role_changed', {'from': 'server', 'to': 'kitchen'}), 'Ira made Sam kitchen staff (was server)');
      expect(d('left'), 'Sam left the team');
    });
  });

  group('walk-throughs', () {
    setUpAll(loadFonts);

    testWidgets('an owner adds an employee and sees their code, once', (t) async {
      await bootApp(t);
      await tapText(t, 'The Amber Room');
      await tapText(t, 'MORE');
      await tapText(t, 'Team');
      expect(find.text('WAITING FOR YOUR YES'), findsOneWidget);
      expect(find.text('Kabir'), findsOneWidget);
      expect(find.text('Rahul S.'), findsOneWidget, reason: 'added, not in yet');

      await tapText(t, 'Add an employee');
      await t.enterText(find.byType(TextField).at(0), 'Priya Nair');
      await t.enterText(find.byType(TextField).at(1), 'priya@example');
      await t.pump();
      await t.ensureVisible(find.text('Make their code'));
      await tapText(t, 'Make their code');
      expect(find.text('That email doesn\'t look right.'), findsOneWidget, reason: 'checked before asking');

      await t.enterText(find.byType(TextField).at(1), 'priya@example.com');
      await t.pump();
      await t.ensureVisible(find.text('Make their code'));
      await tapText(t, 'Make their code');
      expect(find.text('Priya Nair\'s code'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d{3} \d{3}$')), findsOneWidget, reason: 'six digits, spaced to read aloud');
      expect(find.textContaining('Shown once'), findsOneWidget);
      await tapText(t, 'Done');
      expect(find.text('Priya Nair'), findsOneWidget, reason: 'now waiting for her to type it');
    });

    testWidgets('say yes to someone waiting; pause someone, then give access again', (t) async {
      await bootApp(t);
      await tapText(t, 'The Amber Room');
      await tapText(t, 'MORE');
      await tapText(t, 'Team');

      await tapText(t, 'Kabir');
      expect(find.textContaining('Say yes only if you know who this is'), findsOneWidget, reason: 'a deliberate yes, with who they are');
      await tapText(t, 'Approve as a server');
      expect(find.text('WAITING FOR YOUR YES'), findsNothing);
      expect(find.text('Kabir'), findsOneWidget, reason: 'on the team now');

      // Sam is on shift. Pause him: a reason, who to report to.
      expect(find.text('on shift'), findsWidgets);
      await t.ensureVisible(find.text('Sam'));
      await tapText(t, 'Sam');
      await tapText(t, 'Pause their access');
      expect(find.textContaining('Everything here stops for them at once'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Come and see me about Friday');
      await tapText(t, 'Pause access');
      await t.ensureVisible(find.text('Sam'));
      final samTile = find.ancestor(of: find.text('Sam'), matching: find.byType(Row)).first;
      expect(find.descendant(of: samTile, matching: find.text('paused')), findsOneWidget);
      expect(find.descendant(of: samTile, matching: find.text('on shift')), findsNothing, reason: 'pausing clocks them out');

      await tapText(t, 'Sam');
      expect(find.textContaining('Come and see me about Friday'), findsOneWidget);
      await tapText(t, 'Give access again');
      await t.ensureVisible(find.text('Sam'));
      final again = find.ancestor(of: find.text('Sam'), matching: find.byType(Row)).first;
      expect(find.descendant(of: again, matching: find.text('paused')), findsNothing);
    });

    testWidgets('an employee joins with the owner\'s code: a wrong try, then the right one', (t) async {
      await bootApp(t);
      expect(find.text('A CODE TO TYPE'), findsOneWidget);
      await tapText(t, 'Café Nilgiri');
      expect(find.textContaining('Meenakshi added you as a server. Type the 6-digit code'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '111111');
      await tapText(t, 'Join Café Nilgiri');
      expect(find.text('That\'s not the code — 4 tries left.'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '482 913');
      await tapText(t, 'Join Café Nilgiri');
      expect(Session.instance.venue?.name, 'Café Nilgiri');
      expect(Session.instance.venue?.myRole.db, 'server', reason: 'the role the owner chose');
    });

    testWidgets('a paused venue says who to report to', (t) async {
      await bootApp(t);
      expect(find.text('WAITING AND PAUSED'), findsOneWidget);
      await t.ensureVisible(find.text('The Tap House'));
      await tapText(t, 'The Tap House');
      expect(find.text('Your access is paused'), findsOneWidget);
      expect(find.text('Please report to Arjun (manager).'), findsOneWidget);
      expect(find.textContaining('Saturday\'s cash-up'), findsOneWidget);
      await tapText(t, 'Back to my venues');
      expect(find.text('Your venues'), findsWidgets);
    });

    testWidgets('paused mid-shift: the app stops at once, and opens again when unpaused', (t) async {
      final demo = await bootApp(t);
      await tapText(t, 'Mithai Mahal');
      expect(find.text('TILL'), findsOneWidget);

      demo.pauseMe('demo-sweets', reason: 'Please see me before you open up.', reportTo: 'Ira');
      await t.pumpAndSettle();
      expect(find.text('Your access is paused'), findsOneWidget);
      expect(find.text('Please report to Ira (owner).'), findsOneWidget);
      expect(Session.instance.venue, isNull, reason: 'nothing of the venue stays open');

      // No signal: the check fails — and the pause stays on screen, it isn't lifted by a blip.
      demo.offline = true;
      await Session.instance.refreshVenues();
      await t.pumpAndSettle();
      expect(find.text('Your access is paused'), findsOneWidget);
      demo.offline = false;

      demo.unpauseMe('demo-sweets');
      await t.pumpAndSettle();
      expect(Session.instance.venue?.name, 'Mithai Mahal', reason: 'given access again: straight back in');
      expect(find.text('TILL'), findsOneWidget);
    });

    testWidgets('clock in and out; a manager sees the hours by name and the history', (t) async {
      await bootApp(t);
      await tapText(t, 'The Amber Room');
      await tapText(t, 'MORE');
      await t.ensureVisible(find.text('Clock in'));
      await tapText(t, 'Clock in');
      expect(find.textContaining('On since'), findsOneWidget);
      await t.ensureVisible(find.text('Clock out'));
      await tapText(t, 'Clock out');
      expect(find.text('Off the clock'), findsOneWidget);

      await t.drag(find.byType(Scrollable).first, const Offset(0, 800));
      await t.pumpAndSettle();
      await tapText(t, 'Team');
      await t.scrollUntilVisible(find.text('Hours'), 200, scrollable: find.byType(Scrollable).first);
      await tapText(t, 'Hours');
      expect(find.text('ON NOW'), findsOneWidget);
      expect(find.textContaining('never a ranking'), findsOneWidget);
      final names = [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? ''].where((s) => ['Ira', 'Leo', 'Noor', 'Sam'].contains(s)).toList();
      expect(names, [...names]..sort(), reason: 'listed by name, never by hours');

      await t.pageBack();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Team history'), 200, scrollable: find.byType(Scrollable).first);
      await tapText(t, 'Team history');
      expect(find.textContaining('paused Leo\'s access'), findsOneWidget);
      expect(find.text('You (demo) added Rahul S. as a server'), findsOneWidget);
    });
  });
}
