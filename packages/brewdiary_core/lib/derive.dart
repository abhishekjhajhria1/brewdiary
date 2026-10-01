// Everything visual is DERIVED from entries here — a port of src/lib/derive.ts —
// so it can never drift from the truth. Nothing in this file is ever stored.
import 'date.dart';
import 'drinks.dart';
import 'types.dart';

// ── the balance side (gentle limits) ─────────────────────────────────────────
const _alcoholic = {DrinkType.beer, DrinkType.wine, DrinkType.cocktail, DrinkType.spirit};

/// Is this entry alcoholic? Trusts the tagged type; otherwise infers from the name.
/// An UNRECOGNISED drink is never assumed alcoholic.
bool isAlcoholic(String drink, DrinkType? type) {
  if (type != null) return _alcoholic.contains(type);
  final c = canonicalize(drink);
  return c.matched && c.type != null && _alcoholic.contains(c.type);
}

class WeekBalance {
  final int drinks;
  final int dryDays;
  final int windowDays;
  const WeekBalance(this.drinks, this.dryDays, this.windowDays);
}

/// The last 7 days (today included): how much alcohol, and how many dry days.
WeekBalance weekBalance(List<Entry> entries, [String? today]) {
  final end = parseKey(today ?? todayKey());
  final window = <String>{for (var i = 6; i >= 0; i--) toKey(addDays(end, -i))};
  final drinkingDays = <String>{};
  var drinks = 0;
  for (final e in entries) {
    if (!window.contains(e.date) || !isAlcoholic(e.drink, e.type)) continue;
    drinks++;
    drinkingDays.add(e.date);
  }
  return WeekBalance(drinks, window.length - drinkingDays.length, window.length);
}

// ── dry days ─────────────────────────────────────────────────────────────────
bool isDryDay(Entry e) => e.type == DrinkType.none;

List<Entry> drinkEntries(List<Entry> entries) => entries.where((e) => !isDryDay(e)).toList();

/// Count of DRINKS per day-key — what the mosaic shades.
Map<String, int> countsByDate(List<Entry> entries) {
  final m = <String, int>{};
  for (final e in entries) {
    if (isDryDay(e)) continue;
    m[e.date] = (m[e.date] ?? 0) + 1;
  }
  return m;
}

/// Every day you logged ANYTHING, dry days included — what the STREAK counts.
Map<String, int> loggedDates(List<Entry> entries) {
  final m = <String, int>{};
  for (final e in entries) {
    m[e.date] = (m[e.date] ?? 0) + 1;
  }
  return m;
}

Set<String> dryDates(List<Entry> entries) => entries.where(isDryDay).map((e) => e.date).toSet();

/// Intensity bucket 0–4 for the mosaic.
int intensityLevel(int count) {
  if (count <= 0) return 0;
  if (count >= 4) return 4;
  return count;
}

/// Current streak with GRACE: walking back from today. Today being empty doesn't
/// break it; grace replenishes on every logged day — only `grace + 1` misses in a
/// row end the streak.
int currentStreak(Map<String, int> counts, {int grace = 1}) {
  var cursor = parseKey(todayKey());
  if ((counts[toKey(cursor)] ?? 0) == 0) cursor = addDays(cursor, -1);
  var streak = 0;
  var graceLeft = grace;
  while (true) {
    final k = toKey(cursor);
    if ((counts[k] ?? 0) > 0) {
      streak++;
      graceLeft = grace;
      cursor = addDays(cursor, -1);
    } else if (graceLeft > 0) {
      graceLeft--;
      cursor = addDays(cursor, -1);
    } else {
      break;
    }
  }
  return streak;
}

