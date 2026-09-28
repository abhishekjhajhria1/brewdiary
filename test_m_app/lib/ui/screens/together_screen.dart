// Together — a port of src/components/together/Together.tsx (+ Circles.tsx,
// Parties.tsx). The calendar stays yours and quiet; this is the other room. The feed
// leads; plans, circles and parties wait behind their own segment; "Board" only
// exists for people who switched the leaderboard on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/date.dart';
import '../../core/derive.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/circles.dart';
import '../../data/entries.dart';
import '../../data/friends.dart';
import '../../data/parties.dart';
import '../../data/safety.dart';
import '../../data/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import '../widgets/share_card.dart';
import 'party_screens.dart';
import 'plans_section.dart';
import 'split_screen.dart';

enum _Room { feed, plans, circles, parties, board }

const _roomLabel = {_Room.feed: 'Feed', _Room.plans: 'Plans', _Room.circles: 'Circles', _Room.parties: 'Parties', _Room.board: 'Board'};

class TogetherScreen extends StatefulWidget {
  const TogetherScreen({super.key});
  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  _Room _room = _Room.feed;

  @override
  void initState() {
    super.initState();
    // A party link opened before signing in — honour it now.
    final pending = consumePendingPartyCode();
    if (pending != null) {
      PartiesApi.join(pending).then((r) {
        if (r.id != null && mounted) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: r.id!)));
        }
      });
    }
  }

  Future<void> _refresh() async {
    for (final r in [friendsRev, profileRev, plansRev, circlesRev, partiesRev, pointsRev]) {
      r.bump();
    }
  }

  void _openSplit() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SplitScreen()));

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ScrollPage(
      title: 'Together',
      actions: [IconBtn(Ph.receipt, tooltip: 'Split a tab', onTap: _openSplit)],
      onRefresh: _refresh,
      children: [
        Loader<(List<SocialProfile>, bool)>(
          refresh: Listenable.merge([friendsRev, profileRev]),
          load: () async {
            final r = await Future.wait<Object>([FriendsApi.friends(), PointsApi.competeVisible()]);
            return (r[0] as List<SocialProfile>, r[1] as bool);
          },
          builder: (context, data, loading) {
            final friends = data?.$1 ?? const <SocialProfile>[];
            final compete = data?.$2 ?? false;
            final rooms = [_Room.feed, _Room.plans, _Room.circles, _Room.parties, if (compete) _Room.board];
            final room = rooms.contains(_room) ? _room : _Room.feed;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Your calendar stays yours and quiet. This is the other room — what friends are pouring.', style: T.bodyMuted(bd)),
              const SizedBox(height: S.xl),
              Segmented<_Room>(
                options: [for (final r in rooms) (r, _roomLabel[r]!)],
                value: room,
                onChanged: (r) => setState(() => _room = r),
              ),
              switch (room) {
                _Room.feed => _Feed(friends: friends),
                _Room.plans => const PlansSection(),
                _Room.circles => const CirclesSection(),
                _Room.parties => const PartiesSection(),
                _Room.board => const _FriendsBoard(),
              },
              const SizedBox(height: S.section),
              Group(children: [
                GroupTile(icon: Ph.receipt, title: 'Split a tab', subtitle: 'Who paid, who owes — settled at the table.', chevron: true, onTap: _openSplit),
              ]),
            ]);
          },
        ),
      ],
    );
  }
}

// ── the feed ─────────────────────────────────────────────────────────────────
class _Feed extends StatelessWidget {
  final List<SocialProfile> friends;
  const _Feed({required this.friends});

  @override
  Widget build(BuildContext context) {
    return Loader<List<FeedEntry>>(
      refresh: friendsRev,
      load: FriendsApi.feed,
      builder: (context, feed, loading) {
        final items = feed ?? const <FeedEntry>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _People(friends: friends),
          _FriendPicks(feed: items),
          if (friends.isEmpty)
            const EmptyNote("Add a friend by their handle to see what they're pouring.")
          else if (loading && feed == null)
            const Padding(padding: EdgeInsets.only(top: 28), child: Column(children: [Skeleton(height: 110), SizedBox(height: 12), Skeleton(height: 110)]))
          else if (items.isEmpty)
            const EmptyNote('Quiet so far — nothing shared to friends yet. Share an entry from your diary and it lands here.')
          else ...[
            const SizedBox(height: 28),
            for (final item in items) Padding(padding: const EdgeInsets.only(bottom: 12), child: _FeedCard(item: item)),
          ],
        ]);
      },
    );
  }
}

