// Drink canonicalization — a port of src/lib/drinks.ts.
//
// Folds variants/typos into one family so the diary can suggest a name while you
// type, quietly propose the canonical spelling, and group history by family.
// Nothing here is STORED — grouping is derived on the fly from the free text.
import 'types.dart';

class DrinkDef {
  final String canonical;
  final String family;
  final DrinkType type;
  final List<String> aliases;
  const DrinkDef(this.canonical, this.family, this.type, [this.aliases = const []]);
}

const drinks = <DrinkDef>[
  // coffee
  DrinkDef('Espresso', 'Espresso', DrinkType.coffee, ['shot', 'short black', 'doppio']),
  DrinkDef('Flat White', 'Flat White', DrinkType.coffee, ['flatwhite']),
  DrinkDef('Latte', 'Latte', DrinkType.coffee, ['caffe latte', 'cafe latte', 'latté']),
  DrinkDef('Cappuccino', 'Cappuccino', DrinkType.coffee, ['cappucino', 'capp']),
  DrinkDef('Cortado', 'Cortado', DrinkType.coffee, ['gibraltar']),
  DrinkDef('Americano', 'Americano', DrinkType.coffee, ['long black', 'caffe americano']),
  DrinkDef('Macchiato', 'Macchiato', DrinkType.coffee, ['espresso macchiato']),
  DrinkDef('Mocha', 'Mocha', DrinkType.coffee, ['mochaccino', 'caffe mocha']),
  DrinkDef('Cold Brew', 'Cold Brew', DrinkType.coffee, ['coldbrew', 'cold-brew']),
  DrinkDef('Iced Latte', 'Latte', DrinkType.coffee, ['iced coffee', 'ice latte']),
  DrinkDef('Pour-over', 'Filter Coffee', DrinkType.coffee, ['pourover', 'pour over', 'filter', 'filter coffee', 'drip', 'v60']),
  // tea
  DrinkDef('Matcha', 'Matcha', DrinkType.tea, ['matcha latte']),
  DrinkDef('Green Tea', 'Green Tea', DrinkType.tea, ['sencha', 'greentea']),
  DrinkDef('Chamomile', 'Chamomile', DrinkType.tea, ['camomile']),
  DrinkDef('Earl Grey', 'Black Tea', DrinkType.tea, ['earlgrey', 'english breakfast', 'breakfast tea']),
  DrinkDef('Chai', 'Chai', DrinkType.tea, ['chai latte', 'masala chai']),
  // beer
  DrinkDef('IPA', 'IPA', DrinkType.beer, ['india pale ale']),
  DrinkDef('Hazy IPA', 'IPA', DrinkType.beer, ['neipa', 'new england ipa', 'juicy ipa']),
  DrinkDef('West Coast IPA', 'IPA', DrinkType.beer, ['wc ipa']),
  DrinkDef('Double IPA', 'IPA', DrinkType.beer, ['dipa', 'imperial ipa']),
  DrinkDef('Lager', 'Lager', DrinkType.beer, ['pilsner', 'pils', 'helles']),
  DrinkDef('Pale Ale', 'Pale Ale', DrinkType.beer, ['apa', 'american pale ale']),
  DrinkDef('Stout', 'Stout', DrinkType.beer, ['imperial stout', 'milk stout']),
  DrinkDef('Guinness', 'Stout', DrinkType.beer),
  DrinkDef('Porter', 'Stout', DrinkType.beer),
  DrinkDef('Wheat Beer', 'Wheat Beer', DrinkType.beer, ['hefeweizen', 'witbier', 'wit', 'weissbier']),
  DrinkDef('Sour', 'Sour', DrinkType.beer, ['gose', 'berliner weisse']),
  // wine
  DrinkDef('Riesling', 'White Wine', DrinkType.wine),
  DrinkDef('Sauvignon Blanc', 'White Wine', DrinkType.wine, ['sauv blanc', 'sancerre']),
  DrinkDef('Chardonnay', 'White Wine', DrinkType.wine, ['chard']),
  DrinkDef('Pinot Grigio', 'White Wine', DrinkType.wine, ['pinot gris']),
  DrinkDef('Cabernet Sauvignon', 'Red Wine', DrinkType.wine, ['cabernet', 'cab sauv', 'cab']),
  DrinkDef('Merlot', 'Red Wine', DrinkType.wine),
  DrinkDef('Pinot Noir', 'Red Wine', DrinkType.wine, ['pinot']),
  DrinkDef('Malbec', 'Red Wine', DrinkType.wine),
  DrinkDef('Barolo', 'Red Wine', DrinkType.wine, ['nebbiolo']),
  DrinkDef('Syrah', 'Red Wine', DrinkType.wine, ['shiraz']),
  DrinkDef('Rosé', 'Rosé', DrinkType.wine, ['rose wine', 'rosado']),
  DrinkDef('Prosecco', 'Sparkling', DrinkType.wine, ['cava', 'champagne', 'sparkling wine', 'fizz']),
  // cocktails
  DrinkDef('Negroni', 'Negroni', DrinkType.cocktail),
  DrinkDef('Negroni Sbagliato', 'Negroni', DrinkType.cocktail, ['sbagliato']),
  DrinkDef('Boulevardier', 'Negroni', DrinkType.cocktail),
  DrinkDef('White Negroni', 'Negroni', DrinkType.cocktail),
  DrinkDef('Old Fashioned', 'Old Fashioned', DrinkType.cocktail, ['oldfashioned', 'old-fashioned']),
  DrinkDef('Martini', 'Martini', DrinkType.cocktail, ['dry martini', 'gin martini']),
  DrinkDef('Dirty Martini', 'Martini', DrinkType.cocktail),
  DrinkDef('Vodka Martini', 'Martini', DrinkType.cocktail),
  DrinkDef('Espresso Martini', 'Espresso Martini', DrinkType.cocktail, ['espresso martini']),
  DrinkDef('Margarita', 'Margarita', DrinkType.cocktail, ["tommy's margarita", 'spicy margarita', 'mezcal margarita']),
  DrinkDef('Daiquiri', 'Daiquiri', DrinkType.cocktail, ['hemingway daiquiri']),
  DrinkDef('Aperol Spritz', 'Spritz', DrinkType.cocktail, ['aperol', 'spritz']),
  DrinkDef('Campari Spritz', 'Spritz', DrinkType.cocktail),
  DrinkDef('Hugo Spritz', 'Spritz', DrinkType.cocktail, ['hugo']),
  DrinkDef('Manhattan', 'Manhattan', DrinkType.cocktail),
  DrinkDef('Whiskey Sour', 'Sour Cocktail', DrinkType.cocktail, ['whisky sour']),
  DrinkDef('Amaretto Sour', 'Sour Cocktail', DrinkType.cocktail),
  DrinkDef('Mojito', 'Mojito', DrinkType.cocktail),
  DrinkDef('Moscow Mule', 'Mule', DrinkType.cocktail, ['mule']),
  DrinkDef('Gin & Tonic', 'Gin & Tonic', DrinkType.cocktail, ['gin and tonic', 'g&t', 'gt', 'gin tonic']),
  DrinkDef('Paloma', 'Paloma', DrinkType.cocktail),
  DrinkDef('Cosmopolitan', 'Cosmopolitan', DrinkType.cocktail, ['cosmo']),
  DrinkDef('Piña Colada', 'Piña Colada', DrinkType.cocktail, ['pina colada', 'colada']),
  // spirits
  DrinkDef('Whiskey', 'Whiskey', DrinkType.spirit, ['whisky', 'bourbon', 'scotch', 'rye']),
  DrinkDef('Tequila', 'Tequila', DrinkType.spirit, ['mezcal']),
  DrinkDef('Gin', 'Gin', DrinkType.spirit),
  DrinkDef('Vodka', 'Vodka', DrinkType.spirit),
  DrinkDef('Rum', 'Rum', DrinkType.spirit, ['dark rum', 'white rum']),
  DrinkDef('Brandy', 'Brandy', DrinkType.spirit, ['cognac', 'armagnac']),
  // soft
  DrinkDef('Water', 'Water', DrinkType.soft, ['sparkling water', 'still water']),
  DrinkDef('Kombucha', 'Kombucha', DrinkType.soft),
  DrinkDef('Lemonade', 'Soft Drink', DrinkType.soft, ['sprite', '7up']),
  DrinkDef('Cola', 'Soft Drink', DrinkType.soft, ['coke', 'pepsi', 'coca cola', 'coca-cola']),
  DrinkDef('Orange Juice', 'Juice', DrinkType.soft, ['oj', 'juice']),
  DrinkDef('Ginger Beer', 'Soft Drink', DrinkType.soft),
];

