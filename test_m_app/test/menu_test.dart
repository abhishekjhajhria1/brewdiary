// Table menus: the menu a tag opens, the picks worked out from the diary on the
// phone, and "Log it" writing the drink into today with the venue filled in.
import 'package:brewdiary/app.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/ui/screens/menu_screen.dart';
import 'package:brewdiary/ui/screens/taste_card.dart';
import 'package:brewdiary/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  testWidgets('a table menu: picks from the diary, and Log it writes today with the venue', (t) async {
    await bootApp(t, prefs: const {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'}, signedIn: true);
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => MenuView(menu: sampleMenu())));
    await t.pumpAndSettle();

    expect(find.text('Soka'), findsWidgets);
    expect(find.text("YOU'D PROBABLY LIKE"), findsOneWidget);
    expect(find.text('₹450'), findsWidgets);

    final before = entryStore.entries.length;
    await t.tap(find.text('Log it').first);
    await t.pump();
    expect(entryStore.entries.length, before + 1);
    final e = entryStore.entries.last;
    expect(e.date, todayKey());
    expect(e.venue, 'Soka');
    await t.pump(const Duration(seconds: 4)); // let the toast go

    // No alcohol only.
    await t.tap(find.text('No alcohol only'));
    await t.pumpAndSettle();
    expect(find.textContaining('Garden Spritz'), findsOneWidget);
    expect(find.textContaining('Negroni'), findsNothing);
  });

  testWidgets('without the cloud, a menu link says so plainly', (t) async {
    await bootApp(t, prefs: const {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'});
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const MenuScreen(slug: 'soka')));
    await t.pumpAndSettle();
    expect(find.textContaining("isn't connected"), findsOneWidget);
  });

  testWidgets('the taste card: from the diary, lines can be hidden, and a dry night goes first', (t) async {
    await bootApp(t, prefs: const {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'}, signedIn: true);
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const TasteCardScreen()));
    await t.pumpAndSettle();
    expect(find.text('INTO'), findsOneWidget);
    await t.ensureVisible(find.bySemanticsLabel('Show Into'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Show Into'));
    await t.pumpAndSettle();
    expect(find.text('INTO'), findsNothing);
    await t.ensureVisible(find.bySemanticsLabel('Nothing with alcohol tonight'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Nothing with alcohol tonight'));
    await t.pumpAndSettle();
    expect(find.text('Nothing with alcohol'), findsOneWidget, reason: 'the identity page says so');
    expect(find.byType(BdToggle), findsWidgets);
  });

  testWidgets('the menu shows the veg mark and allergens (051)', (t) async {
    await bootApp(t, prefs: const {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'}, signedIn: true);
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => MenuView(menu: sampleMenu())));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Masala fries'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byType(DietMark), findsOneWidget);
    expect(find.text('Contains gluten'), findsOneWidget);
    expect(find.byTooltip('Add Masala fries'), findsNothing, reason: 'no ordering without a table that takes orders');
  });
}
