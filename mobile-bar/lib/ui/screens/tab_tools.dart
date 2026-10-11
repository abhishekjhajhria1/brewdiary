// What a server does with a tab mid-service (058), each one sheet: move the party to
// another table (or to the bar), bring another tab into this one, split the bill by item
// (pick the lines, they move to a new check, each is settled on its own), and hand the
// table to someone else at shift change. The database checks every move; nothing is
// deleted — a merged tab is kept, marked merged.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../logic/roles.dart';
import '../../logic/service.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';

/// "T4", "T4 · check 2", "Bar 3" — how a tab is named on a list.
String tabLabel(ServiceTab t, Map<String, String> tableLabels) {
  final table = t.tableId == null ? null : tableLabels[t.tableId];
  if (table == null) return t.name ?? 'Tab';
  return t.name == null ? table : '$table · ${t.name}';
}

/// Move the party to another table, or to the bar. Returns where it went (for the toast),
/// or null if nothing moved.
Future<String?> moveTabFlow(BuildContext context, Venue venue, ServiceTab tab) async {
  final tables = (await Backend.i.tables(venue.id)).where((t) => t.active && !t.isPickup).toList();
  final open = await Backend.i.openTabs(venue.id);
  if (!context.mounted) return null;
  final busy = {for (final t in open) if (t.tableId != null && t.id != tab.id) t.tableId!};
  final picked = await showBdSheet<String>(context, title: 'Move to…', builder: (ctx) {
    final bd = ctx.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Free tables first. The order, the bill and the server move with it.', style: T.bodyMuted(bd)),
      const SizedBox(height: S.m),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        for (final t in [...tables.where((t) => !busy.contains(t.id)), ...tables.where((t) => busy.contains(t.id))])
          if (t.id != tab.tableId) BdChip(busy.contains(t.id) ? '${t.label} · seated' : t.label, icon: busy.contains(t.id) ? Ph.usersThree : Ph.table, onTap: () => Navigator.pop(ctx, t.id)),
      ]),
      const SizedBox(height: S.l),
      BdButton('To the bar instead', icon: Ph.beerStein, kind: BtnKind.quiet, onTap: () => Navigator.pop(ctx, '')),
    ]);
  });
  if (picked == null || !context.mounted) return null;
  if (picked.isEmpty) {
    final name = TextEditingController(text: tab.name ?? '');
    final go = await showBdSheet<bool>(context, title: 'A tab at the bar', builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LineField(controller: name, label: 'Name it', hint: 'Bar 3, the birthday…', autofocus: true, maxLength: 40, onSubmitted: (_) => Navigator.pop(ctx, true)),
          const SizedBox(height: S.l),
          BdButton('Move to the bar', onTap: () => Navigator.pop(ctx, true)),
        ]));
    final label = name.text.trim();
    name.dispose();
    if (go != true || !context.mounted) return null;
    final ok = await runAction(context, () => Backend.i.moveTab(tab.id, barName: label));
    return ok ? label : null;
  }
  final to = tables.firstWhere((t) => t.id == picked);
  final ok = await runAction(context, () => Backend.i.moveTab(tab.id, toTableId: to.id));
  return ok ? to.label : null;
}

/// Bring another open tab into this one: its lines move here, it's kept as merged.
Future<bool> mergeInFlow(BuildContext context, Venue venue, ServiceTab into) async {
  final open = (await Backend.i.openTabs(venue.id)).where((t) => t.id != into.id).toList();
  final labels = {for (final t in await Backend.i.tables(venue.id)) t.id: t.label};
  final totals = <String, double>{for (final t in open) t.id: tabTotal(await Backend.i.tabLines(t.id))};
  if (!context.mounted) return false;
  if (open.isEmpty) {
    toast(context, 'No other open tab to bring in.');
    return false;
  }
  final from = await showBdSheet<ServiceTab>(context, title: 'Bring a tab into this one', builder: (ctx) {
    final bd = ctx.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Its order joins this bill and it closes as merged. Nothing is lost.', style: T.bodyMuted(bd)),
      const SizedBox(height: S.m),
      Group(children: [
        for (final t in open)
          GroupTile(
            icon: Ph.receipt,
            title: tabLabel(t, labels),
            subtitle: '${DateTime.now().difference(t.openedAt).inMinutes}m · ${money(totals[t.id] ?? 0, venue.currency)}',
            onTap: () => Navigator.pop(ctx, t),
          ),
      ]),
    ]);
  });
  if (from == null || !context.mounted) return false;
  return runAction(context, () => Backend.i.mergeTabs(from.id, into.id), done: '${tabLabel(from, labels)} is on this bill now.');
}

