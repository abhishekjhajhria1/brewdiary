// Circles — a port of src/components/together/Circles.tsx. A private room: a few
// friends, one combined mosaic, what was shared into it, and opt-in challenges.
// The list lives in Together; each circle opens as its own page.
import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/circles.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';
import '../widgets/social.dart';

class CirclesSection extends StatelessWidget {
  const CirclesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: S.l),
      Text('Private rooms — a few friends, one shared mosaic.', style: T.bodyMuted(bd)),
      const SizedBox(height: S.m),
      Row(children: [
        Expanded(child: BdButton('New circle', kind: BtnKind.secondary, icon: Ph.plus, height: 44, onTap: () => showBdSheet(context, title: 'New circle', builder: (_) => const _CircleForm(join: false)))),
        const SizedBox(width: S.s),
        Expanded(child: BdButton('Join with code', kind: BtnKind.secondary, icon: Ph.ticket, height: 44, onTap: () => showBdSheet(context, title: 'Join a circle', builder: (_) => const _CircleForm(join: true)))),
      ]),
      const SizedBox(height: S.l),
      Loader<List<Circle>>(
        retry: true,
        refresh: circlesRev,
        load: CirclesApi.mine,
        builder: (context, circles, loading) {
          if (circles == null) return const Skeleton(height: 112);
          if (circles.isEmpty) {
            return const EmptyNote('A circle is a private room — a few friends, one combined mosaic. Start one, or join with a code.', icon: Ph.usersThree);
          }
          return Group(children: [
            for (final c in circles)
              GroupTile(
                icon: Ph.usersThree,
                title: c.name,
                subtitle: '${c.memberCount} ${c.memberCount == 1 ? 'member' : 'members'}',
                chevron: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CircleScreen(circle: c))),
              ),
          ]);
        },
      ),
    ]);
  }
}

/// Start a circle, or join one with its code.
class _CircleForm extends StatefulWidget {
  final bool join;
  const _CircleForm({required this.join});
  @override
  State<_CircleForm> createState() => _CircleFormState();
}

class _CircleFormState extends State<_CircleForm> {
  final _draft = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_draft.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = widget.join ? (await CirclesApi.join(_draft.text)).error : await CirclesApi.create(_draft.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
      toast(context, widget.join ? "You're in." : 'Circle started — share its code from the circle page.');
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.join ? 'Paste the code a friend sent you.' : 'Name it for the people in it — the name is only seen inside.', style: T.bodyMuted(bd)),
      const SizedBox(height: S.xl),
      LineField(
        controller: _draft,
        autofocus: true,
        label: widget.join ? 'Invite code' : 'Circle name',
        hint: widget.join ? 'e.g. 7KQ2-M9' : '“tuesday tastings”',
        caps: widget.join ? TextCapitalization.characters : TextCapitalization.sentences,
        error: _error,
        action: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: S.xxl),
      BdButton(widget.join ? 'Join' : 'Create', busy: _busy, onTap: _draft.text.trim().isEmpty ? null : _submit),
    ]);
  }
}

