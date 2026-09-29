// The host's waitlist — who's waiting for a table, how long they've waited against what
// they were quoted, and seating them. A first name or "party of 4" is all it keeps, and
// the database forgets every name within a day.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

class WaitlistScreen extends StatelessWidget {
  final Venue venue;
  const WaitlistScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final can = Session.instance.can(Cap.seatGuests);
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Waitlist',
          subtitle: venue.name,
          back: true,
          tabBar: false,
          onRefresh: () async => floorRev.bump(),
          children: [
            if (can) ...[
              BdButton('Add a party', icon: Ph.plus, onTap: () => _add(context)),
              const SizedBox(height: S.l),
            ],
            Loader<List<WaitParty>>(
              load: () => Backend.i.waitlist(venue.id),
              refresh: floorRev,
              retry: true,
              builder: (context, list, loading) {
                if (list == null) return const Skeleton(height: 160);
                final waiting = list.where((p) => p.status == 'waiting').toList();
                if (waiting.isEmpty) return const EmptyNote('Nobody waiting.');
                return Group(children: [
                  for (final p in waiting)
                    GroupTile(
                      title: '${p.name} · ${p.party}',
                      subtitle: _waited(p),
                      trailing: can
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              AccentPill('Seat', onTap: () => runAction(context, () => Backend.i.setWaitStatus(p.id, 'seated'), done: '${p.name} seated — open their table on the floor.')),
                              IconBtn(Ph.x, tooltip: '${p.name} left', onTap: () => runAction(context, () => Backend.i.setWaitStatus(p.id, 'left'))),
                            ])
                          : null,
                    ),
                ]);
              },
            ),
            const SizedBox(height: S.m),
            Text('Just a first name or "party of 4" — and every name is gone within a day.', style: T.caption(bd)),
          ],
        ),
      ),
    );
  }

  String _waited(WaitParty p) {
    final m = DateTime.now().difference(p.createdAt).inMinutes;
    if (p.quotedMin == null) return 'waiting ${m}m';
    final over = m - p.quotedMin!;
    return over > 0 ? 'waiting ${m}m · ${over}m over the ${p.quotedMin}m quote' : 'waiting ${m}m of ${p.quotedMin}m quoted';
  }

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    var party = 2;
    int? quote = 15;
    await showBdSheet<void>(context, title: 'Add a party', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LineField(controller: name, label: 'First name, or "party of 4"', autofocus: true, maxLength: 40, caps: TextCapitalization.words),
          const SizedBox(height: S.m),
          Text('How many', style: T.label(ctx.bd)),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [for (var n = 1; n <= 10; n++) BdChip('$n', active: party == n, onTap: () => set(() => party = n))]),
          const SizedBox(height: S.m),
          Text('Quoted wait', style: T.label(ctx.bd)),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [for (final q in const [5, 10, 15, 20, 30, 45]) BdChip('${q}m', active: quote == q, onTap: () => set(() => quote = q))]),
          const SizedBox(height: S.xl),
          BdButton('Add', onTap: () async {
            final ok = await runAction(ctx, () => Backend.i.addToWaitlist(venue.id, WaitParty(id: newId(), name: name.text, party: party, quotedMin: quote, createdAt: DateTime.now())));
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
        ]);
      });
    });
    name.dispose();
  }
}
