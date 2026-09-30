// The till's arithmetic (050). The server prices every sale again in ring_sale() — this
// only lets the screen show the same total before the tap, and warn before the law
// refuses (an ID check, the per-sale limit, a dry day).
import '../data/models.dart';

class BasketLine {
  final ShopProduct product;

  /// Units, or grams when the product is sold by weight.
  final int qty;
  const BasketLine(this.product, this.qty);

  /// The same sum as ring_sale(): price × qty, or price per kg × grams / 1000.
  double get total => product.byWeight ? (product.price * qty / 1000 * 100).round() / 100 : product.price * qty;

  /// "2 ×", "250 g"
  String get qtyLabel => product.byWeight ? (qty >= 1000 && qty % 1000 == 0 ? '${qty ~/ 1000} kg' : '$qty g') : '$qty ×';
}

class Basket {
  final List<BasketLine> lines;
  const Basket([this.lines = const []]);

  double get total => lines.fold(0, (s, l) => s + l.total);
  bool get hasAlcohol => lines.any((l) => l.product.isAlcohol);
  bool get isEmpty => lines.isEmpty;

  /// Millilitres of alcohol in the basket — what a per-sale limit counts.
  double get alcoholMl => lines.where((l) => l.product.isAlcohol).fold(0, (s, l) => s + (l.product.size ?? 0) * l.qty);

  /// Add [qty] of a product: units stack on the same line; a weight replaces it.
  Basket add(ShopProduct p, [int qty = 1]) {
    final i = lines.indexWhere((l) => l.product.id == p.id);
    if (i < 0) return Basket([...lines, BasketLine(p, qty)]);
    final next = [...lines];
    next[i] = BasketLine(p, p.byWeight ? qty : lines[i].qty + qty);
    return Basket(next);
  }

  /// Set a line's quantity; zero removes it.
  Basket set(String productId, int qty) =>
      Basket([for (final l in lines) if (l.product.id != productId) l else if (qty > 0) BasketLine(l.product, qty)]);

  /// The wire shape ring_sale() reads: what and how many — never a price.
  List<Map<String, Object>> toLines() => [for (final l in lines) {'product': l.product.id, 'qty': l.qty}];
}

/// Why the till won't ring this basket yet, or null when it may.
String? basketBlock(Basket b, SaleStatus? status, {required bool idChecked}) {
  if (b.isEmpty) return 'Add something first.';
  if (!b.hasAlcohol) return null;
  if (status == null) return 'Checking the rules for alcohol…';
  if (!status.researched || !status.allowedNow) return status.reason ?? 'Alcohol can\'t be sold here right now.';
  if (status.maxMl != null && b.alcoholMl > status.maxMl!) return 'Over the per-sale limit here (${status.maxMl} ml).';
  if (!idChecked) return 'Check ID first: ${status.minAge ?? 21} or over.';
  return null;
}

/// The excise register as CSV — what the state's own form is filled from.
String registerCsv(List<RegisterRow> rows) {
  String q(String s) => s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  return [
    'date,brand,product,size_ml,opening,received,sold,other,closing',
    for (final r in rows) [d(r.day), q(r.brand ?? ''), q(r.name), r.size?.toStringAsFixed(0) ?? '', r.opening, r.received, r.sold, r.other, r.closing].join(','),
  ].join('\n');
}
