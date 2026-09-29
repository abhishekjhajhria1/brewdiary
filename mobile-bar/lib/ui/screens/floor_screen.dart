// The floor — the service home for any place with tables (a bar, club, restaurant or
// café). Every table at a glance: free, seated, food ready, or asking for something —
// colour, a word and a mark, never colour alone. Tap a free table to open a tab, a
// seated one to see it. The inbox (a guest's order from the table, "bill please"), the
// bar and kitchen tickets, the waitlist and tonight's room are one tap away.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/service.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'floor_setup_screen.dart';
import 'host_screen.dart';
import 'inbox_screen.dart';
import 'station_screen.dart';
import 'tab_screen.dart';
import 'tonight_screen.dart';
import 'waitlist_screen.dart';

typedef FloorData = ({
  List<VenueArea> areas,
  List<VenueTable> tables,
  List<ServiceTab> tabs,
  Map<String, List<OrderLine>> lines,
  List<InboxItem> inbox,
  int waiting,
});

Future<FloorData> loadFloor(Venue v) async {
  final s = Session.instance;
  final results = await Future.wait<Object>([
    Backend.i.areas(v.id),
    Backend.i.tables(v.id),
    Backend.i.openTabs(v.id),
    s.can(Cap.floorView) ? Backend.i.inbox(v.id).catchError((_) => const <InboxItem>[]) : Future.value(const <InboxItem>[]),
    Backend.i.waitlist(v.id).catchError((_) => const <WaitParty>[]),
  ]);
  final tabs = results[2] as List<ServiceTab>;
  final lines = <String, List<OrderLine>>{};
  for (final t in tabs) {
    lines[t.id] = await Backend.i.tabLines(t.id);
  }
  return (
    areas: results[0] as List<VenueArea>,
    tables: (results[1] as List<VenueTable>).where((t) => t.active).toList(),
    tabs: tabs,
    lines: lines,
    inbox: results[3] as List<InboxItem>,
    waiting: (results[4] as List<WaitParty>).where((p) => p.status == 'waiting').length,
  );
}

