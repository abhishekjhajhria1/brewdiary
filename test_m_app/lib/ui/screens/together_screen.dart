// Together — a port of src/components/together/Together.tsx. The calendar stays
// yours and quiet; this is the other room. The feed leads; plans, circles and
// parties wait behind their own segment; "Board" only exists for people who
// switched the leaderboard on. Circles and parties live in their own files.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/derive.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/friends.dart';
import '../../data/parties.dart';
import '../../data/safety.dart';
import '../../data/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';
import '../widgets/share_card.dart';
import '../widgets/social.dart';
import 'circles_section.dart';
import 'parties_section.dart';
import 'party_screens.dart';
import 'plans_section.dart';
import 'split_screen.dart';

enum _Room { feed, plans, circles, parties, board }

const _roomLabel = {_Room.feed: 'Feed', _Room.plans: 'Plans', _Room.circles: 'Circles', _Room.parties: 'Parties', _Room.board: 'Board'};

Future<void> showAddFriend(BuildContext context) => showBdSheet(context, title: 'Add a friend', builder: (_) => const _AddFriendSheet());

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
    return ScrollPage(
      title: 'Together',
      subtitle: 'Your calendar stays yours and quiet. This is the other room — what friends are pouring.',
      actions: [
        IconBtn(Ph.userPlus, tooltip: 'Add a friend', onTap: () => showAddFriend(context)),
        IconBtn(Ph.receipt, tooltip: 'Split a tab', onTap: _openSplit),
      ],
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
              Segmented<_Room>(
                options: [for (final r in rooms) (r, _roomLabel[r]!)],
                value: room,
                onChanged: (r) => setState(() => _room = r),
              ),
              const SizedBox(height: S.xs),
              switch (room) {
                _Room.feed => _Feed(friends: friends, loadingFriends: data == null),
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
  final bool loadingFriends;
  const _Feed({required this.friends, required this.loadingFriends});

  @override
  Widget build(BuildContext context) {
    return Loader<List<FeedEntry>>(
      refresh: friendsRev,
      load: FriendsApi.feed,
      builder: (context, feed, loading) {
        final items = feed ?? const <FeedEntry>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Requests(),
          if (friends.isNotEmpty) _People(friends: friends),
          _FriendPicks(feed: items),
          if (loadingFriends || (loading && feed == null))
            const Padding(padding: EdgeInsets.only(top: S.xxl), child: Column(children: [Skeleton(height: 132), SizedBox(height: S.m), Skeleton(height: 132)]))
          else if (friends.isEmpty)
            EmptyNote("Add a friend by their handle to see what they're pouring.", icon: Ph.usersThree, action: 'Find a friend', onAction: () => showAddFriend(context))
          else if (items.isEmpty)
            const EmptyNote('Quiet so far — nothing shared to friends yet. Share an entry from your diary and it lands here.', icon: Ph.cheers)
          else ...[
            const SectionHeader('Lately'),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: S.m),
              FeedCard(item: items[i]),
            ],
          ],
        ]);
      },
    );
  }
}

class _Requests extends StatelessWidget {
  const _Requests();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<FriendRequest>>(
      refresh: friendsRev,
      load: FriendsApi.requests,
      builder: (context, reqs, _) {
        if (reqs == null || reqs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader('Friend requests', trailing: Text('${reqs.length}', style: T.caption(bd))),
          Group(children: [
            for (final r in reqs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.s),
                child: Row(children: [
                  Initial(r.profile.initial, size: 40),
                  const SizedBox(width: S.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.row(bd)),
                      Text('@${r.profile.handle}', style: T.caption(bd)),
                    ]),
                  ),
                  TextAction('Accept', accent: true, onTap: () => FriendsApi.accept(r.friendshipId)),
                  IconBtn(Ph.x, tooltip: 'Ignore ${r.profile.name}', size: 18, color: bd.faint, onTap: () => FriendsApi.decline(r.friendshipId)),
                ]),
              ),
          ]),
        ]);
      },
    );
  }
}

/// Your friends as a row of faces — tap one to peek at their mosaic.
class _People extends StatelessWidget {
  final List<SocialProfile> friends;
  const _People({required this.friends});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget person({required Widget face, required String name, required VoidCallback onTap, required String semantics}) => Semantics(
          button: true,
          label: semantics,
          excludeSemantics: true,
          child: Pressable(
            onTap: onTap,
            child: SizedBox(
              width: 68,
              child: Column(children: [
                face,
                const SizedBox(height: 6),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: T.caption(bd, color: bd.muted)),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Friends', trailing: Text('${friends.length}', style: T.caption(bd))),
      SizedBox(
        height: 84,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          person(
            face: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: bd.lineStrong, width: 1)),
              child: Icon(Ph.userPlus, size: 22, color: bd.accentText),
            ),
            name: 'Add',
            semantics: 'Add a friend',
            onTap: () => showAddFriend(context),
          ),
          for (final f in friends)
            person(
              face: Initial(f.initial, size: 52),
              name: f.name,
              semantics: '${f.name}, @${f.handle}',
              onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: f)),
            ),
        ]),
      ),
    ]);
  }
}

