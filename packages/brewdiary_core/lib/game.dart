// The passport game — everything here is DERIVED from entries, never stored.
// Twin: src/lib/passportGame.ts (same rules, same test cases).
//
// Built on the Octalysis drives, white-hat first:
//   • Meaning        — a rank you grow into: Newcomer → Legend.
//   • Accomplishment — miles, feats with progress, a rank bar.
//   • Ownership      — eight collections to fill, one slot per drink family.
//   • Creativity     — pick your quests' order, your cover (in the app).
//   • Scarcity       — a stamp each season that only that season gives.
//   • Curiosity      — a few first tastes come out gilded; you can't predict which.
//   • Loss, gently   — "the monsoon stamp closes in 12 days". Never a streak to lose.
//
// THE RULE: nothing rewards drinking more. Miles come from range — a first taste,
// a new kind, a new place, a dry night — never from a count. The tenth Negroni
// earns nothing; two first tastes a night is the most that counts; one new place
// a night; every dry night earns, and every season and every week has an
// alcohol-free way through.
import 'date.dart';
import 'derive.dart';
import 'drinks.dart';
import 'types.dart';

// ── miles ────────────────────────────────────────────────────────────────────
const milesFirstTaste = 10;
const milesNewKind = 25;
const milesNewPlace = 15;
const milesDryNight = 10;
const milesCollection = 50;
const milesQuest = 20;
const milesSeason = 30;

/// At most this many first tastes count toward miles on one night — range, not rounds.
const firstTastesPerNight = 2;

enum MileSource { firstTaste, newKind, newPlace, dryNight, collection, quest, season }

class MileEvent {
  final MileSource source;
  final String label;
  final String date;
  final int miles;
  final bool gilded;
  const MileEvent(this.source, this.label, this.date, this.miles, {this.gilded = false});
  String get key => '${source.name}|$label|$date';
}

// ── ranks ────────────────────────────────────────────────────────────────────
class Rank {
  final int index;
  final String title;
  final int from;
  final String line;
  const Rank(this.index, this.title, this.from, this.line);
}

const ranks = <Rank>[
  Rank(0, 'Newcomer', 0, 'The first pages are blank on purpose.'),
  Rank(1, 'Taster', 50, 'You notice what is in the glass.'),
  Rank(2, 'Explorer', 150, 'The menu reads like a map now.'),
  Rank(3, 'Voyager', 300, 'Places and pours you can name.'),
  Rank(4, 'Connoisseur', 500, 'You know what you like, and why.'),
  Rank(5, 'Cartographer', 800, 'You have drawn most of the map.'),
  Rank(6, 'Polymath', 1200, 'Coffee to cognac, all of it yours.'),
  Rank(7, 'Legend', 1700, 'A passport other people ask about.'),
];

Rank rankFor(int miles) => ranks.lastWhere((r) => miles >= r.from);

// ── collections ──────────────────────────────────────────────────────────────
class Collection {
  final String id;
  final String title;
  final List<String> families;
  const Collection(this.id, this.title, this.families);
}

/// Every drink family (but Water) sits in exactly one collection.
const collections = <Collection>[
  Collection('coffee', 'Coffee bar', ['Espresso', 'Americano', 'Macchiato', 'Cortado', 'Flat White', 'Cappuccino', 'Latte', 'Mocha', 'Cold Brew', 'Filter Coffee']),
  Collection('tea', 'Tea house', ['Chai', 'Black Tea', 'Green Tea', 'Matcha', 'Chamomile']),
  Collection('zero', 'Zero proof', ['Kombucha', 'Juice', 'Soft Drink']),
  Collection('brewery', 'The brewery', ['Lager', 'Pale Ale', 'IPA', 'Wheat Beer', 'Sour', 'Stout']),
  Collection('cellar', 'The cellar', ['White Wine', 'Rosé', 'Red Wine', 'Sparkling']),
  Collection('classics', 'Classic cocktails', ['Negroni', 'Old Fashioned', 'Martini', 'Manhattan', 'Margarita', 'Daiquiri', 'Sour Cocktail', 'Mojito']),
  Collection('long', 'Long & bright', ['Spritz', 'Gin & Tonic', 'Paloma', 'Mule', 'Cosmopolitan', 'Piña Colada', 'Espresso Martini']),
  Collection('backbar', 'The back bar', ['Whiskey', 'Tequila', 'Gin', 'Vodka', 'Rum', 'Brandy']),
];

