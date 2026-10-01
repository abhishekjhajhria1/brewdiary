// "Your diary, as a book": the PDF builds from a full bundle and from an empty one.
// With TOUR defined the sample book is also written to test/tour/diary_book.pdf
// for a look.
import 'dart:io';

import 'package:brewdiary/data/export.dart';
import 'package:brewdiary/ui/export/diary_book.dart';
import 'package:brewdiary_core/seed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'helpers.dart';

Future<BookFonts> _fonts() async {
  Future<pw.Font> f(String n) async => pw.Font.ttf((await File('assets/fonts/$n').readAsBytes()).buffer.asByteData());
  return BookFonts(serif: await f('Newsreader.ttf'), serifItalic: await f('Newsreader-Italic.ttf'), sans: await f('HankenGrotesk.ttf'));
}

void main() {
  setUpAll(configureForTests);

  test('a full diary becomes a PDF book', () async {
    final bundle = ExportBundle(
      name: 'Asha Rao',
      handle: 'asha',
      memberSince: '2026-03-02T10:00:00Z',
      generated: DateTime(2026, 9, 28, 21),
      entries: seedEntries(),
      friends: ['Mira Kapoor @mira', 'Arjun Mehta @arjun', 'Kabir Singh @kabir'],
      circles: [(name: 'Friday people', members: 5)],
      parties: [(name: "Mira's birthday", date: '2026-09-26', venue: 'Soka, Bandra')],
      plans: [(title: 'Sunday coffee crawl', date: '2026-10-04', city: 'Mumbai')],
      comments: [(body: 'That smoky one was unreal — next time I am trying it.', at: '2026-09-27T09:12:00Z')],
      expenses: [(what: 'Round at Soka', amount: 2500, at: '2026-09-26T22:10:00Z', paidByMe: true), (what: 'Cab home', amount: 420, at: '2026-09-27T01:05:00Z', paidByMe: false)],
      wishlist: [(drink: 'Mezcal Paloma', done: false), (drink: 'Yuzu sour', done: true)],
      venueNotes: [(venue: 'Soka', body: 'Likes the corner table; celebrating a birthday.', tags: ['regular', 'birthday'])],
      visits: 4,
      perks: [(reward: 'A dessert on the house', at: '2026-09-12T20:00:00Z')],
      chats: [
        (at: DateTime(2026, 9, 20, 20), user: 'Something smoky but not too strong?', assistant: 'A mezcal highball, love — smoke on the nose, mostly soda, and a long squeeze of lime. Or a smoked lapsang iced tea if tonight is a quiet one.'),
        (at: DateTime(2026, 9, 26, 19), user: 'What goes with truffle fries?', assistant: 'Something with bubbles to cut the richness — a dry cider, a crisp lager, or a lime soda with a pinch of salt.'),
      ],
    );
    final bytes = await buildDiaryBook(bundle, await _fonts());
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(20000));
    if (const bool.hasEnvironment('TOUR')) {
      Directory('test/tour').createSync(recursive: true);
      File('test/tour/diary_book.pdf').writeAsBytesSync(bytes);
    }
  });

  test('an empty diary still makes a kind little book', () async {
    final bytes = await buildDiaryBook(ExportBundle(name: 'You', generated: DateTime(2026, 9, 28), entries: const []), await _fonts());
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
