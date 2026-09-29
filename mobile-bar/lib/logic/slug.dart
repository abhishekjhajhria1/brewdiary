// The web address a venue lives at (bwdy.site/m/<slug> on every table tag). A port of
// slugify()/isValidSlug() in src/lib/venues.ts; the database checks the same pattern.

final _slugRe = RegExp(r'^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])$');

const _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', 'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'œ': 'oe',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss', 'ğ': 'g',
  'ı': 'i', 'ş': 's', 'ł': 'l', 'ž': 'z', 'č': 'c', 'ř': 'r', 'š': 's', 'ő': 'o', 'ű': 'u',
};

/// "Café Noir & Co." → "cafe-noir-co". 2–40 chars, letters/digits/hyphens.
String slugify(String name) {
  final lower = name.toLowerCase();
  final folded = StringBuffer();
  for (final ch in lower.split('')) {
    folded.write(_fold[ch] ?? ch);
  }
  var s = folded.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 40) s = s.substring(0, 40);
  return s.replaceAll(RegExp(r'-+$'), '');
}

bool isValidSlug(String slug) => _slugRe.hasMatch(slug);
