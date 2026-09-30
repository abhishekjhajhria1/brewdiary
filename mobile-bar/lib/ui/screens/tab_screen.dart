// A tab — what a table (or a named tab at the bar) has ordered, where each line is
// (sent, being made, ready, served), and the bill. Lines go straight to the bar or the
// kitchen; the server marks them served. A void always says why.
//
// The bill is the staff's: split it evenly or not, write down how each part was paid
// (cash, card, UPI, a voucher — their word), add a tip if there is one, and close it.
// brewdiary records what they say; it never takes or checks a payment.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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

const _statusWord = {'sent': 'sent', 'preparing': 'making', 'ready': 'ready', 'served': 'served', 'void': 'void'};
const _statusTone = {'sent': Tone.wait, 'preparing': Tone.info, 'ready': Tone.good, 'served': Tone.calm, 'void': Tone.late};

class TabScreen extends StatelessWidget {
  final Venue venue;
  final String tabId;
  final String where;
  const TabScreen({super.key, required this.venue, required this.tabId, required this.where});

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: where,
          subtitle: venue.name,
          back: true,
          tabBar: false,
          maxWidth: kWideMaxWidth,
          onRefresh: () async => floorRev.bump(),
          children: [
            Loader<(List<OrderLine>, bool)>(
              load: () async {
                final lines = await Backend.i.tabLines(tabId);
                final open = (await Backend.i.openTabs(venue.id)).any((t) => t.id == tabId);
                return (lines, open);
              },
              refresh: floorRev,
              retry: true,
              builder: (context, data, loading) {
                if (data == null) return const Skeleton(height: 240);
                final (lines, open) = data;
                final live = lines.where((l) => l.status != 'void').toList();
                final orders = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (lines.isEmpty) EmptyNote(open ? 'Nothing ordered yet.' : 'This tab is closed.'),
                  if (lines.isNotEmpty)
                    Group(children: [for (final l in lines) _LineTile(venue: venue, line: l, open: open)]),
                  if (open && s.can(Cap.takeOrders)) ...[
                    const SizedBox(height: S.l),
                    BdButton('Add to the order', icon: Ph.plus, onTap: () => _add(context)),
                  ],
                ]);
                final bill = _BillPane(venue: venue, tabId: tabId, where: where, lines: lines, open: open);
                return LayoutBuilder(builder: (context, c) {
                  if (c.maxWidth >= 840) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: orders),
                      const SizedBox(width: S.xl),
                      Expanded(flex: 2, child: bill),
                    ]);
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    orders,
                    if (live.isNotEmpty || open) ...[const SizedBox(height: S.xl), bill],
                  ]);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final menu = await Backend.i.menu(venue.id).catchError((_) => const <MenuItem>[]);
    if (!context.mounted) return;
    final picked = await showBdSheet<List<Map<String, Object?>>>(context, title: 'Add to $where', builder: (ctx) => _Picker(venue: venue, menu: menu));
    if (picked == null || picked.isEmpty || !context.mounted) return;
    final n = picked.fold<int>(0, (s, l) => s + (l['qty'] as int));
    await runAction(context, () => Backend.i.addLines(tabId, picked), done: 'Sent — $n ${n == 1 ? 'item' : 'items'}.');
  }
}

