// "What can I make tonight?" — the shelf you already own, turned into something to make.
//
// This is the CD3 (creativity & feedback) half of the app: the Pantry has been collecting
// ingredients since it shipped and nothing ever read them. Here they become a live answer.
//
// THE RULES THIS FEATURE LIVES UNDER (they shape every line below):
//  1. It only ever shows what you can make with what you ALREADY HAVE. It never says "buy
//     X to unlock this" — for alcohol that is promotion, and inducement-to-purchase is
//     exactly the thing the jurisdiction layer exists to refuse. No shopping list, ever.
//  2. Coffee, tea and soft drinks sit in the same list as spirits and are matched by the
//     same rules. A shelf of milk and coffee makes just as much as a shelf of gin.
//  3. Nothing about it rewards drinking more: it is a MAKING prompt, not a pour count. It
//     suggests a thing to make, never a second one, and no spark, perk or streak touches it.
//  4. Derived and pure. The pantry is per-device (pantry.ts); this file just reads it.
import { normalize } from "./drinks";
import type { DrinkType } from "./types";

export interface Recipe {
  /** What you'd call it — matches the drinks dictionary spelling where one exists. */
  name: string;
  /** The family it belongs to, so a made drink lands on the Passport like any other. */
  family: string;
  type: DrinkType;
  /** Everything you must have. All of these must be on the shelf. */
  needs: string[];
  /** Nice to have — never required, never a reason to shop. */
  nice?: string[];
  /** One line. Enough to actually make it; not a recipe blog. */
  method: string;
}

// A deliberately small, real set. Weighted towards things people actually keep in.
// Non-alcoholic first, and not as an afterthought — for most people that shelf is fuller.
export const RECIPES: Recipe[] = [
  // ── coffee ────────────────────────────────────────────────────────────────
  { name: "Latte", family: "Latte", type: "coffee", needs: ["coffee", "milk"],
    method: "Pull a shot, steam the milk to just past warm, pour it through the crema." },
  { name: "Iced Latte", family: "Latte", type: "coffee", needs: ["coffee", "milk", "ice"],
    method: "Shot over ice, top with cold milk, stir once." },
  { name: "Americano", family: "Americano", type: "coffee", needs: ["coffee", "water"],
    method: "A shot, then hot water to taste — the water after, not before." },
  { name: "Mocha", family: "Mocha", type: "coffee", needs: ["coffee", "milk", "chocolate"],
    method: "Stir chocolate into the hot shot until it dissolves, then the steamed milk." },
  { name: "Cold Brew", family: "Cold Brew", type: "coffee", needs: ["coffee", "water", "ice"],
    method: "Coarse grounds steeped in cold water overnight, strained, poured over ice." },
  { name: "Affogato", family: "Affogato", type: "coffee", needs: ["coffee", "ice cream"],
    method: "A scoop in the glass, a hot shot straight over it. Eat it quickly." },

  // ── tea ───────────────────────────────────────────────────────────────────
  { name: "Chai", family: "Chai", type: "tea", needs: ["tea", "milk", "ginger"], nice: ["cardamom", "sugar"],
    method: "Boil tea with the spices, add milk, bring it up once more, strain." },
  { name: "Iced Tea", family: "Black Tea", type: "tea", needs: ["tea", "ice"], nice: ["lemon", "sugar"],
    method: "Brew it double-strength, cool it, pour over plenty of ice." },
  { name: "Mint Tea", family: "Mint Tea", type: "tea", needs: ["tea", "mint"],
    method: "Fresh mint in the pot with the leaves; let it sit a minute longer than you think." },
  { name: "Matcha Latte", family: "Matcha", type: "tea", needs: ["matcha", "milk"],
    method: "Whisk the matcha with a little hot water first, then the milk." },

  // ── soft & sober ──────────────────────────────────────────────────────────
  { name: "Lemonade", family: "Lemonade", type: "soft", needs: ["lemon", "sugar", "water"], nice: ["mint", "ice"],
    method: "Juice, sugar, water — three, two, one, then taste and argue with yourself." },
  { name: "Nimbu Pani", family: "Lemonade", type: "soft", needs: ["lemon", "sugar", "water", "salt"], nice: ["cumin", "ice"],
    method: "Lime, sugar, a good pinch of salt, cold water. Cumin if you have it." },
  { name: "Virgin Mojito", family: "Mojito", type: "soft", needs: ["mint", "lime", "sugar", "soda"], nice: ["ice"],
    method: "Press the mint with sugar and lime — don't shred it — then soda over ice." },
  { name: "Ginger Fizz", family: "Ginger Fizz", type: "soft", needs: ["ginger", "soda", "lime"], nice: ["honey", "ice"],
    method: "Ginger steeped in a little hot water and honey, cooled, lengthened with soda." },
  { name: "Hot Chocolate", family: "Hot Chocolate", type: "soft", needs: ["milk", "chocolate"],
    method: "Warm the milk, melt the chocolate into it slowly. Never let it boil." },

  // ── cocktails ─────────────────────────────────────────────────────────────
  { name: "Negroni", family: "Negroni", type: "cocktail", needs: ["gin", "campari", "sweet vermouth"], nice: ["orange", "ice"],
    method: "Equal parts, stirred over ice, orange peel over the top." },
  { name: "Boulevardier", family: "Negroni", type: "cocktail", needs: ["whisky", "campari", "sweet vermouth"], nice: ["orange", "ice"],
    method: "A Negroni that swapped the gin for whisky. Stir, don't shake." },
  { name: "Martini", family: "Martini", type: "cocktail", needs: ["gin", "dry vermouth"], nice: ["olive", "lemon", "ice"],
    method: "Stir with plenty of ice until the glass hurts to hold. Twist or olive." },
  { name: "Gin & Tonic", family: "Gin & Tonic", type: "cocktail", needs: ["gin", "tonic"], nice: ["lime", "ice"],
    method: "Ice first, gin, then tonic poured down the side to keep the bubbles." },
  { name: "Daiquiri", family: "Daiquiri", type: "cocktail", needs: ["rum", "lime", "sugar"], nice: ["ice"],
    method: "Two, one, three-quarters. Shake hard, strain, drink cold." },
  { name: "Mojito", family: "Mojito", type: "cocktail", needs: ["rum", "mint", "lime", "sugar", "soda"], nice: ["ice"],
    method: "Press the mint gently with sugar and lime, rum, crushed ice, top with soda." },
  { name: "Old Fashioned", family: "Old Fashioned", type: "cocktail", needs: ["whisky", "sugar", "bitters"], nice: ["orange", "ice"],
    method: "Sugar and bitters, a splash of water, then whisky over one big cube. Stir slowly." },
  { name: "Whisky Sour", family: "Sour", type: "cocktail", needs: ["whisky", "lemon", "sugar"], nice: ["egg white", "ice"],
    method: "Shake hard. With egg white, shake again without ice first." },
  { name: "Margarita", family: "Margarita", type: "cocktail", needs: ["tequila", "lime", "triple sec"], nice: ["salt", "ice"],
    method: "Shake, strain, salt half the rim so you can choose halfway through." },
  { name: "Moscow Mule", family: "Mule", type: "cocktail", needs: ["vodka", "ginger beer", "lime"], nice: ["mint", "ice"],
    method: "Build it in the glass over ice. Lime in, then dropped in." },
  { name: "Cuba Libre", family: "Highball", type: "cocktail", needs: ["rum", "cola", "lime"], nice: ["ice"],
    method: "Rum over ice, cola, a lime wedge squeezed and dropped." },
  { name: "Espresso Martini", family: "Espresso Martini", type: "cocktail", needs: ["vodka", "coffee", "coffee liqueur"], nice: ["sugar", "ice"],
    method: "Shake a fresh shot with the vodka and liqueur until the foam holds." },
  { name: "Americano (cocktail)", family: "Negroni", type: "cocktail", needs: ["campari", "sweet vermouth", "soda"], nice: ["orange", "ice"],
    method: "Campari and vermouth over ice, lengthened with soda. The Negroni's lighter parent." },
  { name: "Spritz", family: "Spritz", type: "cocktail", needs: ["prosecco", "aperol", "soda"], nice: ["orange", "ice"],
    method: "Three prosecco, two Aperol, one soda. Ice to the top, orange slice." },
  { name: "Kir", family: "Kir", type: "wine", needs: ["white wine", "cassis"],
    method: "A splash of cassis in the bottom, cold white wine on top." },

  // ── beer & wine, the simple ones ──────────────────────────────────────────
  { name: "Shandy", family: "Shandy", type: "beer", needs: ["beer", "lemonade"],
    method: "Half and half, or however you like it. Pour the beer first." },
  { name: "Michelada", family: "Michelada", type: "beer", needs: ["beer", "lime", "salt"], nice: ["hot sauce", "ice"],
    method: "Salt the rim, lime and hot sauce in the glass, cold beer poured over." },
];