class CollectionState {
  final Collection collection;
  final Map<String, String> tried; // family → first date
  final String? completedOn;
  const CollectionState(this.collection, this.tried, this.completedOn);
  int get have => tried.length;
  int get total => collection.families.length;
  bool get complete => completedOn != null;
}

// ── seasons ──────────────────────────────────────────────────────────────────
class SeasonDef {
  final String id;
  final String title;
  final String line;
  final List<String> families;
  const SeasonDef(this.id, this.title, this.line, this.families);
}

const seasons = <SeasonDef>[
  SeasonDef('winter', 'Winter warmer', 'Something warm and deep.', ['Chai', 'Mocha', 'Latte', 'Black Tea', 'Stout', 'Red Wine', 'Brandy', 'Whiskey', 'Old Fashioned']),
  SeasonDef('spring', 'Spring bloom', 'Something green and floral.', ['Chamomile', 'Green Tea', 'Matcha', 'Kombucha', 'Gin & Tonic', 'Spritz', 'Rosé', 'Mojito', 'Gin']),
  SeasonDef('monsoon', 'Monsoon', 'Something for the rain.', ['Chai', 'Filter Coffee', 'Black Tea', 'Cappuccino', 'Mocha', 'Stout', 'Whiskey', 'Rum']),
  SeasonDef('harvest', 'Harvest', 'Something from the vine and the field.', ['Cold Brew', 'Americano', 'Juice', 'Red Wine', 'White Wine', 'Sparkling', 'Wheat Beer', 'Brandy', 'Manhattan']),
];

/// Dec–Feb winter, Mar–May spring, Jun–Sep monsoon, Oct–Nov harvest.
SeasonDef _seasonOfMonth(int m) => m == 12 || m <= 2
    ? seasons[0]
    : m <= 5
        ? seasons[1]
        : m <= 9
            ? seasons[2]
            : seasons[3];

class SeasonWindow {
  final SeasonDef def;
  final int year; // a winter belongs to the year of its December
  final String start;
  final String end;
  const SeasonWindow(this.def, this.year, this.start, this.end);
  String get id => '${def.id}-$year';
  String get label => '${def.title} $year';
}

SeasonWindow seasonWindow(String dayKey) {
  final d = parseKey(dayKey);
  final def = _seasonOfMonth(d.month);
  switch (def.id) {
    case 'winter':
      final y = d.month == 12 ? d.year : d.year - 1;
      return SeasonWindow(def, y, toKey(DateTime(y, 12, 1)), toKey(DateTime(y + 1, 3, 0)));
    case 'spring':
      return SeasonWindow(def, d.year, toKey(DateTime(d.year, 3, 1)), toKey(DateTime(d.year, 5, 31)));
    case 'monsoon':
      return SeasonWindow(def, d.year, toKey(DateTime(d.year, 6, 1)), toKey(DateTime(d.year, 9, 30)));
    default:
      return SeasonWindow(def, d.year, toKey(DateTime(d.year, 10, 1)), toKey(DateTime(d.year, 11, 30)));
  }
}

class SeasonNow {
  final SeasonWindow window;
  final int daysLeft;
  final String? earnedOn;
  final String? earnedWith;
  final List<String> picks; // what would earn it, untried first
  const SeasonNow(this.window, this.daysLeft, this.earnedOn, this.earnedWith, this.picks);
}

// ── weekly quests ────────────────────────────────────────────────────────────
class QuestDef {
  final String id;
  final String title;
  final String line;
  final int target;
  const QuestDef(this.id, this.title, this.line, [this.target = 1]);
}

const _gentleQuests = <QuestDef>[
  QuestDef('dry_two', 'Two quiet nights', 'Keep two dry nights this week.', 2),
  QuestDef('free_new', 'Alcohol-free first', 'A coffee, tea or soft drink you never have had.'),
];
const _otherQuests = <QuestDef>[
  QuestDef('new_family', 'Something new', 'A first taste — any drink you have never logged.'),
  QuestDef('new_place', 'Somewhere new', 'Log from a place you have never been.'),
  QuestDef('new_note', 'A new note', 'A drink with a flavour you have not met yet.'),
  QuestDef('with_friend', 'Good company', 'Log a moment with someone — coffee counts.'),
  QuestDef('write_it', 'Write it down', 'Add a line to an entry: what made it.'),
  QuestDef('new_kind', 'A new kind', 'A kind you have never had — tea, beer, wine…'),
];

