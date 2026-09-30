// The rota (supabase/054): a week grouped by day, the words for a shift, and the rules the
// database keeps (who may ask for which shift; clashes) so a screen can explain a refusal
// before it asks. The DATABASE decides; this only says it plainly.
import '../data/models.dart';
import 'roles.dart';

/// Weekday as the database stores it: 0 = Sunday … 6 = Saturday (quiet_nights, cannot_work).
int dbWeekday(DateTime d) => d.weekday % 7;

const _dayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _dayLong = ['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];
const _month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Mon", indexed by [dbWeekday].
String weekdayShort(int dbDay) => _dayShort[dbDay % 7];

/// The seven days of the week that starts on [monday].
List<DateTime> weekDays(DateTime monday) => [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];

/// "29 Sep – 5 Oct".
String weekLabel(DateTime monday) {
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  return '${monday.day} ${_month[monday.month - 1]} – ${sunday.day} ${_month[sunday.month - 1]}';
}

/// "Mon 29".
String dayLabel(DateTime d) => '${_dayShort[dbWeekday(d)]} ${d.day}';

/// "4 Oct".
String dateLabel(DateTime d) => '${d.day} ${_month[d.month - 1]}';

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "18:00–02:00 (+1)" — the (+1) when it ends on a later day.
String shiftTimes(DateTime start, DateTime end) {
  final days = DateTime(end.year, end.month, end.day).difference(DateTime(start.year, start.month, start.day)).inDays;
  return '${_hm(start)}–${_hm(end)}${days > 0 ? ' (+$days)' : ''}';
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Shifts grouped by the day they start on (a night past midnight is one night), each
/// day's shifts by start time then name.
Map<DateTime, List<RotaShift>> byDay(Iterable<RotaShift> shifts) {
  final out = <DateTime, List<RotaShift>>{};
  for (final s in shifts) {
    (out[_day(s.startsAt)] ??= []).add(s);
  }
  for (final list in out.values) {
    list.sort((a, b) {
      final t = a.startsAt.compareTo(b.startsAt);
      return t != 0 ? t : (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
    });
  }
  return out;
}

/// Time off that covers any part of [day].
List<TimeOff> offOn(Iterable<TimeOff> offs, DateTime day) {
  final lo = _day(day);
  final hi = DateTime(lo.year, lo.month, lo.day + 1);
  return [for (final o in offs) if (o.startsAt.isBefore(hi) && o.endsAt.isAfter(lo)) o];
}

/// May someone whose role here is [mine] ask for a [shift]-role shift? Their own role, or
/// a shift lead, manager or owner (the same rule as rota_take_shift()).
bool canTakeRole(StaffRole mine, StaffRole shift) =>
    mine == shift || mine == StaffRole.owner || mine == StaffRole.manager || mine == StaffRole.supervisor;

/// Why putting [member] on [start, end) is a problem, or null. Double booking and approved
/// time off are refused by the database; a day they said they can't work is only a warning.
String? clashFor(RotaMember member, DateTime start, DateTime end, Iterable<RotaShift> shifts, Iterable<TimeOff> offs, {String? exceptShiftId}) {
  for (final s in shifts) {
    if (s.id == exceptShiftId || s.userId != member.userId) continue;
    if (s.startsAt.isBefore(end) && s.endsAt.isAfter(start)) return '${member.name} is already on ${shiftTimes(s.startsAt, s.endsAt)}';
  }
  for (final o in offs) {
    if (o.userId == member.userId && o.status == 'approved' && o.startsAt.isBefore(end) && o.endsAt.isAfter(start)) {
      return '${member.name} is off then';
    }
  }
  final d = dbWeekday(start);
  if (member.cannotWork?.contains(d) ?? false) return '${member.name} can\'t work ${_dayLong[d]}';
  return null;
}

/// Planned minutes per person across [shifts] (open shifts left out), in NAME order —
/// never ranked by hours.
List<({String userId, String name, int minutes})> plannedByPerson(Iterable<RotaShift> shifts) {
  final mins = <String, int>{};
  final names = <String, String>{};
  for (final s in shifts) {
    if (s.userId == null) continue;
    mins[s.userId!] = (mins[s.userId!] ?? 0) + s.minutes;
    names[s.userId!] = s.name ?? 'someone';
  }
  final out = [for (final e in mins.entries) (userId: e.key, name: names[e.key]!, minutes: e.value)];
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// What a shift's tag says, for the person looking at it.
String? shiftTag(RotaShift s, {required String? me}) {
  if (!s.published) return 'draft';
  if (!s.active) return 'needs cover';
  final w = s.swap;
  if (w != null && w.taken) return w.toUser == me ? 'you asked' : 'asked: ${w.toName ?? 'someone'}';
  if (w != null) return s.userId == me ? 'you offered it' : 'on offer';
  if (s.open) return 'open';
  return null;
}
