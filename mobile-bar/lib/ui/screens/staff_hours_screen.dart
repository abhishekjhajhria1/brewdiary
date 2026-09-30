// Hours: the time clock's record (053). A manager sees who's on now and everyone's time
// since a date; anyone else sees their own. For pay and fairness only — the list is in
// NAME order, never ranked by hours, and nothing records where anyone was or what they
// did (the same rule as kudos: never a league table of staff).
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
import 'team_screen.dart' show youLabel;

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
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: everyone ? 'Hours' : 'My hours',
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
            Loader<List<ShiftRow>>(
              load: () => Backend.i.shiftHours(venue.id, _since),
              refresh: shiftRev,
              deps: _span,
              retry: true,
              builder: (context, rows, loading) {
                if (rows == null) return const Skeleton(height: 220);
                if (rows.isEmpty) return const EmptyNote('No time on the clock yet. Clock in from More → Your shift.', icon: Ph.clock);
                final on = rows.where((r) => r.onSince != null).toList();
                final total = rows.fold<int>(0, (n, r) => n + r.minutes);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (everyone)
                    StatRow([
                      StatTile('On now', '${on.length}'),
                      StatTile('Team total', formatMinutes(total)),
                    ]),
                  if (everyone) const SizedBox(height: S.l),
                  Group(children: [
                    for (final r in rows)
                      GroupTile(
                        title: r.userId == s.user?.id ? youLabel(r.name) : r.name,
                        subtitle: [
                          roleLabel(r.role, venue.kind),
                          if (r.onSince != null) 'on since ${r.onSince!.hour.toString().padLeft(2, '0')}:${r.onSince!.minute.toString().padLeft(2, '0')}',
                        ].join(' · '),
                        trailing: Text(formatMinutes(r.minutes), style: T.sans(bd, size: 15, weight: FontWeight.w500).copyWith(fontFeatures: T.tnum)),
                        onTap: everyone && r.onSince != null && r.userId != s.user?.id
                            ? () => showActions(context, title: r.name, message: 'On since ${r.onSince!.hour.toString().padLeft(2, '0')}:${r.onSince!.minute.toString().padLeft(2, '0')}.', actions: [
                                  SheetAction('Clock them out', icon: Ph.clock, onTap: () => runAction(context, () => Backend.i.endShift(venue.id, r.userId), done: '${r.name} is clocked out.')),
                                ])
                            : null,
                      ),
                  ]),
                  const SizedBox(height: S.m),
                  Text(
                    everyone
                        ? 'Listed by name, for pay — never a ranking. A shift that crosses the start of the range counts from the start.'
                        : 'Your own time here. Your manager sees the team\'s, by name, for pay.',
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

/// "Your shift" on More: clock in, clock out, and how long you've been on.
class ShiftCard extends StatelessWidget {
  final Venue venue;
  const ShiftCard({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<DateTime?>(
      load: () => Backend.i.myShift(venue.id),
      refresh: shiftRev,
      builder: (context, since, loading) {
        if (loading && since == null) return const Skeleton(height: 96);
        final on = since != null;
        final mins = on ? DateTime.now().difference(since).inMinutes : 0;
        return Glass(
          padding: const EdgeInsets.all(S.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                  on ? 'On since ${since.hour.toString().padLeft(2, '0')}:${since.minute.toString().padLeft(2, '0')} · ${formatMinutes(mins)}' : 'Off the clock',
                  style: T.row(bd),
                ),
              ),
              if (on) const ToneTag('on shift', Tone.good),
            ]),
            const SizedBox(height: S.m),
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
            const SizedBox(height: S.s),
            Text('For your pay. It records when, never where or what you did.', style: T.caption(bd)),
          ]),
        );
      },
    );
  }
}
