// Walk-throughs on the demo venue: the real screens, the real rules, no network.
import 'package:brewdiary_bar/data/session.dart';
import 'package:brewdiary_bar/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('sign in with an emailed code, then pick a venue', (t) async {
    await bootApp(t, signedIn: false);
    expect(find.text('brewdiary bar'), findsWidgets);
    await t.enterText(find.byType(TextField).first, 'you@yourbar.com');
    await tapText(t, 'Email me a code');
    expect(find.text('Check your email'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '123456');
    await tapText(t, 'Sign in');
    expect(find.text('Your venues'), findsWidgets);
    expect(find.text('The Amber Room'), findsOneWidget);
    expect(find.text('Mithai Mahal'), findsOneWidget);
  });

  testWidgets('a bar owner: tonight\'s room, a reward handed over, the guest book', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    expect(Session.instance.venue?.name, 'The Amber Room');

    // Before the shift: Ninkasi's briefing sits on top of the floor.
    expect(find.text('BEFORE YOUR SHIFT'), findsOneWidget);

    // Tonight's room is one tap from the floor: the demo room is live, its guests listed.
    await tapText(t, 'Tonight\'s room');
    expect(find.textContaining('amberfox'), findsWidgets);
    expect(find.text('Anita'), findsOneWidget);

    // Anita has earned the first tier — hand it over.
    await t.scrollUntilVisible(find.byTooltip('Anita\'s rewards'), 150, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -150)); // clear of the tab bar
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Anita\'s rewards'));
    await t.pumpAndSettle();
    expect(find.text('A coffee on us'), findsOneWidget);
    await t.tap(find.text('HAND OVER'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Enjoy'), findsOneWidget); // the toast
    await t.pumpAndSettle();
    expect(find.text('HAND OVER'), findsNothing, reason: 'claimed — progress restarts from zero');
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();

    // Her card: first-party history and the notes this venue keeps.
    await t.tap(find.byTooltip('Open Anita\'s card'));
    await t.pumpAndSettle();
    expect(find.text('VISITS'), findsOneWidget);
    expect(find.textContaining('less Campari'), findsOneWidget);
  });

  testWidgets('the tabs a manager sees: guests, menu, numbers, team', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');

    await tapText(t, 'MENU');
    expect(find.text('Negroni'), findsOneWidget);
    expect(find.text('Kokum Cooler'), findsOneWidget);

    await tapText(t, 'NUMBERS');
    expect(find.text('64'), findsOneWidget); // guests in the window
    expect(find.textContaining('never a ranking'), findsOneWidget);

    await tapText(t, 'MORE');
    await tapText(t, 'Team');
    expect(find.text('Ira'), findsOneWidget);
    expect(find.textContaining('Server'), findsWidgets);
  });

  testWidgets('a sweet shop runs a till, not rooms', (t) async {
    await bootApp(t);
    await tapText(t, 'Mithai Mahal');
    expect(find.text('TILL'), findsOneWidget);
    expect(find.text('COUNTER'), findsOneWidget); // the menu tab is the counter
    await t.enterText(find.byType(TextField).first, 'rohan');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    await tapText(t, 'PUNCH');
    expect(find.text('punched'), findsOneWidget);
  });

  testWidgets('onboarding a shop is a name, a kind and a country', (t) async {
    await bootApp(t);
    await tapText(t, 'Create a venue');
    await t.enterText(find.byType(TextField).first, 'Ghee & Co');
    await t.pump();
    expect(find.textContaining('bwdy.site/m/ghee-co'), findsOneWidget, reason: 'the address follows the name');
    await tapText(t, 'Sweet shop');
    expect(find.textContaining('counts visits'), findsOneWidget, reason: 'a counter\'s card counts visits');
    await t.scrollUntilVisible(find.text('Create venue'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(t, 'Create venue');
    expect(Session.instance.venue?.name, 'Ghee & Co');
    expect(find.text('TILL'), findsOneWidget, reason: 'straight into a working till');
  });

  testWidgets('the area map: neighbourhoods of people who said yes, never a person', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'NUMBERS');
    await t.scrollUntilVisible(find.text('Open the area map'), 200, scrollable: find.byType(Scrollable).first);
    await t.drag(find.byType(Scrollable).first, const Offset(0, -200)); // clear of the tab bar
    await t.pumpAndSettle();
    await tapText(t, 'Open the area map');
    expect(find.text('Your area'), findsWidgets);
    expect(find.text('45+'), findsOneWidget, reason: 'the venue\'s own neighbourhood, in 5s');
    expect(find.textContaining('Busiest: your own neighbourhood'), findsOneWidget);

    await tapText(t, 'Kinds of people');
    expect(find.text('Cocktails & spirits'), findsWidgets);
    await t.tap(find.bySemanticsLabel(RegExp('^Your neighbourhood')));
    await t.pumpAndSettle();
    expect(find.text('Your own neighbourhood'), findsOneWidget); // the sheet's title
    expect(find.text('Explorers'), findsWidgets);
    expect(find.textContaining('No names, no venues'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();

    // What's on around you: public facts about places.
    await t.scrollUntilVisible(find.text('Dry day: Gandhi Jayanti'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('A new brewpub opened on 12th Main'), findsOneWidget);
  });

  testWidgets('Ninkasi for the whole team: a briefing, and answers that never push drink', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'Ask Ninkasi');
    expect(find.text('THIS SHIFT'), findsOneWidget);
    expect(find.textContaining('Tonight\'s room is open'), findsOneWidget);
    expect(find.textContaining('Alcohol-free tonight: Kokum Cooler'), findsOneWidget);
    await tapText(t, 'Someone\'s had enough — what do I do?');
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.textContaining('Stop serving them alcohol'), findsOneWidget);
  });

  testWidgets('a liquor store: a sale needs an ID check, and the stock follows', (t) async {
    await bootApp(t, size: const Size(390, 1400));
    await tapText(t, 'Cellar Door Wines');
    expect(find.text('TILL'), findsOneWidget);
    await tapText(t, 'New sale');
    expect(find.textContaining('Alcohol: on sale'), findsOneWidget);
    await t.tap(find.widgetWithText(AccentPill, 'ADD').first); // Amrut Single Malt
    await t.pumpAndSettle();
    expect(find.text('Check ID first: 21 or over.'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('ID checked'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ring up ₹3,400'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Rung up'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('Tap Add on anything below.'), findsOneWidget, reason: 'the basket clears');
    expect(find.textContaining('11 in stock'), findsOneWidget, reason: 'the ledger moved: 12 − 1');
  });

  testWidgets('a sweet shop sells by weight', (t) async {
    await bootApp(t, size: const Size(390, 1400));
    await tapText(t, 'Mithai Mahal');
    await tapText(t, 'New sale');
    await t.tap(find.widgetWithText(AccentPill, 'ADD').first); // Kaju Katli, per kg
    await t.pumpAndSettle();
    await tapText(t, '250 g');
    expect(find.text('250 g Kaju Katli'), findsOneWidget);
    expect(find.text('Ring up ₹300'), findsOneWidget);
  });

  testWidgets('a night on the floor: an order from a table, the kitchen, the bill', (t) async {
    await bootApp(t, size: const Size(390, 1600));
    await tapText(t, 'The Amber Room');
    expect(find.text('FLOOR'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'^T3, asking')), findsOneWidget, reason: 'T3 ordered from its QR');
    expect(find.bySemanticsLabel(RegExp(r'^T5, seated, 2 guests')), findsOneWidget);
    expect(find.textContaining('1 order from tables'), findsOneWidget);

    // The inbox: accept T3's order onto a new tab — it says to check ID (there's a beer).
    await tapText(t, 'Open');
    expect(find.text('alcohol — check ID at the table'), findsOneWidget);
    expect(find.textContaining('never see who asked'), findsOneWidget);
    await tapText(t, 'Accept');
    await t.pumpAndSettle();
    expect(find.text('T2 asks for the bill'), findsOneWidget);
    await tapText(t, 'DONE');
    expect(find.textContaining('Nothing waiting'), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();

    // The kitchen: T5's fries, sent → making.
    await tapText(t, 'Kitchen tickets');
    expect(find.text('T5'), findsOneWidget);
    await t.tap(find.bySemanticsLabel(RegExp(r'^1 Masala Fries, sent')));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^1 Masala Fries, preparing')), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();

    // T5's tab: add a Kokum Cooler, then settle two ways and close.
    await t.tap(find.bySemanticsLabel(RegExp(r'^T5, seated')));
    await t.pumpAndSettle();
    await tapText(t, 'Add to the order');
    await t.tap(find.byTooltip('Add Kokum Cooler'));
    await t.pumpAndSettle();
    await tapText(t, 'Send 1 item');
    expect(find.text('1 × Kokum Cooler'), findsOneWidget);
    await tapText(t, 'Settle and close');
    await tapText(t, '2 ways');
    expect(find.text('PART 2'), findsOneWidget);
    await tapText(t, 'Close the tab');
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^T5, free')), findsOneWidget, reason: 'the table is free again');
  });

  testWidgets('setting up the floor: a table and its own QR', (t) async {
    await bootApp(t, size: const Size(390, 1400));
    await tapText(t, 'The Amber Room');
    await tapText(t, 'MORE');
    await tapText(t, 'Floor setup');
    expect(find.text('Guests can order from the table'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Add a table'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(t, 'Add a table');
    await t.enterText(find.byType(TextField).first, 'W1');
    await tapText(t, 'Save');
    await t.scrollUntilVisible(find.text('W1'), 200, scrollable: find.byType(Scrollable).first);
    await tapText(t, 'W1');
    expect(find.textContaining('bwdy.site/t/'), findsWidgets);
    expect(find.text('Share the link'), findsOneWidget);
  });

  testWidgets('switching venue goes back to the list', (t) async {
    await bootApp(t);
    await tapText(t, 'The Amber Room');
    await tapText(t, 'MORE');
    await t.scrollUntilVisible(find.text('Switch venue'), 200);
    await t.drag(find.byType(Scrollable).last, const Offset(0, -200)); // clear of the tab bar
    await t.pumpAndSettle();
    await tapText(t, 'Switch venue');
    expect(find.text('Your venues'), findsWidgets);
  });
}
