// Payroll (supabase/054): the CSV and the totals, held to the SAME fixture as the website's
// tests/payroll.test.ts — so the app and the dashboard export the same file byte for byte.
import 'dart:convert';
import 'dart:io';

import 'package:brewdiary_bar/data/models.dart';
import 'package:brewdiary_bar/logic/payroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fx = jsonDecode(File('../tests/fixtures/payroll.json').readAsStringSync()) as Map<String, dynamic>;
  final rows = [for (final r in fx['rows'] as List) PayrollDay.fromJson(Map<String, dynamic>.from(r as Map))];
  DateTime day(String s) {
    final d = DateTime.parse(s);
    return DateTime(d.year, d.month, d.day);
  }

  group('payroll export (parity with the website)', () {
    test('builds the fixture\'s CSV exactly', () {
      expect(
        payrollCsv(venue: fx['venue'] as String, currency: fx['currency'] as String, from: day(fx['from'] as String), to: day(fx['to'] as String), rows: rows),
        fx['csv'],
      );
    });

    test('totals per person, in name order, in whole paise', () {
      final people = payrollTotals(rows);
      expect(
        [
          for (final p in people)
            {
              'user_id': p.userId,
              'days_worked': p.daysWorked,
              'worked_minutes': p.workedMinutes,
              'planned_minutes': p.plannedMinutes,
              'pay_cents': p.payCents,
              'missing_rate': p.missingRate,
            },
        ],
        fx['totals'],
      );
      expect(payrollTotalCents(people), fx['team_pay_cents']);
    });

    test('hours read as hours', () {
      expect(hm(0), '0:00');
      expect(hm(425), '7:05');
      expect(hoursDecimal(425), '7.08');
      expect(hoursDecimal(1), '0.02');
      expect(hoursDecimal(30), '0.50');
    });

    test('a name can\'t run as a spreadsheet formula, and commas and quotes are escaped', () {
      expect(csvField('=SUM(A1)'), "'=SUM(A1)");
      expect(csvField('+91 98765'), "'+91 98765");
      expect(csvField('Sam "Ace", Jr'), '"Sam ""Ace"", Jr"');
      expect(csvField('Noor'), 'Noor');
    });

    test('the file opens in Excel with any script: UTF-8 with a byte-order mark', () {
      final bytes = payrollFileBytes('Name\nनूर\n');
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), 'Name\nनूर\n');
      expect(payrollFileName('The Amber Room!', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), 'payroll-the-amber-room-2026-09-01-to-2026-09-30.csv');
      expect(payrollFileName('मिठाई', DateTime(2026, 9, 1), DateTime(2026, 9, 1)), 'payroll-venue-2026-09-01-to-2026-09-01.csv');
    });
  });

  group('pay periods', () {
    final wed = DateTime(2026, 9, 30, 21, 15); // a Wednesday
    test('this week runs Monday to today — days still to come aren\'t paid for yet', () {
      expect(payPeriod(PayPeriod.thisWeek, wed), (DateTime(2026, 9, 28), DateTime(2026, 9, 30)));
    });
    test('last week is Monday to Sunday', () {
      expect(payPeriod(PayPeriod.lastWeek, wed), (DateTime(2026, 9, 21), DateTime(2026, 9, 27)));
    });
    test('months, including across a year end', () {
      expect(payPeriod(PayPeriod.thisMonth, wed), (DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
      expect(payPeriod(PayPeriod.lastMonth, wed), (DateTime(2026, 8, 1), DateTime(2026, 8, 31)));
      expect(payPeriod(PayPeriod.lastMonth, DateTime(2027, 1, 10)), (DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
      expect(payPeriod(PayPeriod.lastMonth, DateTime(2028, 3, 3)), (DateTime(2028, 2, 1), DateTime(2028, 2, 29)), reason: 'a leap year');
    });
    test('every period fits the database\'s 62-day limit', () {
      for (final p in PayPeriod.values) {
        final (a, b) = payPeriod(p, wed);
        expect(b.difference(a).inDays, lessThanOrEqualTo(62), reason: p.label);
        expect(b.isBefore(a), isFalse, reason: p.label);
      }
    });
  });
}
