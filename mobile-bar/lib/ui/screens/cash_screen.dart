// The cash drawer (058). Open it with a float; a safe drop, a pay-in or a pay-out
// (paying the ice man from the till — a shift lead's call) each with a reason; then count
// and close. The count is BLIND: the person counting types what's in the drawer before the
// app shows what should be there — by notes and coins, or as one number. The close keeps a
// report that can't be changed afterwards: expected, counted, the difference, and the
// takings since it opened by how they were paid.
//
// brewdiary still takes and checks no payment: "cash" is whatever the staff wrote as cash
// when they settled a bill or rang a sale.
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
import '../widgets/shift_notes.dart' show timeWord;
import 'log_book_screen.dart' show whenWord;

const _moveWord = {'pay_in': 'Pay-in', 'pay_out': 'Pay-out', 'drop': 'Safe drop'};

Tone _resultTone(double diff) => switch (countResult(diff)) { CountResult.square => Tone.good, CountResult.slightlyOff => Tone.wait, CountResult.off => Tone.late };

class CashScreen extends StatelessWidget {
  final Venue venue;
  const CashScreen({super.key, required this.venue});

  String _m(double x) => money(x, venue.currency, round: false);

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Cash drawer',
          subtitle: venue.name,
          back: true,
          tabBar: false,
          onRefresh: () async => cashRev.bump(),
          children: [
            Loader<DrawerState>(
              load: () => Backend.i.drawerState(venue.id),
              refresh: cashRev,
              retry: true,
              builder: (context, st, loading) {
                if (st == null) return const Skeleton(height: 220);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (st.open == null) _OpenForm(venue: venue) else _OpenDrawerCard(venue: venue, d: st.open!),
                  if (s.can(Cap.closeDay) && st.closed.isNotEmpty) ...[
                    const SectionHeader('Recent closes'),
                    Group(children: [
                      for (final c in st.closed)
                        GroupTile(
                          icon: Ph.receipt,
                          title: '${c.label} · ${whenWord(c.closedAt)}',
                          subtitle: 'Closed by ${c.closedBy} · counted ${_m(c.report.counted)}',
                          trailing: ToneTag(countWord(c.report.difference, _m), _resultTone(c.report.difference)),
                          chevron: true,
                          onTap: () => showBdSheet<void>(context, title: '${c.label} · ${whenWord(c.closedAt)}', builder: (_) => CashReportView(venue: venue, report: c.report, note: c.note)),
                        ),
                    ]),
                  ],
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenForm extends StatefulWidget {
  final Venue venue;
  const _OpenForm({required this.venue});
  @override
  State<_OpenForm> createState() => _OpenFormState();
}

class _OpenFormState extends State<_OpenForm> {
  final _float = TextEditingController();
  String _label = 'Drawer';

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.all(S.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('No drawer open', style: T.title(bd)),
        const SizedBox(height: S.s),
        Text('Start the night with the float — the change you put in. Everything paid in cash is counted against it.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.l),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final l in const ['Drawer', 'Bar till', 'Front till']) BdChip(l, active: _label == l, onTap: () => setState(() => _label = l)),
        ]),
        const SizedBox(height: S.l),
        LineField(controller: _float, label: 'Float (${widget.venue.currency})', hint: '2000', keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
        const SizedBox(height: S.l),
        BdButton('Open the drawer', icon: Ph.wallet, onTap: double.tryParse(_float.text.trim()) == null
            ? null
            : () => runAction(context, () => Backend.i.openDrawer(widget.venue.id, newId(), double.parse(_float.text.trim()), label: _label), done: 'Drawer open.')),
      ]),
    );
  }
}

class _OpenDrawerCard extends StatelessWidget {
  final Venue venue;
  final OpenDrawer d;
  const _OpenDrawerCard({required this.venue, required this.d});

