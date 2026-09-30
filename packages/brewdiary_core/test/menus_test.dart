// Parity with tests/menus.test.ts — the menu logic must behave exactly like src/lib/menus.ts.
import 'package:brewdiary_core/menus.dart';
import 'package:brewdiary_core/types.dart';
import 'package:test/test.dart';

Map<String, dynamic> row([Map<String, dynamic> over = const {}]) => {
      'venue_name': 'Soka',
      'venue_city': 'Bengaluru',
      'venue_kind': 'bar',
      'currency': 'INR',
      'item_id': 'i1',
      'section': 'Cocktails',
      'name': 'Negroni',
      'description': null,
      'price': '450.00',
      'kind': 'cocktail',
      'no_alcohol': false,
      ...over,
    };

var _n = 0;
Entry entry(String drink, [DrinkType? type]) => Entry(id: 'e${_n++}', date: '2026-09-01', createdAt: '2026-09-01T20:00:00Z', drink: drink, type: type);

void main() {
  test('menuUrl is the plain link a tag holds', () {
    expect(menuUrl('soka'), 'https://bwdy.site/m/soka');
    expect(menuUrl('soka', 'http://localhost:3000/'), 'http://localhost:3000/m/soka');
  });

  test('menuSlugFrom reads /m/<slug> and nothing else', () {
    expect(menuSlugFrom(Uri.parse('https://bwdy.site/m/soka')), 'soka');
    expect(menuSlugFrom(Uri.parse('https://bwdy.site/m/Soka/')), 'soka');
    expect(menuSlugFrom(Uri.parse('https://bwdy.site/p/ABC123')), isNull);
    expect(menuSlugFrom(Uri.parse('https://bwdy.site/m/')), isNull);
    expect(menuSlugFrom(Uri.parse('https://bwdy.site/m/-bad-')), isNull);
  });

  group('groupMenu', () {
    test('groups items into sections in the order the rpc returns them', () {
      final m = groupMenu([
        row({'item_id': 'a', 'section': 'Cocktails', 'name': 'Negroni'}),
        row({'item_id': 'b', 'section': 'Beer', 'name': 'Hazy IPA', 'kind': 'beer', 'price': null}),
        row({'item_id': 'c', 'section': 'Cocktails', 'name': 'Virgin Mojito', 'no_alcohol': true, 'kind': 'soft'}),
      ])!;
      expect(m.venueName, 'Soka');
      expect(m.sections.map((s) => s.name), ['Cocktails', 'Beer']);
      expect(m.sections[0].items.map((i) => i.name), ['Negroni', 'Virgin Mojito']);
      expect(m.sections[0].items[0].price, 450);
      expect(m.sections[1].items[0].price, isNull);
      expect(m.sections[0].items[1].noAlcohol, isTrue);
    });

    test('a verified venue with no items yet has no sections; no rows is no venue', () {
      final m = groupMenu([row({'item_id': null, 'section': null, 'name': null})])!;
      expect(m.venueName, 'Soka');
      expect(m.sections, isEmpty);
      expect(groupMenu([]), isNull);
    });
  });

  group('menuPicks (on the device, from the guest\'s own diary)', () {
    final menu = groupMenu([
      row({'item_id': 'neg', 'name': 'Negroni'}),
      row({'item_id': 'boul', 'name': 'Boulevardier'}),
      row({'item_id': 'ipa', 'section': 'Beer', 'name': 'Hazy IPA', 'kind': 'beer'}),
      row({'item_id': 'fries', 'section': 'Food', 'name': 'Fries', 'kind': 'food'}),
      row({'item_id': 'tea', 'section': 'Hot', 'name': 'Masala chai', 'kind': 'tea'}),
    ])!;

    test("ranks the family you drink most, and skips what you've already had", () {
      final picks = menuPicks(menu, [entry('negroni', DrinkType.cocktail), entry('Negroni', DrinkType.cocktail), entry('IPA', DrinkType.beer)]);
      expect(picks.first, 'boul');
      expect(picks, contains('ipa'));
      expect(picks, isNot(contains('neg')));
    });

    test('never suggests food, and says nothing to an empty diary', () {
      expect(menuPicks(menu, [entry('fries')]), isNot(contains('fries')));
      expect(menuPicks(menu, []), isEmpty);
    });

    test('a dry day is not a taste', () {
      expect(menuPicks(menu, [entry('dry day', DrinkType.none)]), isEmpty);
    });
  });

  test('a table\'s own link (051) — the same answers as tests/tableOrder.test.ts', () {
    expect(tableCodeFrom(Uri.parse('https://bwdy.site/t/AbC12345')), 'abc12345');
    expect(tableCodeFrom(Uri.parse('https://bwdy.site/t/abc1234')), isNull);
    expect(tableCodeFrom(Uri.parse('https://bwdy.site/m/abc12345')), isNull);
    expect(tableUrl('abc12345'), 'https://bwdy.site/t/abc12345');
  });

  test('menus carry the diet mark and allergens (051)', () {
    final m = groupMenu([
      {'venue_name': 'V', 'currency': 'INR', 'item_id': 'x', 'section': 'Food', 'name': 'Paneer Tikka', 'kind': 'food', 'no_alcohol': true, 'diet': 'veg', 'allergens': ['milk']},
    ])!;
    expect(m.sections.first.items.first.diet, 'veg');
    expect(m.sections.first.items.first.allergens, ['milk']);
  });
}