/// Split by item: pick lines, send them to a new check at the same table (or another
/// open tab). Each check is then settled on its own.
Future<bool> splitByItemFlow(BuildContext context, Venue venue, ServiceTab tab, List<OrderLine> lines) async {
  final live = lines.where((l) => l.status != 'void').toList();
  if (live.length < 2) {
    toast(context, 'There\'s only one thing on this bill.');
    return false;
  }
  final picked = await showBdSheet<Set<String>>(context, title: 'Split by item', builder: (ctx) => _PickLines(venue: venue, lines: live));
  if (picked == null || picked.isEmpty || !context.mounted) return false;
  final others = (await Backend.i.openTabs(venue.id)).where((t) => t.id != tab.id && t.tableId == tab.tableId && tab.tableId != null).toList();
  if (!context.mounted) return false;
  String? dest;
  if (others.isNotEmpty) {
    final labels = {for (final t in await Backend.i.tables(venue.id)) t.id: t.label};
    if (!context.mounted) return false;
    dest = await showBdSheet<String>(context, title: 'Move ${picked.length} ${picked.length == 1 ? 'item' : 'items'} to…', builder: (ctx) => Group(children: [
          GroupTile(icon: Ph.plus, title: 'A new check', subtitle: 'Settled on its own', onTap: () => Navigator.pop(ctx, '')),
          for (final t in others) GroupTile(icon: Ph.receipt, title: tabLabel(t, labels), onTap: () => Navigator.pop(ctx, t.id)),
        ]));
    if (dest == null || !context.mounted) return false;
  }
  final ok = await runAction(context, () async {
    var to = dest ?? '';
    if (to.isEmpty) {
      to = newId();
      final here = tab.tableId == null ? 1 : (await Backend.i.openTabs(venue.id)).where((t) => t.tableId == tab.tableId).length;
      await Backend.i.openTab(venue.id, to, tableId: tab.tableId, name: tab.tableId == null ? '${tab.name ?? 'Tab'} · 2' : 'check ${here + 1}', covers: 1);
    }
    await Backend.i.moveLines(picked.toList(), to);
  }, done: 'Split — ${picked.length} ${picked.length == 1 ? 'item is' : 'items are'} on their own check. Settle each one.');
  return ok;
}

class _PickLines extends StatefulWidget {
  final Venue venue;
  final List<OrderLine> lines;
  const _PickLines({required this.venue, required this.lines});
  @override
  State<_PickLines> createState() => _PickLinesState();
}

class _PickLinesState extends State<_PickLines> {
  final _on = <String>{};

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final sum = widget.lines.where((l) => _on.contains(l.id)).fold<double>(0, (s, l) => s + l.total);
    final seats = {for (final l in widget.lines) if (l.seat != null) l.seat!}.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Tap what goes on the new check.', style: T.bodyMuted(bd)),
      if (seats.isNotEmpty) ...[
        const SizedBox(height: S.m),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final s in seats)
            BdChip('Seat $s', icon: Ph.user, onTap: () => setState(() {
                  final ids = widget.lines.where((l) => l.seat == s).map((l) => l.id);
                  ids.every(_on.contains) ? _on.removeAll(ids) : _on.addAll(ids);
                })),
        ]),
      ],
      const SizedBox(height: S.m),
      Group(children: [
        for (final l in widget.lines)
          GroupTile(
            title: '${l.qty} × ${l.name}',
            subtitle: [if (l.seat != null) 'seat ${l.seat}', if (l.note != null) l.note!].join(' · '),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(l.total, widget.venue.currency), style: T.sans(bd, size: 14).copyWith(fontFeatures: T.tnum)),
              const SizedBox(width: S.s),
              Icon(_on.contains(l.id) ? PhFill.checkCircle : Ph.circle, size: 22, color: _on.contains(l.id) ? bd.accentText : bd.faint),
            ]),
            onTap: () => setState(() => _on.contains(l.id) ? _on.remove(l.id) : _on.add(l.id)),
          ),
      ]),
      const SizedBox(height: S.l),
      BdButton(_on.isEmpty ? 'Pick at least one' : 'Move ${_on.length} · ${money(sum, widget.venue.currency)}',
          onTap: _on.isEmpty || _on.length == widget.lines.length ? null : () => Navigator.pop(context, {..._on})),
      if (_on.length == widget.lines.length) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('That\'s everything — leave something on this check.', style: T.caption(bd))),
    ]);
  }
}

/// Hand the table to someone else on the team (shift change). Names in name order.
Future<bool> handOverFlow(BuildContext context, Venue venue, ServiceTab tab) async {
  final team = (await Backend.i.staff(venue.id))
      .where((m) => m.status == StaffStatus.active && roleCan(m.role, Cap.takeOrders) && m.id != tab.serverId)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (!context.mounted) return false;
  if (team.isEmpty) {
    toast(context, 'Nobody else on the team takes orders here.');
    return false;
  }
  final to = await showBdSheet<StaffMember>(context, title: 'Hand this table to…', builder: (ctx) => Group(children: [
        for (final m in team) GroupTile(icon: Ph.user, title: m.name, subtitle: roleLabel(m.role, venue.kind), onTap: () => Navigator.pop(ctx, m)),
      ]));
  if (to == null || !context.mounted) return false;
  return runAction(context, () => Backend.i.assignTab(tab.id, to.id), done: '${to.name} has it now.');
}