  String _m(double x) => money(x, venue.currency, round: false);

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final mayClose = d.mine || s.can(Cap.closeDay);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Glass(
        padding: const EdgeInsets.all(S.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(d.label, style: T.serif(bd, size: 28))),
            const ToneTag('open', Tone.good),
          ]),
          const SizedBox(height: S.xs),
          Text('Opened ${timeWord(d.openedAt)} by ${d.openedBy} · float ${_m(d.float)}', style: T.caption(bd)),
          if (d.expected != null) ...[
            const SizedBox(height: S.m),
            Row(children: [
              Expanded(child: Text('Should hold now', style: T.sans(bd, size: 15, color: bd.muted))),
              RollingText(_m(d.expected!), style: T.serif(bd, size: 24).copyWith(fontFeatures: T.tnum)),
            ]),
          ],
          if (d.moves.isNotEmpty) ...[
            const SizedBox(height: S.m),
            for (final m in d.moves)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text('${_moveWord[m.kind]} · ${m.reason}\n${m.by} · ${timeWord(m.madeAt)}', style: T.sans(bd, size: 14, height: 1.4))),
                  Text('${m.kind == 'pay_in' ? '+' : '−'}${_m(m.amount)}', style: T.sans(bd, size: 15, weight: FontWeight.w600).copyWith(fontFeatures: T.tnum)),
                ]),
              ),
          ],
        ]),
      ),
      const SizedBox(height: S.m),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        BdChip('Safe drop', icon: Ph.downloadSimple, onTap: () => _move(context, 'drop')),
        BdChip('Pay in', icon: Ph.plusCircle, onTap: () => _move(context, 'pay_in')),
        if (s.can(Cap.closeDay)) BdChip('Pay out', icon: Ph.minusCircle, onTap: () => _move(context, 'pay_out')),
      ]),
      const SizedBox(height: S.l),
      BdButton('Count and close', icon: Ph.money, onTap: mayClose ? () => _close(context) : null),
      if (!mayClose) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('${d.openedBy} or a shift lead closes this drawer.', style: T.caption(bd))),
    ]);
  }

  Future<void> _move(BuildContext context, String kind) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final go = await showBdSheet<bool>(context, title: _moveWord[kind], builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(switch (kind) {
          'drop' => 'Cash taken out to the safe, so the drawer doesn\'t hold too much.',
          'pay_in' => 'Cash put in that isn\'t a sale — more change, say.',
          _ => 'Cash paid out of the drawer — the ice delivery, a cab for a guest.',
        }, style: T.bodyMuted(bd)),
        const SizedBox(height: S.l),
        LineField(controller: amount, label: 'Amount (${venue.currency})', keyboard: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
        const SizedBox(height: S.l),
        if (kind != 'pay_in')
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final r in kind == 'drop' ? const ['safe drop', 'end of shift'] : const ['ice delivery', 'supplies', 'a cab for a guest'])
              BdChip(r, onTap: () => reason.text = r),
          ]),
        const SizedBox(height: S.s),
        LineField(controller: reason, label: 'What for', maxLength: 120),
        const SizedBox(height: S.l),
        BdButton('Record it', onTap: () => Navigator.pop(ctx, true)),
      ]);
    });
    final a = double.tryParse(amount.text.trim());
    final r = reason.text.trim();
    amount.dispose();
    reason.dispose();
    if (go != true || !context.mounted) return;
    if (a == null || a <= 0) return toast(context, 'That amount doesn\'t look right.', tone: ToastTone.error);
    await runAction(context, () => Backend.i.cashMove(d.id, kind, a, r), done: '${_moveWord[kind]} recorded.');
  }

  Future<void> _close(BuildContext context) async {
    // This card goes away the moment the drawer closes, so the report opens from the
    // navigator, which stays.
    final nav = Navigator.of(context);
    final report = await showBdSheet<CashReport>(context, title: 'Count the drawer', builder: (_) => _CountSheet(venue: venue, drawerId: d.id));
    if (report == null || !nav.mounted) return;
    await showBdSheet<void>(nav.context, title: 'Drawer closed', builder: (_) => CashReportView(venue: venue, report: report));
  }
}

/// The blind count: by notes and coins (when we know the currency's), or one number.
class _CountSheet extends StatefulWidget {
  final Venue venue;
  final String drawerId;
  const _CountSheet({required this.venue, required this.drawerId});
  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  late final List<double> _notes = denominations(widget.venue.currency);
  late bool _byNotes = _notes.isNotEmpty;
  late final Map<double, TextEditingController> _counts = {for (final n in _notes) n: TextEditingController()};
  final _total = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    _total.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _counted => _byNotes ? countTotal({for (final e in _counts.entries) e.key: int.tryParse(e.value.text.trim()) ?? 0}) : double.tryParse(_total.text.trim());

