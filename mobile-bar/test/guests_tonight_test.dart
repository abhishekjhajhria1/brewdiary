// Finding a guest without searching everyone (056): who opened the menu tonight,
// with the taste they shared, and the 6-letter code from their guest card.
import 'package:brewdiary_bar/data/backend.dart';
import 'package:brewdiary_bar/data/demo_backend.dart';
import 'package:brewdiary_bar/data/models.dart';
import 'package:brewdiary_bar/data/session.dart';
import 'package:brewdiary_bar/ui/theme.dart';
import 'package:brewdiary_bar/ui/widgets/guest_finder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadFonts);

  test('a shared taste reads only its own keys', () {
    final t = GuestTaste.fromJson({'into': ['Negroni', 3, ''], 'dry_tonight': true, 'diary': ['no']});
    expect(t.into, ['Negroni']);
    expect(t.dryTonight, isTrue);
    expect(GuestTaste.fromJson(null).isEmpty, isTrue);
  });

  testWidgets('in tonight shows each guest with their taste; a code finds a guest', (t) async {
    await bootApp(t);
    final venue = (await Backend.i.myVenues()).first;
    Session.instance.select(venue);
    ProfileHit? picked;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(BD.darkTokens),
      home: Scaffold(body: SingleChildScrollView(child: GuestFinder(venue: venue, pickLabel: 'Punch', onPick: (p) => picked = p))),
    ));
    await t.pumpAndSettle();
    expect(find.text('Anita'), findsOneWidget);
    expect(find.text('Nothing with alcohol tonight'), findsOneWidget, reason: 'a dry night goes first');
    expect(find.text('Allergic: peanuts'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'zzzzzz');
    await t.pumpAndSettle();
    await t.tap(find.text('Find'));
    await t.pumpAndSettle();
    expect(picked, isNull);
    expect(find.textContaining('No guest with that code'), findsOneWidget);

    await t.enterText(find.byType(TextField), DemoBackend.demoGuestCode.toLowerCase());
    await t.pumpAndSettle();
    await t.tap(find.text('Find'));
    await t.pumpAndSettle();
    expect(picked?.name, 'Meera');
  });
}
