// Paused: what someone sees when an owner or manager has locked their access (053).
// Nothing works at that venue until they're given access again — the database refuses
// every call — so the screen says so plainly, says who to report to and why, and offers
// the two things left to do: check again, or go to another venue.
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/session.dart';
import '../../logic/staff.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';

class LockedScreen extends StatefulWidget {
  final StaffAccess access;
  const LockedScreen({super.key, required this.access});
  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  bool _busy = false;

  Future<void> _checkAgain() async {
    setState(() => _busy = true);
    await Session.instance.refreshVenues();
    if (!mounted) return;
    setState(() => _busy = false);
    // Still here? Still paused.
    if (Session.instance.lockedOut != null) toast(context, 'Still paused — ${reportLine(widget.access.reportTo, widget.access.reportToRole).toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final a = widget.access;
    final s = Session.instance;
    return Scaffold(
      body: Ambient(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: S.gutter, vertical: S.x3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Ph.lock, size: 36, color: bd.accentText),
                  const SizedBox(height: S.l),
                  Semantics(header: true, child: Text('Your access is paused', style: T.largeTitle(bd))),
                  const SizedBox(height: S.s),
                  Text('${a.venueName} · ${roleLabel(a.role, a.venueKind)}', style: T.bodyMuted(bd)),
                  const SizedBox(height: S.xl),
                  Glass(
                    padding: const EdgeInsets.all(S.xl),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(reportLine(a.reportTo, a.reportToRole), style: T.row(bd)),
                      if (a.lockReason != null && a.lockReason!.trim().isNotEmpty) ...[
                        const SizedBox(height: S.m),
                        Text('\u201c${a.lockReason!.trim()}\u201d', style: T.serif(bd, size: 19, italic: true, height: 1.3)),
                      ],
                      if (a.lockedAt != null) ...[
                        const SizedBox(height: S.m),
                        Text('Paused ${_when(a.lockedAt!)}', style: T.caption(bd)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: S.l),
                  Text(
                    'Nothing you recorded is lost. You\'re off the clock, and the app opens again for you the moment they give you access back.',
                    style: T.caption(bd),
                  ),
                  const SizedBox(height: S.xl),
                  BdButton('Check again', icon: Ph.arrowsClockwise, busy: _busy, onTap: _checkAgain),
                  const SizedBox(height: S.s),
                  BdButton('Back to my venues', kind: BtnKind.secondary, icon: Ph.storefront, onTap: s.leaveVenue),
                  const SizedBox(height: S.s),
                  BdButton('Sign out', kind: BtnKind.quiet, onTap: s.signOut),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _when(DateTime t) {
  final now = DateTime.now();
  final d = now.difference(t);
  String hm(DateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (t.year == now.year && t.month == now.month && t.day == now.day) return 'today at ${hm(t)}';
  if (d.inDays < 7) return '${d.inDays < 1 ? 1 : d.inDays} ${d.inDays <= 1 ? 'day' : 'days'} ago';
  return 'on ${t.day}/${t.month}';
}

/// "3 min ago" / "today at 21:14" / "2 days ago" — shared with the team screens.
String staffWhen(DateTime t) => _when(t);
