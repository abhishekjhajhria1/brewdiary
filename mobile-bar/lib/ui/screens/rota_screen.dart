// The rota (supabase/054). Whoever plans it (owners, managers) builds the week — who, what
// role, when, the break — as drafts only they see, then publishes it for the team, or copies
// last week forward. Everyone sees the published week, gives away a shift they can't do, and
// asks for an open one or a teammate's; a manager says yes before a shift changes hands.
// Hours are shown in name order, never ranked.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/area.dart' show venueTimeZone;
import '../../logic/roles.dart';
import '../../logic/rota.dart';
import '../../logic/staff.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import 'team_screen.dart' show youLabel;
import 'time_off_screen.dart';

class RotaScreen extends StatefulWidget {
  final Venue venue;
  const RotaScreen({super.key, required this.venue});
  @override
  State<RotaScreen> createState() => _RotaScreenState();
}

class _RotaScreenState extends State<RotaScreen> {
  DateTime _monday = weekStart(DateTime.now());
  bool? _mine; // null until the first load decides: planners see everyone, the team their own

  DateTime get _next => DateTime(_monday.year, _monday.month, _monday.day + 7);
  Venue get _venue => widget.venue;
  String _role(StaffRole r) => roleLabel(r, _venue.kind);

  void _week(int by) => setState(() => _monday = DateTime(_monday.year, _monday.month, _monday.day + 7 * by));

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final thisWeek = weekStart(DateTime.now());
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Rota',
          subtitle: weekLabel(_monday),
          back: true,
          tabBar: false,
          onRefresh: () async => rotaRev.bump(),
          actions: [
            IconBtn(Ph.calendarBlank, tooltip: 'Time off', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimeOffScreen(venue: _venue)))),
          ],
          children: [
            const DemoNote(),
            Row(children: [
              IconBtn(Ph.caretLeft, tooltip: 'The week before', onTap: () => _week(-1)),
              Expanded(
                child: Center(
                  child: _monday == thisWeek
                      ? Text('This week', style: T.label(bd))
                      : TextAction('Back to this week', accent: true, onTap: () => setState(() => _monday = thisWeek)),
                ),
              ),
              IconBtn(Ph.caretRight, tooltip: 'The week after', onTap: () => _week(1)),
            ]),
            const SizedBox(height: S.m),
            Loader<RotaWeek>(
              load: () => Backend.i.rotaWeek(_venue.id, _monday, _next),
              refresh: rotaRev,
              deps: _monday,
              retry: true,
              builder: (context, week, loading) {
                if (week == null) return const Skeleton(height: 320);
                final mine = _mine ?? !week.canPlan;
                return _WeekView(
                  venue: _venue,
                  week: week,
                  monday: _monday,
                  mineOnly: mine,
                  onMine: (v) => setState(() => _mine = v),
                  roleWord: _role,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekView extends StatelessWidget {
  final Venue venue;
  final RotaWeek week;
  final DateTime monday;
  final bool mineOnly;
  final ValueChanged<bool> onMine;
  final String Function(StaffRole) roleWord;
  const _WeekView({required this.venue, required this.week, required this.monday, required this.mineOnly, required this.onMine, required this.roleWord});

  DateTime get _next => DateTime(monday.year, monday.month, monday.day + 7);

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = Session.instance.user?.id;
    final myRole = venue.myRole;
    final drafts = week.shifts.where((s) => !s.published).length;
    final asks = week.shifts.where((s) => s.swap?.taken ?? false).toList();
    bool visible(RotaShift s) =>
        !mineOnly || s.userId == me || s.swap?.toUser == me || ((s.open || s.swap?.status == 'offered') && canTakeRole(myRole, s.role) && s.userId != me);
    final days = byDay(week.shifts.where(visible));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (week.canPlan) ...[
        Glass(
          padding: const EdgeInsets.all(S.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              drafts == 0 ? 'Everything this week is published.' : '$drafts ${drafts == 1 ? 'shift is a draft' : 'shifts are drafts'} only planners can see.',
              style: T.row(bd),
            ),
            if (drafts > 0) ...[
              const SizedBox(height: S.m),
              BdButton('Publish this week', icon: Ph.paperPlaneTilt, onTap: () => _publish(context)),
            ],
            const SizedBox(height: S.s),
            Wrap(spacing: S.l, runSpacing: S.s, children: [
              TextAction('Add a shift', accent: true, icon: Ph.plus, onTap: () => _editShift(context)),
              TextAction('Copy last week here', icon: Ph.copy, onTap: () => _copy(context)),
            ]),
          ]),
        ),
        const SizedBox(height: S.l),
      ],
      Segmented<bool>(
        options: const [(false, 'Everyone'), (true, 'Mine')],
        value: mineOnly,
        onChanged: onMine,
      ),
      if (week.canPlan && asks.isNotEmpty) ...[
        const SectionHeader('Waiting for your yes'),
        Group(children: [
          for (final s in asks)
            GroupTile(
              icon: Ph.swap,
              title: '${s.swap!.toName ?? 'Someone'} asked to take ${s.open ? 'an open shift' : '${s.name ?? 'a'}\'s shift'}',
              subtitle: '${dayLabel(s.startsAt)} · ${shiftTimes(s.startsAt, s.endsAt)} · ${roleWord(s.role)}',
              trailing: const ToneTag('asks', Tone.wait),
              onTap: () => _decide(context, s),
            ),
        ]),
      ],
      for (final day in weekDays(monday)) ..._day(context, day, days[day] ?? const []),
      if (week.canPlan) ..._planned(context),
    ]);
  }

  List<Widget> _day(BuildContext context, DateTime day, List<RotaShift> shifts) {
    final bd = context.bd;
    final me = Session.instance.user?.id;
    final off = offOn(week.timeOff, day);
    return [
      SectionHeader(dayLabel(day), padding: const EdgeInsets.only(top: S.xl, bottom: S.s)),
      if (off.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: S.s),
          child: Text(
            'Off: ${off.map((o) => '${o.userId == me ? 'you' : (o.name ?? 'someone')}${o.status == 'requested' ? ' (asked)' : ''}').join(', ')}',
            style: T.caption(bd),
          ),
        ),
      if (shifts.isEmpty)
        Text('Nothing planned.', style: T.caption(bd))
      else
        Group(children: [for (final s in shifts) _tile(context, s)]),
    ];
  }

  Widget _tile(BuildContext context, RotaShift s) {
    final me = Session.instance.user?.id;
    final tag = shiftTag(s, me: me);
    final tone = switch (tag) {
      'draft' => Tone.calm,
      'open' => Tone.info,
      'needs cover' => Tone.late,
      null => Tone.calm,
      _ => Tone.wait,
    };
    final bits = <String>[
      shiftTimes(s.startsAt, s.endsAt),
      roleWord(s.role),
      if (s.breakMinutes > 0) '${s.breakMinutes} min break',
      if (s.area != null) s.area!,
      if (s.note != null && s.note!.isNotEmpty) s.note!,
    ];
    final actions = week.canPlan ? () => _editShift(context, shift: s) : _staffActions(context, s);
    return GroupTile(
      title: s.open ? 'Open shift' : (s.userId == me ? youLabel(s.name ?? 'You') : (s.name ?? 'someone')),
      subtitle: bits.join(' · '),
      trailing: tag == null ? null : ToneTag(tag, tone),
      onTap: actions,
    );
  }

  /// What someone on the team can do with a shift, or null when nothing.
  VoidCallback? _staffActions(BuildContext context, RotaShift s) {
    final me = Session.instance.user?.id;
    final future = s.startsAt.isAfter(DateTime.now());
    final w = s.swap;
    final list = <SheetAction>[
      if (s.userId == me && s.published && future && w == null)
        SheetAction('Give this shift away', icon: Ph.swap, onTap: () => runAction(context, () => Backend.i.offerShift(s.id), done: 'On offer. A manager says yes once someone takes it.')),
      if (w != null && w.fromUser == me && w.status == 'offered')
        SheetAction('Take back the offer', icon: Ph.arrowCounterClockwise, onTap: () => runAction(context, () => Backend.i.withdrawSwap(w.id), done: 'It\'s yours again.')),
      if (w != null && w.toUser == me)
        SheetAction('Take back my ask', icon: Ph.arrowCounterClockwise, onTap: () => runAction(context, () => Backend.i.withdrawSwap(w.id), done: 'Taken back.')),
      if (s.userId != me && future && canTakeRole(venue.myRole, s.role) && ((s.open && w == null) || w?.status == 'offered'))
        SheetAction('Ask to take this shift', icon: Ph.handWaving, onTap: () => runAction(context, () => Backend.i.takeShift(s.id), done: 'Asked. A manager says yes before it\'s yours.')),
    ];
    if (list.isEmpty) return null;
    return () => showActions(context, title: '${dayLabel(s.startsAt)} · ${shiftTimes(s.startsAt, s.endsAt)}', message: roleWord(s.role), actions: list);
  }

  Future<void> _decide(BuildContext context, RotaShift s) => showActions(
        context,
        title: '${s.swap!.toName ?? 'Someone'} asked to take it',
        message: '${dayLabel(s.startsAt)} · ${shiftTimes(s.startsAt, s.endsAt)} · ${roleWord(s.role)}${s.open ? '' : ' · now ${s.name ?? 'someone'}\'s'}',
        actions: [
          SheetAction('Approve', icon: Ph.check, onTap: () => runAction(context, () => Backend.i.decideSwap(s.swap!.id, true), done: 'It\'s ${s.swap!.toName ?? 'theirs'}\'s now.')),
          SheetAction('Say no', icon: Ph.x, destructive: true, onTap: () => runAction(context, () => Backend.i.decideSwap(s.swap!.id, false), done: 'Said no.')),
        ],
      );

  Future<void> _publish(BuildContext context) async {
    try {
      final n = await Backend.i.publishRota(venue.id, monday, _next);
      if (context.mounted) toast(context, n == 0 ? 'Nothing new to publish.' : 'Published $n ${n == 1 ? 'shift' : 'shifts'}: the team can see them now.', tone: n == 0 ? ToastTone.plain : ToastTone.success);
    } on BackendError catch (e) {
      if (context.mounted) toast(context, e.message, tone: ToastTone.error);
    }
  }

  Future<void> _copy(BuildContext context) async {
    final from = DateTime(monday.year, monday.month, monday.day - 7);
    try {
      final n = await Backend.i.copyRota(venue.id, from, monday, 7, tz: venueTimeZone(venue.country, venue.region));
      if (context.mounted) toast(context, n == 0 ? 'Nothing to copy: last week was empty, or it\'s already here.' : 'Copied $n ${n == 1 ? 'shift' : 'shifts'} as drafts. Anyone off or busy became an open shift.', tone: n == 0 ? ToastTone.plain : ToastTone.success);
    } on BackendError catch (e) {
      if (context.mounted) toast(context, e.message, tone: ToastTone.error);
    }
  }

  List<Widget> _planned(BuildContext context) {
    final bd = context.bd;
    final rows = plannedByPerson(week.shifts);
    if (rows.isEmpty) return const [];
    return [
      const SectionHeader('Planned this week'),
      Group(children: [
        for (final r in rows)
          GroupTile(
            title: r.name,
            trailing: Text(formatMinutes(r.minutes), style: T.sans(bd, size: 15, weight: FontWeight.w500).copyWith(fontFeatures: T.tnum)),
          ),
      ]),
      const SizedBox(height: S.s),
      Text('By name, drafts included. For planning, never a ranking.', style: T.caption(bd)),
    ];
  }

  /// Add or change a shift. Starts as a draft; the team sees it once the week is published.
  Future<void> _editShift(BuildContext context, {RotaShift? shift}) async {
    final today = DateTime.now();
    final inWeek = !today.isBefore(monday) && today.isBefore(_next);
    var day = shift == null ? (inWeek ? DateTime(today.year, today.month, today.day) : monday) : DateTime(shift.startsAt.year, shift.startsAt.month, shift.startsAt.day);
    var start = shift?.startsAt ?? DateTime(day.year, day.month, day.day, 18);
    var end = shift?.endsAt ?? DateTime(day.year, day.month, day.day + 1, 2);
    String? who = shift?.userId;
    var role = shift?.role ?? StaffRole.server;
    var brk = shift?.breakMinutes ?? 30;
    final note = TextEditingController(text: shift?.note ?? '');
    var busy = false;

    // Keep the times on the chosen day; an end at or before the start runs into the next.
    void place() {
      start = DateTime(day.year, day.month, day.day, start.hour, start.minute);
      end = DateTime(day.year, day.month, day.day, end.hour, end.minute);
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    }

    place();
    await showBdSheet<void>(context, title: shift == null ? 'Add a shift' : 'Change the shift', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        final member = week.team.where((m) => m.userId == who).firstOrNull;
        final clash = member == null ? null : clashFor(member, start, end, week.shifts, week.timeOff, exceptShiftId: shift?.id);
        final w = shift?.swap;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (w != null && w.taken) ...[
            Glass(
              padding: const EdgeInsets.all(S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${w.toName ?? 'Someone'} asked to take this shift.', style: T.row(bd)),
                const SizedBox(height: S.m),
                Row(children: [
                  Expanded(child: BdButton('Say no', kind: BtnKind.secondary, onTap: () async {
                    final ok = await runAction(ctx, () => Backend.i.decideSwap(w.id, false), done: 'Said no.');
                    if (ok && ctx.mounted) Navigator.pop(ctx);
                  })),
                  const SizedBox(width: S.s),
                  Expanded(child: BdButton('Approve', onTap: () async {
                    final ok = await runAction(ctx, () => Backend.i.decideSwap(w.id, true), done: 'It\'s ${w.toName ?? 'theirs'}\'s now.');
                    if (ok && ctx.mounted) Navigator.pop(ctx);
                  })),
                ]),
              ]),
            ),
            const SizedBox(height: S.l),
          ],
          const Label('Day'),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final d in weekDays(monday))
              BdChip(dayLabel(d), active: d == day, onTap: () => set(() {
                    day = d;
                    place();
                  })),
          ]),
          const SizedBox(height: S.l),
          Row(children: [
            Expanded(
              child: PickerRow(label: 'Starts', value: '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}', onTap: () async {
                final t = await pickTime(ctx, start, title: 'Starts');
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
              child: PickerRow(label: 'Ends', value: shiftTimes(start, end).split('–').last, onTap: () async {
                final t = await pickTime(ctx, end, title: 'Ends');
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
          const Label('Who'),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            BdChip('Open shift', active: who == null, onTap: () => set(() => who = null)),
            for (final m in week.team)
              BdChip(m.name, active: who == m.userId, onTap: () => set(() {
                    who = m.userId;
                    if (m.role != StaffRole.owner) role = m.role;
                  })),
          ]),
          if (clash != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(clash, style: T.sans(bd, size: 13, color: bd.accentText))),
          const SizedBox(height: S.l),
          const Label('Role'),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final r in StaffRole.values)
              if (r != StaffRole.owner) BdChip(roleWord(r), active: role == r, onTap: () => set(() => role = r)),
          ]),
          const SizedBox(height: S.l),
          const Label('Break (unpaid)'),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final b in const [0, 15, 30, 45, 60]) BdChip(b == 0 ? 'None' : '$b min', active: brk == b, onTap: () => set(() => brk = b)),
          ]),
          const SizedBox(height: S.l),
          LineField(controller: note, label: 'Note (optional)', hint: 'A party of 12 at 21:00', maxLength: 200),
          const SizedBox(height: S.xl),
          BdButton(shift == null ? 'Add the shift' : 'Save', busy: busy, onTap: busy
              ? null
              : () async {
                  set(() => busy = true);
                  final ok = await runAction(
                    ctx,
                    () => Backend.i.saveRotaShift(venue.id, id: shift?.id, userId: who, role: role, starts: start, ends: end, breakMinutes: brk, note: note.text),
                    done: shift?.published ?? false ? 'Saved. The team sees the change.' : 'Saved as a draft until you publish.',
                  );
                  if (ctx.mounted) {
                    set(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                }),
          if (shift != null) ...[
            const SizedBox(height: S.s),
            BdButton('Delete the shift', kind: BtnKind.quiet, onTap: () async {
              final yes = await confirm(ctx, title: 'Delete this shift?', body: shift.published ? 'It comes off the published rota at once.' : 'It\'s only a draft.', yes: 'Delete');
              if (!yes || !ctx.mounted) return;
              final ok = await runAction(ctx, () => Backend.i.deleteRotaShift(shift.id), done: 'Deleted.');
              if (ok && ctx.mounted) Navigator.pop(ctx);
            }),
          ],
        ]);
      });
    });
    note.dispose();
  }
}
