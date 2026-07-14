// Where you are decides what this app may lawfully do. One table, two consumers:
// the age gate (age.ts) and the venue's house perk (perks.ts).
//
// ── THE RULE THAT MATTERS ────────────────────────────────────────────────────
// DENY BY DEFAULT. A country we have not researched gets the STRICTEST setting,
// not the most permissive one. Before this file existed, an unknown jurisdiction
// fell through to "anything goes", which meant launching in Bangkok or Oslo would
// have silently done the illegal thing. Now silence means "no", and opening a new
// market is a deliberate act: research it, add a row, cite the source.
//
// Nobody can make an app "legal everywhere" — alcohol law is national, often
// sub-national, and it moves. What we CAN do is make the unsafe thing impossible
// by accident. That's what this is.
//
// Research + citations: internal/legal-and-compliance.md (git-ignored).
// The authority is the DATABASE (public.jurisdiction_policy, migration 021);
// this mirror exists so the UI can explain the rule instead of just blocking.

export interface Jurisdiction {
  /** Legal drinking/purchase age. The age gate uses this. */
  minAge: number;
  /** Is alcohol lawful at all? Where it isn't, the venue/bar layer is off entirely. */
  alcoholLegal: boolean;
  /** May a venue run a loyalty perk at all? */
  allowPerks: boolean;
  /** May the perk's PRIZE be an alcoholic drink? */
  allowAlcoholReward: boolean;
  /** May perk progress accrue from MONEY SPENT (rather than visits)? */
  allowSpendPerk: boolean;
  /**
   * May an OFF-LICENCE (liquor store, bottle shop) run a loyalty card?
   *
   * This is a SEPARATE permission from `allowPerks`, and it is deliberately
   * stricter. At a bar, a visit and a purchase are different events — you can walk
   * in, meet someone, buy nothing. That gap is why our visits punch-card survives
   * in countries that ban alcohol loyalty schemes: we reward turning up, and the
   * prize is never a drink.
   *
   * At an off-licence THAT GAP DOES NOT EXIST. Nobody browses a bottle shop for the
   * atmosphere. A visit IS a purchase, and the purchase is alcohol — so a store card
   * is an alcohol loyalty scheme however we label it. Ireland (Public Health
   * (Alcohol) Act s.23) bans the AWARD of points "in relation to the sale of alcohol
   * products"; Northern Ireland (Art. 57ZB) bans them in every licensed premises.
   *
   * So: a country allowing a BAR card does not thereby allow a STORE card. It has to
   * be researched and switched on by name.
   */
  allowOfftradePerks: boolean;
  /** Said to the venue, in plain English, when something is restricted. */
  note?: string;
}

/** The strictest possible answer — what an unresearched place gets. */
export const STRICT: Jurisdiction = {
  minAge: 21,
  alcoholLegal: true,
  allowPerks: false,
  allowAlcoholReward: false,
  allowSpendPerk: false, allowOfftradePerks: false,
  note: "We haven't confirmed the alcohol-promotion rules here yet, so loyalty perks are off. Tell us and we'll research it.",
};

const NO_ALCOHOL_REWARD =
  "A free or discounted drink can't be earned by buying drinks here — so a perk rewards visits with something non-alcoholic.";

