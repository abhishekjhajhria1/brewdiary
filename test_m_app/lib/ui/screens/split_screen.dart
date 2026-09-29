// Split — a port of src/components/split/Split.tsx. Who bought which round. A split
// has no venue, so it uses the person's OWN currency (set at the age gate from where
// they said they are; changeable in You → Settings).
import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/misc.dart';
import '../../core/money.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/friends.dart';
import '../../data/settings.dart';
import '../../data/split.dart';
import '../home_widget.dart';
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
    return Loader<(List<SocialProfile>, ({List<Expense> expenses, List<Settlement> settlements}))>(
      failed: (context, retry) => SubPage(title: 'Split', child: LoadError(onRetry: retry)),
      refresh: Listenable.merge([splitRev, friendsRev]),
      load: () async => (await FriendsApi.friends(), await SplitApi.load()),
      builder: (context, data, loading) {
        final friends = data?.$1 ?? const <SocialProfile>[];
        final expenses = data?.$2.expenses ?? const <Expense>[];
        final settlements = data?.$2.settlements ?? const <Settlement>[];
        final names = {if (me != null) me.id: 'You', for (final f in friends) f.id: f.name};
        String nameOf(String id) => names[id] ?? 'A friend';
        final balances = me == null ? <String, double>{} : computeBalances(expenses, settlements, me.id);
        final owed = balances.values.where((v) => v > 0).fold<double>(0, (a, b) => a + b);
        final owe = balances.values.where((v) => v < 0).fold<double>(0, (a, b) => a - b);
        if (data != null) HomeWidget.noteSplit(owed: owed, owe: owe, currency: PlaceStore.instance.currency);
        final canAdd = friends.isNotEmpty && me != null;
        void add() => showBdSheet(context, title: 'Split a tab', builder: (_) => _AddExpense(meId: me!.id, friends: friends));

        Widget stat(String label, double v, {bool accent = false}) => Expanded(
              child: Glass(
                padding: const EdgeInsets.all(S.l),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: T.caption(bd)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_money(v), maxLines: 1, style: T.serif(bd, size: 28, color: accent && v > 0 ? bd.accentText : bd.ink).copyWith(fontFeatures: T.tnum)),
                  ),
                ]),
              ),
            );

        return SubPage(
          title: 'Split',
          subtitle: 'Who bought which round. Split a tab with friends and keep the tally quiet until someone settles up.',
          actions: [IconBtn(Ph.plus, tooltip: 'Add an expense', onTap: canAdd ? add : null)],
          onRefresh: () async => splitRev.bump(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [stat("You're owed", owed, accent: true), const SizedBox(width: S.m), stat('You owe', owe)]),
            const SizedBox(height: S.l),
            BdButton('Add an expense', icon: Ph.plus, onTap: canAdd ? add : null),
            if (friends.isEmpty && data != null) const EmptyNote('Add a friend in Together first — splitting takes two.', icon: Ph.users),
            if (balances.isNotEmpty) ...[
              const SectionHeader('Balances'),
              Group(children: [
                for (final b in balances.entries)
                  GroupTile(
                    title: nameOf(b.key),
                    subtitle: b.value > 0 ? 'owes you ${_money(b.value)}' : 'you owe ${_money(b.value)}',
                    trailing: TextAction('Settle up', accent: true, onTap: () async {
                      final what = b.value > 0 ? '${nameOf(b.key)} paid you ${_money(b.value)}' : 'You paid ${nameOf(b.key)} ${_money(b.value)}';
                      if (await confirm(context, title: 'Settle up?', body: '$what — this clears the balance between you.', yes: 'Settle up', no: 'Not yet')) {
                        SplitApi.settleUp(b.key, b.value.abs(), friendOwesMe: b.value > 0);
                      }
                    }),
                  ),
              ]),
            ],
            SectionHeader('Recent', trailing: expenses.isEmpty ? null : Text('${expenses.length}', style: T.caption(bd))),
            if (data == null)
              const Column(children: [Skeleton(height: 64), SizedBox(height: S.s), Skeleton(height: 64)])
            else if (expenses.isEmpty)
              const EmptyNote('No rounds split yet.', icon: Ph.receipt)
            else
              Group(children: [
                for (final e in expenses)
                  GroupTile(
                    title: e.description,
                    subtitle: '${e.payerId == me?.id ? 'You' : nameOf(e.payerId)} paid · split ${e.shares.isEmpty ? 1 : e.shares.length} ${e.shares.length == 1 ? 'way' : 'ways'} · ${shortDay(toKey(DateTime.parse(e.createdAt).toLocal()))}',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_money(e.amount), style: T.row(bd).copyWith(fontFeatures: T.tnum)),
                      if (e.payerId == me?.id)
                        IconBtn(Ph.dotsThree, tooltip: 'More for ${e.description}', color: bd.muted, onTap: () => showActions(context, title: e.description, actions: [
                              SheetAction('Remove this expense', icon: Ph.trash, destructive: true, onTap: () => SplitApi.deleteExpense(e.id)),
                            ])),
                    ]),
                  ),
              ]),
          ]),
        );
      },
    );
  }
}

class _AddExpense extends StatefulWidget {
  final String meId;
  final List<SocialProfile> friends;
  const _AddExpense({required this.meId, required this.friends});
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
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final people = [(widget.meId, 'You'), for (final f in widget.friends) (f.id, f.name)];
    final amt = double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0;
    final valid = _desc.text.trim().isNotEmpty && amt > 0 && _parts.length >= 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LineField(controller: _desc, autofocus: true, label: 'What was it', hint: 'Round at The Kernel', action: TextInputAction.next, onChanged: (_) => setState(() {})),
      const SizedBox(height: S.xl),
      LineField(controller: _amount, label: 'Total (${currencySymbol(PlaceStore.instance.currency)})', hint: '0', size: 22, keyboard: const TextInputType.numberWithOptions(decimal: true), action: TextInputAction.done, onChanged: (_) => setState(() {})),
      const SizedBox(height: S.xl),
      const Label('Who paid'),
      const SizedBox(height: S.xs),
      Wrap(spacing: S.s, children: [for (final p in people) BdChip(p.$2, active: _payer == p.$1, onTap: () => setState(() => _payer = p.$1))]),
      const SizedBox(height: S.l),
      const Label('Split between'),
      const SizedBox(height: S.xs),
      Wrap(spacing: S.s, children: [
        for (final p in people)
          BdChip(p.$2, icon: _parts.contains(p.$1) ? PhBold.check : null, active: _parts.contains(p.$1), onTap: () => setState(() => _parts.contains(p.$1) ? _parts.remove(p.$1) : _parts.add(p.$1))),
      ]),
      const SizedBox(height: S.s),
      Text(valid ? '${_money(amt / _parts.length)} each · ${_parts.length} people' : 'Pick at least two people to split between.', style: T.caption(bd, color: valid ? bd.accentText : bd.faint)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: S.m), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
      const SizedBox(height: S.xxl),
      BdButton('Add expense', busy: _busy, onTap: !valid
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
