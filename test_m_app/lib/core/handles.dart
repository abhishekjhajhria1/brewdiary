// Auto-handles that don't read like a bot — a port of src/lib/handles.ts.
// Shape: `name_word`. The name half is yours; the word half is drawn from a curated
// pool. Brands are REROLL-ONLY: never auto-stamped on anyone at sign-up.
import 'dart:math';

const _pool = <String>[
  // warm · amber · late-night — the house mood
  'amber', 'ember', 'dusk', 'twilight', 'midnight', 'moonlit', 'neon', 'velvet',
  'gold', 'copper', 'cinder', 'glow', 'lantern', 'firefly', 'aurora', 'comet',
  'nova', 'cosmo', 'stardust', 'eclipse', 'halo', 'solstice', 'zephyr', 'mirage',
  'lunar', 'dawn', 'afterglow',
  // the craft
  'neat', 'chaser', 'nightcap', 'nectar', 'spritz', 'tonic', 'cask', 'oak',
  'malt', 'dram', 'cellar', 'vintage', 'reserve', 'brew', 'fizz', 'zest',
  'citrus', 'ginger', 'honey', 'cocoa', 'espresso', 'mocha', 'chai', 'matcha',
  'mint', 'sage', 'clove', 'cardamom', 'saffron', 'juniper',
  // swagger
  'legend', 'rogue', 'maverick', 'phantom', 'wildcard', 'nomad', 'drifter', 'ace',
  'jet', 'turbo', 'bolt', 'blaze', 'rebel', 'ronin', 'viper', 'falcon', 'cobra',
  'phoenix', 'titan', 'atlas', 'orbit', 'echo', 'ghost', 'shadow', 'onyx',
  'obsidian', 'quartz', 'flint', 'arc', 'volt', 'spark', 'fable', 'myth', 'saga',
  'apex', 'redline', 'nitro', 'drift', 'vortex', 'cipher', 'omen', 'relic',
  'rune', 'oracle', 'karma', 'halcyon', 'wolf', 'raven', 'lynx', 'koi', 'jaguar',
  'panther', 'kestrel',
  // one-word phrases
  'onelife', 'solo', 'wander', 'roam', 'freebird', 'offgrid', 'moonchild',
  'nightowl', 'stargazer', 'daydream', 'sidequest', 'lowkey', 'offbeat',
  // cheeky "drunk" words
  'tipsy', 'buzzed', 'boozy', 'merry', 'giddy', 'woozy', 'hoppy', 'sloshed',
  'plastered', 'hammered', 'smashed', 'tanked', 'sauced', 'pickled', 'sozzled',
  'blotto', 'squiffy', 'legless', 'frothy', 'lit',
  // drinks themselves — GENERIC names, never a brand
  'negroni', 'mojito', 'martini', 'sazerac', 'gimlet', 'paloma', 'sidecar', 'julep',
  'daiquiri', 'mule', 'sour', 'spritzer', 'highball',
  'stout', 'porter', 'lager', 'saison', 'gose', 'pilsner', 'amberale',
  'merlot', 'malbec', 'shiraz', 'riesling', 'prosecco', 'cava', 'rose', 'claret',
  'whiskey', 'bourbon', 'rye', 'mezcal', 'tequila', 'sake', 'rum', 'gin', 'mead',
  'cider', 'absinthe', 'brandy', 'vermouth',
  'latte', 'cortado', 'affogato', 'ristretto', 'macchiato', 'oolong', 'sencha',
  'kombucha', 'horchata', 'lassi', 'sangria',
  // brand-VIBE words — coined, not trademarks
  'velocity', 'royale', 'monaco', 'riviera', 'platinum', 'chrome', 'midas',
  'sterling', 'regal', 'empire', 'vertex', 'zenith', 'meridian', 'crest', 'prime',
];

// ⚠ Real brands — TRADEMARKS, REROLL-ONLY. Lawyer sign-off before public launch.
const _brandPool = <String>[
  'ferrari', 'lambo', 'porsche', 'bugatti', 'maserati', 'mclaren', 'bentley',
  'aston', 'corvette', 'camaro', 'mustang',
  'gucci', 'prada', 'versace', 'rolex', 'cartier', 'hermes', 'fendi', 'armani',
  'tesla', 'nvidia', 'spacex',
  'bacardi', 'absolut', 'hennessy', 'patron', 'jameson', 'macallan', 'corona',
  'heineken', 'guinness', 'smirnoff', 'moet', 'campari', 'aperol', 'belvedere',
  'jager', 'baileys',
];

const rerollPool = [..._pool, ..._brandPool];
const handlePool = _pool;

/// How many attempts a caller makes before giving up.
const handleTries = 7;

final _rng = Random();

String slugName(String seed) {
  final s = seed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  final cut = s.length > 14 ? s.substring(0, 14) : s;
  return cut.isEmpty ? 'guest' : cut;
}

T _pick<T>(List<T> arr) => arr[_rng.nextInt(arr.length)];

const _blockedNums = ['1488'];

int _numberTail(int attempt) {
  final digits = min(2 + (attempt - 2), 6);
  final lo = pow(10, digits - 1).toInt();
  final hi = pow(10, digits).toInt();
  for (var i = 0; i < 6; i++) {
    final n = lo + _rng.nextInt(hi - lo);
    if (!_blockedNums.any((b) => n.toString().contains(b))) return n;
  }
  return lo;
}

/// A cool handle for `seed`, e.g. `sekhi_ember` or `sekhi_ember42` once a name is popular.
String coolHandle(String seed, {int attempt = 0, List<String> pool = handlePool}) {
  final base = slugName(seed);
  var word = _pick(pool);
  if (word == base) word = _pick(pool);
  if (attempt < 2) return '${base}_$word';
  return '${base}_$word${_numberTail(attempt)}';
}

/// The name half of an existing handle. `sekhi_geeas2` → `sekhi`.
String handleBase(String handle) {
  final i = handle.indexOf('_');
  return slugName(i == -1 ? handle : handle.substring(0, i));
}

/// A fresh handle for the "try another" button — never equal to the current one.
String reroll(String current, {int attempt = 0}) {
  final base = handleBase(current);
  var next = coolHandle(base, attempt: attempt, pool: rerollPool);
  for (var i = 0; i < 8 && next == current; i++) {
    next = coolHandle(base, attempt: attempt, pool: rerollPool);
  }
  return next;
}