/// The Monday a day's week starts on.
String weekStart(String dayKey) {
  final d = parseKey(dayKey);
  return toKey(addDays(d, -mondayIndex(d)));
}

int _weekIndex(String monday) {
  final d = parseKey(monday);
  return DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1970, 1, 5)).inDays ~/ 7;
}

/// Three quests a week — always one with a gentle, alcohol-free way through.
List<QuestDef> questsForWeek(String monday) {
  final w = _weekIndex(monday);
  final i1 = w % _otherQuests.length;
  final i2 = (i1 + 1 + w % (_otherQuests.length - 1)) % _otherQuests.length;
  return [_gentleQuests[w % _gentleQuests.length], _otherQuests[i1], _otherQuests[i2]];
}

class QuestState {
  final QuestDef def;
  final int progress;
  final String? doneOn;
  const QuestState(this.def, this.progress, this.doneOn);
  bool get done => doneOn != null;
}

// ── feats ────────────────────────────────────────────────────────────────────
class FeatDef {
  final String id;
  final String title;
  final String line;
  final int target;
  const FeatDef(this.id, this.title, this.line, this.target);
}

const feats = <FeatDef>[
  FeatDef('first_page', 'First page', 'Log your first moment — a drink or a dry night.', 1),
  FeatDef('kinds_5', 'Five kinds', 'Five kinds of drink, from coffee to cocktails.', 5),
  FeatDef('zero_3', 'Zero-proof palate', 'Three alcohol-free families.', 3),
  FeatDef('places_3', 'Local map', 'Three places in your passport.', 3),
  FeatDef('quiet_month', 'Quiet month', 'Four dry nights in one month.', 4),
  FeatDef('balanced_week', 'Balanced week', 'Two dry nights and a first taste in one week.', 1),
  FeatDef('notes_8', 'Wide palate', 'Eight different flavour notes.', 8),
  FeatDef('company_3', 'Good company', 'Moments with three different people.', 3),
  FeatDef('full_set', 'Full set', 'Complete any collection.', 1),
  FeatDef('places_10', 'Wanderer', 'Ten places in your passport.', 10),
  FeatDef('kinds_7', 'Every kind', 'Coffee, tea, soft, beer, wine, cocktail and spirit.', 7),
  FeatDef('families_25', 'Half the map', 'Twenty-five drink families.', 25),
  FeatDef('seasons_4', 'Four seasons', 'A stamp from every season.', 4),
];

class FeatState {
  final FeatDef def;
  final int progress;
  final String? earnedOn;
  const FeatState(this.def, this.progress, this.earnedOn);
  bool get earned => earnedOn != null;
}

// ── a little luck ───────────────────────────────────────────────────────────
/// FNV-1a over UTF-16 code units — the same number in Dart and TypeScript.
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// About one first taste in six comes out gilded. Fixed by the drink and the day,
/// so it never changes once earned — and you can't know which until it happens.
bool isGilded(String family, String date) => fnv1a('$family|$date') % 6 == 0;

// ── the whole game ──────────────────────────────────────────────────────────
class PassportGame {
  final int miles;
  final Rank rank;
  final Rank? next;
  final List<MileEvent> ledger; // newest first
  final List<CollectionState> collections;
  final List<FeatState> feats;
  final List<SeasonWindow> seasonsEarned;
  final SeasonNow season;
  final List<QuestState> quests; // this week's
  final int questDaysLeft;
  final Set<String> gilded; // families whose first taste was gilded
  final int families;
  const PassportGame({
    required this.miles,
    required this.rank,
    required this.next,
    required this.ledger,
    required this.collections,
    required this.feats,
    required this.seasonsEarned,
    required this.season,
    required this.quests,
    required this.questDaysLeft,
    required this.gilded,
    required this.families,
  });

  /// 0..1 through the current rank.
  double get progress => next == null ? 1 : (miles - rank.from) / (next!.from - rank.from);
  int get toNext => next == null ? 0 : next!.from - miles;
}

class _Week {
  int dry = 0;
  bool firstTaste = false, freeNew = false, newPlace = false, newNote = false, withFriend = false, wrote = false, newKind = false;
}

const _freeKinds = {DrinkType.coffee, DrinkType.tea, DrinkType.soft};