  String _noteWord(double n) => n >= 1 ? money(n, widget.venue.currency) : '${(n * 100).round()}${widget.venue.currency == 'INR' ? 'p' : 'c'}';

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final counted = _counted;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Count what\'s in it first — the app shows what should be there after.', style: T.bodyMuted(bd)),
      if (_notes.isNotEmpty) ...[
        const SizedBox(height: S.l),
        Segmented<bool>(options: const [(true, 'By notes'), (false, 'One number')], value: _byNotes, onChanged: (v) => setState(() => _byNotes = v)),
      ],
      const SizedBox(height: S.l),
      if (_byNotes)
        for (final n in _notes)
          Padding(
            padding: const EdgeInsets.only(bottom: S.s),
            child: Row(children: [
              SizedBox(width: 72, child: Text(_noteWord(n), style: T.sans(bd, size: 16, weight: FontWeight.w600).copyWith(fontFeatures: T.tnum))),
              Text('×', style: T.sans(bd, size: 16, color: bd.faint)),
              const SizedBox(width: S.m),
              Expanded(child: LineField(controller: _counts[n]!, hint: '0', keyboard: TextInputType.number, onChanged: (_) => setState(() {}))),
            ]),
          )
      else
        LineField(controller: _total, label: 'In the drawer (${widget.venue.currency})', keyboard: const TextInputType.numberWithOptions(decimal: true), autofocus: true, onChanged: (_) => setState(() {})),
      const SizedBox(height: S.m),
      Row(children: [
        Expanded(child: Text('Counted', style: T.sans(bd, size: 16, weight: FontWeight.w600))),
        RollingText(counted == null ? '—' : money(counted, widget.venue.currency, round: false), style: T.serif(bd, size: 28).copyWith(fontFeatures: T.tnum)),
      ]),
      const SizedBox(height: S.l),
      LineField(controller: _note, label: 'Note (optional)', hint: 'A tenner short — the 9 pm change?', maxLength: 200),
      const SizedBox(height: S.l),
      BdButton('Close the drawer', busy: _busy, onTap: counted == null
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                final rep = await Backend.i.closeDrawer(widget.drawerId, counted, note: _note.text);
                if (mounted) Navigator.pop(this.context, rep);
              } on BackendError catch (e) {
                if (mounted) {
                  setState(() => _busy = false);
                  toast(this.context, e.message, tone: ToastTone.error);
                }
              }
            }),
    ]);
  }
}

/// What a close kept: the difference first, then how it was reached.
class CashReportView extends StatelessWidget {
  final Venue venue;
  final CashReport report;
  final String? note;
  const CashReportView({super.key, required this.venue, required this.report, this.note});

  String _m(double x) => money(x, venue.currency, round: false);

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final r = report;
    Widget row(String k, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: T.sans(bd, size: 15, color: strong ? bd.ink : bd.muted, weight: strong ? FontWeight.w600 : FontWeight.w400))),
            Text(v, style: T.sans(bd, size: 15, weight: strong ? FontWeight.w600 : FontWeight.w400).copyWith(fontFeatures: T.tnum)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [ToneTag(countWord(r.difference, _m), _resultTone(r.difference))]),
      const SizedBox(height: S.m),
      row('Counted', _m(r.counted), strong: true),
      row('Should have held', _m(r.expected), strong: true),
      const SizedBox(height: S.s),
      row('Float', _m(r.float)),
      if (r.payIns > 0) row('Pay-ins', '+${_m(r.payIns)}'),
      if (r.payOuts > 0) row('Pay-outs', '−${_m(r.payOuts)}'),
      if (r.drops > 0) row('Safe drops', '−${_m(r.drops)}'),
      const SizedBox(height: S.m),
      Text('SINCE IT OPENED', style: T.label(bd)),
      const SizedBox(height: S.xs),
      row('Bills settled', '${r.bills}'),
      row('Sales', _m(r.sales)),
      if (r.tips > 0) row('Tips', _m(r.tips)),
      for (final e in r.byMethod.entries) row('Paid by ${e.key}', _m(e.value)),
      if (r.voids > 0) row('Voided lines', '${r.voids}'),
      if ((note ?? '').isNotEmpty) ...[const SizedBox(height: S.m), Text('“$note”', style: T.sans(bd, size: 15, color: bd.muted))],
      const SizedBox(height: S.l),
      Text('Kept as it is — a close can\'t be changed afterwards.', style: T.caption(bd)),
    ]);
  }
}
