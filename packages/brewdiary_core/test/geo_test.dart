// The heat map's grid — the same answers as tests/geo.test.ts on the web side.
import 'package:brewdiary_core/geo.dart';
import 'package:test/test.dart';

void main() {
  test('an area splits into 32 neighbourhoods, 8 across and 4 down', () {
    final g = subcells('tdr1');
    expect(g.length, 32);
    expect(g.map((c) => c.cell).toSet().length, 32);
    expect(g.every((c) => c.cell.startsWith('tdr1') && c.cell.length == 5), isTrue);
    expect(g.map((c) => c.col).toSet(), {0, 1, 2, 3, 4, 5, 6, 7});
    expect(g.map((c) => c.row).toSet(), {0, 1, 2, 3});
  });

  test('the corners are where geohash puts them', () {
    final at = {for (final c in subcells('tdr1')) c.cell: (c.col, c.row)};
    expect(at['tdr10'], (0, 3)); // south-west
    expect(at['tdr1z'], (7, 0)); // north-east
    expect(at['tdr1b'], (0, 0)); // north-west
    expect(at['tdr1p'], (7, 3)); // south-east
    expect(subcells('tdr1').first.cell, 'tdr1b', reason: 'screen order: north-west first');
  });

  test('a venue deeper than 5 characters finds its own neighbourhood', () {
    expect(subcells('tdr1v9').first.cell, 'tdr1b');
    expect(directionFrom('tdr1v9', 'tdr1v'), 'your own neighbourhood');
  });

  test('directions read like a person would say them', () {
    expect(directionFrom('tdr1v', 'tdr1y'), '~5 km east');
    expect(directionFrom('tdr1v', 'tdr1u'), '~5 km west');
    expect(directionFrom('tdr1v', 'tdr1t'), '~5 km south');
    expect(directionFrom('tdr1v', 'tdr10'), '~25 km south-west');
    expect(directionFrom('tdr1v', 'tdr1b'), '~25 km west');
    expect(directionFrom('tdr1s', 'tdr1v'), '~5 km north-east');
  });

  test('geohash characters only', () {
    expect(isGeohash('tdr1v9'), isTrue);
    expect(isGeohash('tdr1 main st'), isFalse);
    expect(isGeohash('tdra'), isFalse, reason: 'no a, i, l or o in geohash');
    expect(venueCell(12.9716, 77.5946), 'tdr1v9');
  });
}