class _AddFriendSheet extends StatefulWidget {
  const _AddFriendSheet();
  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
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
    if (q.trim().replaceFirst('@', '').length < 2) {
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
    if (err != null && mounted) {
      setState(() => _requested.remove(id));
      toast(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final typed = _query.text.trim().replaceFirst('@', '').length >= 2;
    return Loader<List<SocialProfile>>(
      refresh: friendsRev,
      load: FriendsApi.friends,
      builder: (context, friends, _) {
        final friendIds = (friends ?? const <SocialProfile>[]).map((f) => f.id).toSet();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GlassField(controller: _query, hint: 'A name or @handle', icon: Ph.magnifyingGlass, autofocus: true, caps: TextCapitalization.none, action: TextInputAction.search, onChanged: _onQuery),
          const SizedBox(height: S.m),
          if (!typed)
            Text('Friends see what you choose to share — never your whole diary. They can peek at your mosaic, never your scores.', style: T.caption(bd))
          else if (_searching && _results.isEmpty)
            const Skeleton(height: 56)
          else if (_results.isEmpty)
            const EmptyNote('No one by that name or handle.')
          else
            Group(children: [
              for (final p in _results)
                GroupTile(
                  title: p.name,
                  subtitle: '@${p.handle}',
                  trailing: friendIds.contains(p.id)
                      ? Text('Friends', style: T.caption(bd))
                      : (_requested.contains(p.id) ? Text('Requested', style: T.caption(bd, color: bd.accentText)) : TextAction('Add', accent: true, icon: Ph.userPlus, onTap: () => _add(p.id))),
                ),
            ]),
        ]);
      },
    );
  }
}

/// "To try, from friends" — drinks friends pour that you haven't logged.
class _FriendPicks extends StatelessWidget {
  final List<FeedEntry> feed;
  const _FriendPicks({required this.feed});
  @override
  Widget build(BuildContext context) {
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
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('To try, from friends'),
          Wrap(spacing: S.s, children: [
            for (final d in picks)
              BdChip(d, icon: Ph.plus, onTap: () {
                wishlist.add(d);
                toast(context, 'Saved $d to your to-try list');
              }),
          ]),
        ]);
      },
    );
  }
}

