// A timesheet (supabase/054): one person's worked shifts — times, breaks, and every change
// made to them. Owners and managers correct times someone forgot, or add a shift that was
// never clocked, always with a reason; the old times stay on record, so every payroll
// figure can be traced. They also decide whether a break is paid. Nobody corrects their
// own times or decides their own pay.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/rota.dart';
import '../../logic/staff.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import 'locked_screen.dart' show staffWhen;

enum _Span { week, fortnight, month }

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class TimesheetScreen extends StatefulWidget {
  final Venue venue;
  final String userId;
  final String name;
  const TimesheetScreen({super.key, required this.venue, required this.userId, required this.name});
  @override
  State<TimesheetScreen> createState() => _TimesheetScreenState();
}

class _TimesheetScreenState extends State<TimesheetScreen> {
  _Span _span = _Span.week;

  DateTime get _from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_span) {
      _Span.week => weekStart(now),
      _Span.fortnight => today.subtract(const Duration(days: 13)),
      _Span.month => today.subtract(const Duration(days: 29)),
    };
  }

  bool get _mayCorrect {
    final s = Session.instance;
    return s.can(Cap.editRota) && widget.userId != s.user?.id;
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = widget.userId == Session.instance.user?.id;
    final now = DateTime.now();
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: me ? 'My timesheet' : widget.name,
          subtitle: me ? null : 'Timesheet',
          back: true,
          tabBar: false,
          onRefresh: () async => shiftRev.bump(),
          children: [
            const DemoNote(),
            Segmented<_Span>(
              options: const [(_Span.week, 'This week'), (_Span.fortnight, '14 days'), (_Span.month, '30 days')],
              value: _span,
              onChanged: (v) => setState(() => _span = v),
            ),
            const SizedBox(height: S.l),
            Loader<List<TimesheetShift>>(
              load: () => Backend.i.timesheet(widget.venue.id, widget.userId, _from, DateTime(now.year, now.month, now.day + 1)),
              refresh: shiftRev,
              deps: _span,
              retry: true,
              builder: (context, shifts, loading) {
                if (shifts == null) return const Skeleton(height: 220);
                final worked = shifts.fold<int>(0, (n, x) => n + x.workedMinutes);
                final breaks = shifts.fold<int>(0, (n, x) => n + x.unpaidBreakMinutes);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  StatRow([
                    StatTile('Worked', formatMinutes(worked)),
                    StatTile('Unpaid breaks', formatMinutes(breaks)),
                  ]),
                  const SizedBox(height: S.l),
                  if (shifts.isEmpty)
                    const EmptyNote('No shifts in this period.')
                  else
                    Group(children: [for (final x in shifts.reversed) _tile(context, x)]),
                  if (_mayCorrect) ...[
                    const SizedBox(height: S.l),
                    BdButton('Add a missed shift', icon: Ph.plus, kind: BtnKind.secondary, onTap: () => _addMissed(context)),
                  ],
                  const SizedBox(height: S.m),
                  Text(
                    'Unpaid breaks come off the hours; paid ones don\'t. Every correction keeps the old times and the reason.',
                    style: T.caption(bd),
                  ),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, TimesheetShift x) {
    final end = x.endedAt;
    final bits = <String>[
      '${formatMinutes(x.workedMinutes)} worked',
      if (x.unpaidBreakMinutes > 0) '${x.unpaidBreakMinutes} min break',
      if (x.paidBreakMinutes > 0) '${x.paidBreakMinutes} min paid break',
    ];
    final actions = <SheetAction>[
      if (_mayCorrect && end != null) SheetAction('Correct the times', icon: Ph.pencilSimple, onTap: () => _correct(context, x)),
      if (x.breaks.isNotEmpty) SheetAction(x.breaks.length == 1 ? 'The break' : 'The breaks', icon: Ph.coffee, onTap: () => _breaks(context, x)),
      if (x.corrected) SheetAction('See the changes', icon: Ph.clockCounterClockwise, onTap: () => _changes(context, x)),
    ];
    return GroupTile(
      title: '${dayLabel(x.startedAt)} ${dateLabel(x.startedAt).split(' ').last} · ${end == null ? '${_hm(x.startedAt)} – on now' : shiftTimes(x.startedAt, end)}',
      subtitle: bits.join(' · '),
      trailing: x.corrected ? const ToneTag('corrected', Tone.info) : (end == null ? const ToneTag('on shift', Tone.good) : null),
      onTap: actions.isEmpty ? null : () => showActions(context, title: shiftTimes(x.startedAt, end ?? DateTime.now()), actions: actions),
    );
  }

  Future<void> _breaks(BuildContext context, TimesheetShift x) => showBdSheet<void>(context, title: x.breaks.length == 1 ? 'The break' : 'The breaks', builder: (ctx) {
        final bd = ctx.bd;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            _mayCorrect
                ? 'A break is unpaid unless you mark it paid. ${widget.name} can\'t change this, and nobody can for themself.'
                : 'A break is unpaid unless an owner or manager marks it paid.',
            style: T.bodyMuted(bd),
          ),
          const SizedBox(height: S.l),
          Group(children: [
            for (final b in x.breaks)
              GroupTile(
                title: '${_hm(b.startedAt)}–${b.endedAt == null ? 'now' : _hm(b.endedAt!)} · ${b.minutes} min',
                trailing: ToneTag(b.paid ? 'paid' : 'unpaid', b.paid ? Tone.good : Tone.calm),
                onTap: !_mayCorrect
                    ? null
                    : () => showActions(ctx, title: '${_hm(b.startedAt)}–${b.endedAt == null ? 'now' : _hm(b.endedAt!)}', actions: [
                          SheetAction(b.paid ? 'Make it unpaid' : 'Mark it paid', icon: Ph.wallet, onTap: () async {
                            final ok = await runAction(ctx, () => Backend.i.setBreakPaid(b.id, !b.paid), done: b.paid ? 'Unpaid — it comes off the hours.' : 'Paid — it counts in the hours.');
                            if (ok && ctx.mounted) Navigator.pop(ctx);
                          }),
                        ]),
              ),
          ]),
        ]);
      });

  Future<void> _changes(BuildContext context, TimesheetShift x) => showBdSheet<void>(context, title: 'Changes to this shift', builder: (ctx) {
        final bd = ctx.bd;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in x.corrections)
            Padding(
              padding: const EdgeInsets.only(bottom: S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  c.kind == 'added'
                      ? 'Added ${shiftTimes(c.newStarted, c.newEnded)}'
                      : '${c.oldStarted == null ? '?' : _hm(c.oldStarted!)}–${c.oldEnded == null ? '?' : _hm(c.oldEnded!)}  →  ${shiftTimes(c.newStarted, c.newEnded)}',
                  style: T.row(bd),
                ),
                const SizedBox(height: 4),
                Text('“${c.reason}”', style: T.serif(bd, size: 17, italic: true, height: 1.3)),
                const SizedBox(height: 4),
                Text('${c.by ?? 'Someone'} · ${staffWhen(c.at)}', style: T.caption(bd)),
              ]),
            ),
        ]);
      });

  Future<void> _correct(BuildContext context, TimesheetShift x) async {
    var start = x.startedAt;
    var end = x.endedAt!;
    final why = TextEditingController();
    String? err;
    var busy = false;
    await showBdSheet<void>(context, title: 'Correct ${widget.name}\'s times', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('The old times are kept with your reason. ${widget.name} sees the change on their timesheet.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          PickerRow(label: 'Started', value: '${dateLabel(start)} ${_hm(start)}', onTap: () async {
            final t = await pickDateTime(ctx, start, title: 'Started', max: DateTime.now());
            if (t != null) set(() => start = t);
          }),
          const SizedBox(height: S.s),
          PickerRow(label: 'Ended', value: '${dateLabel(end)} ${_hm(end)}', onTap: () async {
            final t = await pickDateTime(ctx, end, title: 'Ended', max: DateTime.now());
            if (t != null) set(() => end = t);
          }),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final m in const [-30, -15, 15, 30, 60])
              BdChip('End ${m > 0 ? '+' : '−'}${m.abs()} min', active: false, onTap: () => set(() => end = end.add(Duration(minutes: m)))),
          ]),
          const SizedBox(height: S.l),
          LineField(controller: why, label: 'Why', hint: 'Forgot to clock out — we closed at 01:00', maxLength: 200, error: err),
          const SizedBox(height: S.xl),
          BdButton('Save the correction', busy: busy, onTap: busy
              ? null
              : () async {
                  if (why.text.trim().length < 3) {
                    set(() => err = 'Say why, so the change can be traced.');
                    return;
                  }
                  set(() {
                    err = null;
                    busy = true;
                  });
                  final ok = await runAction(ctx, () => Backend.i.correctShift(x.shiftId, start, end, why.text), done: 'Corrected. The old times are kept.');
                  if (ctx.mounted) {
                    set(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                }),
        ]);
      });
    });
    why.dispose();
  }

  Future<void> _addMissed(BuildContext context) async {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day - 1);
    var start = DateTime(day.year, day.month, day.day, 18);
    var end = DateTime(day.year, day.month, day.day + 1, 0);
    var brk = 30;
    final why = TextEditingController();
    String? err;
    var busy = false;
    void place() {
      start = DateTime(day.year, day.month, day.day, start.hour, start.minute);
      end = DateTime(day.year, day.month, day.day, end.hour, end.minute);
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    }

    await showBdSheet<void>(context, title: 'Add a missed shift', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('For a shift ${widget.name} worked but never clocked. It\'s marked as added, with your reason.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          PickerRow(label: 'Day', value: dateLabel(day), icon: Ph.calendarBlank, onTap: () async {
            final d = await pickDate(ctx, day, title: 'Day', max: now);
            if (d != null) {
              set(() {
                day = d;
                place();
              });
            }
          }),
          const SizedBox(height: S.s),
          Row(children: [
            Expanded(
              child: PickerRow(label: 'Started', value: _hm(start), onTap: () async {
                final t = await pickTime(ctx, start, title: 'Started');
                if (t != null) {
                  set(() {
                    start = t;
                    place();
                  });
                }
              }),
            ),
            const SizedBox(width: S.s),
            Expanded(
              child: PickerRow(label: 'Ended', value: shiftTimes(start, end).split('–').last, onTap: () async {
                final t = await pickTime(ctx, end, title: 'Ended');
                if (t != null) {
                  set(() {
                    end = t;
                    place();
                  });
                }
              }),
            ),
          ]),
          const SizedBox(height: S.l),
          const Label('Break (unpaid)'),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final b in const [0, 15, 30, 45, 60]) BdChip(b == 0 ? 'None' : '$b min', active: brk == b, onTap: () => set(() => brk = b)),
          ]),
          const SizedBox(height: S.l),
          LineField(controller: why, label: 'Why', hint: 'The clock was down on Saturday', maxLength: 200, error: err),
          const SizedBox(height: S.xl),
          BdButton('Add the shift', busy: busy, onTap: busy
              ? null
              : () async {
                  if (why.text.trim().length < 3) {
                    set(() => err = 'Say why, so the hours can be traced.');
                    return;
                  }
                  set(() {
                    err = null;
                    busy = true;
                  });
                  final ok = await runAction(ctx, () => Backend.i.addMissedShift(widget.venue.id, widget.userId, start, end, breakMinutes: brk, reason: why.text), done: 'Added.');
                  if (ctx.mounted) {
                    set(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                }),
        ]);
      });
    });
    why.dispose();
  }
}