class _People extends StatefulWidget {
  final List<SocialProfile> friends;
  const _People({required this.friends});
  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  bool _adding = false;
  final _query = TextEditingController();
  List<SocialProfile> _results = [];
  final Set<String> _requested = {};
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final r = await FriendsApi.search(q);
      if (mounted) {
        setState(() {
          _results = r;
          _searching = false;
        });
      }
    });
  }

  Future<void> _add(String id) async {
    setState(() => _requested.add(id));
    final err = await FriendsApi.sendRequest(id);
    if (err != null && mounted) setState(() => _requested.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final searchOpen = _adding || widget.friends.isEmpty;
    final friendIds = widget.friends.map((f) => f.id).toSet();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Loader<List<FriendRequest>>(
          refresh: friendsRev,
          load: FriendsApi.requests,
          builder: (context, reqs, _) {
            if (reqs == null || reqs.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Label('Friend requests', color: bd.faint),
                const SizedBox(height: 12),
                for (final r in reqs)
                  Glass(
                    margin: const EdgeInsets.only(bottom: 8),
                    radius: rCtl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${r.profile.name} ', style: T.sans(bd)),
                            TextSpan(text: '@${r.profile.handle}', style: T.sans(bd, color: bd.faint)),
                          ]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextAction('Accept', accent: true, onTap: () => FriendsApi.accept(r.friendshipId)),
                      const SizedBox(width: 12),
                      TextAction('Ignore', faint: true, onTap: () => FriendsApi.decline(r.friendshipId)),
                    ]),
                  ),
              ]),
            );
          },
        ),
        if (widget.friends.isNotEmpty)
          SizedBox(
            height: 76,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in widget.friends)
                GestureDetector(
                  onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: f)),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Column(children: [
                      Initial(f.initial),
                      const SizedBox(height: 8),
                      Text(f.name, style: T.sans(bd, size: 12, color: bd.muted)),
                    ]),
                  ),
                ),
              GestureDetector(
                onTap: () => setState(() {
                  _adding = !_adding;
                  _query.clear();
                  _results = [];
                }),
                child: Column(children: [
                  Initial('+', color: _adding ? bd.accent : bd.muted),
                  const SizedBox(height: 8),
                  Text(_adding ? 'Close' : 'Add', style: T.sans(bd, size: 12, color: bd.muted)),
                ]),
              ),
            ]),
          ),
        if (searchOpen) ...[
          const SizedBox(height: 16),
          GlassField(controller: _query, hint: 'Add a friend by name or @handle', onChanged: _onQuery, autofocus: _adding, caps: TextCapitalization.none),
          if (_query.text.trim().length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(children: [
                if (_searching && _results.isEmpty) Align(alignment: Alignment.centerLeft, child: Text('Searching…', style: T.sans(bd, size: 14, color: bd.faint))),
                if (!_searching && _results.isEmpty) Align(alignment: Alignment.centerLeft, child: Text('No one by that name or handle.', style: T.sans(bd, size: 14, color: bd.faint))),
                for (final p in _results)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    child: Row(children: [
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: '${p.name} ', style: T.sans(bd)),
                          TextSpan(text: '@${p.handle}', style: T.sans(bd, color: bd.faint)),
                        ])),
                      ),
                      TextAction(
                        friendIds.contains(p.id) ? 'Friends' : (_requested.contains(p.id) ? 'Requested' : 'Add'),
                        accent: !friendIds.contains(p.id) && !_requested.contains(p.id),
                        onTap: friendIds.contains(p.id) || _requested.contains(p.id) ? null : () => _add(p.id),
                      ),
                    ]),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }
}

