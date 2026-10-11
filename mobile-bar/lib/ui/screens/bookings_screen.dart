// Bookings (058) — the host's book for a day: who's coming, when, how many, which table.
// Tap one to seat them (the table's tab opens with the party size), mark them here, a
// no-show or cancelled. Two bookings on one table at once are flagged. A phone number is
// forgotten the day after and a name a month after, so the venue keeps its no-show
// numbers, not a contact list.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/service.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import '../widgets/shift_notes.dart' show timeWord;
import 'tab_screen.dart';

const _statusTone = {'booked': Tone.info, 'arrived': Tone.wait, 'seated': Tone.good, 'no_show': Tone.late, 'cancelled': Tone.calm};

String dayWord(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

class BookingsScreen extends StatefulWidget {
  final Venue venue;
  const BookingsScreen({super.key, required this.venue});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  /// A day here is the venue's night: 6 am to 6 am, so a 12:30 am booking is tonight's.
  late DateTime _day = _dayOf(nightStart(DateTime.now()));

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final v = widget.venue;
    final today = _dayOf(nightStart(DateTime.now()));
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Bookings',
          subtitle: v.name,
          back: true,
          tabBar: false,
          maxWidth: kWideMaxWidth,
          onRefresh: () async => bookingsRev.bump(),
          children: [
            Wrap(spacing: S.s, runSpacing: S.s, children: [
              BdChip('Today', active: _day == today, onTap: () => setState(() => _day = today)),
              BdChip('Tomorrow', active: _day == today.add(const Duration(days: 1)), onTap: () => setState(() => _day = today.add(const Duration(days: 1)))),
              BdChip(_day.isAfter(today.add(const Duration(days: 1))) || _day.isBefore(today) ? dayWord(_day) : 'Another day', icon: Ph.calendarBlank, onTap: () async {
                final d = await pickDate(context, _day, min: today.subtract(const Duration(days: 30)), max: today.add(const Duration(days: 366)));
                if (d != null && mounted) setState(() => _day = _dayOf(d));
              }),
            ]),
            if (s.can(Cap.seatGuests)) ...[
              const SizedBox(height: S.l),
              BdButton('New booking', icon: Ph.calendarPlus, onTap: () => editBooking(context, v, day: _day)),
            ],
            const SizedBox(height: S.l),
            Loader<(List<Booking>, List<VenueTable>)>(
              deps: _day,
              load: () async => (await Backend.i.bookings(v.id, _day.add(const Duration(hours: 6)), _day.add(const Duration(hours: 30))), (await Backend.i.tables(v.id)).where((t) => !t.isPickup).toList()),
              refresh: bookingsRev,
              retry: true,
              builder: (context, data, loading) {
                if (data == null) return const Skeleton(height: 200);
                final (list, tables) = data;
                final labels = {for (final t in tables) t.id: t.label};
                if (list.isEmpty) return EmptyNote('No bookings for ${dayWord(_day).toLowerCase()}.${s.can(Cap.seatGuests) ? ' Add one with New booking.' : ''}');
                final live = list.where((b) => b.live).fold<int>(0, (n, b) => n + b.party);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${list.where((b) => b.live).length} to come · $live guests', style: T.caption(context.bd)),
                  const SizedBox(height: S.s),
                  Group(children: [
                    for (final b in list)
                      _BookingTile(
                        venue: v,
                        b: b,
                        table: b.tableId == null ? null : labels[b.tableId],
                        clash: list.where((o) => bookingsClash(b, o)).map((o) => o.name).firstOrNull,
                        tables: tables,
                      ),
                  ]),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Venue venue;
  final Booking b;
  final String? table;
  final String? clash;
  final List<VenueTable> tables;
  const _BookingTile({required this.venue, required this.b, required this.tables, this.table, this.clash});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return Semantics(
      button: s.can(Cap.seatGuests),
      label: '${timeWord(b.startsAt)}, ${b.name}, party of ${b.party}${table == null ? '' : ', table $table'}, ${bookingStatusWord[b.status]}',
      excludeSemantics: true,
      child: Pressable(
        enabled: s.can(Cap.seatGuests),
        haptic: false,
        scale: .985,
        onTap: () => _actions(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(timeWord(b.startsAt), maxLines: 1, softWrap: false, style: T.serif(bd, size: 18, color: b.live ? bd.ink : bd.faint).copyWith(fontFeatures: T.tnum))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${b.name} · ${b.party}', style: T.row(bd, color: b.live ? bd.ink : bd.faint)),
                Text([table == null ? 'any table' : 'table $table', '${b.minutes} min', if (b.note != null) b.note!].join(' · '), style: T.caption(bd)),
                if (clash != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Double-booked with $clash on $table', style: T.sans(bd, size: 13, color: bd.accentText))),
              ]),
            ),
            ToneTag(bookingStatusWord[b.status] ?? b.status, _statusTone[b.status] ?? Tone.calm),
          ]),
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context) async {
    final now = DateTime.now();
    await showActions(context, title: '${b.name} · ${b.party} at ${timeWord(b.startsAt)}', message: b.phone == null ? null : 'Phone: ${b.phone} (forgotten the day after)', actions: [
      if (b.live && !venue.kind.isCounter) SheetAction('Seat them now', icon: Ph.usersThree, onTap: () => seatBooking(context, venue, b, tables)),
      if (b.status == 'booked') SheetAction('They\'re here', icon: Ph.handWaving, onTap: () => runAction(context, () => Backend.i.setBookingStatus(b.id, 'arrived'))),
      if (b.live) SheetAction('Edit', icon: Ph.pencilSimple, onTap: () => editBooking(context, venue, existing: b)),
      if (b.live && now.isAfter(b.startsAt.add(const Duration(minutes: 15))))
        SheetAction('No-show', icon: Ph.userMinus, onTap: () => runAction(context, () => Backend.i.setBookingStatus(b.id, 'no_show'), done: 'Marked as a no-show.')),
      if (b.live) SheetAction('Cancel the booking', icon: Ph.x, destructive: true, onTap: () => runAction(context, () => Backend.i.setBookingStatus(b.id, 'cancelled'), done: 'Cancelled.')),
    ]);
  }
}

/// Seat a booking: its table (or pick one), the party size, and straight into the tab.
Future<void> seatBooking(BuildContext context, Venue venue, Booking b, List<VenueTable> tables) async {
  var tableId = b.tableId;
  if (tableId == null) {
    final open = await Backend.i.openTabs(venue.id);
    final busy = {for (final t in open) if (t.tableId != null) t.tableId!};
    if (!context.mounted) return;
    tableId = await showBdSheet<String>(context, title: 'Seat ${b.name} at…', builder: (ctx) => Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final t in tables.where((t) => t.active && !busy.contains(t.id))) BdChip('${t.label} · ${t.seats}', icon: Ph.table, onTap: () => Navigator.pop(ctx, t.id)),
        ]));
    if (tableId == null || !context.mounted) return;
  }
  final id = newId();
  final label = tables.where((t) => t.id == tableId).firstOrNull?.label ?? 'Table';
  final ok = await runAction(context, () async {
    await Backend.i.openTab(venue.id, id, tableId: tableId, covers: b.party);
    await Backend.i.setBookingStatus(b.id, 'seated', tabId: id);
  }, done: '${b.name} seated at $label.');
  if (ok && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => TabScreen(venue: venue, tabId: id, where: label)));
}

