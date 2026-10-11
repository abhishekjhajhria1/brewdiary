// The manager's log (058): what the next shift lead or manager should know — what broke,
// who called, what's owed, who to thank. Newest first. Entries are kept as written: the
// log is a record, not a chat, so nothing here is edited or removed. Only supervisors and
// managers read it. Tonight's pre-shift note (for the whole team) is written from here too.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/shift_notes.dart';

/// "Today 6:40 pm", "Yesterday 11:05 pm", "Mon 6 Oct".
String whenWord(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today ${timeWord(t)}';
  if (diff == 1) return 'Yesterday ${timeWord(t)}';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]}';
}

class LogBookScreen extends StatelessWidget {
  final Venue venue;
  const LogBookScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Shift notes',
          subtitle: venue.name,
          back: true,
          tabBar: false,
          onRefresh: () async => notesRev.bump(),
          children: [
            const SectionHeader('Tonight, for everyone'),
            ShiftNotesCard(venue: venue),
            const SectionHeader('The manager\'s log'),
            BdButton('Add a log entry', icon: Ph.notePencil, kind: BtnKind.secondary, onTap: () => writeNote(context, venue, 'log')),
            const SizedBox(height: S.l),
            Loader<ShiftNotes>(
              load: () => Backend.i.shiftNotes(venue.id),
              refresh: notesRev,
              retry: true,
              builder: (context, notes, loading) {
                if (notes == null) return const Skeleton(height: 160);
                if (notes.log.isEmpty) {
                  return const EmptyNote('Nothing logged yet. What the next manager should know goes here — what broke, who called, what\'s owed.');
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final n in notes.log)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.m),
                      child: Glass(
                        padding: const EdgeInsets.all(S.l),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('${n.author} · ${whenWord(n.createdAt)}', style: T.caption(bd)),
                          const SizedBox(height: S.xs),
                          Text(n.body, style: T.sans(bd, size: 16, height: 1.5)),
                        ]),
                      ),
                    ),
                ]);
              },
            ),
            const SizedBox(height: S.s),
            Text('Kept as written — the log is a record, so entries aren\'t edited or removed. Only shift leads and managers read it.', style: T.caption(bd)),
          ],
        ),
      ),
    );
  }
}