class FloorScreen extends StatefulWidget {
  final Venue venue;
  const FloorScreen({super.key, required this.venue});
  @override
  State<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends State<FloorScreen> {
  Timer? _tick;

  Venue get v => widget.venue;

  @override
  void initState() {
    super.initState();
    // A calm heartbeat: the floor re-reads itself every 20 seconds while it's on screen.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => floorRev.bump());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    return ScrollPage(
      title: 'Floor',
      subtitle: v.name,
      maxWidth: kWideMaxWidth,
      onRefresh: () async => floorRev.bump(),
      children: [
        const DemoNote(),
        ShiftCard(venue: v),
        Loader<FloorData>(
          load: () => loadFloor(v),
          refresh: floorRev,
          retry: true,
          builder: (context, f, loading) {
            if (f == null) return const Skeleton(height: 320);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (f.inbox.isNotEmpty) _InboxBanner(items: f.inbox, onTap: () => _push(InboxScreen(venue: v))),
              _Shortcuts(venue: v, waiting: f.waiting, onPush: _push),
              const SizedBox(height: S.l),
              if (f.tables.isEmpty)
                EmptyNote(
                  s.can(Cap.editSettings) ? 'No tables yet. Add your areas and tables once — each gets its own QR for the menu.' : 'No tables set up yet — a manager adds them under More › Floor.',
                  action: s.can(Cap.editSettings) ? 'Set up the floor' : null,
                  onAction: () => _push(FloorSetupScreen(venue: v)),
                )
              else
                ..._areas(context, f),
              const SizedBox(height: S.l),
              _OpenTabsWithoutTable(venue: v, f: f, onPush: _push),
              if (s.can(Cap.takeOrders)) ...[
                const SizedBox(height: S.m),
                BdButton('A tab at the bar', icon: Ph.plus, kind: BtnKind.secondary, onTap: () => _namedTab(context)),
              ],
            ]);
          },
        ),
      ],
    );
  }

  List<Widget> _areas(BuildContext context, FloorData f) {
    final byArea = <String?, List<VenueTable>>{};
    for (final t in f.tables) {
      byArea.putIfAbsent(t.areaId, () => []).add(t);
    }
    final order = [...f.areas.map((a) => a.id), null];
    return [
      for (final id in order)
        if (byArea[id] != null) ...[
          SectionHeader(f.areas.where((a) => a.id == id).firstOrNull?.name ?? 'Tables'),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 600 ? 4 : 3);
            final w = (c.maxWidth - S.s * (cols - 1)) / cols;
            return Wrap(spacing: S.s, runSpacing: S.s, children: [
              for (final t in byArea[id]!) SizedBox(width: w, child: _TableTile(venue: v, table: t, f: f, onTap: () => _openTable(context, t, f))),
            ]);
          }),
        ],
    ];
  }

  Future<void> _openTable(BuildContext context, VenueTable t, FloorData f) async {
    final tabs = f.tabs.where((x) => x.tableId == t.id).toList();
    if (tabs.length == 1) return _push(TabScreen(venue: v, tabId: tabs.first.id, where: t.label));
    if (tabs.length > 1) {
      await showActions(context, title: t.label, actions: [
        for (final (i, x) in tabs.indexed) SheetAction(x.name ?? 'Check ${i + 1}', icon: Ph.receipt, onTap: () => _push(TabScreen(venue: v, tabId: x.id, where: '${t.label} · ${x.name ?? 'check ${i + 1}'}'))),
        if (Session.instance.can(Cap.takeOrders)) SheetAction('Another check at ${t.label}', icon: Ph.plus, onTap: () => _open(context, t, split: true)),
      ]);
      return;
    }
    if (!Session.instance.can(Cap.takeOrders)) return toast(context, '${t.label} is free.');
    await _open(context, t);
  }

  /// Seat a table: how many, then straight into the tab.
  Future<void> _open(BuildContext context, VenueTable t, {bool split = false}) async {
    final covers = await showBdSheet<int>(context, title: split ? 'Another check at ${t.label}' : 'Seat ${t.label}', builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('How many?', style: T.bodyMuted(bd)),
        const SizedBox(height: S.m),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (var n = 1; n <= (t.seats + 2).clamp(2, 12); n++) BdChip('$n', onTap: () => Navigator.pop(ctx, n)),
        ]),
      ]);
    });
    if (covers == null || !context.mounted) return;
    final id = newId();
    final ok = await runAction(context, () => Backend.i.openTab(v.id, id, tableId: t.id, covers: covers));
    if (ok && context.mounted) _push(TabScreen(venue: v, tabId: id, where: t.label));
  }

  Future<void> _namedTab(BuildContext context) async {
    final name = TextEditingController();
    final go = await showBdSheet<bool>(context, title: 'A tab at the bar', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LineField(controller: name, label: 'Name it', hint: 'Bar 3, the birthday…', autofocus: true, maxLength: 40, onSubmitted: (_) => Navigator.pop(ctx, true)),
        const SizedBox(height: S.l),
        BdButton('Open', onTap: () => Navigator.pop(ctx, true)),
      ]);
    });
    final label = name.text.trim();
    name.dispose();
    if (go != true || !context.mounted) return;
    final id = newId();
    final ok = await runAction(context, () => Backend.i.openTab(v.id, id, name: label));
    if (ok && context.mounted) _push(TabScreen(venue: v, tabId: id, where: label));
  }
}

