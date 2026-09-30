// The area heat map's grid — the twin of src/lib/geohash.ts subcells(). Pure.
//
// A geohash-4 cell (~39 × 20 km, "your area") splits into 32 geohash-5 cells (~5 km,
// "a neighbourhood"). A fifth character adds three longitude bits and two latitude
// bits, so the 32 lie in 8 columns (west → east) by 4 rows (south → north).
import 'misc.dart' show encodeGeohash;

/// A venue's location: ~1.2 × 0.6 km. Fine enough to place it in its neighbourhood
/// for the map, and a venue's address is public anyway. People are never stored
/// finer than [areaPrecision] (misc.dart).
const venuePrecision = 6;

/// Roughly how far apart neighbouring geohash-5 cells are.
const neighbourhoodKm = 5;

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

bool isGeohash(String s) => s.isNotEmpty && s.length <= 12 && s.split('').every(_base32.contains);

class GridCell {
  /// The geohash-5 cell.
  final String cell;

  /// 0 (west) … 7 (east).
  final int col;

  /// 0 (north) … 3 (south): screen order, top row first.
  final int row;
  const GridCell(this.cell, this.col, this.row);
}

/// The 32 neighbourhoods of an area, in screen order (north-west first).
List<GridCell> subcells(String area) {
  final a = area.substring(0, area.length < 4 ? area.length : 4);
  final out = <GridCell>[];
  for (var i = 0; i < 32; i++) {
    final col = ((i >> 4) & 1) * 4 + ((i >> 2) & 1) * 2 + (i & 1);
    final south = ((i >> 3) & 1) * 2 + ((i >> 1) & 1); // 0 = southernmost
    out.add(GridCell('$a${_base32[i]}', col, 3 - south));
  }
  out.sort((x, y) => x.row != y.row ? x.row - y.row : x.col - y.col);
  return out;
}

/// Where [cell] lies from [from] (both geohash-5 in the same area), in plain words:
/// "your own neighbourhood", "~5 km east", "~10 km north-west".
String directionFrom(String from, String cell) {
  GridCell? find(String c) {
    if (c.length < 5) return null;
    for (final g in subcells(c)) {
      if (g.cell == c.substring(0, 5)) return g;
    }
    return null;
  }

  final a = find(from), b = find(cell);
  if (a == null || b == null) return 'nearby';
  final dx = b.col - a.col, dy = a.row - b.row; // +dy = north
  if (dx == 0 && dy == 0) return 'your own neighbourhood';
  final steps = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
  final ns = dy > 0 ? 'north' : (dy < 0 ? 'south' : '');
  final ew = dx > 0 ? 'east' : (dx < 0 ? 'west' : '');
  // A diagonal only when both legs are real; otherwise the stronger one.
  final dir = (ns.isNotEmpty && ew.isNotEmpty && dx.abs() * 2 >= dy.abs() && dy.abs() * 2 >= dx.abs())
      ? '$ns-$ew'
      : (dx.abs() >= dy.abs() ? ew : ns);
  return '~${steps * neighbourhoodKm} km $dir';
}

/// A venue's cell from a position — on the device; coordinates never leave it.
String venueCell(double lat, double lon) => encodeGeohash(lat, lon, venuePrecision);