class CircleScreen extends StatelessWidget {
  final Circle circle;
  const CircleScreen({super.key, required this.circle});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    return Loader<CircleDetail>(
      failed: (context, retry) => SubPage(title: circle.name, child: LoadError(onRetry: retry)),
      refresh: circlesRev,
      load: () => CirclesApi.detail(circle.id),
      builder: (context, detail, loading) {
        final members = detail?.members ?? const <CircleMember>[];
        final entries = detail?.entries ?? const <SharedEntry>[];
        final counts = <String, int>{};
        for (final e in entries) {
          counts[e.date] = (counts[e.date] ?? 0) + 1;
        }
        final mine = circle.createdBy == me;
        return SubPage(
          title: circle.name,
          subtitle: members.isEmpty ? null : members.map((m) => m.id == me ? 'you' : m.name).join(', '),
          onRefresh: () async => circlesRev.bump(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InviteCodeCard(code: circle.inviteCode, shareText: 'Join my brewdiary circle “${circle.name}” — code ${circle.inviteCode}'),
            const SectionHeader('Last 12 weeks, all of you'),
            Glass(padding: const EdgeInsets.all(S.l), child: RecentMosaic(counts: counts)),
            _CircleChallenges(circleId: circle.id),
            SectionHeader('Shared here', trailing: entries.isEmpty ? null : Text('${entries.length}', style: T.caption(bd))),
            if (detail == null)
              const Skeleton(height: 112)
            else if (entries.isEmpty)
              const EmptyNote('Nothing yet. Share an entry from your diary — open the day, tap ⋯, then Share with friends.', icon: Ph.cheers)
            else
              Group(children: [
                for (final e in entries)
                  GroupTile(
                    title: e.mood == null ? e.drink : '${e.drink} · ${e.mood}',
                    subtitle: '${e.userId == me ? 'you' : e.authorName} · ${shortDay(e.date)}${e.venue != null ? ' · ${e.venue}' : ''}',
                  ),
              ]),
            const SizedBox(height: S.section),
            if (mine)
              BdButton('Delete circle', kind: BtnKind.secondary, icon: Ph.trash, onTap: () async {
                if (await confirm(context, title: 'Delete for everyone?', body: 'The circle and what was shared into it go for all members.', yes: 'Delete')) {
                  await CirclesApi.delete(circle.id);
                  if (context.mounted) Navigator.pop(context);
                }
              })
            else
              BdButton('Leave circle', kind: BtnKind.secondary, icon: Ph.signOut, onTap: () async {
                if (await confirm(context, title: 'Leave ${circle.name}?', body: 'You can come back with the code any time.', yes: 'Leave')) {
                  await CirclesApi.leave(circle.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }),
          ]),
        );
      },
    );
  }
}

class _CircleChallenges extends StatelessWidget {
  final String circleId;
  const _CircleChallenges({required this.circleId});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Challenges', action: 'New', onAction: () => showBdSheet(context, title: 'New challenge', builder: (_) => _NewChallenge(circleId: circleId))),
      Loader<List<Challenge>>(
        refresh: challengesRev,
        load: () => ChallengesApi.forCircle(circleId),
        builder: (context, list, loading) {
          if (list == null) return const Skeleton(height: 96);
          if (list.isEmpty) return const EmptyNote('None running. Anyone in the circle can start one — joining is opt-in.', icon: Ph.trophy);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const SizedBox(height: S.m),
              _ChallengeCard(challenge: list[i]),
            ],
            const SizedBox(height: S.s),
            Text('Opt-in — auto-scored challenges count only (never what you poured); competitions are judged by whoever started them. Nothing shows on any calendar.', style: T.caption(bd)),
          ]);
        },
      ),
    ]);
  }
}

class _NewChallenge extends StatefulWidget {
  final String circleId;
  const _NewChallenge({required this.circleId});
  @override
  State<_NewChallenge> createState() => _NewChallengeState();
}