/// ~0.82 lands near the "90% same" intuition once you account for shared tokens.
const _matchThreshold = 0.82;

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
};

/// lowercase, drop accents/punctuation, collapse whitespace — the comparison key.
String normalize(String s) {
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    buf.write(_accents[ch] ?? ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final t = prev;
    prev = curr;
    curr = t;
  }
  return prev[b.length];
}

double _tokenJaccard(String a, String b) {
  final sa = a.split(' ').where((t) => t.isNotEmpty).toSet();
  final sb = b.split(' ').where((t) => t.isNotEmpty).toSet();
  if (sa.isEmpty || sb.isEmpty) return 0;
  final inter = sa.where(sb.contains).length;
  return inter / (sa.length + sb.length - inter);
}

/// 0..1 similarity of two drink names.
double similarity(String a, String b) {
  final na = normalize(a);
  final nb = normalize(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final longest = na.length > nb.length ? na.length : nb.length;
  final charRatio = 1 - _levenshtein(na, nb) / longest;
  final tokenRatio = _tokenJaccard(na, nb);
  return charRatio > tokenRatio ? charRatio : tokenRatio;
}

class _Indexed {
  final DrinkDef def;
  final String key;
  const _Indexed(this.def, this.key);
}

final List<_Indexed> _index = [
  for (final def in drinks) ...[
    _Indexed(def, normalize(def.canonical)),
    for (final a in def.aliases) _Indexed(def, normalize(a)),
  ],
];

final Map<String, DrinkDef> _byKey = () {
  final m = <String, DrinkDef>{};
  for (final i in _index) {
    m.putIfAbsent(i.key, () => i.def);
  }
  return m;
}();

class Canon {
  final String canonical;
  final String family;
  final DrinkType? type;
  final bool matched;
  const Canon({required this.canonical, required this.family, this.type, required this.matched});
}

/// Resolve a free-text drink to its canonical name + family. Exact alias hit first,
/// then a fuzzy fallback. Unknowns come back as their own canonical (matched: false).
Canon canonicalize(String name) {
  final trimmed = name.trim();
  final norm = normalize(trimmed);
  if (norm.isEmpty) return Canon(canonical: trimmed, family: 'Other', matched: false);

  final exact = _byKey[norm];
  if (exact != null) return Canon(canonical: exact.canonical, family: exact.family, type: exact.type, matched: true);

  DrinkDef? best;
  var bestScore = 0.0;
  for (final i in _index) {
    final score = similarity(norm, i.key);
    if (score > bestScore) {
      bestScore = score;
      best = i.def;
    }
  }
  if (best != null && bestScore >= _matchThreshold) {
    return Canon(canonical: best.canonical, family: best.family, type: best.type, matched: true);
  }
  return Canon(canonical: trimmed, family: trimmed, matched: false);
}

String drinkFamily(String name) => canonicalize(name).family;

/// Autocomplete for the log window. The user's OWN history ranks first.
List<String> suggestDrinks(String query, [List<String> history = const [], int n = 6]) {
  final q = normalize(query);
  if (q.isEmpty) return [];
  final seen = <String>{};
  final scored = <(String, double)>[];

  void consider(String display, bool own) {
    final key = normalize(display);
    if (key.isEmpty || seen.contains(key)) return;
    double score;
    if (key == q) {
      return; // never suggest an exact echo of what's typed
    } else if (key.startsWith(q)) {
      score = 0.9;
    } else if (key.contains(q)) {
      score = 0.75;
    } else {
      final sim = similarity(q, key);
      if (sim < 0.55) return;
      score = sim * 0.7;
    }
    seen.add(key);
    scored.add((display, score + (own ? 0.08 : 0)));
  }

  for (final h in history) {
    consider(h, true);
  }
  for (final d in drinks) {
    consider(d.canonical, false);
  }
  // Stable sort by score desc (Dart's sort isn't stable — keep insertion order on ties).
  final indexed = scored.asMap().entries.toList()
    ..sort((a, b) {
      final c = b.value.$2.compareTo(a.value.$2);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return indexed.take(n).map((e) => e.value.$1).toList();
}

// ── flavour notes, per family ──────────────────────────────────────────────
// What each family tastes like, in a few plain words. The palate on the taste
// passport is worked out from these (derive.dart palate()); the bartender sees the
// top notes. Twin: drinks.ts FLAVOURS — keep the two identical.
const flavours = <String, List<String>>{
  'Americano': ['roasty', 'bitter'],
  'Black Tea': ['bitter', 'floral'],
  'Brandy': ['rich', 'fruity'],
  'Cappuccino': ['creamy', 'roasty'],
  'Chai': ['spicy', 'creamy', 'sweet'],
  'Chamomile': ['floral', 'herbal'],
  'Cold Brew': ['roasty', 'smooth'],
  'Cortado': ['roasty', 'creamy'],
  'Cosmopolitan': ['fruity', 'citrus'],
  'Daiquiri': ['citrus', 'sour', 'sweet'],
  'Espresso': ['roasty', 'bitter', 'rich'],
  'Espresso Martini': ['roasty', 'sweet', 'creamy'],
  'Filter Coffee': ['roasty', 'fruity'],
  'Flat White': ['roasty', 'creamy'],
  'Gin': ['herbal', 'crisp'],
  'Gin & Tonic': ['herbal', 'bubbly', 'crisp'],
  'Green Tea': ['herbal', 'crisp'],
  'IPA': ['bitter', 'citrus', 'fruity'],
  'Juice': ['fruity', 'sweet'],
  'Kombucha': ['sour', 'bubbly', 'fruity'],
  'Lager': ['crisp', 'bubbly'],
  'Latte': ['creamy', 'roasty'],
  'Macchiato': ['roasty', 'rich'],
  'Manhattan': ['rich', 'herbal'],
  'Margarita': ['citrus', 'sour'],
  'Martini': ['crisp', 'herbal'],
  'Matcha': ['herbal', 'creamy'],
  'Mocha': ['sweet', 'creamy', 'roasty'],
  'Mojito': ['herbal', 'citrus', 'bubbly'],
  'Mule': ['spicy', 'citrus', 'bubbly'],
  'Negroni': ['bitter', 'herbal', 'citrus'],
  'Old Fashioned': ['rich', 'sweet', 'smoky'],
  'Pale Ale': ['bitter', 'citrus'],
  'Paloma': ['citrus', 'bubbly'],
  'Piña Colada': ['sweet', 'creamy', 'fruity'],
  'Red Wine': ['fruity', 'rich'],
  'Rosé': ['fruity', 'crisp'],
  'Rum': ['sweet', 'rich'],
  'Soft Drink': ['sweet', 'bubbly'],
  'Sour': ['sour', 'fruity'],
  'Sour Cocktail': ['sour', 'citrus'],
  'Sparkling': ['bubbly', 'crisp'],
  'Spritz': ['bitter', 'bubbly', 'citrus'],
  'Stout': ['roasty', 'rich', 'creamy'],
  'Tequila': ['smoky', 'citrus'],
  'Vodka': ['crisp'],
  'Water': [],
  'Wheat Beer': ['fruity', 'spicy', 'bubbly'],
  'Whiskey': ['smoky', 'rich'],
  'White Wine': ['crisp', 'fruity'],
};
