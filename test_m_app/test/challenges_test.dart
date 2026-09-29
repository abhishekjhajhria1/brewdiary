// Parity with tests/challenges.test.ts — variety and consistency, never volume.
import 'package:brewdiary/data/circles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scores each kind from its own count', () {
    final r = <String, dynamic>{'total': 9, 'kinds': 4, 'dates': ['2026-09-01', '2026-09-02', '2026-09-04'], 'days_kept': 6, 'dry_nights': 2, 'new_drinks': 3, 'new_places': 1, 'water_days': 5};
    expect(scoreRow(ChallengeKind.mostLogged, r), 9);
    expect(scoreRow(ChallengeKind.mostKinds, r), 4);
    expect(scoreRow(ChallengeKind.longestStreak, r), greaterThanOrEqualTo(2));
    expect(scoreRow(ChallengeKind.daysKept, r), 6);
    expect(scoreRow(ChallengeKind.dryNights, r), 2);
    expect(scoreRow(ChallengeKind.newDrinks, r), 3);
    expect(scoreRow(ChallengeKind.newPlaces, r), 1);
    expect(scoreRow(ChallengeKind.hydration, r), 5);
    expect(scoreRow(ChallengeKind.freeform, r), 0);
  });

  test('db names match the web', () {
    expect(ChallengeKind.values.map((k) => k.db), ['most_logged', 'most_kinds', 'longest_streak', 'freeform', 'days_kept', 'dry_nights', 'new_drinks', 'new_places', 'hydration']);
    expect(scoredKinds.first, ChallengeKind.daysKept);
    expect(scoredKinds.last, ChallengeKind.mostLogged);
  });

  test('no preset can be won by drinking more', () {
    for (final p in challengePresets) {
      expect([ChallengeKind.mostLogged, ChallengeKind.mostKinds], isNot(contains(p.kind)));
      if (!p.kind.isFreeform) expect(p.kind.isV2, isTrue);
    }
  });
}
