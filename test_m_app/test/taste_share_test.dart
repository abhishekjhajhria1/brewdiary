// What a bar is sent (056): the taste card, the palate's notes and what the person
// told us — loves lead, hidden lines stay hidden, and never an entry or a date.
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/taste_share.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    configureForTests();
    await loadFonts();
  });

  testWidgets('loves lead, preferences ride along, hidden lines stay out', (t) async {
    await bootApp(t, prefs: const {'brewdiary.age.v2': 'ok', 'brewdiary.country.v1': 'IN'}, signedIn: true);
    final s = TasteShareStore.instance;
    await s.setLoves(['Mezcal']);
    await s.setAvoid(['gin']);
    await s.setSweetness('dry');
    await s.setDiet(['Jain']);
    await s.setAllergies(['peanuts']);
    var p = s.payload();
    expect((p['into'] as List).first, 'Mezcal');
    expect(p['avoid'], ['gin']);
    expect(p['sweetness'], 'dry');
    expect(p['diet'], ['Jain']);
    expect(p['allergies'], ['peanuts']);
    expect(p['flavours'], isNotEmpty, reason: 'the palate goes too');
    expect(p.keys.any((k) => k.contains('date') || k.contains('entr') || k.contains('venue')), isFalse);

    await Prefs.setJson(TasteShareStore.hiddenKey, ['palate', 'usually']);
    p = s.payload();
    expect(p.containsKey('flavours'), isFalse);
    expect(p.containsKey('usually'), isFalse);
    await s.setSweetness(null);
    expect(s.payload().containsKey('sweetness'), isFalse);
  });
}