PassportGame passportGame(List<Entry> entries, [String? today]) {
  final now = today ?? todayKey();
  final sorted = [...entries.where((e) => e.date.compareTo(now) <= 0)]
    ..sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.createdAt.compareTo(b.createdAt));

  final ledger = <MileEvent>[];
  final families = <String, String>{}; // matched family → first date
  final kinds = <DrinkType>{};
  final places = <String>{};
  final dry = <String>{};
  final notes = <String>{};
  final people = <String>{};
  final freeFamilies = <String>{};
  final gilded = <String>{};
  final tastesOn = <String, int>{};
  final placeOn = <String>{};
  final dryByMonth = <String, int>{};
  final weeks = <String, _Week>{};
  final questDone = <String, String>{}; // "monday|quest" → date
  final seasonEarned = <String, (SeasonWindow, String, String)>{}; // id → window, date, family
  final collectionDone = <String, String>{};
  final featOn = <String, String>{};

  void feat(String id, int value, String date) {
    final d = feats.firstWhere((f) => f.id == id);
    if (value >= d.target) featOn.putIfAbsent(id, () => date);
  }

  for (final e in sorted) {
    final monday = weekStart(e.date);
    final w = weeks.putIfAbsent(monday, _Week.new);
    feat('first_page', 1, e.date);

    final who = e.whoWith ?? const <String>[];
    if (who.isNotEmpty) w.withFriend = true;
    for (final p in who) {
      final k = p.trim().toLowerCase();
      if (k.isNotEmpty) people.add(k);
    }
    feat('company_3', people.length, e.date);
    if ((e.note ?? '').trim().isNotEmpty) w.wrote = true;

    final place = e.venue?.trim();
    if (place != null && place.isNotEmpty && places.add(place.toLowerCase())) {
      w.newPlace = true;
      if (placeOn.add(e.date)) ledger.add(MileEvent(MileSource.newPlace, place, e.date, milesNewPlace));
      feat('places_3', places.length, e.date);
      feat('places_10', places.length, e.date);
    }

    if (isDryDay(e)) {
      if (dry.add(e.date)) {
        w.dry++;
        ledger.add(MileEvent(MileSource.dryNight, 'Dry night', e.date, milesDryNight));
        final m = e.date.substring(0, 7);
        dryByMonth[m] = (dryByMonth[m] ?? 0) + 1;
        feat('quiet_month', dryByMonth[m]!, e.date);
      }
    } else {
      final c = canonicalize(e.drink);
      final t = e.type ?? c.type;
      if (t != null && t != DrinkType.none && t != DrinkType.other && kinds.add(t)) {
        w.newKind = true;
        ledger.add(MileEvent(MileSource.newKind, t.name, e.date, milesNewKind));
        feat('kinds_5', kinds.length, e.date);
        feat('kinds_7', kinds.length, e.date);
      }
      if (c.matched && c.family != 'Water' && !families.containsKey(c.family)) {
        families[c.family] = e.date;
        w.firstTaste = true;
        final g = isGilded(c.family, e.date);
        if (g) gilded.add(c.family);
        final n = tastesOn[e.date] ?? 0;
        if (n < firstTastesPerNight) {
          tastesOn[e.date] = n + 1;
          ledger.add(MileEvent(MileSource.firstTaste, c.family, e.date, milesFirstTaste, gilded: g));
        }
        feat('families_25', families.length, e.date);
        if (t != null && _freeKinds.contains(t)) {
          freeFamilies.add(c.family);
          w.freeNew = true;
          feat('zero_3', freeFamilies.length, e.date);
        }
        for (final n in flavours[c.family] ?? const <String>[]) {
          if (notes.add(n)) w.newNote = true;
        }
        feat('notes_8', notes.length, e.date);
        for (final col in collections) {
          if (!col.families.contains(c.family) || collectionDone.containsKey(col.id)) continue;
          if (col.families.every(families.containsKey)) {
            collectionDone[col.id] = e.date;
            ledger.add(MileEvent(MileSource.collection, col.title, e.date, milesCollection));
            feat('full_set', 1, e.date);
          }
        }
      }
      if (c.matched) {
        final sw = seasonWindow(e.date);
        if (sw.def.families.contains(c.family) && !seasonEarned.containsKey(sw.id)) {
          seasonEarned[sw.id] = (sw, e.date, c.family);
          ledger.add(MileEvent(MileSource.season, sw.label, e.date, milesSeason));
          feat('seasons_4', seasonEarned.values.map((s) => s.$1.def.id).toSet().length, e.date);
        }
      }
    }

    if (w.dry >= 2 && w.firstTaste) feat('balanced_week', 1, e.date);
    for (final q in questsForWeek(monday)) {
      final k = '$monday|${q.id}';
      if (questDone.containsKey(k)) continue;
      if (_questProgress(q, w) >= q.target) {
        questDone[k] = e.date;
        ledger.add(MileEvent(MileSource.quest, q.title, e.date, milesQuest));
      }
    }
  }

  final miles = ledger.fold<int>(0, (s, x) => s + x.miles);
  final rank = rankFor(miles);
  final next = rank.index + 1 < ranks.length ? ranks[rank.index + 1] : null;

  final thisMonday = weekStart(now);
  final w = weeks[thisMonday] ?? _Week();
  final quests = [for (final q in questsForWeek(thisMonday)) QuestState(q, _questProgress(q, w).clamp(0, q.target), questDone['$thisMonday|${q.id}'])];

  final sw = seasonWindow(now);
  final earned = seasonEarned[sw.id];
  final picks = [...sw.def.families.where((f) => !families.containsKey(f)), ...sw.def.families.where(families.containsKey)];
  final season = SeasonNow(sw, parseKey(sw.end).difference(parseKey(now)).inDays, earned?.$2, earned?.$3, picks);

  final featStates = [
    for (final f in feats) FeatState(f, _featProgress(f.id, families: families.length, kinds: kinds.length, places: places.length, people: people.length, notes: notes.length, free: freeFamilies.length, dryBest: dryByMonth.values.fold(0, (a, b) => a > b ? a : b), sets: collectionDone.length, seasons: seasonEarned.values.map((s) => s.$1.def.id).toSet().length, any: sorted.isEmpty ? 0 : 1, balanced: featOn.containsKey('balanced_week') ? 1 : 0).clamp(0, f.target), featOn[f.id]),
  ];

  return PassportGame(
    miles: miles,
    rank: rank,
    next: next,
    ledger: ledger.reversed.toList(),
    collections: [
      for (final col in collections)
        CollectionState(col, {for (final f in col.families) if (families.containsKey(f)) f: families[f]!}, collectionDone[col.id]),
    ],
    feats: featStates,
    seasonsEarned: [for (final s in seasonEarned.values) s.$1],
    season: season,
    quests: quests,
    questDaysLeft: 6 - mondayIndex(parseKey(now)),
    gilded: gilded,
    families: families.length,
  );
}