/// "To try, from friends" — drinks friends pour that you haven't logged.
class _FriendPicks extends StatelessWidget {
  final List<FeedEntry> feed;
  const _FriendPicks({required this.feed});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Watch(
      to: [entryStore, wishlist],
      builder: (context) {
        final picks = friendPicks(
          feed.map((f) => (drink: f.drink, author: f.author.id)).toList(),
          entryStore.entries.map((e) => e.drink).toList(),
          wishlist.items.map((w) => w.drink).toList(),
          4,
        );
        if (picks.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label('To try, from friends', color: bd.faint),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in picks)
                Glass(
                  radius: rCtl,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  onTap: () {
                    wishlist.add(d);
                    toast(context, 'Saved $d to your to-try list');
                  },
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '$d ', style: T.sans(bd, size: 14)),
                    TextSpan(text: '+', style: T.sans(bd, size: 14, color: bd.accent)),
                  ])),
                ),
            ]),
          ]),
        );
      },
    );
  }
}

class _FeedCard extends StatefulWidget {
  final FeedEntry item;
  const _FeedCard({required this.item});
  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> {
  bool _showComments = false;
  bool _saved = false;
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final item = widget.item;
    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: item.author)),
              child: Text(item.author.name, style: T.sans(bd)),
            ),
          ),
          Text('${timeOfDayLabel(item.createdAt).toLowerCase()} · ${shortDay(item.date)}', style: T.sans(bd, size: 12, color: bd.faint)),
        ]),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: [
          TextSpan(text: item.drink, style: T.serif(bd, size: 26, height: 1.15)),
          if (item.mood != null) TextSpan(text: ' · ${item.mood}', style: T.serif(bd, size: 20, italic: true, color: bd.muted)),
        ])),
        if (item.note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.note!, style: T.sans(bd, color: bd.muted, height: 1.55))),
        if (item.venue != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.venue!, style: T.sans(bd, size: 12, color: bd.faint))),
        const SizedBox(height: 10),
        Row(children: [
          TextAction(item.cheered ? 'Cheered${item.cheers > 0 ? ' ${item.cheers}' : ''}' : 'Cheers${item.cheers > 0 ? ' ${item.cheers}' : ''}',
              accent: item.cheered, onTap: () => FriendsApi.toggleCheers(item.id, item.cheered)),
          const SizedBox(width: 20),
          TextAction(item.comments.isNotEmpty ? 'Comments ${item.comments.length}' : 'Comment', onTap: () => setState(() => _showComments = !_showComments)),
          const Spacer(),
          TextAction(_saved ? 'On your list ✓' : 'To try', faint: _saved, onTap: _saved
              ? null
              : () {
                  wishlist.add(item.drink);
                  setState(() => _saved = true);
                }),
        ]),
        if (_showComments)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: bd.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in item.comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${c.authorName} ', style: T.sans(bd, size: 14)),
                    TextSpan(text: c.body, style: T.sans(bd, size: 14, color: bd.muted)),
                  ])),
                ),
              Row(children: [
                Expanded(child: LineField(controller: _draft, hint: 'Add a comment…', size: 14, onChanged: (_) => setState(() {}))),
                const SizedBox(width: 8),
                TextAction('POST', size: 12, onTap: _draft.text.trim().isEmpty
                    ? null
                    : () {
                        FriendsApi.addComment(item.id, _draft.text);
                        _draft.clear();
                        setState(() {});
                      }),
              ]),
            ]),
          ),
      ]),
    );
  }
}

/// Peeking at a friend's mosaic — never their scores. Plus vouch + safety.
class _FriendSheet extends StatelessWidget {
  final SocialProfile friend;
  const _FriendSheet({required this.friend});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<String>>(
      load: () => FriendsApi.friendDates(friend.id),
      builder: (context, dates, _) {
        final counts = <String, int>{};
        for (final d in dates ?? const <String>[]) {
          counts[d] = (counts[d] ?? 0) + 1;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Initial(friend.initial, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(friend.name, style: T.serif(bd, size: 24)),
                const SizedBox(height: 4),
                Text('@${friend.handle} · ${dates?.length ?? 0} shared', style: T.sans(bd, size: 12, color: bd.faint)),
              ]),
            ),
          ]),
          const SizedBox(height: 28),
          Label('Their last 12 weeks', color: bd.faint),
          const SizedBox(height: 12),
          RecentMosaic(counts: counts),
          _VouchRow(friend: friend),
          const SizedBox(height: 16),
          Row(children: [
            TextAction('Report', faint: true, onTap: () => showReportSheet(context, friend.id, friend.name)),
            const SizedBox(width: 16),
            TextAction('Block', faint: true, onTap: () async {
              if (await confirm(context, title: 'Block ${friend.name}?', body: "They won't be able to find you, and any plan between you is withdrawn.", yes: 'Block')) {
                await SafetyApi.block(friend.id);
                if (context.mounted) Navigator.pop(context);
              }
            }),
          ]),
          const SizedBox(height: 12),
          Text("Peeking at a friend's mosaic — never their scores. Together is for the glance, not the scoreboard.", style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
        ]);
      },
    );
  }
}

