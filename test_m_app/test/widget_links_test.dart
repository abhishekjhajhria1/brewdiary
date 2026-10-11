// Home-screen widget taps: brewdiary://quick/<water|cigarette> logs one for today
// (with Undo — a pocket tap happens), brewdiary://split opens Split. A tap can be
// what starts the app, so a link waits for the saved sign-in to be read first.
import 'package:brewdiary/app.dart';
import 'package:brewdiary/data/auth.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/ui/home_widget.dart';
import 'package:brewdiary_core/date.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

int _today(String drink) => entryStore.entries.where((e) => e.date == todayKey() && e.drink.toLowerCase() == drink).length;

void main() {
  setUpAll(loadFonts);

  testWidgets('+ Water on the widget logs one glass for today, and offers it back', (t) async {
    await bootApp(t, signedIn: true);
    final before = _today('water');
    Shell.openLink(Uri.parse('brewdiary://quick/water'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(_today('water'), before + 1);
    expect(find.text('Undo'), findsOneWidget, reason: 'a pocket tap can be taken back');
    await t.tap(find.text('Undo'));
    await t.pump(const Duration(seconds: 5));
    expect(_today('water'), before);
  });

  testWidgets('a tap that starts the app waits for the saved sign-in, then lands', (t) async {
    await bootApp(t, signedIn: true);
    final before = _today('cigarette');
    auth.status = AuthStatus.loading; // the app just started: the sign-in is still being read
    Shell.openLink(Uri.parse('brewdiary://quick/cigarette'));
    await t.pump(const Duration(milliseconds: 300));
    expect(_today('cigarette'), before, reason: 'not yet — it would land in the wrong diary');
    auth.debugSignIn(auth.profile!); // the sign-in is read
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(_today('cigarette'), before + 1);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('the Split widget, not connected: it says why instead of doing nothing', (t) async {
    await bootApp(t, signedIn: true);
    Shell.openLink(Uri.parse('brewdiary://split'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Split needs you signed in'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  test('the Split widget adds up what you\'re owed and what you owe', () {
    final b = splitTotals({'mira': 900, 'arjun': -250, 'kabir': 120.5, 'leo': 0});
    expect(b.owed, 1020.5);
    expect(b.owe, 250);
  });
}
