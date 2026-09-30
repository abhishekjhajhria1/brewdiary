// The venue app's pure logic: who may do what (checked against the migration itself),
// what kind of place is under which law, the web address, and reading the numbers
// without ever pointing at a person.
import 'dart:io';

import 'package:brewdiary_bar/data/models.dart';
import 'package:brewdiary_bar/logic/area.dart';
import 'package:brewdiary_bar/logic/counter.dart';
import 'package:brewdiary_bar/logic/host_brief.dart';
import 'package:brewdiary_bar/logic/insights.dart';
import 'package:brewdiary_bar/logic/perk_rules.dart';
import 'package:brewdiary_bar/logic/roles.dart';
import 'package:brewdiary_bar/logic/service.dart';
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
      expect(tabsFor(as(StaffRole.kitchen)), [BarTab.service, BarTab.menu, BarTab.more]);
      expect(tabLabel(BarTab.service, as(StaffRole.kitchen)), 'Kitchen', reason: 'the kitchen lands on its tickets');
      expect(tabLabel(BarTab.service, as(StaffRole.server)), 'Floor');
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

  group('the area heat map, read', () {
    const rows = [
      HeatRow('tdr1v', 'people', '', 25),
      HeatRow('tdr1v', 'persona', 'coffee_tea', 10),
      HeatRow('tdr1v', 'persona', 'zero_proof', 5),
      HeatRow('tdr1v', 'taste', 'coffee', 15),
      HeatRow('tdr1v', 'hours', 'evening', 15),
      HeatRow('tdr1v', 'spend', '1000', 25),
      HeatRow('tdr1y', 'people', '', 40),
      HeatRow('tdr1y', 'persona', 'coffee_tea', 20),
      HeatRow('tdr1y', 'hours', 'evening', 20),
      HeatRow('tdr1y', 'hours', 'late', 5),
    ];

    test('rows fold into neighbourhoods', () {
      final m = readMap(rows);
      expect(m.keys, {'tdr1v', 'tdr1y'});
      expect(m['tdr1v']!.people, 25);
      expect(m['tdr1v']!.topPersona, 'coffee_tea');
      expect(m['tdr1v']!.spendFloor, 1000);
      expect(m['tdr1y']!.spendFloor, isNull);
    });

    test('the guide talks about crowds, in plain words', () {
      final g = areaGuide(venueCell: 'tdr1v9', cells: readMap(rows), currency: 'INR', sellsAlcohol: true, sharing: true);
      expect(g.first, 'Busiest: ~5 km east — 40+ people went out there.');
      expect(g, contains('Your own neighbourhood: 25+ people.'));
      expect(g, contains('Coffee & tea people lead in 2 of 2 neighbourhoods.'));
      expect(g, contains('Most people go out in the evening (5–9 pm).'));
      expect(g.any((l) => l.contains('₹1,000+')), isTrue);
      expect(g.any((l) => l.contains('coffee menu')), isTrue, reason: 'a fit suggestion, never "more"');
    });

    test('no spend for a venue that doesn\'t share, and nothing that means "more"', () {
      final g = areaGuide(venueCell: 'tdr1v9', cells: readMap(rows), currency: 'INR', sellsAlcohol: true, sharing: false);
      expect(g.any((l) => l.contains('₹')), isFalse);
      for (final l in g) {
        expect(l.toLowerCase(), isNot(matches(RegExp(r'another round|drink more|upsell|happy hour'))));
      }
    });

    test('an empty map explains itself', () {
      final g = areaGuide(venueCell: 'tdr1v9', cells: const {}, currency: 'INR', sellsAlcohol: true, sharing: true);
      expect(g.single, contains('5 people who said yes'));
    });

    test('hours are read on the venue\'s clock', () {
      expect(venueTimeZone('IN', 'KA'), 'Asia/Kolkata');
      expect(venueTimeZone('US', 'NY'), 'America/New_York');
      expect(venueTimeZone('US', 'CA'), 'America/Los_Angeles');
      expect(venueTimeZone('ZZ', null), 'UTC');
    });

    test('spend reads as a band, never a figure', () {
      expect(spendWords(1000, 'INR'), '₹1,000+');
      expect(spendWords(0, 'INR'), 'under ₹500');
    });
  });

  group('Ninkasi for hosts (the same cases as tests/hostAdvisor.test.ts)', () {
    final brief = HostBrief(
      venueName: 'The Amber Room',
      kind: 'bar',
      role: 'server',
      sellsAlcohol: true,
      counter: false,
      today: DateTime(2026, 10, 1),
      roomOpen: true,
      guestsIn: 6,
      quietTonight: true,
      soldOut: const ['Negroni'],
      alcoholFree: const ['Kokum Cooler'],
      menuItems: 5,
      perks: const [(reward: 'A coffee on us', at: '3 visits')],
      signals: [
        (kind: 'holiday', title: 'Dry day: Gandhi Jayanti', startsOn: DateTime(2026, 10, 2), endsOn: null, where: ''),
        (kind: 'event', title: 'Dussehra fair', startsOn: DateTime(2026, 10, 3), endsOn: DateTime(2026, 10, 5), where: '~5 km east'),
        (kind: 'price', title: 'A craft pint nearby costs ₹350–450', startsOn: null, endsOn: null, where: ''),
      ],
      area: const ['Busiest: your own neighbourhood — 45+ people went out there.'],
    );

    test('briefs the shift, most urgent first', () {
      expect(hostBriefing(brief), [
        'Tomorrow is a dry day (Dry day: Gandhi Jayanti) — let regulars know tonight.',
        'Tonight\'s room is open, 6 guests in.',
        'It\'s a quiet night: a visit counts double toward the card. Worth a word to regulars — it\'s a visit, not a drink, that counts.',
        '86\'d: Negroni. Say so before they order.',
        'Alcohol-free tonight: Kokum Cooler. Offer one with every recommendation.',
        'Around you: Dussehra fair (on Saturday, ~5 km east).',
        'Busiest: your own neighbourhood — 45+ people went out there.',
        'Water is free and on every table. If someone\'s had enough, stop serving alcohol, offer water and food, and get the manager.',
      ]);
    });

    test('on the dry day itself, the law comes first', () {
      final today = HostBrief(venueName: 'x', kind: 'bar', role: 'server', sellsAlcohol: true, counter: false, today: DateTime(2026, 10, 2), signals: brief.signals);
      expect(hostBriefing(today).first, 'Today is a dry day (Dry day: Gandhi Jayanti): no alcohol may be sold. Lead with the alcohol-free list.');
    });

    test('a counter that sells no alcohol gets a till line and nothing about drinking', () {
      final shop = HostBrief(venueName: 'Mithai Mahal', kind: 'sweet_shop', role: 'manager', sellsAlcohol: false, counter: true, today: DateTime(2026, 10, 1));
      final lines = hostBriefing(shop);
      expect(lines.first, 'The till is ready — punch cards once a day per guest.');
      expect(lines.join(' ').toLowerCase(), isNot(contains('alcohol')));
    });

    test('answers the hard question the same way every time', () {
      expect(hostFallbackAnswer(brief, 'Someone\'s had enough — what do I do?'), startsWith('Stop serving them alcohol'));
      expect(hostFallbackAnswer(brief, 'How do I explain the loyalty card?'), contains('never how much anyone drinks'));
    });

    test('the wire shape carries counts and titles, never a guest', () {
      final j = brief.toJson();
      expect(j['today'], '2026-10-01');
      expect(j['guestsIn'], 6);
      expect(j.toString(), isNot(contains('Anita')));
    });
  });

  group('the counter: the same sums as ring_sale()', () {
    const whisky = ShopProduct(id: 'w', name: 'Single Malt', category: 'spirit', size: 750, unit: 'ml', price: 3400, mrp: 3500);
    const tonic = ShopProduct(id: 't', name: 'Tonic', category: 'soft', price: 60);
    const kaju = ShopProduct(id: 'k', name: 'Kaju Katli', category: 'sweet', unit: 'g', byWeight: true, price: 1200);
    const open = SaleStatus(researched: true, allowedNow: true, minAge: 21, maxMl: 2250);

    test('units stack, weights replace, and the total matches the server', () {
      final b = const Basket().add(whisky).add(whisky).add(tonic).add(kaju, 250).add(kaju, 500);
      expect(b.lines.map((l) => l.qty), [2, 1, 500]);
      expect(b.total, 3400 * 2 + 60 + 600);
      expect(b.alcoholMl, 1500);
      expect(b.toLines().first, {'product': 'w', 'qty': 2}, reason: 'what and how many — never a price');
      expect(b.set('w', 0).hasAlcohol, isFalse);
    });

    test('the till explains the law before the server refuses', () {
      final one = const Basket().add(whisky);
      expect(basketBlock(const Basket(), open, idChecked: false), 'Add something first.');
      expect(basketBlock(const Basket().add(tonic), null, idChecked: false), isNull, reason: 'no alcohol, no rule to wait for');
      expect(basketBlock(one, open, idChecked: false), 'Check ID first: 21 or over.');
      expect(basketBlock(one, open, idChecked: true), isNull);
      expect(basketBlock(one.set('w', 4), open, idChecked: true), 'Over the per-sale limit here (2250 ml).');
      const dry = SaleStatus(researched: true, allowedNow: false, reason: 'Dry day: Gandhi Jayanti — no alcohol may be sold today.');
      expect(basketBlock(one, dry, idChecked: true), startsWith('Dry day'));
      const unknown = SaleStatus(researched: false, allowedNow: false, reason: 'We haven\'t researched the retail alcohol rules here yet.');
      expect(basketBlock(one, unknown, idChecked: true), startsWith('We haven\'t researched'));
    });

    test('the excise register exports as CSV', () {
      final csv = registerCsv([RegisterRow(day: DateTime(2026, 10, 1), productId: 'w', name: 'Single Malt', brand: 'Amrut', size: 750, opening: 12, received: 0, sold: 1, other: 0, closing: 11)]);
      expect(csv, 'date,brand,product,size_ml,opening,received,sold,other,closing\n2026-10-01,Amrut,Single Malt,750,12,0,1,0,11');
    });
  });

  group('the door', () {
    test('tonight starts at 6 in the morning, so a night past midnight is one night', () {
      expect(nightStart(DateTime(2026, 10, 2, 1, 30)), DateTime(2026, 10, 1, 6));
      expect(nightStart(DateTime(2026, 10, 1, 20)), DateTime(2026, 10, 1, 6));
      expect(nightStart(DateTime(2026, 10, 1, 6)), DateTime(2026, 10, 1, 6));
    });

    test('amber from 90%, red at full, and it says how many are over', () {
      expect(doorState(50, 120), DoorState.open);
      expect(doorState(108, 120), DoorState.nearly);
      expect(doorState(120, 120), DoorState.full);
      expect(doorState(9, null), DoorState.open);
      expect(doorStateWord(DoorState.open, 22, 120), '98 more can come in');
      expect(doorStateWord(DoorState.nearly, 110, 120), 'nearly full — 10 more');
      expect(doorStateWord(DoorState.full, 120, 120), 'full — hold the door');
      expect(doorStateWord(DoorState.full, 123, 120), '3 over — hold the door');
      expect(doorStateWord(DoorState.open, 9, null), 'counting');
    });
  });

  group('service: the same sums as close_tab()', () {
    final now = DateTime(2026, 10, 1, 20, 0);
    OrderLine l(String id, String tab, double price, int qty, {String status = 'sent', String station = 'bar', int ago = 0, String? table}) =>
        OrderLine(id: id, tabId: tab, name: id, unitPrice: price, qty: qty, status: status, station: station, createdAt: now.subtract(Duration(minutes: ago)), tableLabel: table);

    test('a void never counts toward the bill', () {
      expect(tabTotal([l('a', 't', 320, 2), l('b', 't', 450, 1), l('c', 't', 90, 1, status: 'void')]), 1090);
    });

    test('an even split adds up to the paisa', () {
      expect(splitEven(1000, 3), [333.33, 333.33, 333.34]);
      expect(splitEven(1000, 3).reduce((a, b) => a + b), closeTo(1000, 1e-9));
      expect(splitEven(1090, 1), [1090]);
    });

    test('a table at a glance: asking beats ready beats seated', () {
      const t = VenueTable(id: 'x', label: 'T1', code: 'abcdefgh');
      final tab = ServiceTab(id: 'tab', tableId: 'x', openedAt: now);
      expect(tableState(t, const [], const {}, const []), TableState.free);
      expect(tableState(t, [tab], {'tab': [l('a', 'tab', 100, 1)]}, const []), TableState.open);
      expect(tableState(t, [tab], {'tab': [l('a', 'tab', 100, 1, status: 'ready')]}, const []), TableState.ready);
      expect(tableState(t, [tab], {'tab': [l('a', 'tab', 100, 1, status: 'ready')]}, [InboxItem(kind: 'call', id: 'c', tableId: 'x', tableLabel: 'T1', createdAt: now)]), TableState.attention);
    });

    test('tickets group by tab, oldest first, and run late by station', () {
      final ts = tickets([l('a', 't2', 1, 1, ago: 5, table: 'T2'), l('b', 't1', 1, 1, ago: 20, table: 'T1'), l('c', 't2', 1, 1, ago: 3, table: 'T2')]);
      expect(ts.map((t) => t.where), ['T1', 'T2']);
      expect(ts.last.lines.length, 2);
      expect(lateness('bar', 5), 0);
      expect(lateness('bar', 12), 2);
      expect(lateness('kitchen', 12), 0, reason: 'a kitchen gets longer than a bar');
      expect(lateness('kitchen', 30), 2);
      expect(nextStationStatus('sent'), 'preparing');
      expect(nextStationStatus('preparing'), 'ready');
      expect(nextStationStatus('ready'), isNull);
    });

    test('the shared bill: lines, total, how it was paid', () {
      final text = billText(venue: 'The Amber Room', where: 'T2', currency: 'INR', lines: [l('Negroni', 't', 450, 2), l('Fries', 't', 260, 1, status: 'void')], payments: const [{'method': 'UPI', 'amount': 900}]);
      expect(text, contains('2 × Negroni  ₹900'));
      expect(text, isNot(contains('Fries')));
      expect(text, contains('Total  ₹900'));
      expect(text, contains('Paid by UPI  ₹900'));
    });
  });
}
