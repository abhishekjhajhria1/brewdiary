// Every kind of place that can use the venue app — a bar, but also a café, a restaurant,
// a sweet shop, a bakery, any shop. A MIRROR of public.venue_legal_class() (supabase/046);
// src/lib/venueKinds.ts is the website's copy. The database decides; this explains.
//
// The law that shapes the loyalty card is ALCOHOL law, so what matters is not the sign
// over the door but what the place sells:
//   • on-trade alcohol  (a bar, a club, a licensed restaurant or café) — the bar rules;
//   • off-trade alcohol (an off-licence / liquor store)                — the store rules;
//   • no alcohol        (a sweet shop, a bakery, an unlicensed café)    — neither: a
//     loyalty card for mithai is just a loyalty card.
// And a COUNTER (a shop you buy from and leave) runs no rooms: nobody hangs out in a
// sweet shop, so its visits are punched at the till instead.

enum VenueKind {
  bar('bar', 'Bar or pub'),
  club('club', 'Club'),
  restaurant('restaurant', 'Restaurant'),
  cafe('cafe', 'Café'),
  store('store', 'Liquor store'),
  sweetShop('sweet_shop', 'Sweet shop'),
  bakery('bakery', 'Bakery'),
  shop('shop', 'Shop');

  final String db;
  final String label;
  const VenueKind(this.db, this.label);

  static VenueKind parse(String? s) => VenueKind.values.firstWhere((k) => k.db == s, orElse: () => VenueKind.bar);

  /// Sells alcohol whatever the owner says (a bar is a bar).
  bool get alwaysAlcohol => this == VenueKind.bar || this == VenueKind.club || this == VenueKind.store;

  /// Never sells alcohol (a shop that does is a liquor store — register it as one).
  bool get neverAlcohol => this == VenueKind.sweetShop || this == VenueKind.bakery || this == VenueKind.shop;

  /// The owner chooses: a licensed restaurant or café pours; an unlicensed one doesn't.
  bool get alcoholIsChoice => !alwaysAlcohol && !neverAlcohol;

  /// A counter: you buy and leave. No rooms, no wall board; visits punched at the till.
  bool get isCounter => this == VenueKind.store || this == VenueKind.sweetShop || this == VenueKind.bakery || this == VenueKind.shop;

  /// Table service is the norm (a floor plan, courses, a bill at the table).
  bool get hasTables => this == VenueKind.restaurant || this == VenueKind.cafe || this == VenueKind.bar || this == VenueKind.club;
}

enum LegalClass { onTrade, offTrade, noAlcohol }

/// What the law sees. [servesAlcohol] only matters where it's the owner's choice.
LegalClass legalClass(VenueKind kind, {bool servesAlcohol = false}) {
  if (kind == VenueKind.store) return LegalClass.offTrade;
  if (kind.alwaysAlcohol) return LegalClass.onTrade;
  if (kind.neverAlcohol) return LegalClass.noAlcohol;
  return servesAlcohol ? LegalClass.onTrade : LegalClass.noAlcohol;
}

/// Whether a venue of this kind sells alcohol, given the owner's choice.
bool sellsAlcohol(VenueKind kind, {bool servesAlcohol = false}) => legalClass(kind, servesAlcohol: servesAlcohol) != LegalClass.noAlcohol;

/// What the menu is called here.
String menuWord(VenueKind kind) => switch (kind) {
      VenueKind.store || VenueKind.shop => 'Shelf',
      VenueKind.sweetShop || VenueKind.bakery => 'Counter',
      _ => 'Menu',
    };

/// What the live service tab is called here.
String serviceWord(VenueKind kind) => kind.isCounter ? 'Till' : 'Tonight';

/// What the counter staff are called on a till.
String staffWord(VenueKind kind) => kind.isCounter ? 'Counter' : 'Bartender';
