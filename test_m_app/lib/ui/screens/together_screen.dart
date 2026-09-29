// Together — a port of src/components/together/Together.tsx. The calendar stays
// yours and quiet; this is the other room. The feed leads; plans, circles and
// parties wait behind their own segment; "Board" only exists for people who
// switched the leaderboard on. Circles and parties live in their own files.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
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

Future<void> showAddFriend(BuildContext context) => showBdSheet(context, title: 'Add a friend', builder: (_) => const FriendSearch(autofocus: true));

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
    // Laid out like the website's Together: the title with the friend count, the
    // rooms as tabs, and Split as a quiet link at the foot.
    return Loader<(List<SocialProfile>, bool)>(
      retry: true,
      refresh: Listenable.merge([friendsRev, profileRev]),
      load: () async {
        final r = await Future.wait<Object>([FriendsApi.friends(), PointsApi.competeVisible()]);
        return (r[0] as List<SocialProfile>, r[1] as bool);
      },
      failed: (context, retry) => ScrollPage(title: 'Together', children: [LoadError(onRetry: retry)]),
      builder: (context, data, loading) {
        final bd = context.bd;
        final friends = data?.$1 ?? const <SocialProfile>[];
        final compete = data?.$2 ?? false;
        final rooms = [_Room.feed, _Room.plans, _Room.circles, _Room.parties, if (compete) _Room.board];
        final room = rooms.contains(_room) ? _room : _Room.feed;
        return ScrollPage(
          title: 'Together',
          titleNote: data == null ? null : '${friends.length} ${friends.length == 1 ? 'friend' : 'friends'}',
          subtitle: 'Your calendar stays yours and quiet. This is the other room — what friends are pouring.',
          onRefresh: _refresh,
          children: [
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
            const SizedBox(height: S.x3),
            // The website's foot: a hairline, a sentence, and "Split →".
            Semantics(
              button: true,
              label: 'Split a tab or a round with friends',
              excludeSemantics: true,
              child: Pressable(
                onTap: _openSplit,
                child: Container(
                  padding: const EdgeInsets.only(top: S.l, bottom: S.m),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: bd.line, width: .8))),
                  child: Row(children: [
                    Expanded(child: Text('Split a tab or a round with friends', style: T.body(bd, color: bd.muted))),
                    Text('Split →', style: T.sans(bd, size: 14, weight: FontWeight.w600, color: bd.accentText)),
                  ]),
                ),
              ),
            ),
          ],
        );
      },
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
    final bd = context.bd;
    return Loader<List<FeedEntry>>(
      retry: true,
      refresh: friendsRev,
      load: FriendsApi.feed,
      builder: (context, feed, loading) {
        final items = feed ?? const <FeedEntry>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: S.l),
          _People(friends: friends),
          _FriendPicks(feed: items),
          if (loadingFriends || (loading && feed == null))
            const Padding(padding: EdgeInsets.only(top: S.xxl), child: Column(children: [Skeleton(height: 112), SizedBox(height: S.m), Skeleton(height: 112)]))
          else if (friends.isEmpty)
            Padding(padding: const EdgeInsets.only(top: S.x3), child: Text("Add a friend by their handle to see what they're pouring.", textAlign: TextAlign.center, style: T.body(bd, color: bd.faint)))
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: S.x3),
              child: Text('Quiet so far — nothing shared to friends yet. Share an entry from your diary and it lands here.', textAlign: TextAlign.center, style: T.body(bd, color: bd.faint)),
            )
          else ...[
            const SizedBox(height: S.xxl),
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

/// Friend requests, the row of friends ending in "+ Add", and the search —
/// which, with no friends yet, is simply open (the website's People section).
class _People extends StatefulWidget {
  final List<SocialProfile> friends;
  const _People({required this.friends});
  @override
  State<_People> createState() => _PeopleState();
}

class _PeopleState extends State<_People> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final friends = widget.friends;
    final searchOpen = _adding || friends.isEmpty;
    Widget face({required Widget child, required String name, required VoidCallback onTap, required String semantics, bool accent = false}) => Semantics(
          button: true,
          label: semantics,
          excludeSemantics: true,
          child: Pressable(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(right: S.l),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bd.glassTop, bd.glass]),
                    border: Border.all(color: bd.glassBorder, width: .8),
                  ),
                  child: child,
                ),
                const SizedBox(height: S.s),
                Text(name, maxLines: 1, style: T.caption(bd, color: accent ? bd.accentText : bd.muted)),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _Requests(),
      if (friends.isNotEmpty)
        SizedBox(
          height: 78,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in friends)
              face(
                child: Text(f.initial, style: T.serif(bd, size: 20)),
                name: f.name,
                semantics: '${f.name}, @${f.handle}',
                onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: f)),
              ),
            face(
              child: Text('+', style: T.sans(bd, size: 20, color: _adding ? bd.accentText : bd.muted)),
              name: _adding ? 'Close' : 'Add',
              accent: _adding,
              semantics: _adding ? 'Close the search' : 'Add a friend',
              onTap: () => setState(() => _adding = !_adding),
            ),
          ]),
        ),
      if (searchOpen) Padding(padding: const EdgeInsets.only(top: S.m), child: FriendSearch(autofocus: _adding)),
    ]);
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
        return Padding(
          padding: const EdgeInsets.only(bottom: S.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionHeader('Friend requests', padding: EdgeInsets.only(bottom: S.m)),
            for (final r in reqs)
              Padding(
                padding: const EdgeInsets.only(bottom: S.s),
                child: Glass(
                  padding: const EdgeInsets.fromLTRB(S.l, 2, 4, 2),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: r.profile.name, style: T.row(bd)),
                          TextSpan(text: '  @${r.profile.handle}', style: T.row(bd, color: bd.faint)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextAction('Accept', accent: true, onTap: () => FriendsApi.accept(r.friendshipId)),
                    TextAction('Ignore', faint: true, onTap: () => FriendsApi.decline(r.friendshipId)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Find people by name or @handle and send a request — inline in the feed (open
/// on its own when you have no friends yet) or in the "Add a friend" sheet.
class FriendSearch extends StatefulWidget {
  final bool autofocus;
  const FriendSearch({super.key, this.autofocus = false});
  @override
  State<FriendSearch> createState() => _FriendSearchState();
}

class _FriendSearchState extends State<FriendSearch> {
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
          GlassField(controller: _query, hint: 'Add a friend by name or @handle', icon: Ph.magnifyingGlass, autofocus: widget.autofocus, caps: TextCapitalization.none, action: TextInputAction.search, onChanged: _onQuery),
          if (typed) ...[
            const SizedBox(height: S.s),
            if (_searching && _results.isEmpty)
              Padding(padding: const EdgeInsets.all(S.xs), child: Text('Searching…', style: T.body(bd, color: bd.faint)))
            else if (_results.isEmpty)
              Padding(padding: const EdgeInsets.all(S.xs), child: Text('No one by that name or handle.', style: T.body(bd, color: bd.faint)))
            else
              for (final p in _results)
                Row(children: [
                  const SizedBox(width: S.xs),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: p.name, style: T.row(bd)),
                        TextSpan(text: '  @${p.handle}', style: T.row(bd, color: bd.faint)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  friendIds.contains(p.id)
                      ? TextAction('Friends', faint: true)
                      : (_requested.contains(p.id) ? TextAction('Requested', faint: true) : TextAction('Add', accent: true, onTap: () => _add(p.id))),
                ]),
          ],
        ]);
      },
    );
  }
}

/// "To try, from friends" — drinks friends pour that you haven't logged.
class _FriendPicks extends StatefulWidget {
  final List<FeedEntry> feed;
  const _FriendPicks({required this.feed});
  @override
  State<_FriendPicks> createState() => _FriendPicksState();
}

class _FriendPicksState extends State<_FriendPicks> {
  final Set<String> _added = {};
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Watch(
      to: [entryStore, wishlist],
      builder: (context) {
        final picks = friendPicks(
          widget.feed.map((f) => (drink: f.drink, author: f.author.id)).toList(),
          entryStore.entries.map((e) => e.drink).toList(),
          wishlist.items.map((w) => w.drink).where((d) => !_added.contains(d.toLowerCase())).toList(),
          4,
        );
        if (picks.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('To try, from friends', padding: EdgeInsets.only(top: S.xxl, bottom: S.m)),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final d in picks)
              Pressable(
                onTap: _added.contains(d.toLowerCase())
                    ? () {}
                    : () {
                        wishlist.add(d);
                        setState(() => _added.add(d.toLowerCase()));
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bd.glassTop, bd.glass]),
                    borderRadius: BorderRadius.circular(rCtl),
                    border: Border.all(color: bd.glassBorder, width: .8),
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '$d ', style: T.sans(bd, size: 14, color: _added.contains(d.toLowerCase()) ? bd.faint : bd.ink)),
                    TextSpan(text: _added.contains(d.toLowerCase()) ? '✓' : '+', style: T.sans(bd, size: 14, color: _added.contains(d.toLowerCase()) ? bd.faint : bd.accentText)),
                  ])),
                ),
              ),
          ]),
        ]);
      },
    );
  }
}