// Sub-national overrides, keyed "<COUNTRY>-<REGION>".
const REGIONS: Record<string, Partial<Jurisdiction>> = {
  // Massachusetts and Utah still broadly restrict drink deals.
  "US-MA": { allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Massachusetts restricts drink deals, so a perk here rewards visits with something non-alcoholic." },
  "US-UT": { allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Utah restricts drink deals, so a perk here rewards visits with something non-alcoholic." },

  // NORTHERN IRELAND — the whole perk layer is off. Art. 57ZB of the Licensing and
  // Registration of Clubs (Amendment) Act (NI) 2021 bans awarding OR redeeming
  // loyalty points for alcohol in ALL licensed premises — on-trade included, unlike
  // anywhere else in these tables. The LICENSEE is fined (up to £5,000), so getting
  // clever here would cost a Belfast bar its money and its licence, not ours. NI was
  // silently inheriting Great Britain's row until we caught it.
  "GB-NIR": { allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Northern Ireland bans loyalty and membership rewards on alcohol in every licensed premises, so perks are off here." },
  // SCOTLAND — the bar card stands (no alcohol is given away or discounted, so it's
  // not a "drinks promotion"). The STORE card doesn't: the Alcohol etc. (Scotland)
  // Act 2010 confines off-sales promotions to the alcohol display area.
  "GB-SCT": { allowOfftradePerks: false, note: "Scotland confines off-sales promotions to the alcohol display area, so a shop's loyalty card is off here." },
};

export const JURISDICTIONS: Record<string, Jurisdiction> = {
  // ── home market ───────────────────────────────────────────────────────────
  // Age varies wildly by state (18 in Goa, 21 in Karnataka, 25 in Delhi/Mumbai),
  // so we take the common higher bar. Alcohol ADVERTISING is heavily restricted
  // (surrogate-ad ban), which is why a perk must always stay private — never a
  // public "offers" feed. The perk itself is lawful.
  IN: { minAge: 21, alcoholLegal: true, allowPerks: true, allowAlcoholReward: true, allowSpendPerk: true, allowOfftradePerks: true },

  // ── researched, alcohol reward OK ─────────────────────────────────────────
  US: { minAge: 21, alcoholLegal: true, allowPerks: true, allowAlcoholReward: true, allowSpendPerk: true, allowOfftradePerks: true },

  // ── researched, NON-ALCOHOLIC reward only ─────────────────────────────────
  // Ireland: awarding loyalty points on alcohol purchases is banned outright.
  IE: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Ireland bans loyalty rewards on alcohol, so a perk here rewards visits with something non-alcoholic." },
  // UK: "an alcoholic drink free or at a reduced price on the purchase of one or
  // more drinks" IS the statutory definition of an irresponsible promotion, and
  // the LICENSEE is liable — a bad perk of ours could cost a bar its licence.
  GB: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: true, note: "UK licensing rules treat a free or discounted drink earned by buying drinks as an irresponsible promotion — so a perk here rewards visits with something non-alcoholic." },
  // Australia names loyalty cards that incentivise consumption as an unacceptable
  // promotion, and advertising free/discounted liquor is prohibited.
  AU: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: true, note: "Australian liquor law names loyalty schemes that encourage drinking as an unacceptable promotion — so a perk here rewards visits with something non-alcoholic." },
  // Canada: licensees may not offer inducements; several provinces cap drink specials.
  CA: { minAge: 19, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  // France: Loi Évin restricts alcohol marketing to bare product facts.
  FR: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  DE: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  ES: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  IT: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  NL: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  SG: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  JP: { minAge: 20, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  KR: { minAge: 19, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  NZ: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  ZA: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  BR: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  MX: { minAge: 18, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },
  AE: { minAge: 21, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: NO_ALCOHOL_REWARD },

  // ── researched: NO PERKS AT ALL ───────────────────────────────────────────
  // Thailand bans discounts, giveaways and free offers of alcohol outright, and
  // the 2025 amendments widened "marketing communications" further still.
  TH: { minAge: 20, alcoholLegal: true, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Thailand bans alcohol discounts, giveaways and free offers — no loyalty perk of any kind here." },
  // Norway has had a TOTAL alcohol advertising ban since 1975.
  NO: { minAge: 18, alcoholLegal: true, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Norway bans alcohol advertising outright — no loyalty perk here." },
  SE: { minAge: 18, alcoholLegal: true, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Sweden's alcohol marketing rules are too tight for a loyalty perk." },
  FI: { minAge: 18, alcoholLegal: true, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Finland's alcohol marketing rules are too tight for a loyalty perk." },
  // Turkey banned alcohol promotion, and in 2026 banned brand names/logos in venues.
  TR: { minAge: 18, alcoholLegal: true, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Turkey bans alcohol promotion — no loyalty perk here." },
  // Poland prohibits advertising and promotion of alcohol (beer excepted).
  PL: { minAge: 18, alcoholLegal: true, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Poland prohibits alcohol promotion — no loyalty perk here." },

  // ── alcohol prohibited: the BAR layer is off entirely ─────────────────────
  // brewdiary still works as a diary (coffee, tea, kombucha) — we just never
  // stand up venue rooms, perks, spend or wall screens in these places.
  SA: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  KW: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  LY: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  IR: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  PK: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  BD: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  BN: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  MV: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  SD: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  SO: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  AF: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
  YE: { minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: "Alcohol is prohibited here — the venue features are off." },
};

/** The rules for a place. An unknown place gets STRICT — never the permissive default. */
export function jurisdiction(country?: string | null, region?: string | null): Jurisdiction {
  const c = (country || "").trim().toUpperCase();
  const r = (region || "").trim().toUpperCase();
  const base = JURISDICTIONS[c];
  if (!base) return STRICT;
  const override = r ? REGIONS[`${c}-${r}`] : undefined;
  return override ? { ...base, ...override } : base;
}

/** Legal drinking age where you are. Unknown → 21, the strictest common bar. */
export function minDrinkingAge(country?: string | null, region?: string | null): number {
  return jurisdiction(country, region).minAge;
}

/** The countries we have actually researched — what the pickers offer. */
export const KNOWN_COUNTRIES: { code: string; label: string }[] = [
  { code: "IN", label: "India" },
  { code: "AE", label: "United Arab Emirates" },
  { code: "AU", label: "Australia" },
  { code: "BR", label: "Brazil" },
  { code: "CA", label: "Canada" },
  { code: "DE", label: "Germany" },
  { code: "ES", label: "Spain" },
  { code: "FI", label: "Finland" },
  { code: "FR", label: "France" },
  { code: "GB", label: "United Kingdom" },
  { code: "IE", label: "Ireland" },
  { code: "IT", label: "Italy" },
  { code: "JP", label: "Japan" },
  { code: "KR", label: "South Korea" },
  { code: "MX", label: "Mexico" },
  { code: "NL", label: "Netherlands" },
  { code: "NO", label: "Norway" },
  { code: "NZ", label: "New Zealand" },
  { code: "PL", label: "Poland" },
  { code: "SE", label: "Sweden" },
  { code: "SG", label: "Singapore" },
  { code: "TH", label: "Thailand" },
  { code: "TR", label: "Türkiye" },
  { code: "US", label: "United States" },
  { code: "ZA", label: "South Africa" },
];
