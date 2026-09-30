// Payroll (supabase/054): turn payroll_days() rows into the CSV an accountant opens, and
// the per-person totals the screen shows. Twinned with src/lib/payroll.ts; both are held
// to one fixture (tests/fixtures/payroll.json), so the app and the website export the
// same file byte for byte.
//
// Money is added up in whole paise (cents), never as floating point. People are in NAME
// order — payroll is for pay, never a ranking. brewdiary reports hours and rates; overtime,
// tax and statutory deductions are the payroll provider's.
import 'dart:convert';

import '../data/models.dart';
import 'staff.dart' show weekStart;

/// Minutes as h:mm — "7:05", "0:45".
String hm(int minutes) {
  final m = minutes < 0 ? 0 : minutes;
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Minutes as decimal hours with two places, rounded half up: 425 → "7.08".
String hoursDecimal(int minutes) {
  final hundredths = ((minutes < 0 ? 0 : minutes) * 100 + 30) ~/ 60;
  return _cents(hundredths);
}

int _toCents(double v) => (v * 100).round();

String _cents(int c) {
  final neg = c < 0;
  final a = c.abs();
  return '${neg ? '-' : ''}${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One CSV field: quoted when it holds a comma, quote or line break; text that a
/// spreadsheet would run as a formula (=, +, -, @) is defused with a leading apostrophe.
String csvField(String v) {
  var s = v;
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

String _row(List<String> fields) => fields.map(csvField).join(',');

String _notes(PayrollDay r) => [
      if (r.corrected) 'corrected',
      if (r.stillOn) 'still on',
      if (r.workedMinutes == 0 && r.plannedMinutes > 0) 'planned, not worked',
      if (r.workedMinutes > 0 && r.pay == null) 'no rate',
    ].join('; ');

/// One person's totals over the period.
class PayrollPerson {
  final String userId;
  final String name;
  final String role;
  final int daysWorked;
  final int workedMinutes;
  final int plannedMinutes;
  final int? payCents;
  final bool missingRate;
  final double? rate;
  const PayrollPerson({
    required this.userId,
    required this.name,
    required this.role,
    required this.daysWorked,
    required this.workedMinutes,
    required this.plannedMinutes,
    this.payCents,
    this.missingRate = false,
    this.rate,
  });

  double? get pay => payCents == null ? null : payCents! / 100;
}

/// Totals per person, in name order. [payCents] is null only when nothing worked had a rate.
List<PayrollPerson> payrollTotals(List<PayrollDay> rows) {
  final by = <String, List<PayrollDay>>{};
  for (final r in rows) {
    (by[r.userId] ??= []).add(r);
  }
  final out = <PayrollPerson>[];
  for (final e in by.entries) {
    final days = [...e.value]..sort((a, b) => a.day.compareTo(b.day));
    final worked = days.where((d) => d.workedMinutes > 0).toList();
    final paid = worked.where((d) => d.pay != null).toList();
    final rated = days.where((d) => d.hourlyRate != null).toList();
    out.add(PayrollPerson(
      userId: e.key,
      name: days.first.name,
      role: days.last.role,
      daysWorked: worked.length,
      workedMinutes: days.fold(0, (n, d) => n + d.workedMinutes),
      plannedMinutes: days.fold(0, (n, d) => n + d.plannedMinutes),
      payCents: paid.isEmpty ? null : paid.fold<int>(0, (n, d) => n + _toCents(d.pay!)),
      missingRate: worked.length != paid.length,
      rate: rated.isEmpty ? null : rated.last.hourlyRate,
    ));
  }
  out.sort((a, b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.userId.compareTo(b.userId);
  });
  return out;
}

/// The whole period's pay, in paise, across everyone with a rate.
int payrollTotalCents(List<PayrollPerson> people) => people.fold(0, (n, p) => n + (p.payCents ?? 0));

/// The CSV: a heading line, one row per person per day, then each person's totals and the
/// team's. Numbers use a dot and two decimals so any spreadsheet reads them.
String payrollCsv({required String venue, required String currency, required DateTime from, required DateTime to, required List<PayrollDay> rows}) {
  final sorted = [...rows]..sort((a, b) {
      final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (c != 0) return c;
      final u = a.userId.compareTo(b.userId);
      return u != 0 ? u : a.day.compareTo(b.day);
    });
  final lines = <String>[
    _row(['Payroll', venue, _day(from), _day(to), currency]),
    '',
    _row(['Name', 'Role', 'Date', 'Shifts', 'First in', 'Last out', 'Worked (h:mm)', 'Worked (hours)', 'Unpaid breaks (min)',
      'Paid breaks (min)', 'Planned (h:mm)', 'Rate per hour', 'Pay', 'Notes']),
    for (final r in sorted)
      _row([
        r.name,
        r.role,
        _day(r.day),
        '${r.shifts}',
        r.firstIn ?? '',
        r.lastOut ?? '',
        hm(r.workedMinutes),
        hoursDecimal(r.workedMinutes),
        '${r.unpaidBreakMinutes}',
        '${r.paidBreakMinutes}',
        hm(r.plannedMinutes),
        r.hourlyRate == null ? '' : _cents(_toCents(r.hourlyRate!)),
        r.pay == null ? '' : _cents(_toCents(r.pay!)),
        _notes(r),
      ]),
    '',
    _row(['Totals', 'Role', 'Days worked', 'Worked (h:mm)', 'Worked (hours)', 'Planned (h:mm)', 'Rate per hour', 'Pay', 'Notes']),
  ];
  final people = payrollTotals(rows);
  for (final p in people) {
    lines.add(_row([
      p.name,
      p.role,
      '${p.daysWorked}',
      hm(p.workedMinutes),
      hoursDecimal(p.workedMinutes),
      hm(p.plannedMinutes),
      p.rate == null ? '' : _cents(_toCents(p.rate!)),
      p.payCents == null ? '' : _cents(p.payCents!),
      p.payCents == null && p.workedMinutes > 0 ? 'no rate set' : (p.missingRate ? 'no rate for some days' : ''),
    ]));
  }
  final worked = people.fold<int>(0, (n, p) => n + p.workedMinutes);
  final planned = people.fold<int>(0, (n, p) => n + p.plannedMinutes);
  lines.add(_row(['Team', '', '', hm(worked), hoursDecimal(worked), hm(planned), '', _cents(payrollTotalCents(people)), '']));
  return '${lines.join('\n')}\n';
}

/// Money for the screen from paise, with the venue's formatter.
double centsToAmount(int cents) => cents / 100;

/// The periods the payroll screen offers. A current period stops at today: payroll pays
/// for time worked, so days still to come aren't in it.
enum PayPeriod {
  thisWeek('This week'),
  lastWeek('Last week'),
  thisMonth('This month'),
  lastMonth('Last month');

  final String label;
  const PayPeriod(this.label);
}

/// [p]'s first and last day (both included), as local dates.
(DateTime, DateTime) payPeriod(PayPeriod p, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final monday = weekStart(now);
  return switch (p) {
    PayPeriod.thisWeek => (monday, today),
    PayPeriod.lastWeek => (DateTime(monday.year, monday.month, monday.day - 7), DateTime(monday.year, monday.month, monday.day - 1)),
    PayPeriod.thisMonth => (DateTime(now.year, now.month, 1), today),
    PayPeriod.lastMonth => (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 0)),
  };
}

/// "payroll-the-gin-room-2026-09-01-to-2026-09-30.csv"
String payrollFileName(String venue, DateTime from, DateTime to) {
  var slug = venue.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 40) slug = slug.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  return 'payroll-${slug.isEmpty ? 'venue' : slug}-${_day(from)}-to-${_day(to)}.csv';
}

/// The file's bytes: UTF-8 with a byte-order mark, so Excel reads names in any script
/// (without it, Excel on Windows guesses a legacy code page and mangles them).
List<int> payrollFileBytes(String csv) => [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