int _questProgress(QuestDef q, _Week w) => switch (q.id) {
      'dry_two' => w.dry,
      'free_new' => w.freeNew ? 1 : 0,
      'new_family' => w.firstTaste ? 1 : 0,
      'new_place' => w.newPlace ? 1 : 0,
      'new_note' => w.newNote ? 1 : 0,
      'with_friend' => w.withFriend ? 1 : 0,
      'write_it' => w.wrote ? 1 : 0,
      'new_kind' => w.newKind ? 1 : 0,
      _ => 0,
    };

int _featProgress(String id, {required int families, required int kinds, required int places, required int people, required int notes, required int free, required int dryBest, required int sets, required int seasons, required int any, required int balanced}) =>
    switch (id) {
      'first_page' => any,
      'kinds_5' || 'kinds_7' => kinds,
      'zero_3' => free,
      'places_3' || 'places_10' => places,
      'quiet_month' => dryBest,
      'balanced_week' => balanced,
      'notes_8' => notes,
      'company_3' => people,
      'full_set' => sets,
      'families_25' => families,
      'seasons_4' => seasons,
      _ => 0,
    };

// ── what just happened ──────────────────────────────────────────────────────
class Unlocks {
  final List<MileEvent> events;
  final List<FeatDef> feats;
  final Rank? rankUp;
  const Unlocks(this.events, this.feats, this.rankUp);
  bool get isEmpty => events.isEmpty && feats.isEmpty && rankUp == null;
  int get miles => events.fold(0, (s, e) => s + e.miles);
}

/// What a save added — for the little moment after you log.
Unlocks unlocksBetween(PassportGame before, PassportGame after) {
  final had = {for (final e in before.ledger) e.key};
  final hadFeats = {for (final f in before.feats) if (f.earned) f.def.id};
  return Unlocks(
    [for (final e in after.ledger.reversed) if (!had.contains(e.key)) e],
    [for (final f in after.feats) if (f.earned && !hadFeats.contains(f.def.id)) f.def],
    after.rank.index > before.rank.index ? after.rank : null,
  );
}