/// New or edit: who, how many, when, how long, which table, a phone and a note.
Future<void> editBooking(BuildContext context, Venue venue, {Booking? existing, DateTime? day}) async {
  final tables = (await Backend.i.tables(venue.id)).where((t) => t.active && !t.isPickup).toList();
  if (!context.mounted) return;
  await showBdSheet<void>(context, title: existing == null ? 'New booking' : 'Edit booking', builder: (_) => _BookingForm(venue: venue, tables: tables, existing: existing, day: day));
}

class _BookingForm extends StatefulWidget {
  final Venue venue;
  final List<VenueTable> tables;
  final Booking? existing;
  final DateTime? day;
  const _BookingForm({required this.venue, required this.tables, this.existing, this.day});
  @override
  State<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<_BookingForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late int _party = widget.existing?.party ?? 2;
  late int _minutes = widget.existing?.minutes ?? 90;
  late String? _table = widget.existing?.tableId;
  late DateTime _at = widget.existing?.startsAt ?? _defaultTime(widget.day ?? DateTime.now());
  bool _busy = false;

  /// The next half hour, at least an hour from now on today; 8 pm on another day.
  static DateTime _defaultTime(DateTime day) {
    final now = DateTime.now();
    if (day.year == now.year && day.month == now.month && day.day == now.day) {
      final t = now.add(const Duration(hours: 1));
      return DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 30 : 0).add(Duration(hours: t.minute < 30 ? 0 : 1));
    }
    return DateTime(day.year, day.month, day.day, 20);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final b = Booking(
      id: widget.existing?.id ?? newId(),
      name: _name.text.trim().isEmpty ? 'Party of $_party' : _name.text.trim(),
      party: _party,
      startsAt: _at,
      minutes: _minutes,
      tableId: _table,
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      status: widget.existing?.status ?? 'booked',
      tabId: widget.existing?.tabId,
    );
    final ok = await runAction(context, () => Backend.i.saveBooking(widget.venue.id, b, isNew: widget.existing == null), done: widget.existing == null ? 'Booked: ${b.name}, ${b.party} at ${timeWord(b.startsAt)}.' : 'Saved.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LineField(controller: _name, label: 'Name', hint: 'Mehta — or leave it for "Party of $_party"', caps: TextCapitalization.words, maxLength: 40, autofocus: widget.existing == null),
      const SizedBox(height: S.l),
      const Label('How many'),
      const SizedBox(height: 6),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        for (var n = 1; n <= 12; n++) BdChip('$n', active: _party == n, onTap: () => setState(() => _party = n)),
        if (_party > 12) BdChip('$_party', active: true, onTap: () {}),
        BdChip('More', icon: Ph.plus, onTap: () => setState(() => _party = (_party < 13 ? 13 : _party + 1).clamp(1, 99))),
      ]),
      const SizedBox(height: S.l),
      PickerRow(label: 'Day', value: dayWord(_at), icon: Ph.calendarBlank, onTap: () async {
        final d = await pickDate(context, _at, min: DateTime.now().subtract(const Duration(days: 1)), max: DateTime.now().add(const Duration(days: 366)));
        if (d != null && mounted) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
      }),
      const SizedBox(height: S.s),
      PickerRow(label: 'Time', value: timeWord(_at), onTap: () async {
        final t = await pickTime(context, _at);
        if (t != null && mounted) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
      }),
      const SizedBox(height: S.l),
      const Label('For how long'),
      const SizedBox(height: 6),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        for (final m in const [60, 90, 120, 180]) BdChip(m < 120 ? '$m min' : '${m ~/ 60} h', active: _minutes == m, onTap: () => setState(() => _minutes = m)),
      ]),
      if (widget.tables.isNotEmpty && !widget.venue.kind.isCounter) ...[
        const SizedBox(height: S.l),
        const Label('Table'),
        const SizedBox(height: 6),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          BdChip('Any', active: _table == null, onTap: () => setState(() => _table = null)),
          for (final t in widget.tables) BdChip('${t.label} · ${t.seats}', active: _table == t.id, onTap: () => setState(() => _table = t.id)),
        ]),
      ],
      const SizedBox(height: S.l),
      LineField(controller: _phone, label: 'Phone (optional)', hint: 'Forgotten the day after', keyboard: TextInputType.phone, maxLength: 20),
      const SizedBox(height: S.l),
      LineField(controller: _note, label: 'Note (optional)', hint: 'Anniversary, high chair, by the window', maxLength: 160),
      const SizedBox(height: S.xl),
      BdButton(widget.existing == null ? 'Book it' : 'Save', busy: _busy, onTap: _save),
      const SizedBox(height: S.s),
      Text('A phone number is forgotten the day after, and the name a month after — the venue keeps how many came, not a contact list.', style: T.caption(bd)),
    ]);
  }
}
