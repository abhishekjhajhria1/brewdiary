// Hours: the time clock's record (053, with 054's breaks). A manager sees who's on now (and
// who's on a break) and everyone's time since a date, opens anyone's timesheet, and runs
// payroll; anyone else sees their own. For pay and fairness only — the list is in NAME
// order, never ranked by hours, and nothing records where anyone was or what they did
// (the same rule as kudos: never a league table of staff).
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/staff.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'payroll_screen.dart';
import 'team_screen.dart' show youLabel;
import 'timesheet_screen.dart';

enum _Span { week, fortnight, month }

class StaffHoursScreen extends StatefulWidget {
  final Venue venue;
  const StaffHoursScreen({super.key, required this.venue});
  @override
  State<StaffHoursScreen> createState() => _StaffHoursScreenState();
}

class _StaffHoursScreenState extends State<StaffHoursScreen> {
  _Span _span = _Span.week;

  DateTime get _since {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_span) {
      _Span.week => weekStart(now),
      _Span.fortnight => today.subtract(const Duration(days: 13)),
      _Span.month => today.subtract(const Duration(days: 29)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final everyone = s.can(Cap.editRota);
    final venue = widget.venue;
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: everyone ? 'Hours' : 'My hours',
          back: true,
          tabBar: false,
          onRefresh: () async => shiftRev.bump(),
          children: [
            const DemoNote(),
            if (s.can(Cap.manageTeam)) ...[
              BdButton('Payroll', icon: Ph.wallet, kind: BtnKind.secondary, onTap: () => open(PayrollScreen(venue: venue))),
              const SizedBox(height: S.l),
            ],
            Segmented<_Span>(
              options: const [(_Span.week, 'This week'), (_Span.fortnight, '14 days'), (_Span.month, '30 days')],
              value: _span,
              onChanged: (v) => setState(() => _span = v),
            ),
            const SizedBox(height: S.l),
            Loader<List<ShiftRow>>(
              load: () => Backend.i.shiftHours(venue.id, _since),
              refresh: shiftRev,
              deps: _span,
              retry: true,
              builder: (context, rows, loading) {
                if (rows == null) return const Skeleton(height: 220);
                if (rows.isEmpty) return const EmptyNote('No time on the clock yet. Clock in from More → Your shift.', icon: Ph.clock);
                final on = rows.where((r) => r.onSince != null).toList();
                final resting = on.where((r) => r.onBreakSince != null).length;
                final total = rows.fold<int>(0, (n, r) => n + r.minutes);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (everyone)
                    StatRow([
                      StatTile(resting > 0 ? 'On now · $resting on a break' : 'On now', '${on.length}'),
                      StatTile('Team total', formatMinutes(total)),
                    ]),
                  if (everyone) const SizedBox(height: S.l),
                  Group(children: [
                    for (final r in rows)
                      GroupTile(
                        title: r.userId == s.user?.id ? youLabel(r.name) : r.name,
                        subtitle: [
                          roleLabel(r.role, venue.kind),
                          if (r.onBreakSince != null)
                            'on a break since ${hhmm(r.onBreakSince!)}'
                          else if (r.onSince != null)
                            'on since ${hhmm(r.onSince!)}',
                          if (r.breakMinutes > 0) '${formatMinutes(r.breakMinutes)} breaks',
                        ].join(' · '),
                        trailing: Text(formatMinutes(r.minutes), style: T.sans(bd, size: 15, weight: FontWeight.w500).copyWith(fontFeatures: T.tnum)),
                        onTap: () {
                          final me = r.userId == s.user?.id;
                          if (me || !everyone) {
                            open(TimesheetScreen(venue: venue, userId: r.userId, name: r.name));
                            return;
                          }
                          showActions(context, title: r.name, message: r.onSince == null ? null : 'On since ${hhmm(r.onSince!)}.', actions: [
                            SheetAction('Their timesheet', icon: Ph.listChecks, onTap: () async => open(TimesheetScreen(venue: venue, userId: r.userId, name: r.name))),
                            if (r.onSince != null)
                              SheetAction('Clock them out', icon: Ph.clock, onTap: () => runAction(context, () => Backend.i.endShift(venue.id, r.userId), done: '${r.name} is clocked out.')),
                          ]);
                        },
                      ),
                  ]),
                  const SizedBox(height: S.m),
                  Text(
                    everyone
                        ? 'Listed by name, for pay — never a ranking. Hours are after unpaid breaks. A shift that crosses the start of the range counts from the start. Tap someone for their timesheet.'
                        : 'Your own time here, after unpaid breaks. Tap it for your timesheet. Your manager sees the team\'s, by name, for pay.',
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
}

/// "Your shift" on More: clock in and out, take a break, and how long you've been on.
class ShiftCard extends StatelessWidget {
  final Venue venue;
  const ShiftCard({super.key, required this.venue});

  static String _t(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<(ShiftState?, bool)>(
      load: () async {
        try {
          return (await Backend.i.shiftState(venue.id), true);
        } on BackendError catch (e) {
          if (e.code != 'needs_update') rethrow;
          // A database before 054: the clock works, breaks don't yet.
          final since = await Backend.i.myShift(venue.id);
          return (since == null ? null : ShiftState(onSince: since), false);
        }
      },
      refresh: shiftRev,
      builder: (context, data, loading) {
        if (data == null) return const Skeleton(height: 96);
        final (st, breaks) = data;
        final on = st != null;
        final onBreak = st?.onBreak ?? false;
        final line = !on
            ? 'Off the clock'
            : onBreak
                ? 'On a ${st.breakPaid ? 'paid ' : ''}break since ${_t(st.breakSince!)}'
                : 'On since ${_t(st.onSince)} · ${formatMinutes(DateTime.now().difference(st.onSince).inMinutes - st.breakMinutes)}';
        return Glass(
          padding: const EdgeInsets.all(S.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(line, style: T.row(bd))),
              if (onBreak) const ToneTag('on a break', Tone.wait) else if (on) const ToneTag('on shift', Tone.good),
            ]),
            if (on && st.breakMinutes > 0) ...[
              const SizedBox(height: 4),
              Text('${formatMinutes(st.breakMinutes)} of breaks so far — not counted in your hours', style: T.caption(bd)),
            ],
            const SizedBox(height: S.m),
            if (onBreak)
              BdButton('End my break', icon: Ph.coffee, onTap: () => runAction(context, () => Backend.i.endBreak(venue.id), done: 'Welcome back.'))
            else ...[
              BdButton(
                on ? 'Clock out' : 'Clock in',
                icon: Ph.clock,
                kind: on ? BtnKind.secondary : BtnKind.primary,
                onTap: () => runAction(context, () async {
                  if (on) {
                    await Backend.i.clockOut(venue.id);
                  } else {
                    await Backend.i.clockIn(venue.id);
                  }
                }, done: on ? 'Clocked out. Thanks for tonight.' : 'Clocked in.'),
              ),
              if (on && breaks) ...[
                const SizedBox(height: S.s),
                BdButton('Start a break', icon: Ph.coffee, kind: BtnKind.secondary, onTap: () => runAction(context, () => Backend.i.startBreak(venue.id), done: 'Enjoy your break.')),
              ],
            ],
            const SizedBox(height: S.s),
            Text(
              breaks
                  ? 'For your pay. Breaks come off your hours unless your manager marks one paid. It records when, never where or what you did.'
                  : 'For your pay. It records when, never where or what you did.',
              style: T.caption(bd),
            ),
          ]),
        );
      },
    );
  }
}