/// Longest run of logged days anywhere in history, same replenishing grace.
int longestStreak(Map<String, int> counts, {int grace = 1}) {
  final keys = counts.keys.toList()..sort();
  if (keys.isEmpty) return 0;
  final end = parseKey(keys.last);
  var best = 0;
  var run = 0;
  var graceLeft = grace;
  for (var d = parseKey(keys.first); !d.isAfter(end); d = addDays(d, 1)) {
    if ((counts[toKey(d)] ?? 0) > 0) {
      run++;
      if (run > best) best = run;
      graceLeft = grace;
    } else if (graceLeft > 0) {
      graceLeft--;
    } else {
      run = 0;
      graceLeft = grace;
    }
  }
  return best;
}

class Stats {
  final int total;
  final int kinds;
  final int current;
  final int longest;
  final int dry;
  const Stats({required this.total, required this.kinds, required this.current, required this.longest, required this.dry});
}

Stats stats(List<Entry> entries) {
  final drinks = drinkEntries(entries);
  final logged = loggedDates(entries);
  final kinds = drinks.map((e) => e.drink.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
  return Stats(
    total: drinks.length,
    kinds: kinds.length,
    current: currentStreak(logged),
    longest: longestStreak(logged),
    dry: entries.length - drinks.length,
  );
}

const milestones = [10, 25, 50, 100, 250, 500];

({int? reached, int? next}) milestoneProgress(int total) {
  int? reached;
  int? next;
  for (final m in milestones) {
    if (total >= m) {
      reached = m;
    } else {
      next = m;
      break;
    }
  }
  return (reached: reached, next: next);
}

class MoodWord {
  final String word;
  final int count;
  const MoodWord(this.word, this.count);
  @override
  bool operator ==(Object other) => other is MoodWord && other.word == word && other.count == count;
  @override
  int get hashCode => Object.hash(word, count);
  @override
  String toString() => 'MoodWord($word, $count)';
}

/// The accumulating personal lexicon — distinct mood words by frequency.
List<MoodWord> lexicon(List<Entry> entries) {
  final m = <String, int>{};
  for (final e in entries) {
    final w = e.mood?.trim().toLowerCase();
    if (w != null && w.isNotEmpty) m[w] = (m[w] ?? 0) + 1;
  }
  final list = m.entries.map((e) => MoodWord(e.key, e.value)).toList()
    ..sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.word.compareTo(b.word);
    });
  return list;
}

/// Recent/common drinks for the log sheet quick-pick — frequency, then recency.
List<String> recentDrinks(List<Entry> allEntries, [int n = 5]) {
  final entries = drinkEntries(allEntries);
  final info = <String, ({int count, String last})>{};
  final casing = <String, String>{};
  for (final e in entries) {
    final name = e.drink.trim();
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    final prev = info[key];
    if (prev != null) {
      info[key] = (count: prev.count + 1, last: e.createdAt.compareTo(prev.last) > 0 ? e.createdAt : prev.last);
    } else {
      info[key] = (count: 1, last: e.createdAt);
    }
    casing[key] = name;
  }
  final sorted = info.entries.toList()
    ..sort((a, b) {
      final c = b.value.count.compareTo(a.value.count);
      return c != 0 ? c : b.value.last.compareTo(a.value.last);
    });
  return sorted.take(n).map((e) => casing[e.key] ?? e.key).toList();
}

List<String> recentMoods(List<Entry> entries, [int n = 6]) => lexicon(entries).take(n).map((m) => m.word).toList();

/// A gentle "looking back" memory — an older entry (≥14 days), preferring ones with
/// a note or photo. Deterministic by the current date so it's stable within a day.
Entry? memory(List<Entry> entries) {
  final today = parseKey(todayKey());
  final cutoff = addDays(today, -14);
  final old = drinkEntries(entries).where((e) => !parseKey(e.date).isAfter(cutoff)).toList();
  if (old.isEmpty) return null;
  final rich = old.where((e) => (e.note?.isNotEmpty ?? false) || (e.photos?.isNotEmpty ?? false)).toList();
  final pool = rich.isNotEmpty ? rich : old;
  return pool[today.day % pool.length];
}

