// Menus — a port of src/lib/menus.ts (the pure half). The menu on the table,
// opened by tapping an NFC tag / scanning a QR that holds bwdy.site/m/<slug>.
// "You'd probably like" is worked out HERE, on the phone, from the diary — the
// venue never learns who looked. A menu is never an offer (no discount field).
import 'drinks.dart';
import 'types.dart';

class MenuItem {
  final String id;
  final String section;
  final String name;
  final String? description;
  final double? price;

  /// The diary's DrinkType names plus 'food'.
  final String? kind;
  final bool noAlcohol;

  /// India's menu mark (051): veg, non_veg, egg or vegan.
  final String? diet;

  /// From the EU's 14 (051).
  final List<String> allergens;
  const MenuItem({required this.id, required this.section, required this.name, this.description, this.price, this.kind, this.noAlcohol = false, this.diet, this.allergens = const []});

  /// The DrinkType to log this as (food logs nothing).
  DrinkType? get drinkType => kind == null || kind == 'food' ? null : DrinkType.parse(kind);
}

class MenuSection {
  final String name;
  final List<MenuItem> items;
  const MenuSection(this.name, this.items);
}

class Menu {
  final String venueName;
  final String? venueCity;
  final bool isStore;
  final String currency;
  final List<MenuSection> sections;
  const Menu({required this.venueName, this.venueCity, this.isStore = false, required this.currency, required this.sections});
}

/// The URL to write onto a table's NFC tag / print as its QR.
String menuUrl(String slug, [String origin = 'https://bwdy.site']) => '${origin.replaceAll(RegExp(r'/$'), '')}/m/$slug';

/// The slug in a menu link (`/m/<slug>`), or null if it isn't one.
String? menuSlugFrom(Uri uri) {
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.length < 2 || seg[0] != 'm') return null;
  final slug = seg[1].toLowerCase();
  return RegExp(r'^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])$').hasMatch(slug) ? slug : null;
}

/// A table's own link (`/t/<code>`, 051) → its 8-character code, or null. The twin of
/// parseTableCode() in src/lib/tableOrder.ts.
String? tableCodeFrom(Uri uri) {
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.length < 2 || seg[0] != 't') return null;
  final code = seg[1].trim().toLowerCase();
  return RegExp(r'^[0-9a-z]{8}$').hasMatch(code) ? code : null;
}

/// The URL a table's QR / NFC tag carries.
String tableUrl(String code, [String origin = 'https://bwdy.site']) => '${origin.replaceAll(RegExp(r'/$'), '')}/t/$code';

/// Rows from venue_menu() → a menu, sections in first-seen order.
Menu? groupMenu(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return null;
  final first = rows.first;
  final sections = <MenuSection>[];
  final by = <String, List<MenuItem>>{};
  for (final r in rows) {
    if (r['item_id'] == null) continue; // a verified venue with an empty menu
    final name = (r['section'] as String?) ?? 'Menu';
    var list = by[name];
    if (list == null) {
      list = by[name] = [];
      sections.add(MenuSection(name, list));
    }
    final desc = r['description'] as String?;
    final price = r['price'];
    list.add(MenuItem(
      id: '${r['item_id']}',
      section: name,
      name: '${r['name']}',
      description: desc == null || desc.isEmpty ? null : desc,
      price: price == null ? null : (price is num ? price.toDouble() : double.tryParse('$price')),
      kind: r['kind'] as String?,
      noAlcohol: r['no_alcohol'] == true,
      diet: r['diet'] as String?,
      allergens: [for (final a in (r['allergens'] as List?) ?? const []) '$a'],
    ));
  }
  return Menu(
    venueName: '${first['venue_name']}',
    venueCity: first['venue_city'] as String?,
    isStore: first['venue_kind'] == 'store',
    currency: (first['currency'] as String?) ?? 'INR',
    sections: sections,
  );
}

/// "You'd probably like" — up to [n] item ids, from the guest's OWN diary. Same
/// scoring as the web: a shared drink family (by how often) ×3, plus a shared kind.
/// Food never scores; drinks already had by name are skipped.
List<String> menuPicks(Menu menu, List<Entry> entries, [int n = 3]) {
  final family = <String, int>{};
  final kind = <String, int>{};
  final had = <String>{};
  for (final e in entries) {
    if (e.type == DrinkType.none) continue;
    final c = canonicalize(e.drink);
    family[c.family] = (family[c.family] ?? 0) + 1;
    final t = e.type ?? c.type;
    if (t != null) kind[t.name] = (kind[t.name] ?? 0) + 1;
    had.add(normalize(e.drink));
  }
  if (family.isEmpty) return const [];
  final scored = <({String id, int score})>[];
  for (final s in menu.sections) {
    for (final it in s.items) {
      if (it.kind == 'food' || had.contains(normalize(it.name))) continue;
      final c = canonicalize(it.name);
      final score = (c.matched ? (family[c.family] ?? 0) * 3 : 0) + (it.kind != null ? (kind[it.kind] ?? 0) : 0);
      if (score > 0) scored.add((id: it.id, score: score));
    }
  }
  // Stable sort, like Array.prototype.sort in modern engines.
  final indexed = scored.indexed.toList()..sort((a, b) => b.$2.score != a.$2.score ? b.$2.score.compareTo(a.$2.score) : a.$1.compareTo(b.$1));
  return indexed.take(n).map((x) => x.$2.id).toList();
}
