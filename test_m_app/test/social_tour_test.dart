// Screenshot tour of the social screens (skipped unless TOUR is defined). There's
// no backend in tests, so the list screens render their empty states and the
// cards/party room render from sample data.
//   flutter test test/social_tour_test.dart --dart-define=TOUR=true --update-goldens
// Output: test/tour/*.png (git-ignored).
import 'package:brewdiary/app.dart';
import 'package:brewdiary/core/date.dart';
import 'package:brewdiary/data/circles.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/data/friends.dart';
import 'package:brewdiary/data/parties.dart';
import 'package:brewdiary/data/plans.dart';
import 'package:brewdiary/ui/screens/party_screens.dart';
import 'package:brewdiary/ui/screens/plans_section.dart';
import 'package:brewdiary/ui/screens/split_screen.dart';
import 'package:brewdiary/ui/screens/together_screen.dart';
import 'package:brewdiary/ui/theme.dart';
import 'package:brewdiary/ui/widgets/common.dart';
import 'package:brewdiary/ui/widgets/page.dart';
import 'package:brewdiary/ui/widgets/share_card.dart';
import 'package:brewdiary/ui/widgets/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _tour = bool.fromEnvironment('TOUR');

Future<void> _shot(WidgetTester t, String name) => expectLater(find.byType(BrewdiaryApp), matchesGoldenFile('tour/$name.png'));

Future<void> _scroll(WidgetTester t, double dy) async {
  await t.drag(find.byType(Scrollable).hitTestable().first, Offset(0, -dy), warnIfMissed: false);
  await t.pumpAndSettle();
}

void _tourTest(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, body, skip: !_tour);

Future<void> _boot(WidgetTester t, {bool dark = true}) => bootApp(t, dpr: 2, insets: true, signedIn: true, dark: dark);

Future<void> _push(WidgetTester t, Widget page) async {
  navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => page));
  await t.pumpAndSettle();
}

String _iso(int hour) => DateTime(testNow.year, testNow.month, testNow.day, hour).toUtc().toIso8601String();

final _mira = const SocialProfile(id: 'u2', handle: 'mira', name: 'Mira');
final _arjun = const SocialProfile(id: 'u3', handle: 'arjun', name: 'Arjun');

List<FeedEntry> _feed() => [
      FeedEntry(
        id: 'f1',
        userId: 'u2',
        author: _mira,
        date: todayKey(),
        createdAt: _iso(21),
        drink: 'Mezcal Negroni',
        mood: 'smoky',
        note: 'Tried the house one at Soka — better than mine, sadly.',
        venue: 'Soka, Bandra',
        cheers: 3,
        cheered: true,
        comments: const [FeedComment(id: 'c1', userId: 'u3', body: 'Save me one next time.', createdAt: '', authorName: 'Arjun')],
      ),
      FeedEntry(id: 'f2', userId: 'u3', author: _arjun, date: todayKey(), createdAt: _iso(9), drink: 'Pour-over', mood: 'slow', cheers: 0, cheered: false, comments: const []),
    ];

