// The venue app's pure logic: who may do what (checked against the migration itself),
// what kind of place is under which law, the web address, and reading the numbers
// without ever pointing at a person.
import 'dart:io';

import 'package:brewdiary_bar/data/models.dart';
import 'package:brewdiary_bar/logic/insights.dart';
import 'package:brewdiary_bar/logic/perk_rules.dart';
import 'package:brewdiary_bar/logic/roles.dart';
import 'package:brewdiary_bar/logic/slug.dart';
import 'package:brewdiary_bar/logic/venue_kinds.dart';
import 'package:brewdiary_bar/ui/shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('roles (parity with supabase/045_staff_roles.sql)', () {
    test('the seeded matrix is exactly the app\'s', () {
      final sql = File('../supabase/045_staff_roles.sql').readAsStringSync();
      final seeded = RegExp(r"^\s*\('([a-z]+)', '([a-z0-9_.]+)'\)[,;]", multiLine: true)
          .allMatches(sql)
          .map((m) => '${m[1]}:${m[2]}')
          .toList()
        ..sort();
      final mirror = [for (final r in StaffRole.values) for (final c in roleCaps[r]!) '${r.db}:${c.db}']..sort();
      expect(seeded.length, greaterThan(100));
      expect(mirror, seeded);
    });

    test('the kitchen and the door never touch a guest\'s tab, perks, card or notes', () {
      for (final r in [StaffRole.kitchen, StaffRole.host]) {
        for (final c in [Cap.recordSpend, Cap.redeemPerk, Cap.guestCard, Cap.guestNotes]) {
          expect(roleCan(r, c), isFalse, reason: '${r.db} ${c.db}');
        }
      }
    });

    test('nobody grants owner; a manager manages only the floor', () {
      for (final r in StaffRole.values) {
        expect(canGrant(r, StaffRole.owner), isFalse);
      }
      expect(canGrant(StaffRole.owner, StaffRole.manager), isTrue);
      expect(canGrant(StaffRole.manager, StaffRole.manager), isFalse);
      expect(grantable(StaffRole.manager), [StaffRole.supervisor, StaffRole.bartender, StaffRole.server, StaffRole.host, StaffRole.kitchen]);
      expect(grantable(StaffRole.server), isEmpty);
    });

    test('tabs follow the role', () {
      Venue as(StaffRole r, [VenueKind k = VenueKind.bar]) => Venue(id: 'v', name: 'V', slug: 'v', createdBy: 'o', kind: k, myRole: r);
      expect(tabsFor(as(StaffRole.owner)), [BarTab.service, BarTab.guests, BarTab.menu, BarTab.numbers, BarTab.more]);
      expect(tabsFor(as(StaffRole.server)), [BarTab.service, BarTab.guests, BarTab.more]);
      expect(tabsFor(as(StaffRole.kitchen)), [BarTab.menu, BarTab.more]);
      expect(tabsFor(as(StaffRole.host)), [BarTab.service, BarTab.more]);
      expect(tabLabel(BarTab.service, as(StaffRole.owner, VenueKind.sweetShop)), 'Till');
      expect(tabLabel(BarTab.menu, as(StaffRole.owner, VenueKind.store)), 'Shelf');
    });
  });

  group('what kind of place, under which law', () {
    test('it is what a place SELLS that matters', () {
      expect(legalClass(VenueKind.bar), LegalClass.onTrade);
      expect(legalClass(VenueKind.store), LegalClass.offTrade);
      expect(legalClass(VenueKind.sweetShop, servesAlcohol: true), LegalClass.noAlcohol, reason: 'a sweet shop never sells alcohol');
      expect(legalClass(VenueKind.cafe), LegalClass.noAlcohol);
      expect(legalClass(VenueKind.cafe, servesAlcohol: true), LegalClass.onTrade);
      expect(legalClass(VenueKind.restaurant, servesAlcohol: true), LegalClass.onTrade);
    });

    test('a counter runs no rooms', () {
      expect(VenueKind.values.where((k) => k.isCounter), [VenueKind.store, VenueKind.sweetShop, VenueKind.bakery, VenueKind.shop]);
    });

    test('a sweet shop\'s card is just a loyalty card — but only where we\'ve looked', () {
      final india = perkRules(VenueKind.sweetShop, country: 'IN');
      expect(india.allowed, isTrue);
      expect(india.spend, isFalse, reason: 'a counter\'s spend waits for the till');
      expect(india.alcoholReward, isFalse);
      final cafe = perkRules(VenueKind.cafe, country: 'IN');
      expect(cafe.allowed && cafe.spend, isTrue, reason: 'an unlicensed café may count spend');
      final thailand = perkRules(VenueKind.bakery, country: 'TH');
      expect(thailand.allowed, isTrue, reason: 'Thailand bans ALCOHOL promotions; a bakery card is not one');
      expect(perkRules(VenueKind.cafe, servesAlcohol: true, country: 'TH').allowed, isFalse);
      final unknown = perkRules(VenueKind.sweetShop, country: 'ZW');
      expect(unknown.allowed, isFalse, reason: 'deny by default');
    });

    test('a liquor store: visits only, never an alcoholic reward', () {
      final r = perkRules(VenueKind.store, country: 'IN');
      expect(r.allowed, isTrue);
      expect(r.spend, isFalse);
      expect(r.alcoholReward, isFalse);
      expect(perkRules(VenueKind.store, country: 'IE').allowed, isFalse, reason: 'Ireland: at a shop the visit is the sale');
    });

    test('a bar follows the jurisdiction', () {
      expect(perkRules(VenueKind.bar, country: 'IN').alcoholReward, isTrue);
      expect(perkRules(VenueKind.bar, country: 'GB').alcoholReward, isFalse);
      expect(perkRules(VenueKind.bar, country: 'TH').allowed, isFalse);
      expect(perkRules(VenueKind.club, country: 'US', region: 'MA').spend, isFalse);
    });
  });

  group('web address', () {
    test('slugify', () {
      expect(slugify('Café Noir & Co.'), 'cafe-noir-co');
      expect(slugify('  The Amber Room  '), 'the-amber-room');
      expect(isValidSlug(slugify('Mithai Mahal')), isTrue);
      expect(isValidSlug('a'), isFalse);
      expect(isValidSlug('-bad-'), isFalse);
      expect(slugify('x' * 60).length, 40);
    });
  });

  group('reading the numbers without pointing at anyone', () {
    test('a hidden split stays hidden — no return rate from a null', () {
      const hidden = VenueInsights(guests: 3, tabs: 3, takings: 3000);
      final r = readInsights(hidden);
      expect(r.returnRate, isNull);
      expect(r.averageTab, isNull, reason: 'an average over fewer than 5 tabs points at a person');
    });

    test('return rate and average tab once there are enough people', () {
      const ins = VenueInsights(guests: 20, newGuests: 5, returningGuests: 15, tabs: 10, takings: 25000);
      final r = readInsights(ins);
      expect(r.returnRate, 75);
      expect(r.averageTab, 2500);
    });

    test('busiest and quietest weekday (a day with no visits is "never open")', () {
      expect(peakDays([14, 6, 0, 9, 18, 36, 48]), (6, 1));
      expect(peakDays([0, 0, 0, 5, 0, 0, 0]), (3, null));
      expect(peakDays([1, 2, 3]), (null, null));
    });

    test('trend line', () {
      expect(trendLine(110, 100, 'the 30d before'), '+10% on the 30d before');
      expect(trendLine(90, 100, 'x'), '-10% on x');
      expect(trendLine(5, 0, 'x'), isNull);
    });
  });
}
