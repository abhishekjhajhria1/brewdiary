// The morning after — a few kind, plain things for the day after a night out.
// Opened from the morning check-in (if you asked for one) and from the calendar
// on a morning after you logged a drink. General care, not medical advice; the
// one thing it's firm about is when to get help.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/entries.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

Future<void> showMorningAfter(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MorningAfterScreen()));

/// A morning (5–12h) after an evening with a drink that had alcohol in it.
bool morningAfterWorthOffering(DateTime now) {
  if (now.hour < 5 || now.hour >= 12) return false;
  final yesterday = toKey(addDays(now, -1));
  return entryStore.entries.any((e) => e.date == yesterday && isAlcoholic(e.drink, e.type));
}

class MorningAfterScreen extends StatelessWidget {
  const MorningAfterScreen({super.key});

  static const _care = [
    (Ph.drop, 'Water first', 'A big glass now, then keep sipping through the morning. Alcohol dries you out; this is most of the fix.'),
    (Ph.dropHalf, 'Salt and a little sugar', 'Oral rehydration salts, coconut water, or nimbu pani with a pinch of salt and sugar put back what the night took.'),
    (Ph.leaf, 'Something plain to eat', 'Toast, a banana, eggs, khichdi or curd rice — gentle and steady. Greasy food feels right and rarely helps.'),
    (Ph.coffee, 'Easy on the coffee', 'One cup is fine. More can leave you shakier and drier.'),
    (Ph.moonStars, 'Rest, and skip the "hair of the dog"', 'Another drink only postpones the morning. Sleep and time do the rest.'),
    (Ph.warningCircle, 'Careful with painkillers', 'Avoid paracetamol after a heavy night — it and alcohol are both hard on the liver. Ibuprofen with food is kinder, if your stomach is settled. A pharmacist can tell you what suits you.'),
  ];

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final today = todayKey();
    final hasDryToday = entryStore.entries.any((e) => e.date == today && e.type == DrinkType.none);
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SubPage(
          title: 'The morning after',
          subtitle: 'Go gently. A few things that actually help.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: BdButton('+ Water', kind: BtnKind.secondary, icon: Ph.drop, onTap: () {
                  entryStore.addEntry(date: today, drink: 'Water', type: DrinkType.soft);
                  toast(context, 'A glass of water, logged. Keep them coming.');
                }),
              ),
              const SizedBox(width: S.s),
              Expanded(
                child: BdButton(hasDryToday ? 'Dry today ✓' : 'Dry today', kind: BtnKind.secondary, icon: Ph.leaf, onTap: hasDryToday
                    ? null
                    : () {
                        entryStore.addEntry(date: today, drink: dryDayLabel, type: DrinkType.none);
                        toast(context, "Today's a dry day. It keeps your streak.");
                      }),
              ),
            ]),
            const SizedBox(height: S.xl),
            Group(children: [
              for (final (icon, title, body) in _care)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.m),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, size: 22, color: bd.accentText),
                    const SizedBox(width: S.m),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: T.row(bd)),
                        const SizedBox(height: 2),
                        Text(body, style: T.body(bd, color: bd.muted)),
                      ]),
                    ),
                  ]),
                ),
            ]),
            const SizedBox(height: S.xl),
            Glass(
              strong: true,
              padding: const EdgeInsets.all(S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Get help now if', style: T.row(bd, color: bd.accentText)),
                const SizedBox(height: S.xs),
                Text(
                  'someone can\'t stay awake, is confused, keeps vomiting, has slow or irregular breathing, cold or bluish skin, or a seizure. That\'s alcohol poisoning, not a hangover — don\'t let them sleep it off.',
                  style: T.body(bd),
                ),
                const SizedBox(height: S.m),
                BdButton('Call 112', icon: Ph.phone, onTap: () => launchUrl(Uri.parse('tel:112'))),
                const SizedBox(height: S.xs),
                Text('112 is India\'s emergency number. Elsewhere, use your local one.', style: T.caption(bd)),
              ]),
            ),
            const SizedBox(height: S.l),
            Text('General care, not medical advice. If you\'re unwell or unsure, talk to a doctor or pharmacist.', style: T.caption(bd)),
          ]),
        ),
      ),
    );
  }
}