class _NewChallengeState extends State<_NewChallenge> {
  bool _competition = false;
  final _title = TextEditingController();
  final _rule = TextEditingController();
  ChallengeKind _kind = ChallengeKind.daysKept;
  int _nights = 7;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _rule.dispose();
    super.dispose();
  }

  bool get _canStart => !_competition || (_title.text.trim().isNotEmpty && _rule.text.trim().isNotEmpty);

  Future<void> _start() async {
    if (_busy || !_canStart) return;
    setState(() => _busy = true);
    final starts = todayKey();
    final ends = toKey(addDays(parseKey(starts), (_nights < 1 ? 1 : _nights) - 1));
    await ChallengesApi.create(widget.circleId, kind: _competition ? ChallengeKind.freeform : _kind, startsOn: starts, endsOn: ends, title: _title.text, rule: _competition ? _rule.text : null);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Label('Start from'),
      const SizedBox(height: S.xs),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        for (final p in challengePresets)
          BdChip(p.title, active: _title.text == p.title, onTap: () => setState(() {
                _competition = p.kind.isFreeform;
                if (!p.kind.isFreeform) _kind = p.kind;
                _title.text = p.title;
                _nights = p.days;
              })),
      ]),
      const SizedBox(height: S.xl),
      Segmented<bool>(options: const [(false, 'Challenge'), (true, 'Competition')], value: _competition, onChanged: (v) => setState(() => _competition = v)),
      const SizedBox(height: S.s),
      Text(_competition ? 'You set the rule and pick the winner.' : 'Scored automatically from what people log — counts only.', style: T.caption(bd)),
      const SizedBox(height: S.xl),
      LineField(controller: _title, label: 'Name', hint: _competition ? 'Best homemade cocktail' : 'Negroni Week (optional)', onChanged: (_) => setState(() {})),
      const SizedBox(height: S.xl),
      if (!_competition) ...[
        const Label('Scored by'),
        const SizedBox(height: S.xs),
        Wrap(spacing: S.s, runSpacing: S.s, children: [for (final k in scoredKinds) BdChip(k.label, active: _kind == k, onTap: () => setState(() => _kind = k))]),
      ] else ...[
        const Label('The rule'),
        const SizedBox(height: S.s),
        GlassField(controller: _rule, maxLines: 3, hint: 'Post your best pour; everyone votes on the last night.', onChanged: (_) => setState(() {})),
      ],
      const SizedBox(height: S.xl),
      const Label('How long'),
      const SizedBox(height: S.xs),
      Wrap(spacing: S.s, children: [for (final n in [7, 14, 30]) BdChip('$n nights', active: _nights == n, onTap: () => setState(() => _nights = n))]),
      const SizedBox(height: S.xxl),
      BdButton('Start tonight', busy: _busy, onTap: _canStart ? _start : null),
    ]);
  }
}

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  const _ChallengeCard({required this.challenge});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    final joined = me != null && challenge.participantIds.contains(me);
    final ended = challenge.endsOn.compareTo(todayKey()) < 0;
    final creator = challenge.createdBy == me;
    final heading = (challenge.title?.trim().isNotEmpty ?? false) ? challenge.title!.trim() : challenge.kind.label;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.m, S.xs, S.m),
      child: Loader<List<BoardRow>>(
        refresh: challengesRev,
        load: () => ChallengesApi.board(challenge),
        builder: (context, board, loading) {
          final rows = board ?? const <BoardRow>[];
          final top = rows.isEmpty ? 0 : rows.first.value;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(heading, style: T.sans(bd, size: 16, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${shortDay(challenge.startsOn)} – ${shortDay(challenge.endsOn)}${ended ? ' · ended' : ''}', style: T.caption(bd)),
                ]),
              ),
              if (!ended && me != null) joined ? TextAction('Leave', onTap: () => ChallengesApi.leave(challenge.id)) : TextAction('Join in', accent: true, onTap: () => ChallengesApi.join(challenge.id)),
              if (creator)
                IconBtn(Ph.dotsThree, tooltip: 'More for $heading', color: bd.muted, onTap: () => showActions(context, title: heading, actions: [
                      SheetAction('Remove challenge', icon: Ph.trash, destructive: true, onTap: () => ChallengesApi.delete(challenge.id)),
                    ])),
            ]),
            if (challenge.kind.isFreeform && challenge.rule != null)
              Padding(padding: const EdgeInsets.only(top: S.s, right: S.m), child: Text(challenge.rule!, style: T.body(bd, color: bd.muted).copyWith(fontStyle: FontStyle.italic))),
            const SizedBox(height: S.s),
            if (board == null)
              const Padding(padding: EdgeInsets.only(right: S.m), child: Skeleton(height: 40, radius: rCtl))
            else if (rows.isEmpty)
              Text("No one's in yet.", style: T.caption(bd))
            else
              for (final r in rows)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Row(children: [
                    if (challenge.winnerId == r.userId) ...[Icon(PhFill.star, size: 14, color: bd.accentText), const SizedBox(width: 6)],
                    Expanded(
                      child: Text(
                        '${r.userId == me ? 'you' : r.name}${challenge.winnerId == r.userId ? ' · winner' : ''}',
                        style: T.sans(bd, size: 15, color: challenge.winnerId == r.userId ? bd.accentText : (r.userId == me ? bd.ink : bd.muted)),
                      ),
                    ),
                    if (challenge.kind.isFreeform)
                      (creator ? TextAction(challenge.winnerId == r.userId ? 'Clear' : 'Pick winner', onTap: () => ChallengesApi.setWinner(challenge.id, challenge.winnerId == r.userId ? null : r.userId)) : const SizedBox.shrink())
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: S.m),
                        child: Text('${r.value} ${challenge.kind.unit}', style: T.sans(bd, size: 15, color: r.value == top && top > 0 ? bd.accentText : bd.muted).copyWith(fontFeatures: T.tnum)),
                      ),
                  ]),
                ),
          ]);
        },
      ),
    );
  }
}