/// One shared pour — the website's card: who and when, the drink in serif with
/// its mood, the note and place, then plain words for cheers, comments, to try.
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
    Widget action(String text, {bool active = false, VoidCallback? onTap, String? semantics}) => Semantics(
          button: true,
          label: semantics ?? text,
          excludeSemantics: true,
          child: Pressable(
            onTap: onTap ?? () {},
            enabled: onTap != null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: S.tap),
              child: Padding(
                padding: const EdgeInsets.only(right: S.l),
                child: Center(
                  widthFactor: 1,
                  child: Text(text, style: T.sans(bd, size: 14, weight: active ? FontWeight.w600 : FontWeight.w400, color: active ? bd.accentText : bd.muted).copyWith(fontFeatures: T.tnum)),
                ),
              ),
            ),
          ),
        );
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(
            child: Semantics(
              button: true,
              label: "${item.author.name}'s mosaic",
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: item.author)),
                child: Text(item.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 15)),
              ),
            ),
          ),
          Text('${timeOfDayLabel(item.createdAt).toLowerCase()} · ${shortDay(item.date)}', style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
        ]),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: [
          TextSpan(text: item.drink, style: T.serif(bd, size: 25, height: 1.15)),
          if (item.mood != null) TextSpan(text: ' · ${item.mood}', style: T.serif(bd, size: 20, italic: true, color: bd.muted, height: 1.15)),
        ])),
        if (item.note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.note!, style: T.body(bd, color: bd.muted))),
        if (item.venue != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              link: true,
              label: 'Open ${item.venue} in Maps',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => openMaps(item.venue!),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(item.venue!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(bd).copyWith(decoration: TextDecoration.underline, decorationColor: bd.line)),
                ),
              ),
            ),
          ),
        const SizedBox(height: S.xs),
        Row(children: [
          action(
            item.cheered ? 'Cheered${item.cheers > 0 ? ' ${item.cheers}' : ''}' : 'Cheers${item.cheers > 0 ? ' ${item.cheers}' : ''}',
            active: item.cheered,
            onTap: () => FriendsApi.toggleCheers(item.id, item.cheered),
          ),
          action(item.comments.isNotEmpty ? 'Comments ${item.comments.length}' : 'Comment', onTap: () => setState(() => _showComments = !_showComments)),
          const Spacer(),
          action(_saved ? 'On your list ✓' : 'To try', active: false, semantics: _saved ? 'On your to-try list' : 'Save to your to-try list', onTap: _saved
              ? null
              : () {
                  wishlist.add(item.drink);
                  setState(() => _saved = true);
                }),
        ]),
        if (_showComments)
          Container(
            margin: const EdgeInsets.only(top: S.xs, bottom: S.m),
            padding: const EdgeInsets.only(left: S.l),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: bd.line, width: 1))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in item.comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.s),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${c.authorName} ', style: T.sans(bd, size: 14)),
                    TextSpan(text: c.body, style: T.sans(bd, size: 14, color: bd.muted, height: 1.45)),
                  ])),
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _post(),
                    textInputAction: TextInputAction.send,
                    style: T.sans(bd, size: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add a comment…',
                      hintStyle: T.sans(bd, size: 14, color: bd.faint),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: bd.lineStrong)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: bd.ink)),
                    ),
                  ),
                ),
                TextAction('POST', faint: _draft.text.trim().isEmpty, size: 12, onTap: _draft.text.trim().isEmpty ? null : _post),
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
