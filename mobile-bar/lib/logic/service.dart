// Service arithmetic and reading (051) — pure. The server prices every line and keeps
// the subtotal; this lets the screens show the same sums, split a bill evenly, read the
// floor at a glance, and group the bar's and kitchen's tickets.
import 'package:brewdiary_core/money.dart' show formatMoney;

import '../data/models.dart';

/// What a bill comes to: every line that isn't void.
double tabTotal(Iterable<OrderLine> lines) => lines.fold(0, (s, l) => s + l.total);

/// [total] split [n] ways in whole paise/cents: the shares add up exactly, the last
/// takes the rounding.
List<double> splitEven(double total, int n) {
  if (n <= 1) return [total];
  final cents = (total * 100).round();
  final share = cents ~/ n;
  return [for (var i = 0; i < n; i++) (i == n - 1 ? cents - share * (n - 1) : share) / 100];
}

/// A table at a glance, most urgent first.
enum TableState { attention, ready, open, free }

TableState tableState(VenueTable t, List<ServiceTab> open, Map<String, List<OrderLine>> lines, List<InboxItem> inbox) {
  if (inbox.any((i) => i.tableId == t.id)) return TableState.attention;
  final tabs = open.where((x) => x.tableId == t.id).toList();
  if (tabs.isEmpty) return TableState.free;
  if (tabs.any((x) => (lines[x.id] ?? const []).any((l) => l.status == 'ready'))) return TableState.ready;
  return TableState.open;
}

String tableStateWord(TableState s) => switch (s) {
      TableState.attention => 'asking',
      TableState.ready => 'food ready',
      TableState.open => 'seated',
      TableState.free => 'free',
    };

/// One ticket on a station screen: a tab's open lines for that station.
class Ticket {
  final String tabId;
  final String where; // "T2", "Bar 3"
  final List<OrderLine> lines;
  const Ticket(this.tabId, this.where, this.lines);