/// One shared pour in the feed: who, what, the mood, cheers and comments.
class FeedCard extends StatefulWidget {
  final FeedEntry item;
  const FeedCard({super.key, required this.item});
  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard> {
  bool _showComments = false;
  bool _saved = false;
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _post() {
    if (_draft.text.trim().isEmpty) return;
    FriendsApi.addComment(widget.item.id, _draft.text);
    _draft.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final item = widget.item;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.m, S.s, S.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          label: "${item.author.name}'s mosaic",
          child: Pressable(
            onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: item.author)),
            child: Row(children: [
              Initial(item.author.initial, size: 34),
              const SizedBox(width: S.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 15, weight: FontWeight.w600)),
                  Text('${timeOfDayLabel(item.createdAt)} · ${shortDay(item.date)}', style: T.caption(bd)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: S.m),
        Padding(
          padding: const EdgeInsets.only(right: S.s),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: item.drink, style: T.serif(bd, size: 25, height: 1.15)),
            if (item.mood != null) TextSpan(text: '  ${item.mood}', style: T.serif(bd, size: 19, italic: true, color: bd.muted, height: 1.15)),
          ])),
        ),
        if (item.note != null) Padding(padding: const EdgeInsets.only(top: 6, right: S.s), child: Text(item.note!, style: T.body(bd, color: bd.muted))),
        if (item.venue != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Ph.mapPin, size: 14, color: bd.faint),
              const SizedBox(width: 4),
              Flexible(child: Text(item.venue!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(bd))),
            ]),
          ),
        const SizedBox(height: S.xs),
        Row(children: [
          _CardAction(
            icon: item.cheered ? PhFill.cheers : Ph.cheers,
            label: item.cheers > 0 ? '${item.cheers}' : 'Cheers',
            semantics: item.cheered ? 'Cheered, ${item.cheers}' : 'Cheers',
            active: item.cheered,
            onTap: () => FriendsApi.toggleCheers(item.id, item.cheered),
          ),
          _CardAction(
            icon: Ph.chatCircle,
            label: item.comments.isNotEmpty ? '${item.comments.length}' : 'Comment',
            semantics: item.comments.isNotEmpty ? '${item.comments.length} comments' : 'Comment',
            active: _showComments,
            onTap: () => setState(() => _showComments = !_showComments),
          ),
          const Spacer(),
          _CardAction(
            icon: _saved ? PhBold.check : Ph.plus,
            label: _saved ? 'On your list' : 'To try',
            semantics: _saved ? 'On your to-try list' : 'Add to your to-try list',
            active: _saved,
            onTap: _saved
                ? null
                : () {
                    wishlist.add(item.drink);
                    setState(() => _saved = true);
                  },
          ),
        ]),
        if (_showComments)
          Padding(
            padding: const EdgeInsets.only(right: S.s, bottom: S.s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Divider(height: S.l, thickness: .8, color: bd.line),
              for (final c in item.comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.s),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${c.authorName}  ', style: T.sans(bd, size: 14, weight: FontWeight.w600)),
                    TextSpan(text: c.body, style: T.sans(bd, size: 14, color: bd.muted, height: 1.45)),
                  ])),
                ),
              Row(children: [
                Expanded(child: GlassField(controller: _draft, hint: 'Add a comment', action: TextInputAction.send, onChanged: (_) => setState(() {}), onSubmitted: (_) => _post())),
                IconBtn(Ph.paperPlaneTilt, tooltip: 'Post comment', color: bd.accentText, onTap: _draft.text.trim().isEmpty ? null : _post),
              ]),
            ]),
          ),
      ]),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String semantics;
  final bool active;
  final VoidCallback? onTap;
  const _CardAction({required this.icon, required this.label, required this.semantics, this.active = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final color = active ? bd.accentText : bd.muted;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap ?? () {},
        enabled: onTap != null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: S.tap, minWidth: S.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.s),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(label, style: T.sans(bd, size: 14, weight: FontWeight.w500, color: color).copyWith(fontFeatures: T.tnum)),
            ]),
          ),
        ),
      ),
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
            Initial(friend.initial, size: 56),
            const SizedBox(width: S.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(friend.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.title(bd)),
                const SizedBox(height: 2),
                Text('@${friend.handle} · ${dates?.length ?? 0} shared', style: T.caption(bd)),
              ]),
            ),
          ]),
          const SectionHeader('Their last 12 weeks', padding: EdgeInsets.only(top: S.x3, bottom: S.m)),
          Glass(padding: const EdgeInsets.all(S.l), child: RecentMosaic(counts: counts)),
          _VouchRow(friend: friend),
          const SizedBox(height: S.m),
          Group(children: [
            GroupTile(icon: Ph.flag, title: 'Report ${friend.name}', onTap: () => showReportSheet(context, friend.id, friend.name)),
            GroupTile(icon: Ph.prohibit, title: 'Block ${friend.name}', destructive: true, onTap: () async {
              if (await confirm(context, title: 'Block ${friend.name}?', body: "They won't be able to find you, and any plan between you is withdrawn.", yes: 'Block')) {
                await SafetyApi.block(friend.id);
                if (context.mounted) Navigator.pop(context);
              }
            }),
          ]),
          const SizedBox(height: S.m),
          Text("Peeking at a friend's mosaic — never their scores. Together is for the glance, not the scoreboard.", style: T.caption(bd)),
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
    return Loader<Set<String>>(
      refresh: vouchRev,
      load: VouchApi.vouchedByMe,
      builder: (context, ids, loading) {
        final has = ids?.contains(friend.id) ?? false;
        return Padding(
          padding: const EdgeInsets.only(top: S.xl),
          child: Group(
            footer: "Stake your word that they're a real person you know — it gently raises their standing. It's a count, never a rating, and you can undo it any time.",
            children: [
              SettingRow(
                title: has ? 'You vouch for ${friend.name}' : 'Vouch for ${friend.name}',
                trailing: has
                    ? BdButton('Undo', kind: BtnKind.secondary, expand: false, height: 40, onTap: () => VouchApi.unvouch(friend.id))
                    : BdButton('Vouch', expand: false, height: 40, icon: Ph.sealCheck, onTap: () async {
                        final err = await VouchApi.vouch(friend.id);
                        if (err != null && context.mounted) toast(context, err);
                      }),
              ),
            ],
          ),
        );
      },
    );
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
        if (board == null) return const Padding(padding: EdgeInsets.only(top: S.xxl), child: Skeleton(height: 160));
        if (board.isEmpty) return const EmptyNote('Quiet board. Sparks come from showing up; vibe is what your table and the bar hand you.', icon: Ph.trophy);
        final top = board.first.sparks;
        final mine = board.indexWhere((r) => r.userId == me);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('You and the friends who opted in'),
          Group(children: [
            for (var i = 0; i < board.length; i++)
              PointsRow(rank: i + 1, name: board[i].userId == me ? 'You' : board[i].name, sparks: board[i].sparks, vibe: board[i].vibe, leads: board[i].sparks > 0 && board[i].sparks == top),
          ]),
          if (mine >= 0) ...[
            const SizedBox(height: S.l),
            BdButton('Share your score', kind: BtnKind.secondary, icon: Ph.shareNetwork, onTap: () => showScoreCard(context, Score(name: 'you', sparks: board[mine].sparks, vibe: board[mine].vibe, context: 'with friends', rank: mine + 1, of: board.length))),
          ],
          const SizedBox(height: S.m),
          Text('Nobody is ranked by what they spent. Switch this off any time in You → Settings.', style: T.caption(bd)),
        ]);
      },
    );
  }
}