class _VouchRow extends StatelessWidget {
  final SocialProfile friend;
  const _VouchRow({required this.friend});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<Set<String>>(
      refresh: vouchRev,
      load: VouchApi.vouchedByMe,
      builder: (context, ids, loading) {
        final has = ids?.contains(friend.id) ?? false;
        return Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.only(top: 16),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: bd.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Vouch for ${friend.name}', style: T.sans(bd, size: 14))),
              SizedBox(
                width: 110,
                child: has
                    ? LineButton('Vouched ✓', height: 36, onTap: () => VouchApi.unvouch(friend.id))
                    : InkButton('Vouch', height: 36, uppercase: false, onTap: () async {
                        final err = await VouchApi.vouch(friend.id);
                        if (err != null && context.mounted) toast(context, err);
                      }),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              "Stake your word that they're a real person you know — it gently raises their standing. It's a count, never a rating, and you can undo it any time.",
              style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
            ),
          ]),
        );
      },
    );
  }
}

/// Report someone — write-only, to the safety team, never back to anyone.
Future<void> showReportSheet(BuildContext context, String userId, String name, {String? planId}) {
  return showBdSheet(context, builder: (_) => _ReportSheet(userId: userId, name: name, planId: planId));
}

class _ReportSheet extends StatefulWidget {
  final String userId;
  final String name;
  final String? planId;
  const _ReportSheet({required this.userId, required this.name, this.planId});
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _note = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (_sent) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Thanks for telling us.', style: T.serif(bd, size: 28)),
        const SizedBox(height: 10),
        Text('Our safety team will look at it. Nothing about this report is shared with ${widget.name}.', style: T.sans(bd, color: bd.muted, height: 1.6)),
        const SizedBox(height: 20),
        InkButton('Done', onTap: () => Navigator.pop(context)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Report ${widget.name}', style: T.serif(bd, size: 28)),
      const SizedBox(height: 16),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in reportReasons.entries) BdChip(r.value, active: _reason == r.key, onTap: () => setState(() => _reason = r.key)),
      ]),
      const SizedBox(height: 16),
      GlassField(controller: _note, hint: 'Anything we should know? (optional)', maxLines: 3),
      const SizedBox(height: 20),
      InkButton('Send report', busy: _busy, onTap: _reason == null
          ? null
          : () async {
              setState(() => _busy = true);
              final err = await SafetyApi.report(widget.userId, _reason!, note: _note.text, planId: widget.planId);
              if (!mounted) return;
              setState(() {
                _busy = false;
                _sent = err == null;
              });
              if (err != null) toast(this.context, err);
            }),
    ]);
  }
}

// ── the friends leaderboard (opt-in on both sides) ───────────────────────────
class _FriendsBoard extends StatelessWidget {
  const _FriendsBoard();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    return Loader<List<PointRow>>(
      refresh: pointsRev,
      load: PointsApi.friendsBoard,
      builder: (context, board, loading) {
        if (board == null) return const Padding(padding: EdgeInsets.only(top: 28), child: Skeleton(height: 120));
        if (board.isEmpty) return const EmptyNote('Quiet board. Sparks come from showing up; vibe is what your table and the bar hand you.');
        final top = board.first.sparks;
        final mine = board.indexWhere((r) => r.userId == me);
        return Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label('You and the friends who opted in', color: bd.faint),
            const SizedBox(height: 8),
            Hairlines(children: [
              for (var i = 0; i < board.length; i++) _pointRow(bd, i + 1, board[i].userId == me ? 'you' : board[i].name, board[i].sparks, board[i].vibe, board[i].sparks > 0 && board[i].sparks == top),
            ]),
            if (mine >= 0) ...[
              const SizedBox(height: 16),
              LineButton('Share your score', onTap: () => showScoreCard(context, Score(name: 'you', sparks: board[mine].sparks, vibe: board[mine].vibe, context: 'with friends', rank: mine + 1, of: board.length))),
            ],
            const SizedBox(height: 16),
            Text('Nobody is ranked by what they spent. Switch this off any time in You → Settings.', style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
          ]),
        );
      },
    );
  }
}

