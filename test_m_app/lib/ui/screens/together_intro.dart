// Together, before you're in — so the tab is always there. Signed out, it shows
// what the other room is (a glimpse of a friend's pour, what lives here, how
// private it stays) and one clear way in. In a build that isn't connected to the
// brewdiary cloud it says so plainly instead of offering a sign-up that can't
// reach anyone.
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/auth.dart';
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
    final connected = Config.cloud;
    return ScrollPage(
      title: 'Together',
      subtitle: 'Your calendar stays yours and quiet. This is the other room — what friends are pouring.',
      children: [
        const _Glimpse(),
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
        if (connected)
          Glass(
            padding: const EdgeInsets.all(S.xxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Bring your friends in.', style: T.serif(bd, size: 28, height: 1.1)),
              const SizedBox(height: S.s),
              Text('Together needs a diary — an email and a password. Your nights on this phone come with you.', style: T.bodyMuted(bd)),
              const SizedBox(height: S.xl),
              BdButton('Create a diary', onTap: () => showAuthSheet(context, signup: true)),
              const SizedBox(height: S.xs),
              Center(child: TextAction('I already have one — sign in', accent: true, onTap: () => showAuthSheet(context, signup: false))),
            ]),
          )
        else
          Glass(
            padding: const EdgeInsets.all(S.xl),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Ph.info, size: 22, color: bd.accentText),
              const SizedBox(width: S.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("This build isn't connected yet", style: T.row(bd)),
                  const SizedBox(height: 4),
                  Text(
                    auth.isAuthed
                        ? 'Your diary, Ninkasi and Discover all work on this phone. Together reaches your friends through the brewdiary cloud, which this build was made without.'
                        : 'Your diary, Ninkasi and Discover all work on this phone. Together reaches your friends through the brewdiary cloud — it switches on in a connected build.',
                    style: T.body(bd, color: bd.muted),
                  ),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

/// A still glimpse of a friend's pour — what the feed looks like, not a real person.
class _Glimpse extends StatelessWidget {
  const _Glimpse();

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget card({required String name, required String when, required String drink, required String mood, String? note, required int cheers, bool front = false}) => Glass(
          strong: front,
          padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, S.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Initial(name[0], size: 30),
              const SizedBox(width: S.s),
              Text(name, style: T.sans(bd, size: 14, weight: FontWeight.w600)),
              const Spacer(),
              Text(when, style: T.caption(bd)),
            ]),
            const SizedBox(height: S.s),
            Text.rich(TextSpan(children: [
              TextSpan(text: drink, style: T.serif(bd, size: 22, height: 1.15)),
              TextSpan(text: '  $mood', style: T.serif(bd, size: 17, italic: true, color: bd.muted)),
            ])),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, style: T.sans(bd, size: 14, color: bd.muted))),
            const SizedBox(height: S.s),
            Row(children: [
              Icon(PhFill.cheers, size: 17, color: bd.accentText),
              const SizedBox(width: 5),
              Text('$cheers', style: T.sans(bd, size: 13, weight: FontWeight.w500, color: bd.accentText)),
              const SizedBox(width: S.l),
              Icon(Ph.chatCircle, size: 17, color: bd.muted),
            ]),
          ]),
        );
    return ExcludeSemantics(
      child: Stack(clipBehavior: Clip.none, children: [
        // The card behind, peeking out — the feed keeps going.
        Padding(
          padding: const EdgeInsets.fromLTRB(S.xxl, 0, S.xxl, 0),
          child: Opacity(opacity: .45, child: card(name: 'Arjun', when: 'Morning', drink: 'Pour-over', mood: 'slow', cheers: 1)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 34),
          // An opaque backing so the card behind doesn't show through the glass.
          child: DecoratedBox(
            decoration: BoxDecoration(color: bd.sheet, borderRadius: BorderRadius.circular(rTile)),
            child: card(name: 'Mira', when: 'Evening', drink: 'Mezcal Negroni', mood: 'smoky', note: 'Tried the house one at Soka — better than mine.', cheers: 3, front: true),
          ),
        ),
      ]),
    );
  }
}