class _TableTile extends StatelessWidget {
  final Venue venue;
  final VenueTable table;
  final FloorData f;
  final VoidCallback onTap;
  const _TableTile({required this.venue, required this.table, required this.f, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final state = tableState(table, f.tabs, f.lines, f.inbox);
    final tabs = f.tabs.where((t) => t.tableId == table.id).toList();
    final total = tabs.fold<double>(0, (s, t) => s + tabTotal(f.lines[t.id] ?? const []));
    final mins = tabs.isEmpty ? null : DateTime.now().difference(tabs.map((t) => t.openedAt).reduce((a, b) => a.isBefore(b) ? a : b)).inMinutes;
    final covers = tabs.fold<int>(0, (s, t) => s + (t.covers ?? 0));
    final tone = switch (state) { TableState.attention => Tone.late, TableState.ready => Tone.good, TableState.open => Tone.info, TableState.free => Tone.calm };
    final color = bd.tone(tone);
    return Semantics(
      button: true,
      label: '${table.label}, ${tableStateWord(state)}${covers > 0 ? ', $covers guests' : ''}',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 104,
          padding: const EdgeInsets.all(S.m),
          decoration: BoxDecoration(
            color: state == TableState.free ? bd.glass : color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(rTile),
            border: Border.all(color: state == TableState.free ? bd.glassBorder : color.withValues(alpha: .7), width: state == TableState.attention ? 1.6 : .8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(table.label, style: T.serif(bd, size: 24), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (covers > 0) Text('$covers', style: T.sans(bd, size: 13, weight: FontWeight.w600, color: color).copyWith(fontFeatures: T.tnum)),
              if (state != TableState.free) ...[
                const SizedBox(width: 3),
                Icon(state == TableState.attention ? Ph.bellRinging : (state == TableState.ready ? Ph.checkCircle : Ph.usersThree), size: 18, color: color),
              ],
            ]),
            const Spacer(),
            Text(tableStateWord(state), style: T.sans(bd, size: 12.5, weight: FontWeight.w600, color: state == TableState.free ? bd.faint : color)),
            Text(
              mins == null ? '${table.seats} seats' : '${mins}m · ${money(total, venue.currency)}',
              style: T.caption(bd).copyWith(fontFeatures: T.tnum),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      ),
    );
  }
}

class _InboxBanner extends StatelessWidget {
  final List<InboxItem> items;
  final VoidCallback onTap;
  const _InboxBanner({required this.items, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final orders = items.where((i) => i.kind == 'order').length;
    final calls = items.length - orders;
    final text = [if (orders > 0) '$orders ${orders == 1 ? 'order' : 'orders'} from tables', if (calls > 0) '$calls ${calls == 1 ? 'call' : 'calls'}'].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: S.l),
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(S.l),
          decoration: BoxDecoration(color: bd.accent.withValues(alpha: .16), borderRadius: BorderRadius.circular(rTile), border: Border.all(color: bd.accent.withValues(alpha: .6))),
          child: Row(children: [
            Icon(Ph.bellRinging, color: bd.accentText),
            const SizedBox(width: S.m),
            Expanded(child: Text(text, style: T.sans(bd, size: 15.5, weight: FontWeight.w600))),
            Text('Open', style: T.sans(bd, size: 14, weight: FontWeight.w600, color: bd.accentText)),
          ]),
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  final Venue venue;
  final int waiting;
  final void Function(Widget) onPush;
  const _Shortcuts({required this.venue, required this.waiting, required this.onPush});
  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    return Wrap(spacing: S.s, runSpacing: S.s, children: [
      if (s.can(Cap.barStation)) BdChip('Bar tickets', icon: Ph.beerStein, onTap: () => onPush(StationScreen(venue: venue, station: 'bar'))),
      if (s.can(Cap.kitchenStation)) BdChip('Kitchen tickets', icon: Ph.cookingPot, onTap: () => onPush(StationScreen(venue: venue, station: 'kitchen'))),
      if (s.can(Cap.floorView)) BdChip(waiting > 0 ? 'Waitlist · $waiting' : 'Waitlist', icon: Ph.hourglass, onTap: () => onPush(WaitlistScreen(venue: venue))),
      if (s.can(Cap.floorView)) BdChip('Inbox', icon: Ph.chatCircleDots, onTap: () => onPush(InboxScreen(venue: venue))),
      if (s.can(Cap.openRoom) || s.can(Cap.guestsAtTables)) BdChip('Tonight\'s room', icon: Ph.doorOpen, onTap: () => onPush(TonightScreen(venue: venue, pushed: true))),
    ]);
  }
}

class _OpenTabsWithoutTable extends StatelessWidget {
  final Venue venue;
  final FloorData f;
  final void Function(Widget) onPush;
  const _OpenTabsWithoutTable({required this.venue, required this.f, required this.onPush});
  @override
  Widget build(BuildContext context) {
    final loose = f.tabs.where((t) => t.tableId == null).toList();
    if (loose.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Tabs at the bar'),
      Group(children: [
        for (final t in loose)
          GroupTile(
            icon: Ph.receipt,
            title: t.name ?? 'Tab',
            subtitle: '${DateTime.now().difference(t.openedAt).inMinutes}m · ${money(tabTotal(f.lines[t.id] ?? const []), venue.currency)}',
            chevron: true,
            onTap: () => onPush(TabScreen(venue: venue, tabId: t.id, where: t.name ?? 'Tab')),
          ),
      ]),
    ]);
  }
}