Widget _pointRow(BD bd, int rank, String name, int sparks, int vibe, bool leads, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        SizedBox(width: 20, child: Text('$rank', style: T.sans(bd, size: 12, color: bd.faint))),
        Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: T.sans(bd))),
        Text.rich(TextSpan(children: [
          TextSpan(text: '$sparks ', style: T.sans(bd, size: 14, color: leads ? bd.accent : bd.muted)),
          TextSpan(text: 'sparks', style: T.sans(bd, size: 12, color: bd.faint)),
          if (vibe > 0) ...[
            TextSpan(text: '   $vibe ', style: T.sans(bd, size: 14, color: bd.muted)),
            TextSpan(text: 'vibe', style: T.sans(bd, size: 12, color: bd.faint)),
          ],
        ])),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ]),
    );

Widget pointRow(BD bd, int rank, String name, int sparks, int vibe, bool leads, {Widget? trailing}) => _pointRow(bd, rank, name, sparks, vibe, leads, trailing: trailing);

// ── circles ──────────────────────────────────────────────────────────────────
class CirclesSection extends StatefulWidget {
  const CirclesSection({super.key});
  @override
  State<CirclesSection> createState() => _CirclesSectionState();
}

class _CirclesSectionState extends State<CirclesSection> {
  String _mode = 'idle'; // idle | new | join
  final _draft = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_draft.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    if (_mode == 'new') {
      err = await CirclesApi.create(_draft.text);
    } else {
      err = (await CirclesApi.join(_draft.text)).error;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err == null) {
        _draft.clear();
        _mode = 'idle';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Private rooms — a few friends, one shared mosaic.', style: T.sans(bd, size: 14, color: bd.faint))),
          TextAction('New', accent: _mode == 'new', onTap: () => setState(() => _mode = _mode == 'new' ? 'idle' : 'new')),
          const SizedBox(width: 12),
          TextAction('Join with code', accent: _mode == 'join', onTap: () => setState(() => _mode = _mode == 'join' ? 'idle' : 'join')),
        ]),
        if (_mode != 'idle') ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GlassField(controller: _draft, autofocus: true, hint: _mode == 'new' ? 'Name the circle — “tuesday tastings”…' : 'Paste the invite code', onSubmitted: (_) => _submit(), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            SizedBox(width: 90, child: InkButton(_mode == 'new' ? 'Create' : 'Join', height: 44, uppercase: false, busy: _busy, onTap: _draft.text.trim().isEmpty ? null : _submit)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.muted))),
        ],
        const SizedBox(height: 12),
        Loader<List<Circle>>(
          refresh: circlesRev,
          load: CirclesApi.mine,
          builder: (context, circles, loading) {
            if (circles == null) return const Skeleton(height: 56);
            if (circles.isEmpty) {
              return _mode == 'idle'
                  ? Text('A circle is a private room — a few friends, one combined mosaic. Start one, or join with a code.', style: T.sans(bd, size: 14, color: bd.faint, height: 1.5))
                  : const SizedBox.shrink();
            }
            return Column(children: [
              for (final c in circles)
                Glass(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => showBdSheet(context, builder: (_) => _CircleSheet(circle: c)),
                  child: Row(children: [
                    Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis, style: T.sans(bd))),
                    Text('${c.memberCount} ${c.memberCount == 1 ? 'member' : 'members'}', style: T.sans(bd, size: 12, color: bd.faint)),
                  ]),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

class _CircleSheet extends StatelessWidget {
  final Circle circle;
  const _CircleSheet({required this.circle});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    return Loader<CircleDetail>(
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
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(circle.name, style: T.serif(bd, size: 26)),
          const SizedBox(height: 4),
          Text(members.isEmpty ? '…' : members.map((m) => m.id == me ? 'you' : m.name).join(', '), style: T.sans(bd, size: 12, color: bd.faint)),
          const SizedBox(height: 20),
          _CodeRow(label: 'Invite code', code: circle.inviteCode),
          const SizedBox(height: 24),
          Label('Last 12 weeks, all of you', color: bd.faint),
          const SizedBox(height: 12),
          RecentMosaic(counts: counts),
          _CircleChallenges(circleId: circle.id),
          const SizedBox(height: 28),
          Label('Shared here', color: bd.faint),
          const SizedBox(height: 8),
          if (detail == null)
            const Skeleton(height: 64)
          else if (entries.isEmpty)
            Text('Nothing yet. Share an entry from your diary — tap it, then Share.', style: T.sans(bd, size: 14, color: bd.faint))
          else
            Hairlines(children: [
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: e.drink, style: T.sans(bd)),
                      if (e.mood != null) TextSpan(text: ' · ${e.mood}', style: T.sans(bd, color: bd.muted).copyWith(fontStyle: FontStyle.italic)),
                    ])),
                    const SizedBox(height: 2),
                    Text('${e.userId == me ? 'you' : e.authorName} · ${shortDay(e.date)}${e.venue != null ? ' · ${e.venue}' : ''}', style: T.sans(bd, size: 12, color: bd.faint)),
                  ]),
                ),
            ]),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: mine
                ? TextAction('Delete circle', faint: true, onTap: () async {
                    if (await confirm(context, title: 'Delete for everyone?', body: 'The circle and what was shared into it go for all members.', yes: 'Delete')) {
                      await CirclesApi.delete(circle.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  })
                : TextAction('Leave circle', faint: true, onTap: () async {
                    await CirclesApi.leave(circle.id);
                    if (context.mounted) Navigator.pop(context);
                  }),
          ),
        ]);
      },
    );
  }
}