class _LineTile extends StatelessWidget {
  final Venue venue;
  final OrderLine line;
  final bool open;
  const _LineTile({required this.venue, required this.line, required this.open});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final l = line;
    final s = Session.instance;
    final isVoid = l.status == 'void';
    return GroupTile(
      title: '${l.qty} × ${l.name}',
      subtitle: [
        if (l.seat != null) 'seat ${l.seat}',
        if (l.note != null) l.note!,
        if (l.source == 'guest') 'from the table',
        if (isVoid && l.voidReason != null) 'void: ${l.voidReason}',
      ].join(' · '),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ToneTag(_statusWord[l.status] ?? l.status, _statusTone[l.status] ?? Tone.calm),
        const SizedBox(width: S.s),
        Text(money(l.unitPrice * l.qty, venue.currency),
            style: T.sans(bd, size: 14, color: isVoid ? bd.faint : bd.ink).copyWith(fontFeatures: T.tnum, decoration: isVoid ? TextDecoration.lineThrough : null)),
      ]),
      onTap: !open || isVoid
          ? null
          : () => showActions(context, title: l.name, actions: [
                if (l.status == 'ready' && s.can(Cap.takeOrders)) SheetAction('Served', icon: Ph.check, onTap: () => runAction(context, () => Backend.i.setLineStatus(l.id, 'served'))),
                if (l.status != 'served' && l.status != 'ready' && s.can(Cap.takeOrders)) SheetAction('Served (it\'s on the table)', icon: Ph.check, onTap: () => runAction(context, () => Backend.i.setLineStatus(l.id, 'served'))),
                if (s.can(Cap.voidOwn) || s.can(Cap.approveVoids)) SheetAction('Void', icon: Ph.x, destructive: true, onTap: () => _void(context)),
              ]),
    );
  }

  Future<void> _void(BuildContext context) async {
    final reason = await showBdSheet<String>(context, title: 'Void ${line.name}', builder: (ctx) {
      final other = TextEditingController();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final r in const ['rang it twice', 'wrong item', 'sent back', 'changed their mind']) BdChip(r, onTap: () => Navigator.pop(ctx, r)),
        ]),
        const SizedBox(height: S.l),
        LineField(controller: other, label: 'Or say why', onSubmitted: (t) => Navigator.pop(ctx, t)),
        const SizedBox(height: S.m),
        BdButton('Void it', kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, other.text)),
      ]);
    });
    if (reason == null || !context.mounted) return;
    await runAction(context, () => Backend.i.voidLine(line.id, reason), done: 'Voided.');
  }
}

/// Choose items from the menu: tap to add, tap again for more; notes and seats per line.
class _Picker extends StatefulWidget {
  final Venue venue;
  final List<MenuItem> menu;
  const _Picker({required this.venue, required this.menu});
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final Map<String, int> _qty = {};
  final Map<String, String> _note = {};
  final _q = TextEditingController();
  String? _section;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final items = widget.menu.where((m) => m.available).toList();
    if (items.isEmpty) return const EmptyNote('Nothing on the menu that\'s available — add items under Menu.');
    final sections = {for (final m in items) m.section}.toList();
    final q = _q.text.trim().toLowerCase();
    final shown = items.where((m) => (_section == null || m.section == _section) && (q.isEmpty || m.name.toLowerCase().contains(q))).toList();
    final count = _qty.values.fold<int>(0, (s, n) => s + n);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlassField(controller: _q, hint: 'Find on the menu', icon: Ph.magnifyingGlass, onChanged: (_) => setState(() {})),
      const SizedBox(height: S.s),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Padding(padding: const EdgeInsets.only(right: S.s), child: BdChip('All', active: _section == null, onTap: () => setState(() => _section = null))),
          for (final sct in sections) Padding(padding: const EdgeInsets.only(right: S.s), child: BdChip(sct, active: _section == sct, onTap: () => setState(() => _section = sct))),
        ]),
      ),
      const SizedBox(height: S.m),
      for (final m in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            if (m.diet != null) Padding(padding: const EdgeInsets.only(right: S.s), child: DietMark(m.diet!)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: T.sans(bd, size: 15.5)),
                Text([if (m.price != null) money(m.price!, widget.venue.currency), m.station == 'kitchen' ? 'kitchen' : (m.station == 'bar' ? 'bar' : ''), if (_note[m.id] != null) '“${_note[m.id]}”'].where((x) => x.isNotEmpty).join(' · '),
                    style: T.caption(bd)),
              ]),
            ),
            if ((_qty[m.id] ?? 0) > 0) ...[
              IconBtn(Ph.minus, tooltip: 'One fewer ${m.name}', onTap: () => setState(() => _qty[m.id] = (_qty[m.id]! - 1).clamp(0, 99))),
              SizedBox(width: 24, child: Text('${_qty[m.id]}', textAlign: TextAlign.center, style: T.sans(bd, size: 16, weight: FontWeight.w600).copyWith(fontFeatures: T.tnum))),
              IconBtn(Ph.notePencil, tooltip: 'Note for ${m.name}', onTap: () => _noteFor(m)),
            ],
            IconBtn(Ph.plus, tooltip: 'Add ${m.name}', onTap: () => setState(() => _qty[m.id] = ((_qty[m.id] ?? 0) + 1).clamp(0, 99))),
          ]),
        ),
      const SizedBox(height: S.l),
      BdButton(count == 0 ? 'Pick something' : 'Send $count ${count == 1 ? 'item' : 'items'}', onTap: count == 0
          ? null
          : () => Navigator.pop(context, [
                for (final e in _qty.entries)
                  if (e.value > 0) {'item': e.key, 'qty': e.value, 'note': _note[e.key]},
              ])),
    ]);
  }

  Future<void> _noteFor(MenuItem m) async {
    final c = TextEditingController(text: _note[m.id] ?? '');
    final got = await showBdSheet<String>(context, title: 'Note for ${m.name}', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final n in const ['no ice', 'less spicy', 'no onion', 'allergy — see me', 'on the side']) BdChip(n, onTap: () => Navigator.pop(ctx, n)),
        ]),
        const SizedBox(height: S.l),
        LineField(controller: c, label: 'Note', maxLength: 120, onSubmitted: (t) => Navigator.pop(ctx, t)),
        const SizedBox(height: S.m),
        BdButton('Done', onTap: () => Navigator.pop(ctx, c.text)),
      ]);
    });
    c.dispose();
    if (got != null && mounted) setState(() => got.trim().isEmpty ? _note.remove(m.id) : _note[m.id] = got.trim());
  }
}

