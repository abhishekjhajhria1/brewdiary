// Every kind of place that can use the venue layer — a mirror of venue_legal_class() and
// venue_is_counter() in supabase/047. mobile-bar/lib/logic/venue_kinds.dart is the same
// table for the venue app. The DATABASE decides; these explain.
//
// What the law sees is what a place SELLS: on-trade alcohol (a bar, a club, a licensed
// restaurant or café) follows the bar rules; off-trade alcohol (a liquor store) the
// store rules; a place that sells no alcohol (a sweet shop, a bakery, any shop, an
// unlicensed café) neither — its loyalty card is just a loyalty card.

export const VENUE_KINDS = ["bar", "club", "restaurant", "cafe", "store", "sweet_shop", "bakery", "shop"] as const;
export type VenueKind = (typeof VENUE_KINDS)[number];

export const VENUE_KIND_LABEL: Record<VenueKind, string> = {
  bar: "Bar or pub",
  club: "Club",
  restaurant: "Restaurant",
  cafe: "Café",
  store: "Liquor store",
  sweet_shop: "Sweet shop",
  bakery: "Bakery",
  shop: "Shop",
};

export const VENUE_KIND_BLURB: Record<VenueKind, string> = {
  bar: "People drink here",
  club: "Music, a door, a bar",
  restaurant: "Tables, food, maybe a licence",
  cafe: "Coffee, tea, maybe a licence",
  store: "Alcohol, carried out",
  sweet_shop: "Mithai, sweets, snacks",
  bakery: "Bread, cakes, coffee",
  shop: "Anything else, no alcohol",
};

export type LegalClass = "on_trade" | "off_trade" | "no_alcohol";

export function parseVenueKind(s: unknown): VenueKind {
  return (VENUE_KINDS as readonly string[]).includes(String(s)) ? (s as VenueKind) : "bar";
}

/** The owner chooses (a licensed restaurant pours; an unlicensed café doesn't). */
export function alcoholIsChoice(kind: VenueKind): boolean {
  return kind === "restaurant" || kind === "cafe";
}

export function legalClass(kind: VenueKind, servesAlcohol = false): LegalClass {
  if (kind === "store") return "off_trade";
  if (kind === "bar" || kind === "club") return "on_trade";
  if (alcoholIsChoice(kind) && servesAlcohol) return "on_trade";
  return "no_alcohol";
}

export function sellsAlcohol(kind: VenueKind, servesAlcohol = false): boolean {
  return legalClass(kind, servesAlcohol) !== "no_alcohol";
}

/** A counter: you buy and leave. No rooms; visits are punched at the till. */
export function isCounter(kind: VenueKind): boolean {
  return kind === "store" || kind === "sweet_shop" || kind === "bakery" || kind === "shop";
}
