// The inbox — what the tables asked for from their phones: orders to accept or decline,
// and calls ("staff", "the bill", "water"). It says which table and what — never who.
// Accepting puts the order on the table's open tab (or opens one), priced by the server
// as if staff had keyed it; an order with alcohol reminds you to check ID.
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

const _callWord = {'staff': 'wants someone', 'bill': 'asks for the bill', 'water': 'asks for water'};

class InboxScreen extends StatelessWidget {
  final Venue venue;
  const InboxScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Inbox',
          subtitle: venue.tableService ? 'from the tables' : 'ordering from tables is off (More › Floor)',
          back: true,
          tabBar: false,
          onRefresh: () async => floorRev.bump(),
          children: [
            Loader<List<InboxItem>>(
              load: () => Backend.i.inbox(venue.id),
              refresh: floorRev,
              retry: true,
              builder: (context, items, loading) {
                if (items == null) return const Skeleton(height: 200);
                if (items.isEmpty) return const EmptyNote('Nothing waiting. When a table orders or calls from its QR, it lands here.');
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final i in items) Padding(padding: const EdgeInsets.only(bottom: S.m), child: i.kind == 'order' ? _OrderCard(venue: venue, item: i) : _CallCard(item: i)),
                  Text('Staff never see who asked — only the table.', style: T.caption(bd)),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _ago(DateTime t) {
  final m = DateTime.now().difference(t).inMinutes;
  return m < 1 ? 'just now' : '${m}m ago';
}

class _OrderCard extends StatelessWidget {
  final Venue venue;
  final InboxItem item;
  const _OrderCard({required this.venue, required this.item});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final can = Session.instance.can(Cap.takeOrders);
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${item.tableLabel} · an order', style: T.sans(bd, size: 17, weight: FontWeight.w600))),
          Text(_ago(item.createdAt), style: T.caption(bd)),
        ]),
        const SizedBox(height: S.s),
        for (final l in item.lines) Text('${l.qty} × ${l.name}${l.note == null ? '' : ' — ${l.note}'}', style: T.sans(bd, size: 15)),
        if (item.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${item.note}”', style: T.bodyMuted(bd))),
        if (item.hasAlcohol) ...[
          const SizedBox(height: S.s),
          const ToneTag('alcohol — check ID at the table', Tone.wait),
        ],
        if (can) ...[
          const SizedBox(height: S.m),
          Row(children: [
            Expanded(child: BdButton('Accept', icon: Ph.check, onTap: () => _accept(context))),
            const SizedBox(width: S.s),
            Expanded(child: BdButton('Decline', kind: BtnKind.secondary, onTap: () => _decline(context))),
          ]),
        ],
      ]),
    );
  }

  Future<void> _accept(BuildContext context) async {
    final open = (await Backend.i.openTabs(venue.id).catchError((_) => const <ServiceTab>[])).where((t) => t.tableId == item.tableId).toList();
    if (!context.mounted) return;
    String? tab;
    if (open.length == 1) {
      tab = open.first.id;
    } else if (open.length > 1) {
      tab = await showBdSheet<String>(context, title: 'Which check at ${item.tableLabel}?', builder: (ctx) => Column(children: [
            for (final (i, t) in open.indexed) GroupTile(title: t.name ?? 'Check ${i + 1}', onTap: () => Navigator.pop(ctx, t.id), chevron: true),
          ]));
      if (tab == null) return;
    }
    if (!context.mounted) return;
    await runAction(context, () => Backend.i.acceptRequest(item.id, tab ?? newId()), done: 'On ${item.tableLabel}\'s tab — sent to the bar and kitchen.');
  }

  Future<void> _decline(BuildContext context) async {
    final reason = await showBdSheet<String>(context, title: 'Decline ${item.tableLabel}\'s order', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('They\'ll see why on their phone.', style: T.bodyMuted(ctx.bd)),
        const SizedBox(height: S.m),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final r in const ['sold out — ask your server', 'kitchen\'s closed', 'we\'ll come and take it', 'last orders have gone']) BdChip(r, onTap: () => Navigator.pop(ctx, r)),
        ]),
      ]);
    });
    if (reason == null || !context.mounted) return;
    await runAction(context, () => Backend.i.declineRequest(item.id, reason: reason), done: 'Declined.');
  }
}

class _CallCard extends StatelessWidget {
  final InboxItem item;
  const _CallCard({required this.item});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Row(children: [
        Icon(item.callKind == 'bill' ? Ph.receipt : (item.callKind == 'water' ? Ph.drop : Ph.handWaving), color: bd.accentText),
        const SizedBox(width: S.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item.tableLabel} ${_callWord[item.callKind] ?? 'is calling'}', style: T.sans(bd, size: 16, weight: FontWeight.w600)),
            Text(_ago(item.createdAt), style: T.caption(bd)),
          ]),
        ),
        AccentPill('Done', onTap: () => runAction(context, () => Backend.i.resolveCall(item.id))),
      ]),
    );
  }
}
