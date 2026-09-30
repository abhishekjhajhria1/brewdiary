// The loyalty card: up to three tiers, each its own punch-card with its own clock, and
// the quiet nights that make a visit count double. What a tier may BE depends on what
// the venue sells and where it is — the database decides; this screen explains.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../logic/perk_rules.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'numbers_screen.dart';

class PerksScreen extends StatefulWidget {
  final Venue venue;
  const PerksScreen({super.key, required this.venue});
  @override
  State<PerksScreen> createState() => _PerksScreenState();
}

class _PerksScreenState extends State<PerksScreen> {
  late List<int> _quiet = [...widget.venue.quietNights];
  Venue get v => widget.venue;
  PerkRules get rules => perkRules(v.kind, servesAlcohol: v.servesAlcohol, country: v.country, region: v.region);

  Future<void> _toggleQuiet(int d) async {
    final next = _quiet.contains(d) ? (_quiet.where((x) => x != d).toList()) : ([..._quiet, d]..sort());
    setState(() => _quiet = next);
    await runAction(context, () => Backend.i.updateVenue(v.id, quietNights: next));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final r = rules;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Loyalty card',
          back: true,
          tabBar: false,
          children: [
            Glass(
              padding: const EdgeInsets.all(S.l),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Ph.scales, size: 20, color: bd.muted),
                const SizedBox(width: S.m),
                Expanded(child: Text(r.note, style: T.sans(bd, size: 14, color: bd.muted, height: 1.5))),
              ]),
            ),
            if (!v.verified)
              Padding(
                padding: const EdgeInsets.only(top: S.m),
                child: Text('Tiers start once brewdiary verifies you (Setup) — an unverified venue can\'t promise a real-world reward.', style: T.caption(bd)),
              ),
            const SectionHeader('Tiers'),
            Loader<List<PerkTier>>(
              load: () => Backend.i.perks(v.id),
              refresh: perksRev,
              retry: true,
              builder: (context, tiers, loading) {
                if (tiers == null) return const Skeleton(height: 120);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (tiers.isEmpty) const EmptyNote('No tiers yet. "3 visits: a coffee. 10 visits: a dessert." is how most cards start.'),
                  if (tiers.isNotEmpty)
                    Group(children: [
                      for (final t in tiers)
                        GroupTile(
                          icon: Ph.gift,
                          title: t.reward,
                          subtitle: t.kind == PerkKind.spend ? 'after ${money(t.threshold, t.currency)} spent' : 'after ${t.threshold.toStringAsFixed(0)} visits',
                          trailing: IconBtn(Ph.trash, tooltip: 'Remove this tier', onTap: () async {
                            final yes = await confirm(context, title: 'Remove this tier?', body: 'Guests stop earning it. Rewards already claimed stay on the record.', yes: 'Remove');
                            if (yes && context.mounted) await runAction(context, () => Backend.i.removePerk(t.id), done: 'Removed.');
                          }),
                        ),
                    ]),
                  if (tiers.length < 3 && r.allowed && v.verified) ...[
                    const SizedBox(height: S.l),
                    BdButton('Add a tier', icon: Ph.plus, kind: BtnKind.secondary, onTap: () => _add(context, r)),
                  ],
                  if (tiers.length >= 3) Padding(padding: const EdgeInsets.only(top: S.m), child: Text('Three tiers is the most — a card people can remember.', style: T.caption(bd))),
                ]);
              },
            ),
            const SectionHeader('Quiet nights'),
            Text('A visit on a quiet night counts double toward the card. It rewards turning up — never drinking more, and never a discount on a drink.', style: T.caption(bd)),
            const SizedBox(height: S.m),
            Wrap(spacing: S.s, runSpacing: S.s, children: [
              for (var d = 0; d < 7; d++) BdChip(weekdayShort[d], active: _quiet.contains(d), onTap: () => _toggleQuiet(d)),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, PerkRules r) async {
    final threshold = TextEditingController(text: '5');
    final reward = TextEditingController();
    var kind = PerkKind.visits;
    var alcoholic = false;
    await showBdSheet<void>(context, title: 'A new tier', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.spend)
            Segmented<PerkKind>(options: const [(PerkKind.visits, 'Visits'), (PerkKind.spend, 'Spend')], value: kind, onChanged: (k) => set(() => kind = k)),
          const SizedBox(height: S.m),
          LineField(
            controller: threshold,
            label: kind == PerkKind.spend ? 'After spending (${v.currency})' : 'After this many visits',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: S.l),
          LineField(controller: reward, label: 'The reward', hint: v.sellsAlcohol ? 'A coffee on us' : 'A box of kaju katli', maxLength: 120),
          if (r.alcoholReward)
            SettingRow(
              title: 'The reward is a drink with alcohol',
              hint: 'Lawful here. Most venues pick something non-alcoholic anyway.',
              trailing: BdToggle(on: alcoholic, label: 'Alcoholic reward', onChanged: (x) => set(() => alcoholic = x)),
            ),
          const SizedBox(height: S.xl),
          BdButton('Add tier', onTap: () async {
            final n = double.tryParse(threshold.text.replaceAll(',', '').trim());
            if (n == null || n <= 0) return toast(ctx, 'Type a number above zero.');
            if (reward.text.trim().isEmpty) return toast(ctx, 'Say what they get.');
            final ok = await runAction(ctx, () => Backend.i.addPerk(v.id, kind: kind, threshold: n, reward: reward.text, rewardAlcoholic: alcoholic), done: 'Tier added.');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
          const SizedBox(height: S.s),
          Text('Private between each guest and you — never advertised, never on a leaderboard.', style: T.caption(bd)),
        ]);
      });
    });
    threshold.dispose();
    reward.dispose();
  }
}
