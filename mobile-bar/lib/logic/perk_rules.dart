// What a venue's loyalty card may lawfully be — the mirror of venue_perks_guard()
// (supabase/030, widened for every kind of shop in 047). The database refuses an
// unlawful tier whatever the app says; this lets the screen explain the rule first.
import 'package:brewdiary_core/jurisdiction.dart';

import 'venue_kinds.dart';

class PerkRules {
  /// May this venue run a loyalty card at all?
  final bool allowed;

  /// May progress count money spent (not only visits)?
  final bool spend;

  /// May a reward be an alcoholic drink?
  final bool alcoholReward;

  /// The rule in one plain sentence, for the licensee.
  final String note;
  const PerkRules({required this.allowed, required this.spend, required this.alcoholReward, required this.note});
}

PerkRules perkRules(VenueKind kind, {bool servesAlcohol = false, required String country, String? region}) {
  final legal = legalClass(kind, servesAlcohol: servesAlcohol);
  final researched = jurisdictions.containsKey(country.toUpperCase());
  if (legal == LegalClass.noAlcohol) {
    // No alcohol is sold, so alcohol-promotion law has nothing to say about the card.
    // Still deny-by-default on the country: we operate only where we've looked.
    // A counter's spend has nowhere to be recorded until the till records it, so its
    // card counts visits for now (mirrors perkPolicy() in src/lib/perks.ts).
    return PerkRules(
      allowed: researched,
      spend: researched && !kind.isCounter,
      alcoholReward: false,
      note: researched
          ? 'No alcohol is sold here, so the card is just a loyalty card — any reward that isn\'t alcohol.'
          : 'We haven\'t researched this country yet, so loyalty cards are off here for now.',
    );
  }
  final j = jurisdiction(country, region);
  if (!j.alcoholLegal) {
    return PerkRules(allowed: false, spend: false, alcoholReward: false, note: j.note ?? 'Alcohol is prohibited here.');
  }
  if (legal == LegalClass.offTrade) {
    final ok = j.allowPerks && j.allowOfftradePerks;
    return PerkRules(
      allowed: ok,
      spend: false,
      alcoholReward: false,
      note: ok
          ? 'A liquor store\'s card counts visits — once a day — and its reward is never alcohol. Our rule, stricter than the law: at a shop the visit is the purchase.'
          : 'A loyalty card isn\'t permitted for a liquor store here — at a shop a visit is a purchase, so the card would be an alcohol loyalty scheme.',
    );
  }
  return PerkRules(
    allowed: j.allowPerks,
    spend: j.allowPerks && j.allowSpendPerk,
    alcoholReward: j.allowPerks && j.allowAlcoholReward,
    note: j.note ?? (j.allowAlcoholReward ? 'Perks can count visits or spend, and a reward may be a drink.' : 'Perks reward visits with something non-alcoholic.'),
  );
}