  DateTime get since => lines.map((l) => l.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
  bool get allReady => lines.every((l) => l.status == 'ready');
  int minutes(DateTime now) => now.difference(since).inMinutes;
}

/// Group a station's lines into tickets, oldest first.
List<Ticket> tickets(List<OrderLine> lines) {
  final by = <String, List<OrderLine>>{};
  for (final l in lines) {
    by.putIfAbsent(l.tabId, () => []).add(l);
  }
  final out = [for (final e in by.entries) Ticket(e.key, e.value.first.tableLabel ?? e.value.first.tabName ?? 'Tab', e.value)];
  out.sort((a, b) => a.since.compareTo(b.since));
  return out;
}

/// How late a ticket is running: 0 on time, 1 getting long, 2 late.
int lateness(String station, int minutes) {
  final (warn, late) = station == 'kitchen' ? (15, 25) : (7, 12);
  return minutes >= late ? 2 : (minutes >= warn ? 1 : 0);
}

/// The station's next step for a line.
String? nextStationStatus(String status) => switch (status) {
      'sent' => 'preparing',
      'preparing' => 'ready',
      _ => null,
    };

/// A bill to hand over or share: plain text, the venue's own money format.
String billText({
  required String venue,
  required String where,
  required List<OrderLine> lines,
  required String currency,
  List<Map<String, Object>> payments = const [],
  double? tip,
}) {
  String m(num x) => formatMoney(x, currency);
  final live = lines.where((l) => l.status != 'void').toList();
  final b = StringBuffer()
    ..writeln(venue)
    ..writeln(where)
    ..writeln('');
  for (final l in live) {
    b.writeln('${l.qty} × ${l.name}  ${m(l.total)}');
  }
  b
    ..writeln('')
    ..writeln('Total  ${m(tabTotal(live))}');
  if (tip != null && tip > 0) b.writeln('Tip  ${m(tip)}');
  for (final p in payments) {
    b.writeln('Paid by ${p['method']}  ${m(p['amount'] as num)}');
  }
  b.write('Thank you.');
  return b.toString();
}

/// Where the venue's night starts: 6 in the morning. A night that runs past midnight
/// still counts from the evening before, and a café's day from its first coffee.
DateTime nightStart(DateTime now, {int hour = 6}) {
  final today = DateTime(now.year, now.month, now.day, hour);
  return now.isBefore(today) ? today.subtract(const Duration(days: 1)) : today;
}

/// The door against the licensed capacity.
enum DoorState { open, nearly, full }

/// Nearly full from 90%; full at the capacity (and past it, which the count still
/// records — a clicker that won't count someone already inside is a wrong clicker).
DoorState doorState(int inside, int? capacity) {
  if (capacity == null || capacity <= 0) return DoorState.open;
  if (inside >= capacity) return DoorState.full;
  if (inside * 10 >= capacity * 9) return DoorState.nearly;
  return DoorState.open;
}

String doorStateWord(DoorState s, int inside, int? capacity) => switch (s) {
      DoorState.open => capacity == null ? 'counting' : '${capacity - inside} more can come in',
      DoorState.nearly => 'nearly full — ${capacity! - inside} more',
      DoorState.full => inside > capacity! ? '${inside - capacity} over — hold the door' : 'full — hold the door',
    };

// ── the stations' all-day count, the drawer, bookings (058) ────────────────

/// What a station still has to make, item by item ("3 × Negroni"): the lines that are
/// new or being made, summed by name, most first (then by name). Ready lines are done.
List<({String name, int qty})> allDay(Iterable<OrderLine> lines) {
  final by = <String, int>{};
  for (final l in lines) {
    if (l.status == 'sent' || l.status == 'preparing') by[l.name] = (by[l.name] ?? 0) + l.qty;
  }
  final out = [for (final e in by.entries) (name: e.key, qty: e.value)];
  out.sort((a, b) => b.qty != a.qty ? b.qty.compareTo(a.qty) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// The notes and coins a drawer is counted in, by the currency of the place. Empty when
/// we don't know them (then the count is one number).
List<double> denominations(String currency) => switch (currency) {
      'INR' => const [500, 200, 100, 50, 20, 10, 5, 2, 1],
      'GBP' => const [50, 20, 10, 5, 2, 1, .5, .2, .1],
      'EUR' => const [100, 50, 20, 10, 5, 2, 1, .5, .2, .1],
      'USD' => const [100, 50, 20, 10, 5, 1, .25, .1],
      _ => const [],
    };

/// A count by notes and coins: how many of each → the total (rounded to the paisa/cent).
double countTotal(Map<double, int> counts) => (counts.entries.fold<double>(0, (s, e) => s + e.key * e.value) * 100).round() / 100;

/// How a close came out: square (within one unit), a little off, or a lot off.
enum CountResult { square, slightlyOff, off }

CountResult countResult(double difference, {double small = 100}) {
  final d = difference.abs();
  if (d < 1) return CountResult.square;
  if (d <= small) return CountResult.slightlyOff;
  return CountResult.off;
}

String countWord(double difference, String Function(double) money) {
  if (difference.abs() < 1) return 'Square — the drawer matches.';
  return difference > 0 ? '${money(difference)} over' : '${money(-difference)} short';
}

/// A free table with a booking soon: the next live booking at it within [within].
Booking? nextBookingAt(String tableId, List<Booking> bookings, DateTime now, {Duration within = const Duration(hours: 3)}) {
  Booking? best;
  for (final b in bookings) {
    if (b.tableId != tableId || !b.live) continue;
    if (b.startsAt.isBefore(now.subtract(const Duration(minutes: 30))) || b.startsAt.isAfter(now.add(within))) continue;
    if (best == null || b.startsAt.isBefore(best.startsAt)) best = b;
  }
  return best;
}

/// Two bookings on one table that overlap (a double booking to sort out).
bool bookingsClash(Booking a, Booking b) =>
    a.id != b.id && a.tableId != null && a.tableId == b.tableId && a.live && b.live && a.startsAt.isBefore(b.endsAt) && b.startsAt.isBefore(a.endsAt);

const bookingStatusWord = {'booked': 'booked', 'arrived': 'here', 'seated': 'seated', 'no_show': 'no-show', 'cancelled': 'cancelled'};
