// Auto-handles that don't read like a bot.
//
// The old generator gave you `sekhi_geeas2` — six random base36 chars, forgettable
// and faintly machine-stamped. But a handle here is PERMANENT and PUBLIC: it's your
// `/u/<handle>` address and how a friend finds you, and there is no rename flow. The
// first one you get is the only one you get, so it should feel like a name, not a
// serial number.
//
// Shape: `name_word`. The name half is yours (from what you typed at sign-up); the
// word half is drawn from a curated pool — `sekhi_ember`, `sekhi_rogue`,
// `sekhi_nightcap`. Two people called "sekhi" can both land on "ember"; `handle` is
// UNIQUE in the database, so the caller retries with a fresh word and, only if it
// keeps clashing, falls back to a short readable tail (`sekhi_ember7`).
//
// ── what's in the pool, and the one line still held ──────────────────────────
// The words lean into the app's own mood: warm, amber, late-night, a bit of swagger,
// and — a deliberate maintainer call — a set of cheeky "drunk" words (tipsy, blotto,
// squiffy…). A handle is low-stakes and re-rollable, so these are fun, not a health
// message; someone who doesn't want one taps "Change". Still kept OUT:
//   • real trademarks (you asked for "ferrari" — the *vibe* is here as turbo / apex /
//     redline, but auto-stamping a brand onto thousands of strangers is a fight we
//     don't need);
//   • anything crude, or that turns into a slur next to a name.

// One flat pool. Grouped only for the reader; picked from uniformly.
const POOL: readonly string[] = [
  // warm · amber · late-night — the house mood
  "amber", "ember", "dusk", "twilight", "midnight", "moonlit", "neon", "velvet",
  "gold", "copper", "cinder", "glow", "lantern", "firefly", "aurora", "comet",
  "nova", "cosmo", "stardust", "eclipse", "halo", "solstice", "zephyr", "mirage",
  "lunar", "dawn", "afterglow",
  // the craft — tasteful, never the hangover
  "neat", "chaser", "nightcap", "nectar", "spritz", "tonic", "cask", "oak",
  "malt", "dram", "cellar", "vintage", "reserve", "brew", "fizz", "zest",
  "citrus", "ginger", "honey", "cocoa", "espresso", "mocha", "chai", "matcha",
  "mint", "sage", "clove", "cardamom", "saffron", "juniper",
  // swagger — edge without the mess
  "legend", "rogue", "maverick", "phantom", "wildcard", "nomad", "drifter", "ace",
  "jet", "turbo", "bolt", "blaze", "rebel", "ronin", "viper", "falcon", "cobra",
  "phoenix", "titan", "atlas", "orbit", "echo", "ghost", "shadow", "onyx",
  "obsidian", "quartz", "flint", "arc", "volt", "spark", "fable", "myth", "saga",
  "apex", "redline", "nitro", "drift", "vortex", "cipher", "omen", "relic",
  "rune", "oracle", "karma", "halcyon", "wolf", "raven", "lynx", "koi", "jaguar",
  "panther", "kestrel",
  // one-word phrases — memorable, like the ones you liked
  "onelife", "solo", "wander", "roam", "freebird", "offgrid", "moonchild",
  "nightowl", "stargazer", "daydream", "sidequest", "lowkey", "offbeat",
  // cheeky "drunk" words — the fun register, not the grim one
  "tipsy", "buzzed", "boozy", "merry", "giddy", "woozy", "hoppy", "sloshed",
  "plastered", "hammered", "smashed", "tanked", "sauced", "pickled", "sozzled",
  "blotto", "squiffy", "legless", "frothy", "lit",
  // drinks themselves — GENERIC names (a cocktail, a style, a bean), never a brand.
  // "mojito" is a word; "Bacardi" is a trademark — and an alcohol trademark on an
  // alcohol app is the one thing our whole jurisdiction/advertising layer exists to
  // avoid. Brands are handled separately, on purpose. See BRAND note below.
  "negroni", "mojito", "martini", "sazerac", "gimlet", "paloma", "sidecar", "julep",
  "daiquiri", "mule", "sour", "spritzer", "highball",
  "stout", "porter", "lager", "saison", "gose", "pilsner", "amberale",
  "merlot", "malbec", "shiraz", "riesling", "prosecco", "cava", "rose", "claret",
  "whiskey", "bourbon", "rye", "mezcal", "tequila", "sake", "rum", "gin", "mead",
  "cider", "absinthe", "brandy", "vermouth",
  "latte", "cortado", "affogato", "ristretto", "macchiato", "oolong", "sencha",
  "kombucha", "horchata", "lassi", "sangria",
  // brand-VIBE words — feel premium/fast/luxe, but coined, not trademarks. Safe to
  // auto-assign; this is the "ferrari energy" without the ferrari lawyers.
  "velocity", "royale", "monaco", "riviera", "platinum", "chrome", "midas",
  "sterling", "regal", "empire", "vertex", "zenith", "meridian", "crest", "prime",
];