/// An invite code with a copy action.
class _CodeRow extends StatelessWidget {
  final String label;
  final String code;
  const _CodeRow({required this.label, required this.code});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: bd.line))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label(label, color: bd.faint),
            const SizedBox(height: 2),
            SelectableText(code, style: T.sans(bd, spacing: 2).copyWith(fontFeatures: T.tnum)),
          ]),
        ),
        TextAction('Copy', onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          toast(context, 'Copied');
        }),
      ]),
    );
  }
}

Widget codeRow(String label, String code) => _CodeRow(label: label, code: code);

class _CircleChallenges extends StatefulWidget {
  final String circleId;
  const _CircleChallenges({required this.circleId});
  @override
  State<_CircleChallenges> createState() => _CircleChallengesState();
}

class _CircleChallengesState extends State<_CircleChallenges> {
  bool _creating = false;
  bool _competition = false;
  final _title = TextEditingController();
  final _rule = TextEditingController();
  ChallengeKind _kind = ChallengeKind.longestStreak;
  int _nights = 7;
  bool _busy = false;

  bool get _canStart => !_competition || (_title.text.trim().isNotEmpty && _rule.text.trim().isNotEmpty);

  Future<void> _start() async {
    if (_busy || !_canStart) return;
    setState(() => _busy = true);
    final starts = todayKey();
    final ends = toKey(addDays(parseKey(starts), (_nights < 1 ? 1 : _nights) - 1));
    await ChallengesApi.create(widget.circleId,
        kind: _competition ? ChallengeKind.freeform : _kind, startsOn: starts, endsOn: ends, title: _title.text, rule: _competition ? _rule.text : null);
    if (!mounted) return;
    setState(() {
      _creating = false;
      _busy = false;
      _title.clear();
      _rule.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Label('Challenges', color: bd.faint)),
          TextAction('New', accent: _creating, onTap: () => setState(() => _creating = !_creating)),
        ]),
        if (_creating)
          Container(
            margin: const EdgeInsets.only(bottom: 12, top: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: bd.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, children: [
                BdChip('Challenge', active: !_competition, onTap: () => setState(() => _competition = false)),
                BdChip('Competition', active: _competition, onTap: () => setState(() => _competition = true)),
              ]),
              const SizedBox(height: 12),
              LineField(controller: _title, size: 14, hint: _competition ? 'Name it — e.g. Best homemade cocktail' : 'Name it (optional) — e.g. Negroni Week', onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              if (!_competition)
                Wrap(spacing: 6, runSpacing: 6, children: [for (final k in scoredKinds) BdChip(k.label, active: _kind == k, onTap: () => setState(() => _kind = k))])
              else
                GlassField(controller: _rule, maxLines: 3, hint: 'The rule — e.g. post your best pour; everyone votes on the last night. You pick the winner.', onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final n in [7, 14, 30]) BdChip('$n nights', active: _nights == n, onTap: () => setState(() => _nights = n)),
              ]),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: TextAction('Start tonight →', accent: true, onTap: _busy || !_canStart ? null : _start)),
            ]),
          ),
        Loader<List<Challenge>>(
          refresh: challengesRev,
          load: () => ChallengesApi.forCircle(widget.circleId),
          builder: (context, list, loading) {
            if (list == null) return const Skeleton(height: 48);
            if (list.isEmpty) {
              return _creating ? const SizedBox.shrink() : Text('None running. Anyone in the circle can start one — joining is opt-in.', style: T.sans(bd, size: 14, color: bd.faint, height: 1.5));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in list) _ChallengeBlock(challenge: c),
              const SizedBox(height: 8),
              Text('Opt-in — auto-scored challenges count only (never what you poured); competitions are judged by whoever started them. Nothing shows on any calendar.',
                  style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
            ]);
          },
        ),
      ]),
    );
  }
}

