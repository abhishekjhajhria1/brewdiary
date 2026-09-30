// Time off (supabase/054): ask for days off, see what's been answered, and set the weekdays
// you can't work. Whoever plans the rota answers requests here too — a manager's own goes to
// the owner, and nobody answers their own. The team sees who's off on the rota, never why.
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

class TimeOffScreen extends StatelessWidget {
  final Venue venue;
  const TimeOffScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final me = s.user?.id;
    final plan = s.can(Cap.editRota);
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Time off',
          back: true,
          tabBar: false,
          onRefresh: () async => rotaRev.bump(),
          children: [
            const DemoNote(),
            if (s.can(Cap.ownShift)) BdButton('Ask for time off', icon: Ph.calendarPlus, onTap: () => _ask(context)),
            Loader<(List<TimeOff>, RotaWeek)>(
              load: () async {
                final monday = weekStart(DateTime.now());
                final list = await Backend.i.timeOffList(venue.id);
                final week = await Backend.i.rotaWeek(venue.id, monday, DateTime(monday.year, monday.month, monday.day + 7));
                return (list, week);
              },
              refresh: rotaRev,
              retry: true,
              builder: (context, data, loading) {
                if (data == null) return const Padding(padding: EdgeInsets.only(top: S.xl), child: Skeleton(height: 200));
                final (list, week) = data;
                final mine = list.where((o) => o.userId == me).toList();
                final waiting = list.where((o) => o.userId != me && o.status == 'requested').toList();
                final coming = list.where((o) => o.userId != me && o.status == 'approved' && o.endsAt.isAfter(DateTime.now())).toList();
                final myDays = week.team.where((m) => m.userId == me).firstOrNull?.cannotWork ?? const <int>[];
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (plan && waiting.isNotEmpty) ...[
                    const SectionHeader('Waiting for your yes'),
                    Group(children: [for (final o in waiting) _answerTile(context, o)]),
                  ],
                  const SectionHeader('Your requests'),
                  if (mine.isEmpty)
                    Text('Nothing asked for yet.', style: T.caption(bd))
                  else
                    Group(children: [for (final o in mine) _mineTile(context, o)]),
                  const SectionHeader('Days you can\'t work'),
                  Text('Whoever plans the rota sees these when they put you on a shift.', style: T.caption(bd)),
                  const SizedBox(height: S.s),
                  _CannotWork(venueId: venue.id, days: myDays),
                  if (plan && coming.isNotEmpty) ...[
                    const SectionHeader('Coming up'),
                    Group(children: [
                      for (final o in coming)
                        GroupTile(title: o.name ?? 'someone', subtitle: _range(o), trailing: const ToneTag('off', Tone.good)),
                    ]),
                  ],
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _range(TimeOff o) {
    final first = DateTime(o.startsAt.year, o.startsAt.month, o.startsAt.day);
    final last = o.lastDay;
    return first == last ? dateLabel(first) : '${dateLabel(first)} – ${dateLabel(last)}';
  }

  static (String, Tone) _status(String s) => switch (s) {
        'approved' => ('approved', Tone.good),
        'declined' => ('declined', Tone.late),
        'cancelled' => ('cancelled', Tone.calm),
        _ => ('asked', Tone.wait),
      };

  Widget _mineTile(BuildContext context, TimeOff o) {
    final (word, tone) = _status(o.status);
    final live = (o.status == 'requested' || o.status == 'approved') && o.endsAt.isAfter(DateTime.now());
    return GroupTile(
      title: _range(o),
      subtitle: [if (o.note != null) o.note!, if (o.decidedBy != null && o.status != 'requested') 'by ${o.decidedBy}'].join(' · '),
      trailing: ToneTag(word, tone),
      onTap: live
          ? () => showActions(context, title: _range(o), actions: [
                SheetAction('Cancel this request', icon: Ph.x, destructive: true, onTap: () => runAction(context, () => Backend.i.cancelTimeOff(o.id), done: 'Cancelled.')),
              ])
          : null,
    );
  }

  Widget _answerTile(BuildContext context, TimeOff o) => GroupTile(
        title: o.name ?? 'someone',
        subtitle: [_range(o), if (o.note != null) o.note!].join(' · '),
        trailing: const ToneTag('asked', Tone.wait),
        onTap: () => showActions(context, title: '${o.name ?? 'Someone'} · ${_range(o)}', message: o.note, actions: [
          SheetAction('Approve', icon: Ph.check, onTap: () => runAction(context, () => Backend.i.decideTimeOff(o.id, true), done: 'Approved. Nobody can be put on the rota for them then.')),
          SheetAction('Say no', icon: Ph.x, destructive: true, onTap: () => runAction(context, () => Backend.i.decideTimeOff(o.id, false), done: 'Said no.')),
        ]),
      );

  Future<void> _ask(BuildContext context) async {
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day + 1);
    var last = first;
    final note = TextEditingController();
    var busy = false;
    await showBdSheet<void>(context, title: 'Ask for time off', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('An owner or manager answers. Once approved, nobody can put you on the rota then.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          PickerRow(label: 'First day', value: dateLabel(first), icon: Ph.calendarBlank, onTap: () async {
            final d = await pickDate(ctx, first, title: 'First day', min: DateTime(now.year, now.month, now.day));
            if (d != null) {
              set(() {
                first = d;
                if (last.isBefore(first)) last = first;
              });
            }
          }),
          const SizedBox(height: S.s),
          PickerRow(label: 'Last day', value: dateLabel(last), icon: Ph.calendarBlank, onTap: () async {
            final d = await pickDate(ctx, last, title: 'Last day', min: first);
            if (d != null) set(() => last = d);
          }),
          const SizedBox(height: S.l),
          LineField(controller: note, label: 'Note (optional)', hint: 'A wedding in the family', maxLength: 200),
          const SizedBox(height: S.xl),
          BdButton('Send', busy: busy, onTap: busy
              ? null
              : () async {
                  set(() => busy = true);
                  final ok = await runAction(
                    ctx,
                    () => Backend.i.requestTimeOff(venue.id, first, DateTime(last.year, last.month, last.day + 1), note: note.text),
                    done: 'Asked. You\'ll see the answer here.',
                  );
                  if (ctx.mounted) {
                    set(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                }),
        ]);
      });
    });
    note.dispose();
  }
}

class _CannotWork extends StatefulWidget {
  final String venueId;
  final List<int> days;
  const _CannotWork({required this.venueId, required this.days});
  @override
  State<_CannotWork> createState() => _CannotWorkState();
}

class _CannotWorkState extends State<_CannotWork> {
  late Set<int> _days = {...widget.days};

  @override
  void didUpdateWidget(covariant _CannotWork old) {
    super.didUpdateWidget(old);
    if (old.days.join(',') != widget.days.join(',')) _days = {...widget.days};
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: S.s, runSpacing: S.s, children: [
      for (final d in const [1, 2, 3, 4, 5, 6, 0])
        BdChip(weekdayShort(d), active: _days.contains(d), onTap: () async {
          final next = {..._days};
          if (!next.remove(d)) next.add(d);
          setState(() => _days = next);
          final ok = await runAction(context, () => Backend.i.setCannotWork(widget.venueId, next.toList()));
          if (!ok && mounted) setState(() => _days = {...widget.days});
        }),
    ]);
  }
}