/// Friend recommendations — drinks friends pour that you haven't logged yet, ranked
/// by how many DISTINCT friends pour them (then total frequency).
List<String> friendPicks(
  List<({String drink, String author})> friendDrinks,
  List<String> myDrinks, [
  List<String> excluded = const [],
  int n = 4,
]) {
  final skip = [...myDrinks, ...excluded].map((d) => d.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
  final info = <String, ({String display, Set<String> authors, int total})>{};
  for (final f in friendDrinks) {
    final name = f.drink.trim();
    if (name.isEmpty) continue;
    final key = name.toLowerCase();
    if (skip.contains(key)) continue;
    final cur = info[key];
    if (cur != null) {
      cur.authors.add(f.author);
      info[key] = (display: cur.display, authors: cur.authors, total: cur.total + 1);
    } else {
      info[key] = (display: name, authors: {f.author}, total: 1);
    }
  }
  final list = info.values.toList()
    ..sort((a, b) {
      var c = b.authors.length.compareTo(a.authors.length);
      if (c != 0) return c;
      c = b.total.compareTo(a.total);
      if (c != 0) return c;
      return a.display.compareTo(b.display);
    });
  return list.take(n).map((v) => v.display).toList();
}

class YearReview {
  final int total;
  final int kinds;
  final int days;
  final String? topDrink;
  final String? topMood;
  final String? busiestMonth;
  const YearReview({required this.total, required this.kinds, required this.days, this.topDrink, this.topMood, this.busiestMonth});
}

/// A calm look-back over everything logged — drinks only, no rating logic.
YearReview yearReview(List<Entry> allEntries) {
  final entries = drinkEntries(allEntries);
  final drinkCounts = <String, int>{};
  final casing = <String, String>{};
  final monthCounts = <int, int>{};
  final days = <String>{};
  for (final e in entries) {
    final name = e.drink.trim();
    if (name.isNotEmpty) {
      final key = name.toLowerCase();
      drinkCounts[key] = (drinkCounts[key] ?? 0) + 1;
      casing[key] = name;
    }
    final m = parseKey(e.date).month - 1;
    monthCounts[m] = (monthCounts[m] ?? 0) + 1;
    days.add(e.date);
  }
  String? topKey;
  var topN = 0;
  drinkCounts.forEach((k, v) {
    if (v > topN) {
      topN = v;
      topKey = k;
    }
  });
  int? topMonth;
  var topMonthN = 0;
  monthCounts.forEach((k, v) {
    if (v > topMonthN) {
      topMonthN = v;
      topMonth = k;
    }
  });
  final lex = lexicon(entries);
  return YearReview(
    total: entries.length,
    kinds: casing.length,
    days: days.length,
    topDrink: topKey != null ? casing[topKey] : null,
    topMood: lex.isNotEmpty ? lex.first.word : null,
    busiestMonth: topMonth != null ? monthNames[topMonth!] : null,
  );
}

// ── the taste card ───────────────────────────────────────────────────────────
// What you're into, in a few words — for showing a bartender ON YOUR SCREEN.
// Derived on the phone from the diary and never sent anywhere.
class TasteProfile {
  /// Drink families you come back to, most first (max 4).
  final List<String> favourites;

  /// The kinds you usually drink, most first (max 3).
  final List<DrinkType> kinds;

  /// Your most-used mood words (max 3).
  final List<String> moods;

  /// Share of your drinks with no alcohol, 0..1.
  final double noAlcoholShare;

  /// How many drinks the card is drawn from.
  final int basedOn;
  const TasteProfile({required this.favourites, required this.kinds, required this.moods, required this.noAlcoholShare, required this.basedOn});
}

/// The taste card from the last [days] of the diary (default ~6 months).
TasteProfile tasteProfile(List<Entry> allEntries, [int days = 180]) {
  final cutoff = toKey(addDays(parseKey(todayKey()), -days));
  final entries = drinkEntries(allEntries).where((e) => e.date.compareTo(cutoff) >= 0).toList();
  final fam = <String, int>{};
  final kind = <DrinkType, int>{};
  var soft = 0;
  for (final e in entries) {
    final c = canonicalize(e.drink);
    final f = c.matched ? c.family : e.drink.trim();
    if (f.isNotEmpty) fam[f] = (fam[f] ?? 0) + 1;
    final t = e.type ?? c.type;
    if (t != null && t != DrinkType.none) kind[t] = (kind[t] ?? 0) + 1;
    if (!isAlcoholic(e.drink, e.type)) soft++;
  }
  List<K> top<K>(Map<K, int> m, int n, String Function(K) label) {
    final l = m.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : label(a.key).compareTo(label(b.key)));
    return l.take(n).map((x) => x.key).toList();
  }

  return TasteProfile(
    // A favourite is something you've had at least twice — once is a visit, not a taste.
    favourites: top({for (final x in fam.entries) if (x.value >= 2) x.key: x.value}, 4, (k) => k),
    kinds: top(kind, 3, (k) => k.name),
    moods: lexicon(entries).take(3).map((m) => m.word).toList(),
    noAlcoholShare: entries.isEmpty ? 0 : soft / entries.length,
    basedOn: entries.length,
  );
}

