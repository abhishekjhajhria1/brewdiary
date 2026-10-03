// A diary is never deleted (055): clearing it keeps everything, removing an entry
// puts it away, and importing a file adds — it never replaces or overwrites.
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  testWidgets('signed out: a fresh diary keeps everything on the phone', (t) async {
    await bootApp(t, prefs: const {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'}, signedIn: true);
    final before = entryStore.entries.length;
    expect(before, greaterThan(0));
    final first = entryStore.entries.first.id;
    entryStore.deleteEntry(first);
    expect(entryStore.entries.any((e) => e.id == first), isFalse);
    expect(await entryStore.archivedCount(), 1, reason: 'removed is put away, not destroyed');
    expect(await entryStore.clearDiary(), isNull);
    expect(entryStore.entries, isEmpty);
    expect(await entryStore.archivedCount(), before);
  });

  testWidgets('import adds, skips what is already here, and never overwrites', (t) async {
    await bootApp(t, prefs: const {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'}, signedIn: true);
    final mine = entryStore.entries.first;
    final n = entryStore.entries.length;
    final added = await entryStore.importEntries([
      Entry(id: mine.id, date: mine.date, createdAt: mine.createdAt, drink: 'Something else entirely'),
      Entry(id: 'from-a-backup', date: todayKey(), createdAt: appNow().toUtc().toIso8601String(), drink: 'Paloma'),
    ]);
    expect(added, 1);
    expect(entryStore.entries.length, n + 1);
    expect(entryStore.entries.firstWhere((e) => e.id == mine.id).drink, mine.drink, reason: 'an entry already here is left alone');
    expect(entryStore.entries.where((e) => e.drink == 'Paloma').single.id, isNot('from-a-backup'), reason: 'imports get fresh ids');
  });
}
