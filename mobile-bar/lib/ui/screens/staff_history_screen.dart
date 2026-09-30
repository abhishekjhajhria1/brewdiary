// The team's history (053): every change to the roster — added, joined, approved, said
// no to, role changed, paused, given access again, removed, left, a new code, a manager
// clocking someone out — with who did it and when. A trigger writes it, so no path can
// skip it. Owners and managers read the venue's; each person reads their own.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../logic/roles.dart';
import '../../logic/staff.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'locked_screen.dart' show staffWhen;

class StaffHistoryScreen extends StatelessWidget {
  final Venue venue;

  /// One person's history instead of the whole team's.
  final String? userId;
  final String? name;
  const StaffHistoryScreen({super.key, required this.venue, this.userId, this.name});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: name == null ? 'Team history' : '$name · history',
          back: true,
          tabBar: false,
          onRefresh: () async => staffRev.bump(),
          children: [
            const DemoNote(),
            Loader<List<StaffEvent>>(
              load: () => Backend.i.staffHistory(venue.id, userId: userId),
              refresh: staffRev,
              retry: true,
              builder: (context, events, loading) {
                if (events == null) return const Skeleton(height: 240);
                if (events.isEmpty) return const EmptyNote('Nothing yet. Every change to the team shows up here.');
                return Group(children: [
                  for (final e in events)
                    GroupTile(
                      icon: _icon(e.kind),
                      title: describeStaffEvent(
                        kind: e.kind,
                        actor: e.actor,
                        subject: e.subject,
                        detail: e.detail,
                        roleWord: (db) => roleLabel(StaffRole.parse(db), venue.kind),
                      ),
                      subtitle: staffWhen(e.at),
                    ),
                ]);
              },
            ),
            const SizedBox(height: S.m),
            Text('Kept by the database on every change, whichever app made it.', style: T.caption(bd)),
          ],
        ),
      ),
    );
  }
}

IconData _icon(String kind) => switch (kind) {
      'enrolled' || 'code_reissued' => Ph.key,
      'enrolment_revoked' || 'declined' => Ph.prohibit,
      'requested' => Ph.hourglass,
      'joined' || 'approved' => Ph.userCheck,
      'role_changed' => Ph.userGear,
      'locked' => Ph.lock,
      'unlocked' => Ph.key,
      'removed' || 'left' => Ph.userMinus,
      'details_changed' => Ph.identificationBadge,
      'shift_ended_by_manager' => Ph.clock,
      _ => Ph.clockCounterClockwise,
    };
