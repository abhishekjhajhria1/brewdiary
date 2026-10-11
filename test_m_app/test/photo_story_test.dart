// What a photo overlay says about a night: the day's lines grouped by drink, the
// place you were at most, everyone you were with, what was new to you, the bill.
import 'package:brewdiary/ui/screens/photo_studio.dart';
import 'package:brewdiary_core/types.dart';
import 'package:flutter_test/flutter_test.dart';

Entry _e(String id, String date, String drink, {DrinkType? type, String? venue, List<String>? who, String? mood, String? note, String at = '12:00:00'}) =>
    Entry(id: id, date: date, createdAt: DateTime.parse('${date}T$at').toUtc().toIso8601String(), drink: drink, type: type, venue: venue, whoWith: who, mood: mood, note: note);

void main() {
  final diary = [
    _e('a', '2026-09-20', 'Paloma'),
    _e('b', '2026-09-26', 'Mezcal Negroni', venue: 'Soka', who: ['Mira'], at: '21:40:00'),
    _e('c', '2026-09-26', 'mezcal negroni ', venue: 'Soka', who: ['Mira', 'Arjun'], mood: 'electric', at: '22:30:00'),
    _e('d', '2026-09-26', 'Paloma', venue: 'The Daily', note: 'Candles twice.', at: '23:10:00'),
    _e('e', '2026-09-27', 'Dry day', type: DrinkType.none),
  ];

  test('lines group the same drink, however it was typed', () {
    final s = NightStory.fromDay('2026-09-26', diary);
    expect(s.lines.map((l) => (l.name, l.qty)), [('Mezcal Negroni', 2), ('Paloma', 1)]);
  });

  test('the place you were at most, everyone you were with, the first time', () {
    final s = NightStory.fromDay('2026-09-26', diary);
    expect(s.venue, 'Soka');
    expect(s.who, ['Mira', 'Arjun']);
    expect(s.time, '21:40');
    expect(s.mood, 'electric');
    expect(s.note, 'Candles twice.');
  });

  test('new to you counts kinds first had tonight — variety, never volume', () {
    expect(NightStory.fromDay('2026-09-26', diary).newToYou, 1, reason: 'Paloma was had on the 20th');
  });

  test('a dry night has no lines and says so', () {
    final s = NightStory.fromDay('2026-09-27', diary);
    expect(s.dry, isTrue);
    expect(s.lines, isEmpty);
    expect(s.title, 'A dry night');
  });

  test('the bill: what was typed, else the priced lines, else nothing', () {
    const plain = NightStory(dateKey: '2026-09-26', lines: [StoryLine('Paloma')]);
    expect(plain.billTotal, isNull);
    const priced = NightStory(dateKey: '2026-09-26', lines: [StoryLine('Negroni', qty: 2, price: 650), StoryLine('Fries', price: 380), StoryLine('Water')]);
    expect(priced.billTotal, 1680);
    expect(priced.copyWith(total: () => 2000).billTotal, 2000);
  });
}