/// The bill: the total, an even split, how it was paid (the staff's word), a tip.
class _BillPane extends StatelessWidget {
  final Venue venue;
  final String tabId;
  final String where;
  final List<OrderLine> lines;
  final bool open;
  const _BillPane({required this.venue, required this.tabId, required this.where, required this.lines, required this.open});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final total = tabTotal(lines);
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('THE BILL', style: T.label(bd)),
        const SizedBox(height: S.s),
        Row(children: [
          Expanded(child: Text('Total', style: T.sans(bd, size: 16, weight: FontWeight.w600))),
          Text(money(total, venue.currency), style: T.serif(bd, size: 28).copyWith(fontFeatures: T.tnum)),
        ]),
        const SizedBox(height: S.m),
        BdButton('Share the bill', icon: Ph.shareNetwork, kind: BtnKind.quiet, onTap: () => SharePlus.instance.share(ShareParams(text: billText(venue: venue.name, where: where, lines: lines, currency: venue.currency)))),
        if (open && s.can(Cap.takePayment)) ...[
          const SizedBox(height: S.s),
          BdButton('Settle and close', icon: Ph.receipt, onTap: () => _settle(context, total)),
        ],
        if (open && s.can(Cap.approveVoids) && !lines.any((l) => l.status == 'served')) ...[
          const SizedBox(height: S.s),
          BdButton('Void this tab', kind: BtnKind.quiet, onTap: () => _voidTab(context)),
        ],
      ]),
    );
  }

  Future<void> _settle(BuildContext context, double total) async {
    final done = await showBdSheet<bool>(context, title: 'Settle $where', builder: (ctx) => _Settle(venue: venue, tabId: tabId, total: total));
    if (done == true && context.mounted) Navigator.of(context).pop();
  }

  Future<void> _voidTab(BuildContext context) async {
    final yes = await confirm(context, title: 'Void this tab?', body: 'For a tab opened by mistake. Nothing on it was served.', yes: 'Void');
    if (!yes || !context.mounted) return;
    final ok = await runAction(context, () => Backend.i.voidTab(tabId, 'opened by mistake'), done: 'Voided.');
    if (ok && context.mounted) Navigator.of(context).pop();
  }
}

class _Settle extends StatefulWidget {
  final Venue venue;
  final String tabId;
  final double total;
  const _Settle({required this.venue, required this.tabId, required this.total});
  @override
  State<_Settle> createState() => _SettleState();
}

