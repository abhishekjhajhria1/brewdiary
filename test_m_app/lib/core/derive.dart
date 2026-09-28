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
