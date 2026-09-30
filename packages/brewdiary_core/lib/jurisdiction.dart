// Where you are decides what this app may lawfully do — a port of
// src/lib/jurisdiction.ts. DENY BY DEFAULT: an unresearched country gets the
// STRICTEST setting, never the most permissive one.
//
// The authority is the DATABASE (public.jurisdiction_policy). This mirror exists so
// the UI can explain the rule instead of just blocking.

class Jurisdiction {
  final int minAge;
  final bool alcoholLegal;
  final bool allowPerks;
  final bool allowAlcoholReward;
  final bool allowSpendPerk;
  final bool allowOfftradePerks;
  final String? note;

  const Jurisdiction({
    required this.minAge,
    required this.alcoholLegal,
    required this.allowPerks,
    required this.allowAlcoholReward,
    required this.allowSpendPerk,
    required this.allowOfftradePerks,
    this.note,
  });

  Jurisdiction merge({bool? allowPerks, bool? allowAlcoholReward, bool? allowSpendPerk, bool? allowOfftradePerks, String? note}) {
    return Jurisdiction(
      minAge: minAge,
      alcoholLegal: alcoholLegal,
      allowPerks: allowPerks ?? this.allowPerks,
      allowAlcoholReward: allowAlcoholReward ?? this.allowAlcoholReward,
      allowSpendPerk: allowSpendPerk ?? this.allowSpendPerk,
      allowOfftradePerks: allowOfftradePerks ?? this.allowOfftradePerks,
      note: note ?? this.note,
    );
  }
}

/// The strictest possible answer — what an unresearched place gets.
const strict = Jurisdiction(
  minAge: 21,
  alcoholLegal: true,
  allowPerks: false,
  allowAlcoholReward: false,
  allowSpendPerk: false,
  allowOfftradePerks: false,
  note: "We haven't confirmed the alcohol-promotion rules here yet, so loyalty perks are off. Tell us and we'll research it.",
);

const _noAlcoholReward =
    "A free or discounted drink can't be earned by buying drinks here — so a perk rewards visits with something non-alcoholic.";
const _prohibited = 'Alcohol is prohibited here — the venue features are off.';

// Compact row builders so the table reads like the source.
Jurisdiction _open(int age, {bool offtrade = true}) => Jurisdiction(
    minAge: age, alcoholLegal: true, allowPerks: true, allowAlcoholReward: true, allowSpendPerk: true, allowOfftradePerks: offtrade);
Jurisdiction _visitsOnly(int age, String note, {bool offtrade = false}) => Jurisdiction(
    minAge: age, alcoholLegal: true, allowPerks: true, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: offtrade, note: note);
Jurisdiction _noPerks(int age, String note) => Jurisdiction(
    minAge: age, alcoholLegal: true, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: note);
Jurisdiction _dry() => const Jurisdiction(
    minAge: 21, alcoholLegal: false, allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false, note: _prohibited);