class _ChallengeBlock extends StatelessWidget {
  final Challenge challenge;
  const _ChallengeBlock({required this.challenge});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    final joined = me != null && challenge.participantIds.contains(me);
    final ended = challenge.endsOn.compareTo(todayKey()) < 0;
    final creator = challenge.createdBy == me;
    final heading = (challenge.title?.trim().isNotEmpty ?? false) ? challenge.title!.trim() : challenge.kind.label;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: bd.line))),
      child: Loader<List<BoardRow>>(
        refresh: challengesRev,
        load: () => ChallengesApi.board(challenge),
        builder: (context, board, loading) {
          final rows = board ?? const <BoardRow>[];
          final top = rows.isEmpty ? 0 : rows.first.value;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: heading, style: T.sans(bd)),
                  TextSpan(text: '  ${shortDay(challenge.startsOn)} – ${shortDay(challenge.endsOn)}${ended ? ' · ended' : ''}', style: T.sans(bd, size: 12, color: bd.faint)),
                ])),
              ),
              if (!ended && me != null)
                joined ? TextAction('Leave', faint: true, onTap: () => ChallengesApi.leave(challenge.id)) : TextAction('Join in', accent: true, onTap: () => ChallengesApi.join(challenge.id)),
              if (creator) ...[const SizedBox(width: 12), TextAction('Remove', faint: true, onTap: () => ChallengesApi.delete(challenge.id))],
            ]),
            if (challenge.kind.isFreeform && challenge.rule != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(challenge.rule!, style: T.sans(bd, size: 14, color: bd.muted).copyWith(fontStyle: FontStyle.italic))),
            const SizedBox(height: 6),
            if (board == null)
              Text('…', style: T.sans(bd, size: 14, color: bd.faint))
            else if (rows.isEmpty)
              Text("No one's in yet.", style: T.sans(bd, size: 14, color: bd.faint))
            else
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${r.userId == me ? 'you' : r.name}${challenge.winnerId == r.userId ? '  · WINNER' : ''}',
                        style: T.sans(bd, size: 14, color: challenge.winnerId == r.userId ? bd.accent : (r.userId == me ? bd.ink : bd.muted)),
                      ),
                    ),
                    if (challenge.kind.isFreeform)
                      (creator
                          ? TextAction(challenge.winnerId == r.userId ? 'clear' : 'pick winner', size: 12, faint: true, onTap: () => ChallengesApi.setWinner(challenge.id, challenge.winnerId == r.userId ? null : r.userId))
                          : const SizedBox.shrink())
                    else
                      Text('${r.value} ${challenge.kind.unit}', style: T.sans(bd, size: 14, color: r.value == top && top > 0 ? bd.accent : bd.muted)),
                  ]),
                ),
          ]);
        },
      ),
    );
  }
}

// ── parties ──────────────────────────────────────────────────────────────────
class PartiesSection extends StatefulWidget {
  const PartiesSection({super.key});
  @override
  State<PartiesSection> createState() => _PartiesSectionState();
}

