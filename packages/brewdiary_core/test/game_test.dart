// The passport game. Twin: tests/passportGame.test.ts — the same cases, the same
// numbers, so the two copies can't drift.
import 'package:brewdiary_core/drinks.dart';
import 'package:brewdiary_core/game.dart';
import 'package:brewdiary_core/types.dart';
import 'package:test/test.dart';

var _seq = 0;
Entry e(String date, String drink, {DrinkType? type, String? venue, List<String>? who, String? note, int hour = 20}) {
  _seq++;
  return Entry(
    id: 'g$_seq',
    date: date,
    createdAt: '${date}T${hour.toString().padLeft(2, '0')}:${(_seq % 60).toString().padLeft(2, '0')}:00.000Z',
    drink: drink,
    type: type,
    venue: venue,
    whoWith: who,
    note: note,
  );
}

Entry dry(String date) => e(date, 'Dry day', type: DrinkType.none);

// A fortnight in September 2026 (Mon 14 → Sun 27).
final diary = [
  e('2026-09-14', 'Negroni', venue: 'Soka'),
  e('2026-09-14', 'Paloma', venue: 'Soka'),
  e('2026-09-14', 'Margarita', venue: 'Bar Termini'), // third first taste, second place: neither counts tonight
  dry('2026-09-15'),
  e('2026-09-16', 'Flat White', who: ['Mira']),
  dry('2026-09-17'),
  e('2026-09-19', 'Negroni', venue: 'Soka'), // the second Negroni earns nothing
  e('2026-09-21', 'Chai', note: 'Ginger, a lot of it'),
  e('2026-09-22', 'Kombucha', venue: 'Third Wave'),
  dry('2026-09-23'),
  e('2026-09-24', 'Stout', who: ['Arjun', 'Mira']),
];

void main() {
  test('every family but Water sits in exactly one collection', () {
    final all = {for (final d in drinks) d.family}..remove('Water');
    final placed = [for (final c in collections) ...c.families];
    expect(placed.toSet(), all);
    expect(placed.length, all.length);
  });

  test('ranks climb with miles', () {
    expect(rankFor(0).title, 'Newcomer');
    expect(rankFor(49).title, 'Newcomer');
    expect(rankFor(50).title, 'Taster');
    expect(rankFor(1700).title, 'Legend');
  });

  test('seasons: winter belongs to its December', () {
    expect(seasonWindow('2027-01-15').id, 'winter-2026');
    expect(seasonWindow('2026-12-01').end, '2027-02-28');
    expect(seasonWindow('2026-07-01').id, 'monsoon-2026');
    expect(seasonWindow('2026-10-31').def.id, 'harvest');
    expect(seasonWindow('2026-04-02').start, '2026-03-01');
  });

  test('quests: three a week, one always gentle, fixed by the week', () {
    expect(weekStart('2026-09-27'), '2026-09-21');
    expect(questsForWeek('2026-09-14').map((q) => q.id), ['dry_two', 'new_family', 'write_it']);
    expect(questsForWeek('2026-09-21').map((q) => q.id), ['free_new', 'new_place', 'new_family']);
    for (var i = 0; i < 40; i++) {
      final ids = questsForWeek('2026-${(1 + i ~/ 4).toString().padLeft(2, '0')}-0${1 + i % 4}').map((q) => q.id).toList();
      expect(ids.toSet().length, 3);
      expect(ids.first, anyOf('dry_two', 'free_new'));
    }
  });

  test('gilding is fixed by the drink and the day', () {
    expect(fnv1a(''), 0x811c9dc5);
    expect(fnv1a('Paloma|2026-09-14'), 1528518063);
    expect(isGilded('Kombucha', '2026-09-22'), true);
    expect(isGilded('Chai', '2026-09-21'), fnv1a('Chai|2026-09-21') % 6 == 0);
  });

  test('miles come from range, never volume', () {
    final g = passportGame(diary, '2026-09-27');
    final bySource = <MileSource, int>{};
    for (final x in g.ledger) {
      bySource[x.source] = (bySource[x.source] ?? 0) + x.miles;
    }
    // first tastes: Negroni, Paloma (Margarita capped), Flat White, Chai, Kombucha, Stout
    expect(bySource[MileSource.firstTaste], 60);
    // kinds: cocktail, coffee, tea, soft, beer
    expect(bySource[MileSource.newKind], 125);
    // places: Soka (Termini the same night doesn't count), Third Wave
    expect(bySource[MileSource.newPlace], 30);
    expect(bySource[MileSource.dryNight], 30);
    // Monsoon 2026: Chai (Flat White isn't a monsoon pick; Chai is)
    expect(bySource[MileSource.season], 30);
    expect(g.ledger.where((x) => x.source == MileSource.season).single.label, 'Monsoon 2026');
    // week 14: two quiet nights + something new (write it down: no line that week) → 40;
    // week 21: alcohol-free first (Chai), somewhere new, something new → 60
    expect(bySource[MileSource.quest], 100);
    expect(g.miles, 375);
    expect(g.rank.title, 'Voyager');
    expect(g.next!.title, 'Connoisseur');
    expect(g.toNext, 125);
    expect(g.families, 7); // Margarita still fills its slot
  });

  test('collections, feats and this week', () {
    final g = passportGame(diary, '2026-09-27');
    final classics = g.collections.firstWhere((c) => c.collection.id == 'classics');
    expect(classics.tried.keys, ['Negroni', 'Margarita']);
    expect(classics.have, 2);
    expect(classics.total, 8);
    final earned = [for (final f in g.feats) if (f.earned) f.def.id];
    expect(earned, ['first_page', 'kinds_5', 'zero_3', 'places_3', 'balanced_week', 'notes_8']);
    expect(g.feats.firstWhere((f) => f.def.id == 'company_3').progress, 2);
    expect(g.quests.map((q) => (q.def.id, q.progress, q.done)), [('free_new', 1, true), ('new_place', 1, true), ('new_family', 1, true)]);
    expect(g.gilded, {'Kombucha'});
    expect(g.questDaysLeft, 0);
    expect(g.season.window.id, 'monsoon-2026');
    expect(g.season.daysLeft, 3);
    expect(g.season.earnedWith, 'Chai');
    expect(g.season.picks.first, 'Filter Coffee');
    expect(g.season.picks.skip(6), ['Chai', 'Stout']); // what you've had goes last
  });

  test('an empty diary is a Newcomer with everything ahead', () {
    final g = passportGame(const [], '2026-09-27');
    expect(g.miles, 0);
    expect(g.rank.title, 'Newcomer');
    expect(g.ledger, isEmpty);
    expect(g.feats.where((f) => f.earned), isEmpty);
    expect(g.season.earnedOn, isNull);
    expect(g.quests.length, 3);
  });

  test('unlocks: what a save added', () {
    final before = passportGame(diary.take(3).toList(), '2026-09-14');
    final after = passportGame(diary.take(3).toList()..add(e('2026-09-14', 'Espresso')), '2026-09-14');
    final u = unlocksBetween(before, after);
    // a third first taste tonight: the slot fills, no miles; but coffee is a new kind
    expect(u.events.map((x) => (x.source, x.label, x.miles)), [(MileSource.newKind, 'coffee', 25)]);
    expect(after.collections.firstWhere((c) => c.collection.id == 'coffee').tried.keys, ['Espresso']);
    expect(u.isEmpty, false);
  });
}
