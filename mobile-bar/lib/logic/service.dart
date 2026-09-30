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
