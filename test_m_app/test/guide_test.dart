// Finding things: the first-time card on the calendar (once, then gone for good),
// and the guide — every feature, where it lives, a tap that goes there.
import 'package:brewdiary/app.dart';
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/ui/screens/guide_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('the calendar\'s first-time card: shown once, gone for good when dismissed', (t) async {
    await bootApp(t, size: const Size(390, 1600), signedIn: true);
    expect(find.text('NEW HERE?'), findsOneWidget);
    await t.tap(find.byTooltip('Got it — hide this'));
    await t.pumpAndSettle();
    expect(find.text('NEW HERE?'), findsNothing);
    expect(Prefs.getString('brewdiary.firststeps.v1'), 'done', reason: 'remembered on this phone');
  });

  testWidgets('the guide: from the card, and each row takes you there', (t) async {
    await bootApp(t, size: const Size(390, 1600), signedIn: true);
    await t.tap(find.text("See what's in brewdiary"));
    await t.pumpAndSettle();
    expect(find.text("What's in brewdiary"), findsWidgets);
    for (final title in ['Log a drink', 'Share a night', 'The feed', 'Split the bill', 'Tonight', 'The morning after']) {
      expect(find.text(title), findsOneWidget, reason: '$title is listed');
    }

    // A tab row: back to the shell, on that tab.
    await t.tap(find.text('The feed'));
    await t.pumpAndSettle();
    expect(find.byType(GuideScreen), findsNothing);
    expect(t.widget<Semantics>(find.byKey(const ValueKey('tab-together'))).properties.selected, isTrue);

    // A page row: the guide closes and the page opens.
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const GuideScreen()));
    await t.pumpAndSettle();
    await t.tap(find.text('Log a drink'));
    await t.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('What did you drink?'.toUpperCase()), findsOneWidget, reason: "today's log sheet");
  });
}