// ── the taste passport ───────────────────────────────────────────────────────
// Stamps for VARIETY, never volume: places been, kinds tried, families met, dry
// nights kept. Ten nights at one bar is one stamp; a dry night is a stamp too.
class PassportStamp {
  final String place;
  final String date; // the first night you logged there
  const PassportStamp(this.place, this.date);
}

class Passport {
  final List<PassportStamp> stamps;
  final int places;
  final int kinds;
  final int families;
  final int dryNights;
  final String? since;
  const Passport({required this.stamps, required this.places, required this.kinds, required this.families, required this.dryNights, required this.since});
}

Passport passport(List<Entry> entries, [int n = 6]) {
  final first = <String, PassportStamp>{};
  final kinds = <DrinkType>{};
  final families = <String>{};
  String? since;
  for (final e in entries) {
    if (since == null || e.date.compareTo(since) < 0) since = e.date;
    final place = e.venue?.trim();
    if (place != null && place.isNotEmpty) {
      final k = place.toLowerCase();
      final prev = first[k];
      if (prev == null || e.date.compareTo(prev.date) < 0) first[k] = PassportStamp(prev?.place ?? place, e.date);
    }
    if (isDryDay(e)) continue;
    final c = canonicalize(e.drink);
    final t = e.type ?? c.type;
    if (t != null) kinds.add(t);
    families.add(c.matched ? c.family : e.drink.trim().toLowerCase());
  }
  final stamps = first.values.toList()..sort((a, b) => b.date != a.date ? b.date.compareTo(a.date) : a.place.compareTo(b.place));
  return Passport(stamps: stamps.take(n).toList(), places: stamps.length, kinds: kinds.length, families: families.length, dryNights: dryDates(entries).length, since: since);
}

// ── visa stamps for a stretch of the calendar ───────────────────────────────
// What a month (or a year) added to the passport: a place first visited, a drink
// first tasted, a kind first tried, and each dry night. Variety, never volume —
// the tenth Negroni earns nothing; the first Paloma does.
enum StampKind { place, firstTaste, newKind, dry }

class VisaStamp {
  final StampKind kind;
  final String label; // the place, the drink family, the kind's name, or 'Dry night'
  final String date;
  const VisaStamp(this.kind, this.label, this.date);
}

