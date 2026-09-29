// Walk-throughs on the demo venue: the real screens, the real rules, no network.
import 'package:brewdiary_bar/data/session.dart';
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

    // Tonight: the demo room is live and its guests are listed.
    expect(find.textContaining('amberfox'), findsWidgets);
    expect(find.text('Anita'), findsOneWidget);

    // Before the shift: Ninkasi's briefing sits on top.
    expect(find.text('BEFORE YOUR SHIFT'), findsOneWidget);

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
