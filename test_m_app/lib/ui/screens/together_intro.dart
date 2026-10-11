// Together, before you're in — so the tab is always there. Signed out, it shows
// what the other room is (what lives here, how private it stays) and one clear way
// in. No made-up friends: the feed is only ever real people.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'landing_screen.dart' show showAuthSheet;

class TogetherIntro extends StatelessWidget {
  const TogetherIntro({super.key});

  static const _rooms = [
    (Ph.cheers, 'Feed', 'What friends are pouring — only what each of them chose to share.'),
    (Ph.calendarPlus, 'Plans', 'Plan a night. Friends, or friends of friends, ask to join; you say who comes.'),
    (Ph.usersThree, 'Circles', 'A private room for a few of you: one combined mosaic, opt-in challenges.'),
    (Ph.confetti, 'Parties', 'One night, one room. Everyone logs, and the party page becomes the recap.'),
    (Ph.receipt, 'Split', 'Who bought which round — settled at the table, not the next morning.'),
  ];

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ScrollPage(
      title: 'Together',
      subtitle: 'Your calendar stays yours and quiet. This is the other room — what friends are pouring.',
      children: [
        const SectionHeader('What lives here'),
        Group(children: [
          for (final r in _rooms)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.m),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: bd.accent.withValues(alpha: .14)),
                  child: Icon(r.$1, size: 18, color: bd.accentText),
                ),
                const SizedBox(width: S.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.$2, style: T.sans(bd, size: 16, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(r.$3, style: T.body(bd, color: bd.muted)),
                  ]),
                ),
              ]),
            ),
        ]),
        const SizedBox(height: S.m),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Ph.lock, size: 16, color: bd.faint)),
          const SizedBox(width: S.s),
          Expanded(child: Text('Every entry starts private. Sharing is a separate tap, always after the fact — and friends peek at your mosaic, never your scores.', style: T.caption(bd))),
        ]),
        const SizedBox(height: S.x3),
        Glass(
          padding: const EdgeInsets.all(S.xxl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Bring your friends in.', style: T.serif(bd, size: 28, height: 1.1)),
            const SizedBox(height: S.s),
            Text('Together needs a diary — just your email. Your nights on this phone come with you.', style: T.bodyMuted(bd)),
            const SizedBox(height: S.xl),
            BdButton('Create a diary', onTap: () => showAuthSheet(context, signup: true)),
            const SizedBox(height: S.xs),
            Center(child: TextAction('I already have one — sign in', accent: true, onTap: () => showAuthSheet(context, signup: false))),
          ]),
        ),
      ],
    );
  }
}