class _Preview extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Preview({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => SubPage(title: title, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
}

Widget _partyPreview() {
  final party = Party(id: 'p1', name: 'Friday tasting', hostId: 'local', venue: 'Bar Termini', date: todayKey(), inviteCode: 'FRI-7KQ2', going: 3);
  const guests = [
    PartyGuest(id: 'local', handle: 'sekhi', name: 'Sekhi', rsvp: Rsvp.going, pending: false),
    PartyGuest(id: 'u2', handle: 'mira', name: 'Mira', rsvp: Rsvp.going, pending: false),
    PartyGuest(id: 'u3', handle: 'arjun', name: 'Arjun', rsvp: Rsvp.maybe, pending: false),
    PartyGuest(id: 'u4', handle: 'dev', name: 'Dev', rsvp: Rsvp.going, pending: true),
  ];
  final entries = [
    SharedEntry(id: 's1', userId: 'u2', authorName: 'Mira', date: todayKey(), createdAt: _iso(20), drink: 'Negroni', mood: 'bright'),
    SharedEntry(id: 's2', userId: 'local', authorName: 'Sekhi', date: todayKey(), createdAt: _iso(21), drink: 'Aperol Spritz', mood: 'bright'),
    SharedEntry(id: 's3', userId: 'u3', authorName: 'Arjun', date: todayKey(), createdAt: _iso(22), drink: 'Lime soda', mood: 'easy'),
  ];
  return Builder(
    builder: (context) => SubPage(
      title: party.name,
      subtitle: 'Tonight · ${party.venue}',
      child: PartyBody(detail: PartyDetail(party, guests, entries)),
    ),
  );
}

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  _tourTest('together tab (empty, no backend)', (t) async {
    await _boot(t);
    await _push(t, const Ambient(child: Scaffold(backgroundColor: Colors.transparent, body: TogetherScreen())));
    await _shot(t, 's1_together_empty');
    await t.tap(find.text('Plans'));
    await t.pumpAndSettle();
    await _shot(t, 's2_plans_empty');
    await t.tap(find.text('Circles'));
    await t.pumpAndSettle();
    await _shot(t, 's3_circles_empty');
    await t.tap(find.text('Parties'));
    await t.pumpAndSettle();
    await _shot(t, 's4_parties_empty');
    await t.tap(find.text('Host a night'));
    await t.pumpAndSettle();
    await _shot(t, 's5_host_sheet');
  });

  _tourTest('feed + plan cards (sample data)', (t) async {
    await _boot(t);
    await _push(
      t,
      _Preview(title: 'Feed', children: [
        for (final f in _feed()) ...[FeedCard(item: f), const SizedBox(height: S.m)],
        const SectionHeader('Plans'),
        PlanCard(
          plan: Plan(
            id: 'pl1',
            hostId: 'u2',
            hostName: 'Mira',
            hostHandle: 'mira',
            title: 'Mezcal night at mine',
            date: todayKey(),
            time: '20:30',
            city: 'Bandra',
            note: 'Bring one bottle you love. I have limes.',
            drinks: const ['Mezcal', 'Paloma'],
            vibeTags: const ['low-key'],
            joinPolicy: JoinPolicy.friends,
            capacity: 6,
            going: 3,
          ),
        ),
        const SizedBox(height: S.m),
        MyPlanCard(
          plan: MyPlan(id: 'pl2', title: 'Sunday coffee crawl', date: toKey(addDays(testNow, 3)), time: '10:00', drinks: const [], vibeTags: const [], joinPolicy: JoinPolicy.fof, status: PlanStatus.open, going: 2, pending: 1),
        ),
        const SectionHeader('Board'),
        const Group(children: [
          PointsRow(rank: 1, name: 'Mira', sparks: 12, vibe: 4, leads: true),
          PointsRow(rank: 2, name: 'You', sparks: 9, vibe: 2),
          PointsRow(rank: 3, name: 'Arjun', sparks: 4, vibe: 0),
        ]),
        const SizedBox(height: S.m),
        const InviteCodeCard(code: 'FRI-7KQ2', shareText: 'Join me'),
      ]),
    );
    await _shot(t, 's6_feed_cards');
    await t.tap(find.text('1').first, warnIfMissed: false);
    await _scroll(t, 640);
    await _shot(t, 's7_feed_cards_2');
    await _scroll(t, 640);
    await _shot(t, 's8_feed_cards_3');
  });

  _tourTest('party room (sample data)', (t) async {
    await _boot(t);
    await _push(t, _partyPreview());
    await _shot(t, 's9_party');
    await _scroll(t, 640);
    await _shot(t, 's10_party_2');
    await _scroll(t, 640);
    await _shot(t, 's11_party_3');
  });

  _tourTest('split + sheets', (t) async {
    await _boot(t);
    await _push(t, const SplitScreen());
    await _shot(t, 's12_split_empty');
    showReportSheet(navigatorKey.currentContext!, 'u2', 'Mira');
    await t.pumpAndSettle();
    await _shot(t, 's13_report_sheet');
    Navigator.of(navigatorKey.currentContext!).pop();
    await t.pumpAndSettle();
    showAddFriend(navigatorKey.currentContext!);
    await t.pumpAndSettle();
    await _shot(t, 's14_add_friend');
  });

  _tourTest('share cards', (t) async {
    await _boot(t);
    showShareCard(navigatorKey.currentContext!, entryStore.entries.last);
    await t.pumpAndSettle();
    await _shot(t, 's17_share_card');
    await t.tap(find.text('Poster'));
    await t.pumpAndSettle();
    await _shot(t, 's18_share_poster');
    Navigator.of(navigatorKey.currentContext!).pop();
    await t.pumpAndSettle();
    showScoreCard(navigatorKey.currentContext!, const Score(name: 'you', sparks: 9, vibe: 2, context: 'Friday tasting', rank: 2, of: 3));
    await t.pumpAndSettle();
    await _shot(t, 's19_score_card');
  });

  _tourTest('light theme social', (t) async {
    await _boot(t, dark: false);
    await _push(t, _Preview(title: 'Feed', children: [for (final f in _feed()) ...[FeedCard(item: f), const SizedBox(height: S.m)]]));
    await _shot(t, 's15_feed_light');
    await _push(t, _partyPreview());
    await _shot(t, 's16_party_light');
  });
}
