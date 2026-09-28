// The taste card — what you're into, in a few words, to hold up for a bartender.
//
// It's worked out on this phone from your diary and shown on your screen, nothing
// more: brewdiary never sends it to a venue (no diary ever reaches a bar). You
// choose what shows — hide any line — and "Nothing with alcohol tonight" puts that
// first, in big type, for the nights you're sitting it out.
import 'package:flutter/material.dart';

import '../../core/derive.dart';
import '../../core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

Future<void> showTasteCard(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TasteCardScreen()));

const _kindWords = {
  DrinkType.cocktail: 'Cocktails',
  DrinkType.beer: 'Beer',
  DrinkType.wine: 'Wine',
  DrinkType.spirit: 'Spirits',
  DrinkType.coffee: 'Coffee',
  DrinkType.tea: 'Tea',
  DrinkType.soft: 'Soft drinks',
  DrinkType.other: 'Something else',
};

class TasteCardScreen extends StatefulWidget {
  const TasteCardScreen({super.key});
  @override
  State<TasteCardScreen> createState() => _TasteCardScreenState();
}

class _TasteCardScreenState extends State<TasteCardScreen> {
  static const _hiddenKey = 'brewdiary.tastecard.hidden';
  late final Set<String> _hidden = {...(Prefs.getJson<List<dynamic>>(_hiddenKey) ?? const []).map((e) => '$e')};
  bool _dryTonight = false;

  void _toggle(String line) {
    setState(() => _hidden.contains(line) ? _hidden.remove(line) : _hidden.add(line));
    Prefs.setJson(_hiddenKey, _hidden.toList());
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = tasteProfile(entryStore.entries);
    final name = auth.profile?.name;
    final lines = <(String key, String label, String value)>[
      if (p.favourites.isNotEmpty) ('into', 'Into', p.favourites.join(', ')),
      if (p.kinds.isNotEmpty) ('usually', 'Usually', p.kinds.map((k) => _kindWords[k] ?? k.name).join(' · ')),
      if (p.moods.isNotEmpty) ('mood', 'In the mood for', p.moods.join(', ')),
      if (p.noAlcoholShare >= .4) ('free', 'Often', 'alcohol-free — happy with a good non-alcoholic pour'),
    ];

    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SubPage(
          title: name == null ? 'My taste' : "$name's taste",
          subtitle: 'Hold this up for the bartender.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Glass(
              strong: true,
              padding: const EdgeInsets.all(S.xxl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_dryTonight) ...[
                  Text('NOTHING WITH ALCOHOL TONIGHT', style: T.label(bd, color: bd.accentText)),
                  const SizedBox(height: S.s),
                  Text('Surprise me with something good and alcohol-free.', style: T.serif(bd, size: 26, height: 1.2)),
                  if (lines.any((l) => !_hidden.contains(l.$1))) Divider(height: S.x3, color: bd.line),
                ],
                if (p.basedOn < 5 && !_dryTonight)
                  Text('Log a few more drinks and this fills in — it learns from your diary.', style: T.bodyMuted(bd)),
                for (final l in lines)
                  if (!_hidden.contains(l.$1))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.s),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.$2.toUpperCase(), style: T.label(bd)),
                        const SizedBox(height: 4),
                        Text(l.$3, style: T.serif(bd, size: 24, height: 1.2)),
                      ]),
                    ),
              ]),
            ),
            const SizedBox(height: S.xl),
            Group(children: [
              SettingRow(
                title: 'Nothing with alcohol tonight',
                hint: 'Puts it first, in big type.',
                trailing: BdToggle(on: _dryTonight, label: 'Nothing with alcohol tonight', onChanged: (v) => setState(() => _dryTonight = v)),
              ),
              for (final l in lines)
                SettingRow(
                  title: 'Show "${l.$2}"',
                  trailing: BdToggle(on: !_hidden.contains(l.$1), label: 'Show ${l.$2}', onChanged: (_) => _toggle(l.$1)),
                ),
            ]),
            const SizedBox(height: S.l),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Ph.lock, size: 16, color: bd.faint)),
              const SizedBox(width: S.s),
              Expanded(
                child: Text(
                  'Worked out on this phone from the last six months of your diary, and shown on your screen only. brewdiary never sends it to a venue.',
                  style: T.caption(bd),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