List<VisaStamp> stampsBetween(List<Entry> entries, String from, String to) {
  final sorted = [...entries]..sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.createdAt.compareTo(b.createdAt));
  final places = <String>{}, families = <String>{}, kinds = <DrinkType>{}, dry = <String>{};
  final out = <VisaStamp>[];
  for (final e in sorted) {
    if (e.date.compareTo(to) > 0) break;
    final inside = e.date.compareTo(from) >= 0;
    final place = e.venue?.trim();
    if (place != null && place.isNotEmpty && places.add(place.toLowerCase()) && inside) out.add(VisaStamp(StampKind.place, place, e.date));
    if (isDryDay(e)) {
      if (dry.add(e.date) && inside) out.add(VisaStamp(StampKind.dry, 'Dry night', e.date));
      continue;
    }
    final c = canonicalize(e.drink);
    final t = e.type ?? c.type;
    if (t != null && t != DrinkType.none && kinds.add(t) && inside) out.add(VisaStamp(StampKind.newKind, t.name, e.date));
    final fam = c.matched ? c.family : e.drink.trim();
    if (fam.isNotEmpty && families.add(fam.toLowerCase()) && inside) out.add(VisaStamp(StampKind.firstTaste, fam, e.date));
  }
  return out;
}

// ── the palate: what you lean towards, in flavour words ─────────────────────
// Each family you had counts once per night (a long night doesn't tilt it), and
// lends its notes (flavours). Top six, as a share of the strongest. Twin: derive.ts.
class PalateNote {
  final String note;
  final double share; // 0..1, relative to your strongest note
  const PalateNote(this.note, this.share);
}

List<PalateNote> palate(List<Entry> entries, [int days = 365]) {
  final cutoff = toKey(addDays(parseKey(todayKey()), -days));
  final seen = <String>{};
  final counts = <String, int>{};
  for (final e in entries) {
    if (isDryDay(e) || e.date.compareTo(cutoff) < 0) continue;
    final c = canonicalize(e.drink);
    if (!c.matched) continue;
    if (!seen.add('${e.date}|${c.family}')) continue;
    for (final n in flavours[c.family] ?? const <String>[]) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return const [];
  final top = counts.values.reduce((a, b) => a > b ? a : b);
  final list = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  return [for (final x in list.take(6)) PalateNote(x.key, (x.value / top * 100).round() / 100)];
}

// ── next stamps: something you haven't had that you might like ──────────────
// Families you've never logged, ranked by the flavour notes they share with your
// palate, with a nudge for a kind you've never tried. Always at least one
// alcohol-free pick. Variety, never volume. Twin: derive.ts.
class NextStamp {
  final String family;
  final DrinkType type;
  final String why;
  const NextStamp(this.family, this.type, this.why);
}

const _noAlcoholKinds = {DrinkType.coffee, DrinkType.tea, DrinkType.soft};

List<NextStamp> nextStamps(List<Entry> entries, [int n = 4]) {
  final triedFam = <String>{};
  final triedKind = <DrinkType>{};
  for (final e in entries) {
    if (isDryDay(e)) continue;
    final c = canonicalize(e.drink);
    if (c.matched) triedFam.add(c.family);
    final t = e.type ?? c.type;
    if (t != null) triedKind.add(t);
  }
  final notes = palate(entries).take(3).map((p) => p.note).toList();
  final families = <String, DrinkType>{};
  for (final d in drinks) {
    families.putIfAbsent(d.family, () => d.type);
  }
  final scored = <(NextStamp, int)>[];
  for (final f in families.entries) {
    if (triedFam.contains(f.key) || f.key == 'Water') continue;
    final shared = (flavours[f.key] ?? const <String>[]).where(notes.contains).toList();
    final newKind = !triedKind.contains(f.value);
    final score = shared.length * 2 + (newKind ? 1 : 0);
    final why = shared.isNotEmpty ? '${shared.join(' and ')}, like what you enjoy' : (newKind ? 'a new kind for your passport' : 'something new');
    scored.add((NextStamp(f.key, f.value, why), score));
  }
  scored.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.family.compareTo(b.$1.family));
  final out = scored.take(n).map((x) => x.$1).toList();
  if (out.isNotEmpty && !out.any((x) => _noAlcoholKinds.contains(x.type))) {
    final free = scored.where((x) => _noAlcoholKinds.contains(x.$1.type)).firstOrNull;
    if (free != null) out[out.length - 1] = free.$1;
  }
  return out;
}