class _PartiesSectionState extends State<PartiesSection> {
  String _mode = 'idle';
  final _name = TextEditingController();
  final _venue = TextEditingController();
  final _code = TextEditingController();
  DateTime _date = appNow();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_mode == 'new') {
      final r = await PartiesApi.create(name: _name.text, date: toKey(_date), venue: _venue.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = r.error;
        if (r.error == null) {
          _name.clear();
          _venue.clear();
          _date = appNow();
          _mode = 'idle';
        }
      });
    } else {
      final r = await PartiesApi.join(_code.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = r.error;
        if (r.error == null) {
          _code.clear();
          _mode = 'idle';
        }
      });
      if (r.id != null && mounted) {
        if (r.pending) toast(context, "Request sent to ${r.name} — the host will let you in.");
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: r.id!)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('One night, one room — everything guests share lands here.', style: T.sans(bd, size: 14, color: bd.faint))),
          TextAction('Host one', accent: _mode == 'new', onTap: () => setState(() => _mode = _mode == 'new' ? 'idle' : 'new')),
          const SizedBox(width: 12),
          TextAction('Join with code', accent: _mode == 'join', onTap: () => setState(() => _mode = _mode == 'join' ? 'idle' : 'join')),
        ]),
        if (_mode == 'new')
          Glass(
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Label("What's the occasion?"),
              const SizedBox(height: 6),
              LineField(controller: _name, autofocus: true, hint: 'Housewarming, friday tasting…', onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Label('When'),
                    const SizedBox(height: 6),
                    DateField(value: _date, onChanged: (d) => setState(() => _date = d)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Label('Where (optional)'),
                    const SizedBox(height: 6),
                    LineField(controller: _venue, hint: 'A bar, a flat…'),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              InkButton('Host it', uppercase: false, busy: _busy, onTap: _name.text.trim().isEmpty ? null : _submit),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.muted))),
            ]),
          ),
        if (_mode == 'join') ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GlassField(controller: _code, autofocus: true, hint: 'Paste the party code', caps: TextCapitalization.none, onChanged: (_) => setState(() {}), onSubmitted: (_) => _submit())),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: InkButton('Join', height: 44, uppercase: false, busy: _busy, onTap: _code.text.trim().isEmpty ? null : _submit)),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.muted))),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Loader<List<Party>>(
          refresh: partiesRev,
          load: PartiesApi.mine,
          builder: (context, parties, loading) {
            if (parties == null) return const Skeleton(height: 56);
            if (parties.isEmpty) {
              return _mode == 'idle'
                  ? Text('Host a night or join one with a code — everyone logs, the party page becomes the recap.', style: T.sans(bd, size: 14, color: bd.faint, height: 1.5))
                  : const SizedBox.shrink();
            }
            final today = todayKey();
            final upcoming = parties.where((p) => p.date.compareTo(today) >= 0).toList();
            final past = parties.where((p) => p.date.compareTo(today) < 0).toList();
            Widget tile(Party p, bool muted) => Glass(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: p.id))),
                  child: Row(children: [
                    Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis, style: T.sans(bd, color: muted ? bd.muted : bd.ink))),
                    Text('${shortDay(p.date)} · ${p.going} going', style: T.sans(bd, size: 12, color: bd.faint)),
                  ]),
                );
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final p in upcoming) tile(p, false),
              if (past.isNotEmpty) ...[
                if (upcoming.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12, bottom: 8), child: Label('Recaps', color: bd.faint)),
                for (final p in past) tile(p, true),
              ],
            ]);
          },
        ),
      ]),
    );
  }
}

/// A date field that opens the house date wheels.
class DateField extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;
  final String? label;
  const DateField({super.key, required this.value, required this.onChanged, this.first, this.last, this.label});
  @override
  Widget build(BuildContext context) {
    return PickerField(
      label: label,
      value: toKey(value) == todayKey() ? 'Today' : writtenDate(value),
      icon: Ph.calendarBlank,
      onTap: () async {
        final picked = await pickDate(context, initial: value, first: first, last: last, title: label ?? 'Pick a date');
        if (picked != null) onChanged(picked);
      },
    );
  }
}