// Pantry entries are free text ("Sweet Vermouth", "limes", "coffee beans"). Fold both
// sides through the dictionary's normalizer, then match on word containment either way,
// so "limes" satisfies "lime" and "coffee beans" satisfies "coffee".
function has(pantryNorm: string[], want: string): boolean {
  const w = normalize(want);
  if (!w) return false;
  return pantryNorm.some((p) => p === w || p.includes(w) || w.includes(p));
}

export interface Makeable {
  recipe: Recipe;
  /** The optional extras you happen to have — flavour, never a requirement. */
  extras: string[];
}

/**
 * Everything the shelf can make right now. Ordered so the list feels like a shelf rather
 * than a ranking: most-complete first (the ones where you also have the nice-to-haves),
 * then alphabetical. There is deliberately NO "you're one ingredient away from…" — that is
 * a shopping prompt, and for alcohol a shopping prompt is advertising.
 */
export function makeable(pantry: string[]): Makeable[] {
  const norm = pantry.map(normalize).filter(Boolean);
  if (!norm.length) return [];

  return RECIPES.filter((r) => r.needs.every((n) => has(norm, n)))
    .map((recipe) => ({
      recipe,
      extras: (recipe.nice ?? []).filter((n) => has(norm, n)),
    }))
    .sort(
      (a, b) =>
        b.extras.length - a.extras.length || a.recipe.name.localeCompare(b.recipe.name),
    );
}

/**
 * The ingredients that would open up the most NEW recipes — used only to explain the
 * pantry's own emptiness ("add what's on your shelf"), never rendered as something to buy.
 * Returns dictionary staples already implied by what you have, so it stays a prompt to
 * FINISH DESCRIBING your shelf rather than to go shopping.
 */
export function commonStaples(n = 6): string[] {
  const freq = new Map<string, number>();
  for (const r of RECIPES) for (const need of r.needs) {
    freq.set(need, (freq.get(need) ?? 0) + 1);
  }
  return [...freq.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, n)
    .map(([name]) => name);
}
