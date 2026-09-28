// Split — a port of src/components/split/Split.tsx. Who bought which round. A split
// has no venue, so it uses the person's OWN currency (set at the age gate from where
// they said they are; changeable in You → settings).
import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/misc.dart';
import '../../core/money.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/friends.dart';
import '../../data/settings.dart';
import '../../data/split.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

String _money(double n) => formatMoney(((n.abs()) * 100).round() / 100, PlaceStore.instance.currency);

class SplitScreen extends StatelessWidget {
  const SplitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.profile;
    return SubPage(
      title: 'split',
      child: Loader<(List<SocialProfile>, ({List<Expense> expenses, List<Settlement> settlements}))>(
        refresh: Listenable.merge([splitRev, friendsRev]),
        load: () async => (await FriendsApi.friends(), await SplitApi.load()),
        builder: (context, data, loading) {
          final friends = data?.$1 ?? const <SocialProfile>[];
          final expenses = data?.$2.expenses ?? const <Expense>[];
          final settlements = data?.$2.settlements ?? const <Settlement>[];
          final names = {if (me != null) me.id: 'You', for (final f in friends) f.id: f.name};
          String nameOf(String id) => names[id] ?? 'friend';
          final balances = me == null ? <String, double>{} : computeBalances(expenses, settlements, me.id);
          final owed = balances.values.where((v) => v > 0).fold<double>(0, (a, b) => a + b);
          final owe = balances.values.where((v) => v < 0).fold<double>(0, (a, b) => a - b);

          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PageHeader('Split'),
            Text('Who bought which round. Split a tab with friends, and keep the tally quiet until someone settles up.', style: T.sans(bd, color: bd.muted, height: 1.6)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Label("You're owed", color: bd.faint),
                    const SizedBox(height: 4),
                    Text(_money(owed), style: T.serif(bd, size: 24, color: bd.accent)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Label('You owe', color: bd.faint),
                    const SizedBox(height: 4),
                    Text(_money(owe), style: T.serif(bd, size: 24)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Opacity(
              opacity: friends.isEmpty ? .4 : 1,
              child: Pressable(
                enabled: friends.isNotEmpty && me != null,
                onTap: () => showBdSheet(context, builder: (_) => _AddExpense(meId: me!.id, meName: me.name, friends: friends)),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(rCtl)),
                  child: Text('ADD AN EXPENSE', style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.accentContrast, spacing: 1.7)),
                ),
              ),
            ),
            if (friends.isEmpty) const EmptyNote('Add a friend in Together first — splitting takes two.'),
            if (balances.isNotEmpty) ...[
              const SizedBox(height: 32),
              Label('Balances', color: bd.faint),
              const SizedBox(height: 12),
              Hairlines(children: [
                for (final b in balances.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(children: [
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${nameOf(b.key)} ', style: T.sans(bd)),
                          TextSpan(text: b.value > 0 ? 'owes you ' : '— you owe ', style: T.sans(bd, color: bd.muted)),
                          TextSpan(text: _money(b.value), style: T.sans(bd, weight: FontWeight.w500, color: b.value > 0 ? bd.accent : bd.ink)),
                        ])),
                      ),
                      TextAction('Settle up', onTap: () => SplitApi.settleUp(b.key, b.value.abs(), friendOwesMe: b.value > 0)),
                    ]),
                  ),
              ]),
            ],
            const SizedBox(height: 32),
            Label('Recent', color: bd.faint),
            const SizedBox(height: 12),
            if (data == null)
              const Column(children: [Skeleton(height: 64), SizedBox(height: 8), Skeleton(height: 64)])
            else if (expenses.isEmpty)
              Text('No rounds split yet.', style: T.sans(bd, size: 14, color: bd.faint))
            else
              for (final e in expenses)
                Glass(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.description, overflow: TextOverflow.ellipsis, style: T.sans(bd)),
                        Text(
                          '${e.payerId == me?.id ? 'You' : nameOf(e.payerId)} paid · split ${e.shares.isEmpty ? 1 : e.shares.length} ${e.shares.length == 1 ? 'way' : 'ways'} · ${shortDay(toKey(DateTime.parse(e.createdAt).toLocal()))}',
                          style: T.sans(bd, size: 12, color: bd.faint),
                        ),
                      ]),
                    ),
                    Text(_money(e.amount), style: T.sans(bd)),
                    if (e.payerId == me?.id) ...[const SizedBox(width: 12), TextAction('Remove', size: 12, faint: true, onTap: () => SplitApi.deleteExpense(e.id))],
                  ]),
                ),
          ]);
        },
      ),
    );
  }
}

class _AddExpense extends StatefulWidget {
  final String meId;
  final String meName;
  final List<SocialProfile> friends;
  const _AddExpense({required this.meId, required this.meName, required this.friends});
  @override
  State<_AddExpense> createState() => _AddExpenseState();
}

class _AddExpenseState extends State<_AddExpense> {
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  late String _payer = widget.meId;
  late final Set<String> _parts = {widget.meId};
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final people = [(widget.meId, 'You'), for (final f in widget.friends) (f.id, f.name)];
    final amt = double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
    final valid = _desc.text.trim().isNotEmpty && amt > 0 && _parts.length >= 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Split a tab', style: T.serif(bd, size: 26)),
      const SizedBox(height: 20),
      Label('What was it', color: bd.faint),
      const SizedBox(height: 6),
      LineField(controller: _desc, autofocus: true, hint: 'Round at The Kernel', onChanged: (_) => setState(() {})),
      const SizedBox(height: 20),
      Label('Total (${currencySymbol(PlaceStore.instance.currency)})', color: bd.faint),
      const SizedBox(height: 6),
      LineField(controller: _amount, hint: '0', keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
      const SizedBox(height: 20),
      Label('Who paid', color: bd.faint),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [for (final p in people) BdChip(p.$2, active: _payer == p.$1, onTap: () => setState(() => _payer = p.$1))]),
      const SizedBox(height: 20),
      Label('Split between', color: bd.faint),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in people)
          BdChip(p.$2, active: _parts.contains(p.$1), onTap: () => setState(() => _parts.contains(p.$1) ? _parts.remove(p.$1) : _parts.add(p.$1))),
      ]),
      if (valid) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${_money(amt / _parts.length)} each · ${_parts.length} people', style: T.sans(bd, size: 12, color: bd.faint))),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accent))),
      const SizedBox(height: 20),
      InkButton('Add expense', busy: _busy, onTap: !valid
          ? null
          : () async {
              setState(() {
                _busy = true;
                _error = null;
              });
              final err = await SplitApi.addExpense(payerId: _payer, description: _desc.text, amount: amt, participantIds: _parts.toList());
              if (!mounted) return;
              if (err != null) {
                setState(() {
                  _busy = false;
                  _error = err;
                });
              } else {
                Navigator.pop(this.context);
              }
            }),
    ]);
  }
}
