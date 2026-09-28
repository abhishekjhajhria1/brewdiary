// Date helpers — a port of src/lib/date.ts. Keys are local-time YYYY-MM-DD so
// "the day it's for" matches the user's calendar.

String _two(int n) => n.toString().padLeft(2, '0');

String toKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime parseKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String todayKey() => toKey(DateTime.now());

/// Calendar-day arithmetic (DST-safe: builds a new local date rather than adding hours).
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second);

DateTime addMonths(DateTime d, int n) => DateTime(d.year, d.month + n, 1);

bool isSameDay(DateTime a, DateTime b) => toKey(a) == toKey(b);

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Monday-first weekday labels (Swiss / ISO).
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdaysLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Monday-first index 0..6 (Dart's weekday is 1=Mon..7=Sun).
int mondayIndex(DateTime d) => d.weekday - 1;

class GridDay {
  final DateTime date;
  final String key;
  final bool inMonth;
  final bool isToday;
  final bool isFuture;
  const GridDay({required this.date, required this.key, required this.inMonth, required this.isToday, required this.isFuture});
}

/// A Monday-first 6-row grid covering the given month (month is 0-based, like JS).
List<GridDay> monthGrid(int year, int month) {
  final first = DateTime(year, month + 1, 1);
  final lead = mondayIndex(first);
  final start = addDays(first, -lead);
  final todayK = todayKey();
  final now = DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);

  return List.generate(42, (i) {
    final date = addDays(start, i);
    final key = toKey(date);
    return GridDay(
      date: date,
      key: key,
      inMonth: date.month == month + 1,
      isToday: key == todayK,
      isFuture: date.isAfter(todayDate),
    );
  });
}

String formatDayLong(String key) {
  final d = parseKey(key);
  return '${monthNames[d.month - 1]} ${d.day}';
}

String timeOfDayLabel(String iso) {
  final h = DateTime.parse(iso).toLocal().hour;
  if (h < 5) return 'Late night';
  if (h < 11) return 'Morning';
  if (h < 15) return 'Midday';
  if (h < 18) return 'Afternoon';
  if (h < 22) return 'Evening';
  return 'Nightcap';
}

/// Short "Jul 9" form used across lists.
String shortDay(String key) {
  final d = parseKey(key);
  return '${monthNames[d.month - 1].substring(0, 3)} ${d.day}';
}
