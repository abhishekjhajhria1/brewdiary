// First-run demo history — a port of src/lib/seed.ts. Realistic, contextual content
// so the mosaic has something to show before the person logs anything.
import 'date.dart';
import 'types.dart';

class _Seed {
  final int offset;
  final int hour;
  final String drink;
  final DrinkType type;
  final String mood;
  final String? note;
  final String? venue;
  const _Seed(this.offset, this.hour, this.drink, this.type, this.mood, {this.note, this.venue});
}

const _seed = [
  _Seed(0, 8, 'Flat white', DrinkType.coffee, 'steady'),
  _Seed(0, 21, 'Negroni', DrinkType.cocktail, 'celebratory', venue: 'Bar Termini', note: "Marco's leaving drinks."),
  _Seed(1, 20, 'Riesling', DrinkType.wine, 'easy'),
  _Seed(2, 9, 'Cold brew', DrinkType.coffee, 'focused'),
  _Seed(3, 19, 'Guinness', DrinkType.beer, 'cozy', venue: 'The Harp'),
  _Seed(4, 8, 'Espresso', DrinkType.coffee, 'quick'),
  _Seed(4, 21, 'Barolo', DrinkType.wine, 'special', note: 'With the short rib.'),
  _Seed(5, 16, 'Matcha', DrinkType.tea, 'calm'),
  _Seed(6, 22, 'Old Fashioned', DrinkType.cocktail, 'warm'),
  _Seed(8, 8, 'Cortado', DrinkType.coffee, 'ordinary'),
  _Seed(9, 19, 'Sancerre', DrinkType.wine, 'bright'),
  _Seed(9, 23, 'Negroni', DrinkType.cocktail, 'loose'),
  _Seed(10, 18, 'Hazy IPA', DrinkType.beer, 'loose'),
  _Seed(12, 9, 'Pour-over', DrinkType.coffee, 'slow'),
  _Seed(14, 20, 'Margarita', DrinkType.cocktail, 'fun'),
  _Seed(16, 22, 'Chamomile', DrinkType.tea, 'sleepy'),
  _Seed(18, 21, 'Cabernet', DrinkType.wine, 'rich'),
  _Seed(21, 8, 'Cappuccino', DrinkType.coffee, 'bright'),
  _Seed(25, 17, 'Aperol Spritz', DrinkType.cocktail, 'sunny'),
  _Seed(28, 19, 'Stout', DrinkType.beer, 'cozy'),
];

List<Entry> seedEntries() {
  final now = appNow();
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (var i = 0; i < _seed.length; i++)
      () {
        final s = _seed[i];
        final day = addDays(today, -s.offset);
        final created = DateTime(day.year, day.month, day.day, s.hour, (i * 7) % 60);
        return Entry(id: 'seed_$i', date: toKey(day), createdAt: created.toUtc().toIso8601String(), drink: s.drink, type: s.type, mood: s.mood, note: s.note, venue: s.venue);
      }(),
  ];
}