class _SettleState extends State<_Settle> {
  static const _methods = ['Cash', 'Card', 'UPI', 'Other'];
  int _ways = 1;
  late List<({TextEditingController amount, String method})> _parts = [(amount: TextEditingController(text: _fmt(widget.total)), method: 'UPI')];
  final _tip = TextEditingController();
  bool _busy = false;

  static String _fmt(double x) => x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(2);

  @override
  void dispose() {
    for (final p in _parts) {
      p.amount.dispose();
    }
    _tip.dispose();
    super.dispose();
  }

  void _split(int n) {
    final shares = splitEven(widget.total, n);
    for (final p in _parts) {
      p.amount.dispose();
    }
    setState(() {
      _ways = n;
      _parts = [for (final x in shares) (amount: TextEditingController(text: _fmt(x)), method: _parts.isEmpty ? 'UPI' : _parts.first.method)];
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final paid = _parts.fold<double>(0, (s, p) => s + (double.tryParse(p.amount.text.trim()) ?? 0));
    final diff = paid - widget.total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Total ${money(widget.total, widget.venue.currency)}', style: T.sans(bd, size: 16, weight: FontWeight.w600)),
      const SizedBox(height: S.m),
      Text('Split evenly', style: T.label(bd)),
      const SizedBox(height: S.s),
      Wrap(spacing: S.s, runSpacing: S.s, children: [for (var n = 1; n <= 6; n++) BdChip(n == 1 ? 'One bill' : '$n ways', active: _ways == n, onTap: () => _split(n))]),
      const SizedBox(height: S.l),
      for (final (i, p) in _parts.indexed) ...[
        Row(children: [
          Expanded(child: LineField(controller: p.amount, label: _parts.length == 1 ? 'Paid' : 'Part ${i + 1}', keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: S.s),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final m in _methods) BdChip(m, active: p.method == m, onTap: () => setState(() => _parts[i] = (amount: p.amount, method: m))),
        ]),
        const SizedBox(height: S.l),
      ],
      LineField(controller: _tip, label: 'Tip (optional)', keyboard: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: S.s),
      if (diff.abs() >= .01)
        Text(diff > 0 ? '${money(diff, widget.venue.currency)} more than the total — fine if that\'s what happened.' : '${money(-diff, widget.venue.currency)} less than the total — fine if that\'s what happened.',
            style: T.caption(bd)),
      const SizedBox(height: S.l),
      BdButton('Close the tab', busy: _busy, onTap: () async {
        setState(() => _busy = true);
        final payments = [
          for (final p in _parts)
            if ((double.tryParse(p.amount.text.trim()) ?? 0) > 0) {'method': p.method, 'amount': double.parse(p.amount.text.trim())},
        ];
        final tip = double.tryParse(_tip.text.trim());
        final ok = await runAction(this.context, () => Backend.i.closeTab(widget.tabId, payments, tip: tip), done: 'Closed. Thank you.');
        if (!mounted) return;
        setState(() => _busy = false);
        if (ok) Navigator.pop(this.context, true);
      }),
      const SizedBox(height: S.s),
      Text('You record how it was paid — brewdiary never takes or checks a payment.', style: T.caption(bd)),
    ]);
  }
}

/// India's menu mark: a square with a dot, green for veg, brown for non-veg — plus a word
/// for screen readers.
class DietMark extends StatelessWidget {
  final String diet;
  const DietMark(this.diet, {super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final color = switch (diet) {
      'veg' || 'vegan' => bd.tone(Tone.good),
      'egg' => bd.tone(Tone.wait),
      _ => bd.tone(Tone.late),
    };
    return Semantics(
      label: switch (diet) { 'veg' => 'vegetarian', 'vegan' => 'vegan', 'egg' => 'contains egg', _ => 'non-vegetarian' },
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(border: Border.all(color: color, width: 1.4), borderRadius: BorderRadius.circular(2)),
        alignment: Alignment.center,
        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: diet == 'non_veg' ? BoxShape.rectangle : BoxShape.circle)),
      ),
    );
  }
}