final Map<String, Jurisdiction> jurisdictions = {
  // home market — the common higher bar (18 in Goa, 21 in Karnataka, 25 in Delhi/Mumbai)
  'IN': _open(21),
  'US': _open(21),
  'IE': _visitsOnly(18, 'Ireland bans loyalty rewards on alcohol, so a perk here rewards visits with something non-alcoholic.'),
  'GB': _visitsOnly(18,
      'UK licensing rules treat a free or discounted drink earned by buying drinks as an irresponsible promotion — so a perk here rewards visits with something non-alcoholic.',
      offtrade: true),
  'AU': _visitsOnly(18,
      'Australian liquor law names loyalty schemes that encourage drinking as an unacceptable promotion — so a perk here rewards visits with something non-alcoholic.',
      offtrade: true),
  'CA': _visitsOnly(19, _noAlcoholReward),
  'FR': _visitsOnly(18, _noAlcoholReward),
  'DE': _visitsOnly(18, _noAlcoholReward),
  'ES': _visitsOnly(18, _noAlcoholReward),
  'IT': _visitsOnly(18, _noAlcoholReward),
  'NL': _visitsOnly(18, _noAlcoholReward),
  'SG': _visitsOnly(18, _noAlcoholReward),
  'JP': _visitsOnly(20, _noAlcoholReward),
  'KR': _visitsOnly(19, _noAlcoholReward),
  'NZ': _visitsOnly(18, _noAlcoholReward),
  'ZA': _visitsOnly(18, _noAlcoholReward),
  'BR': _visitsOnly(18, _noAlcoholReward),
  'MX': _visitsOnly(18, _noAlcoholReward),
  'AE': _visitsOnly(21, _noAlcoholReward),
  'TH': _noPerks(20, 'Thailand bans alcohol discounts, giveaways and free offers — no loyalty perk of any kind here.'),
  'NO': _noPerks(18, 'Norway bans alcohol advertising outright — no loyalty perk here.'),
  'SE': _noPerks(18, "Sweden's alcohol marketing rules are too tight for a loyalty perk."),
  'FI': _noPerks(18, "Finland's alcohol marketing rules are too tight for a loyalty perk."),
  'TR': _noPerks(18, 'Turkey bans alcohol promotion — no loyalty perk here.'),
  'PL': _noPerks(18, 'Poland prohibits alcohol promotion — no loyalty perk here.'),
  for (final c in ['SA', 'KW', 'LY', 'IR', 'PK', 'BD', 'BN', 'MV', 'SD', 'SO', 'AF', 'YE']) c: _dry(),
};

/// Sub-national overrides, keyed `COUNTRY-REGION`.
Jurisdiction? _region(String key, Jurisdiction base) {
  switch (key) {
    case 'US-MA':
      return base.merge(allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false,
          note: 'Massachusetts restricts drink deals, so a perk here rewards visits with something non-alcoholic.');
    case 'US-UT':
      return base.merge(allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false,
          note: 'Utah restricts drink deals, so a perk here rewards visits with something non-alcoholic.');
    case 'GB-NIR':
      return base.merge(allowPerks: false, allowAlcoholReward: false, allowSpendPerk: false, allowOfftradePerks: false,
          note: 'Northern Ireland bans loyalty and membership rewards on alcohol in every licensed premises, so perks are off here.');
    case 'GB-SCT':
      return base.merge(allowOfftradePerks: false,
          note: "Scotland confines off-sales promotions to the alcohol display area, so a shop's loyalty card is off here.");
  }
  return null;
}

/// The rules for a place. An unknown place gets STRICT — never the permissive default.
Jurisdiction jurisdiction(String? country, [String? region]) {
  final c = (country ?? '').trim().toUpperCase();
  final r = (region ?? '').trim().toUpperCase();
  final base = jurisdictions[c];
  if (base == null) return strict;
  if (r.isEmpty) return base;
  return _region('$c-$r', base) ?? base;
}

/// Legal drinking age where you are. Unknown → 21, the strictest common bar.
int minDrinkingAge(String? country, [String? region]) => jurisdiction(country, region).minAge;

/// The countries we have actually researched — what the pickers offer.
const knownCountries = <(String, String)>[
  ('IN', 'India'),
  ('AE', 'United Arab Emirates'),
  ('AU', 'Australia'),
  ('BR', 'Brazil'),
  ('CA', 'Canada'),
  ('DE', 'Germany'),
  ('ES', 'Spain'),
  ('FI', 'Finland'),
  ('FR', 'France'),
  ('GB', 'United Kingdom'),
  ('IE', 'Ireland'),
  ('IT', 'Italy'),
  ('JP', 'Japan'),
  ('KR', 'South Korea'),
  ('MX', 'Mexico'),
  ('NL', 'Netherlands'),
  ('NO', 'Norway'),
  ('NZ', 'New Zealand'),
  ('PL', 'Poland'),
  ('SE', 'Sweden'),
  ('SG', 'Singapore'),
  ('TH', 'Thailand'),
  ('TR', 'Türkiye'),
  ('US', 'United States'),
  ('ZA', 'South Africa'),
];

String countryLabel(String? code) {
  for (final c in knownCountries) {
    if (c.$1 == code) return c.$2;
  }
  return code ?? '';
}
