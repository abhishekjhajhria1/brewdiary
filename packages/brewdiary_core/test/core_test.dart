// Parity tests — ported from the web app's vitest suite (tests/*.test.ts) so the
// Dart logic is proven to behave exactly like src/lib.
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/drinks.dart';
import 'package:brewdiary_core/handles.dart';
import 'package:brewdiary_core/jurisdiction.dart';
import 'package:brewdiary_core/misc.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import 'package:test/test.dart';

var _seq = 0;
Entry entry({String date = '2026-07-09', String? createdAt, String drink = 'Negroni', DrinkType? type, String? mood}) {
  _seq++;
  return Entry(
    id: 'e$_seq',
    date: date,
    createdAt: createdAt ?? DateTime(2026, 7, 9, 20).toUtc().toIso8601String(),
    drink: drink,
    type: type,
    mood: mood,
  );
}

String dayBack(int n) => toKey(addDays(DateTime.now(), -n));
String day(int offset) => toKey(addDays(DateTime.now(), offset));

void main() {
  group('date', () {
    test('toKey/parseKey round-trip in local time', () {
      expect(toKey(DateTime(2026, 7, 9)), '2026-07-09');
      expect(parseKey('2026-07-09'), DateTime(2026, 7, 9));
    });
    test('monthGrid is Monday-first, 42 days, covers the month', () {
      final g = monthGrid(2026, 6); // July 2026 (0-based month)
      expect(g.length, 42);
      expect(mondayIndex(g.first.date), 0);
      expect(g.where((d) => d.inMonth).length, 31);
    });
    test('timeOfDayLabel buckets', () {
      expect(timeOfDayLabel(DateTime(2026, 1, 1, 8).toIso8601String()), 'Morning');
      expect(timeOfDayLabel(DateTime(2026, 1, 1, 23).toIso8601String()), 'Nightcap');
      expect(timeOfDayLabel(DateTime(2026, 1, 1, 3).toIso8601String()), 'Late night');
    });
  });

  group('derive', () {
    test('intensityLevel buckets 0..4', () {
      expect([0, 1, 2, 3, 9].map(intensityLevel).toList(), [0, 1, 2, 3, 4]);
    });
    test('countsByDate counts multiple entries per day', () {
      final c = countsByDate([entry(date: '2026-07-09'), entry(date: '2026-07-09'), entry(date: '2026-07-08')]);
      expect(c['2026-07-09'], 2);
      expect(c['2026-07-08'], 1);
    });
    test('currentStreak counts back from today', () {
      expect(currentStreak(countsByDate([entry(date: dayBack(0)), entry(date: dayBack(1)), entry(date: dayBack(2))])), 3);
    });
    test('an empty today does not break the streak', () {
      expect(currentStreak(countsByDate([entry(date: dayBack(1)), entry(date: dayBack(2))])), 2);
    });
    test('forgives one missed day, two in a row end it', () {
      expect(currentStreak(countsByDate([entry(date: dayBack(0)), entry(date: dayBack(2))])), 2);
    });
    test('grace replenishes', () {
      expect(currentStreak(countsByDate([entry(date: dayBack(0)), entry(date: dayBack(2)), entry(date: dayBack(4))])), 3);
    });
    test('streaks are 0 with no entries', () {
      expect(currentStreak({}), 0);
      expect(longestStreak({}), 0);
    });
    test('longestStreak bridges a single gap', () {
      final c = countsByDate([
        entry(date: '2026-06-01'),
        entry(date: '2026-06-02'),
        entry(date: '2026-06-04'),
        entry(date: '2026-06-05'),
      ]);
      expect(longestStreak(c), 4);
    });
    test('longestStreak: isolated gaps bridge, a double gap breaks', () {
      final c = countsByDate([
        entry(date: '2026-06-01'),
        entry(date: '2026-06-02'),
        entry(date: '2026-06-04'),
        entry(date: '2026-06-06'),
        entry(date: '2026-06-09'),
      ]);
      expect(longestStreak(c), 4);
    });
    test('milestoneProgress', () {
      expect(milestoneProgress(0), (reached: null, next: 10));
      expect(milestoneProgress(10), (reached: 10, next: 25));
      expect(milestoneProgress(600), (reached: 500, next: null));
    });
    test('lexicon: distinct moods by frequency then alpha', () {
      final lex = lexicon([entry(mood: 'cozy'), entry(mood: 'Cozy'), entry(mood: 'happy'), entry(mood: ' ')]);
      expect(lex, [const MoodWord('cozy', 2), const MoodWord('happy', 1)]);
    });
    test('recentDrinks ranks by frequency keeping most-recent casing', () {
      final d = recentDrinks([
        entry(drink: 'Negroni', createdAt: '2026-07-01T20:00:00Z'),
        entry(drink: 'negroni', createdAt: '2026-07-02T20:00:00Z'),
        entry(drink: 'Cortado', createdAt: '2026-07-03T20:00:00Z'),
      ]);
      expect(d.first, 'negroni');
      expect(d, contains('Cortado'));
    });
    test('friendPicks ranks by distinct friends and excludes mine/saved', () {
      final fd = [
        (drink: 'Negroni', author: 'A'),
        (drink: 'negroni', author: 'B'),
        (drink: 'Martini', author: 'A'),
        (drink: 'Cortado', author: 'A'),
        (drink: 'Mezcal', author: 'C'),
      ];
      expect(friendPicks(fd, ['cortado'], ['mezcal']), ['Negroni', 'Martini']);
      expect(friendPicks(fd, [], [], 1), ['Negroni']);
    });
    test('stats totals and distinct kinds', () {
      final s = stats([entry(drink: 'Negroni'), entry(drink: 'negroni'), entry(drink: 'Cortado')]);
      expect(s.total, 3);
      expect(s.kinds, 2);
    });
  });

  group('dry days', () {
    Entry dry(String d) => entry(date: d, drink: dryDayLabel, type: DrinkType.none);
    Entry drink(String d, [String name = 'negroni']) => entry(date: d, drink: name);

    test('identified by type, not name', () {
      expect(isDryDay(dry(day(0))), isTrue);
      expect(isDryDay(drink(day(0))), isFalse);
      expect(isDryDay(entry(date: day(0), drink: 'dry day', type: DrinkType.cocktail)), isFalse);
    });
    test('KEEPS the streak', () {
      final es = [drink(day(0)), dry(day(-1)), drink(day(-2)), dry(day(-3))];
      expect(currentStreak(loggedDates(es)), 4);
    });
    test('does not shade the mosaic', () {
      final es = [drink(day(0)), dry(day(-1))];
      expect(countsByDate(es)[day(-1)], isNull);
      expect(countsByDate(es)[day(0)], 1);
      expect(loggedDates(es)[day(-1)], 1);
    });
    test('reported as its own thing, never as a drink', () {
      final es = [drink(day(0)), dry(day(-1)), drink(day(-2), 'cortado')];
      final s = stats(es);
      expect(s.total, 2);
      expect(s.kinds, 2);
      expect(s.dry, 1);
      expect(s.current, 3);
    });
    test('never in suggestions or the year review', () {
      final es = [drink(day(0)), dry(day(-1)), dry(day(-2))];
      expect(recentDrinks(es), ['negroni']);
      final yr = yearReview(es);
      expect(yr.total, 1);
      expect(yr.topDrink, 'negroni');
    });
    test('exposed for the calendar marker', () {
      final es = [drink(day(0)), dry(day(-1))];
      expect(dryDates(es).contains(day(-1)), isTrue);
      expect(dryDates(es).contains(day(0)), isFalse);
      expect(drinkEntries(es).length, 1);
    });
  });

  group('balance', () {
    test('isAlcoholic trusts tag, infers from name, never guesses unknowns', () {
      expect(isAlcoholic('mystery', DrinkType.beer), isTrue);
      expect(isAlcoholic('mystery', DrinkType.coffee), isFalse);
      expect(isAlcoholic('IPA', null), isTrue);
      expect(isAlcoholic('Negroni', null), isTrue);
      expect(isAlcoholic('Flat White', null), isFalse);
      expect(isAlcoholic("grandma's kombucha experiment", null), isFalse);
      expect(isAlcoholic('', null), isFalse);
    });
    test('weekBalance counts a rolling 7 days', () {
      const today = '2026-07-14';
      final es = [
        entry(date: '2026-07-14', drink: 'IPA'),
        entry(date: '2026-07-12', drink: 'Negroni'),
        entry(date: '2026-07-12', drink: 'Negroni'),
        entry(date: '2026-07-01', drink: 'IPA'), // outside window
        entry(date: '2026-07-13', drink: 'Flat White'),
      ];
      final b = weekBalance(es, today);
      expect(b.drinks, 3);
      expect(b.dryDays, 5);
      expect(weekBalance([], today).dryDays, 7);
    });
  });

  group('drinks', () {
    test('normalize', () {
      expect(normalize('  Flat-White '), 'flat white');
      expect(normalize('Rosé'), 'rose');
      expect(normalize('G&T'), 'g t');
    });
    test('similarity', () {
      expect(similarity('Flat White', 'flat-white'), 1);
      expect(similarity('cappuccino', 'cappucino'), greaterThan(0.85));
      expect(similarity('espresso', 'chamomile'), lessThan(0.4));
    });
    test('canonicalize alias, typo, family, novel', () {
      final a = canonicalize('flatwhite');
      expect(a.matched, isTrue);
      expect(a.canonical, 'Flat White');
      expect(a.type, DrinkType.coffee);
      expect(canonicalize('cappucino').canonical, 'Cappuccino');
      expect(drinkFamily('Negroni Sbagliato'), 'Negroni');
      expect(drinkFamily('Boulevardier'), 'Negroni');
      expect(drinkFamily('West Coast IPA'), 'IPA');
      final n = canonicalize('Homebrew kvass #3');
      expect(n.matched, isFalse);
      expect(n.canonical, 'Homebrew kvass #3');
    });
    test('suggestDrinks', () {
      final out = suggestDrinks('neg', ['Negroni night special']);
      expect(out.first, 'Negroni night special');
      expect(out, contains('Negroni'));
      expect(suggestDrinks('Negroni', ['Negroni']), isNot(contains('Negroni')));
      expect(suggestDrinks('', []), isEmpty);
    });
  });

  group('money', () {
    test('currencyForCountry', () {
      expect(currencyForCountry('GB'), 'GBP');
      expect(currencyForCountry('gb'), 'GBP');
      expect(currencyForCountry('ZZ'), defaultCurrency);
      expect(currencyForCountry(null), defaultCurrency);
    });
    test('formatMoney symbols + lakh grouping', () {
      expect(formatMoney(3000, 'GBP'), contains('£'));
      expect(formatMoney(3000, 'EUR'), contains('€'));
      expect(formatMoney(3000, 'GBP'), isNot(contains('₹')));
      expect(formatMoney(123456, 'INR'), '₹1,23,456');
      expect(formatMoney(123456, 'USD'), r'$123,456');
      expect(formatMoney(3000, 'JPY'), isNot(contains('.')));
      expect(formatMoney(100, 'INR'), '₹100');
      expect(formatMoney(100.5, 'INR'), '₹100.50');
      expect(formatMoney(100.5, 'INR', true), '₹101');
      expect(formatMoney(42, 'NOTACURRENCY'), '42');
      expect(currencySymbol('GBP'), '£');
      expect(currencySymbol('INR'), '₹');
    });
    test('spendBand never reveals the figure', () {
      expect(spendBand(2340, 'INR'), '₹1,000+');
      expect(spendBand(999, 'INR'), '₹500+');
      expect(spendBand(4999, 'INR'), '₹2,500+');
      expect(spendBand(2000, 'INR'), spendBand(2499, 'INR'));
      expect(spendBand(140, 'USD'), r'$125+');
      expect(spendBand(60, 'GBP'), '£50+');
      expect(spendBand(300, 'INR'), 'under ₹500');
      expect(spendBand(double.nan, 'INR'), 'under ₹500');
      expect(spendBand(1200, 'ZZZ'), endsWith('+'));
    });
  });

  group('jurisdiction', () {
    test('deny by default', () {
      expect(jurisdiction('ZZ').allowPerks, isFalse);
      expect(minDrinkingAge('ZZ'), 21);
      expect(minDrinkingAge(null), 21);
    });
    test('real ages', () {
      expect(minDrinkingAge('US'), 21);
      expect(minDrinkingAge('DE'), 18);
      expect(minDrinkingAge('JP'), 20);
      expect(minDrinkingAge('KR'), 19);
    });
    test('regions override', () {
      expect(jurisdiction('GB', 'NIR').allowPerks, isFalse);
      expect(jurisdiction('GB').allowPerks, isTrue);
      expect(jurisdiction('US', 'MA').allowAlcoholReward, isFalse);
    });
  });

  group('handles', () {
    test('slugName', () {
      expect(slugName('Sekhi Gill!'), 'sekhigill');
      expect(slugName('anita.roy_92'), 'anitaroy92');
      expect(slugName('a' * 40).length, 14);
      expect(slugName(''), 'guest');
      expect(slugName('你好'), 'guest');
    });
    test('coolHandle shape per attempt', () {
      expect(coolHandle('sekhi'), matches(RegExp(r'^sekhi_[a-z]+$')));
      expect(coolHandle('sekhi', attempt: 2), matches(RegExp(r'^sekhi_[a-z]+\d{2}$')));
      expect(coolHandle('sekhi', attempt: 6), matches(RegExp(r'^sekhi_[a-z]+\d{6}$')));
    });
    test('never auto-assigns a brand at sign-up', () {
      const brands = ['ferrari', 'bacardi', 'gucci', 'tesla', 'absolut', 'rolex'];
      for (var i = 0; i < 500; i++) {
        expect(brands, isNot(contains(coolHandle('sekhi').split('_')[1])));
      }
    });
    test('reroll keeps the base and changes the handle', () {
      expect(handleBase('sekhi_geeas2'), 'sekhi');
      expect(handleBase('solo'), 'solo');
      for (var i = 0; i < 50; i++) {
        final cur = coolHandle('sekhi');
        expect(reroll(cur), isNot(cur));
      }
      expect(reroll('raj_ember', attempt: 2), matches(RegExp(r'^raj_[a-z]+\d{2}$')));
    });
  });

  group('split', () {
    Expense exp(String payer, List<(String, double)> shares) => Expense(
          id: 'x${_seq++}',
          payerId: payer,
          description: 'd',
          amount: shares.fold(0, (a, s) => a + s.$2),
          createdAt: '2026-07-01',
          shares: shares.map((s) => ExpenseShare(s.$1, s.$2)).toList(),
        );
    test('positive = they owe me', () {
      final b = computeBalances([exp('me', [('me', 40), ('A', 30), ('B', 30)])], [], 'me');
      expect(b['A'], 30);
      expect(b.containsKey('me'), isFalse);
    });
    test('negative = I owe the payer; nets; settlements drop to zero', () {
      final es = [exp('me', [('me', 40), ('A', 30), ('B', 30)]), exp('A', [('A', 50), ('me', 50)])];
      expect(computeBalances(es, [], 'me')['A'], -20);
      final b = computeBalances(es, [const Settlement(id: 's', fromId: 'me', toId: 'A', amount: 20, createdAt: '')], 'me');
      expect(b.containsKey('A'), isFalse);
      expect(b['B'], 30);
    });
    test('splitEvenly sums to the total', () {
      final parts = splitEvenly(100, 3);
      expect(parts.fold<double>(0, (a, b) => a + b), closeTo(100, 0.001));
    });
  });

  group('misc', () {
    test('dedupeTags', () {
      expect(dedupeTags([' Chill ', 'chill', 'Late']), ['chill', 'late']);
      expect(dedupeTags(List.generate(20, (i) => 't$i')).length, 8);
    });
    test('longestRun', () {
      expect(longestRun(['2026-01-01', '2026-01-02', '2026-01-04']), 2);
      expect(longestRun([]), 0);
    });
    test('trust tops out at established without a strong signal', () {
      expect(trustLevelFrom(const TrustSignals(tenureDays: 400, activeDays: 400, friends: 50)), TrustLevel.established);
      expect(trustLevelFrom(const TrustSignals(tenureDays: 400, activeDays: 400, friends: 50, presenceChecked: true)), TrustLevel.trusted);
      expect(trustLevelFrom(const TrustSignals(tenureDays: 0, activeDays: 0, friends: 0)), TrustLevel.fresh);
    });
    test('geohash', () {
      expect(encodeGeohash(12.9716, 77.5946, 4).length, 4);
      expect(encodeGeohash(57.64911, 10.40744, 6), 'u4pruy');
    });
    test('formatVolume + ageFrom', () {
      expect(formatVolume(750), '750 ml');
      expect(formatVolume(1500), '1.5 L');
      expect(ageFrom(DateTime(2000, 6, 15), DateTime(2026, 6, 14)), 25);
      expect(ageFrom(DateTime(2000, 6, 15), DateTime(2026, 6, 15)), 26);
    });
  });

  group('tasteProfile (parity with tests/derive.test.ts)', () {
    final t = todayKey();
    Entry e(String drink, [DrinkType? type, String? mood, String? date]) => entry(drink: drink, type: type, mood: mood, date: date ?? t);

    test('favourites are families you came back to, most first', () {
      final p = tasteProfile([e('Negroni'), e('Boulevardier'), e('negroni'), e('IPA', DrinkType.beer), e('Hazy IPA', DrinkType.beer), e('Pinot Noir')]);
      expect(p.favourites, ['Negroni', 'IPA']);
      expect(p.kinds.first, DrinkType.cocktail);
      expect(p.basedOn, 6);
    });

    test('counts alcohol-free drinks, ignores dry days, and forgets the old diary', () {
      final old = toKey(addDays(parseKey(t), -400));
      final p = tasteProfile([
        e('Flat white', DrinkType.coffee, 'cozy'), e('Flat white', DrinkType.coffee, 'cozy'), e('Negroni', null, 'bright'),
        e('dry day', DrinkType.none), e('Negroni', null, null, old),
      ]);
      expect(p.basedOn, 3);
      expect(p.noAlcoholShare, closeTo(2 / 3, 1e-9));
      expect(p.moods, ['cozy', 'bright']);
      expect(p.favourites, ['Flat White']);
    });

    test('an empty diary is an empty card', () {
      final p = tasteProfile([]);
      expect([p.favourites, p.kinds, p.moods, p.noAlcoholShare, p.basedOn], [isEmpty, isEmpty, isEmpty, 0, 0]);
    });
  });

  group('passport (parity with tests/derive.test.ts)', () {
    Entry e(String drink, String date, [String? venue, DrinkType? type]) => Entry(id: 'p${_seq++}', date: date, createdAt: '${date}T20:00:00Z', drink: drink, venue: venue, type: type);

    test('one stamp per place, dated by the first visit, newest first', () {
      final p = passport([
        e('Negroni', '2026-09-01', 'Soka'),
        e('Negroni', '2026-09-10', 'soka '),
        e('Negroni', '2026-09-12', 'Soka'),
        e('IPA', '2026-08-20', 'Toit', DrinkType.beer),
        e('Flat white', '2026-09-05', 'Blue Tokai', DrinkType.coffee),
      ]);
      expect(p.stamps.map((s) => (s.place, s.date)), [('Blue Tokai', '2026-09-05'), ('Soka', '2026-09-01'), ('Toit', '2026-08-20')]);
      expect([p.places, p.kinds, p.families, p.since], [3, 3, 3, '2026-08-20']);
    });

    test('a dry night is a stamp of its own, not a kind', () {
      final p = passport([e('dry day', '2026-09-02', null, DrinkType.none), e('dry day', '2026-09-03', null, DrinkType.none)]);
      expect([p.dryNights, p.kinds], [2, 0]);
    });

    test('an empty diary is an empty passport', () {
      final p = passport([]);
      expect([p.stamps, p.places, p.kinds, p.families, p.dryNights, p.since], [isEmpty, 0, 0, 0, 0, null]);
    });
  });
}