// ── real brands — TRADEMARKS, and therefore REROLL-ONLY ──────────────────────
// These never come out of `coolHandle` (the sign-up path), so we NEVER auto-stamp a
// brand on anyone. A person only lands one by actively pressing "try another" and
// choosing to keep it — which is what makes it genuinely user-selected, the strongest
// footing for a trademark appearing in a handle at all.
//
// Alcohol brands are in here at the maintainer's explicit direction. Two eyes-open
// caveats live with them:
//   • an alcohol brand shown publicly by an alcohol app (/u/<handle>, the kiosk wall,
//     friend search) can read as alcohol ADVERTISING — the exact thing the
//     jurisdiction layer (020–030) is built to avoid, India especially;
//   • reroll-only softens it (user-chosen, never app-pushed) but does not erase it.
// ⚠ GET A LAWYER'S SIGN-OFF ON THIS LIST BEFORE PUBLIC LAUNCH. It's on the pre-launch
//   list. Until then it ships behind a deliberate user action, not by default.
const BRAND_POOL: readonly string[] = [
  // cars
  "ferrari", "lambo", "porsche", "bugatti", "maserati", "mclaren", "bentley",
  "aston", "corvette", "camaro", "mustang",
  // fashion · lux
  "gucci", "prada", "versace", "rolex", "cartier", "hermes", "fendi", "armani",
  // tech
  "tesla", "nvidia", "spacex",
  // alcohol — maintainer's call; ⚠ lawyer sign-off before launch (see note above)
  "bacardi", "absolut", "hennessy", "patron", "jameson", "macallan", "corona",
  "heineken", "guinness", "smirnoff", "moet", "campari", "aperol", "belvedere",
  "jager", "baileys",
];

// What the re-roll button draws from: everything safe, PLUS the brands. So a person
// hunting for a new handle can happen onto a brand and keep it — but nobody is ever
// assigned one they didn't choose.
const REROLL_POOL: readonly string[] = [...POOL, ...BRAND_POOL];

/** How many attempts a caller makes before giving up (see `coolHandle`). Seven means
 *  the numeric tail reaches 6 digits — a million variants per word — so no single name
 *  prefix will ever exhaust. */
export const HANDLE_TRIES = 7;

/** The name half: lowercase, letters+digits only, capped so `name_word` stays short
 *  enough to read and to type. Falls back to "guest" for an empty/symbol-only seed. */
export function slugName(seed: string): string {
  return (seed || "").toLowerCase().replace(/[^a-z0-9]+/g, "").slice(0, 14) || "guest";
}

function pick<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * A cool handle for `seed`, e.g. `sekhi_ember` or, once a name gets popular,
 * `sekhi_ember42`.
 *
 * `attempt` climbs only when the database says the handle is taken, and it drives a
 * TRAILING NUMBER that widens the namespace as more people share a name:
 *
 *   attempt 0–1  →  sekhi_ember        (clean — the case for the vast majority)
 *   attempt 2    →  sekhi_ember73       (2 digits · ×100)
 *   attempt 3    →  sekhi_ember512      (3 digits · ×1,000)
 *   attempt 4–6  →  …4, 5, 6 digits     (up to a million per word)
 *
 * So `name_word` has ~150 slots, but `name_word{number}` has effectively unlimited —
 * a name shared by a hundred thousand people still resolves in a couple of tries. The
 * number is TRAILING on purpose: `ember42` is the shape people know from every other
 * app and reads cleanly, where a leading digit (`42ember`) does not.
 *
 * `pool` defaults to the safe POOL — so the SIGN-UP path never auto-assigns a brand.
 * The re-roll button passes REROLL_POOL to let a user opt into one by choosing it.
 */
export function coolHandle(seed: string, attempt = 0, pool: readonly string[] = POOL): string {
  const base = slugName(seed);
  let word = pick(pool);
  if (word === base) word = pick(pool); // avoid the odd "ace_ace"

  if (attempt < 2) return `${base}_${word}`;
  return `${base}_${word}${numberTail(attempt)}`;
}

// Number sequences we will not AUTO-STAMP onto a stranger. This isn't moralising
// about fun (69 and 420 stay — this is a drink app) — it's the unambiguous hate
// codes, which in a random draw across a lot of signups WILL eventually come up and
// which nobody should be handed by default. Kept deliberately tiny: "1488" is THE
// canonical one; blocking "88" or "666" would wrongly reject a lucky or a spooky
// number people actually like. Someone can still type nothing and re-roll; this only
// governs what we generate.
const BLOCKED_NUMS = ["1488"];

/** The digit-count grows with the attempt; at 2 digits the smallest is 10, so the
 *  number never looks like a lonely "ember3". Capped at 6 digits (a million). */
function numberTail(attempt: number): number {
  const digits = Math.min(2 + (attempt - 2), 6);
  const lo = 10 ** (digits - 1);
  const hi = 10 ** digits;
  for (let i = 0; i < 6; i++) {
    const n = lo + Math.floor(Math.random() * (hi - lo));
    if (!BLOCKED_NUMS.some((b) => String(n).includes(b))) return n;
  }
  return lo; // a blocked draw six times running is astronomically unlikely; lo is clean
}

/** The name half of an existing handle — everything before the first underscore,
 *  re-slugged for safety. `sekhi_geeas2` → `sekhi`. */
export function handleBase(handle: string): string {
  const i = (handle || "").indexOf("_");
  return slugName(i === -1 ? handle : handle.slice(0, i));
}

/**
 * A fresh handle for the "try another" button: same name half, never equal to what
 * they already have (so the button visibly does something each press).
 *
 * `attempt` is 0 for a voluntary press (clean words, the nice case) and climbs only if
 * saving keeps hitting "taken" — so a person whose name has exhausted every clean word
 * still gets offered a numbered one instead of pressing forever.
 *
 * Draws from REROLL_POOL (the safe words PLUS the brands), because THIS is the
 * user-chosen path — the only place a trademark handle may surface, and only because
 * they pressed the button and kept it.
 */
export function reroll(current: string, attempt = 0): string {
  const base = handleBase(current);
  let next = coolHandle(base, attempt, REROLL_POOL);
  for (let i = 0; i < 8 && next === current; i++) next = coolHandle(base, attempt, REROLL_POOL);
  return next;
}
