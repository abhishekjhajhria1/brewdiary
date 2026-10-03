// Together — a port of src/components/together/Together.tsx. The calendar stays
// yours and quiet; this is the other room. The feed leads; plans, circles and
// parties wait behind their own segment; "Board" only exists for people who
// switched the leaderboard on. Circles and parties live in their own files.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../../config.dart';
import '../../data/auth.dart';
import '../../data/circles.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/friends.dart';
import '../../data/parties.dart';
import '../../data/plans.dart';
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

Future<void> showAddFriend(BuildContext context) => showBdSheet(context, title: 'Add a friend', builder: (_) => const FriendSearch(autofocus: true));

/// Ready data for previews and tests — the screen draws it instead of asking the
/// server.
class TogetherPreview {
  final List<SocialProfile> friends;
  final List<FeedEntry> feed;
  final List<Party> parties;
  final List<MyPlan> plans;
  final bool compete;
  final List<Circle>? circles;
  final CirclePreview? circle;
  final List<PointRow>? board;
  const TogetherPreview({this.friends = const [], this.feed = const [], this.parties = const [], this.plans = const [], this.compete = false, this.circles, this.circle, this.board});
}

class _Data {
  final List<SocialProfile> friends;
  final bool compete;
  final List<FeedEntry> feed;
  final List<Party> parties;
  final List<MyPlan> plans;
  const _Data(this.friends, this.compete, this.feed, this.parties, this.plans);
}

class TogetherScreen extends StatefulWidget {
  final TogetherPreview? preview;
  const TogetherScreen({super.key, this.preview});
  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

enum _Room { feed, plans, circles, parties, board }

const _roomLabel = {_Room.feed: 'Feed', _Room.plans: 'Plans', _Room.circles: 'Circles', _Room.parties: 'Parties', _Room.board: 'Board'};

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

  Future<_Data> _load() async {
    final r = await Future.wait<Object>([
      FriendsApi.friends(),
      PointsApi.competeVisible(),
      FriendsApi.feed(),
      PartiesApi.mine().catchError((_) => <Party>[]),
      PlansApi.mine().catchError((_) => <MyPlan>[]),
    ]);
    return _Data(r[0] as List<SocialProfile>, r[1] as bool, r[2] as List<FeedEntry>, r[3] as List<Party>, r[4] as List<MyPlan>);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    if (p != null) return _page(_Data(p.friends, p.compete, p.feed, p.parties, p.plans), loading: false);
    return Loader<_Data>(
      retry: true,
      refresh: Listenable.merge([friendsRev, profileRev, partiesRev, plansRev]),
      load: _load,
      failed: (context, retry) => ScrollPage(title: 'Together', children: [LoadError(onRetry: retry)]),
      builder: (context, data, loading) => _page(data, loading: data == null),
    );
  }

  // Laid out like the website's Together: the title with the friend count, the
  // rooms as tabs (Feed · Plans · Circles · Parties, and Board for people who
  // switched the leaderboard on), and Split as a quiet link at the foot.
  Widget _page(_Data? data, {required bool loading}) {
    final bd = context.bd;
    final friends = data?.friends ?? const <SocialProfile>[];
    final feed = data?.feed ?? const <FeedEntry>[];
    final rooms = [_Room.feed, _Room.plans, _Room.circles, _Room.parties, if (data?.compete ?? false) _Room.board];
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
          _Room.feed => _feedRoom(data, friends, feed, loading: loading),
          _Room.plans => const PlansSection(),
          _Room.circles => CirclesSection(preview: widget.preview?.circles, previewDetail: widget.preview?.circle),
          _Room.parties => PartiesSection(preview: widget.preview?.parties),
          _Room.board => _FriendsBoard(preview: widget.preview?.board),
        },
        const SizedBox(height: S.x3),
        // The website's foot: a hairline, a sentence, and "Split →".
        Semantics(
          button: true,
          label: 'Split a tab or a round with friends',
          excludeSemantics: true,
          child: Pressable(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SplitScreen())),
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
  }

  /// The feed room: requests, your people (a ring on anyone who shared today),
  /// an invite until you have three, what's coming up, their week, picks to try,
  /// then the feed itself.
  Widget _feedRoom(_Data? data, List<SocialProfile> friends, List<FeedEntry> feed, {required bool loading}) {
    final bd = context.bd;
    final today = todayKey();
    final out = {for (final f in feed) if (f.date == today) f.userId};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: S.l),
      if (widget.preview == null) const _Requests(),
      _FriendsRail(friends: friends, outTonight: out, loading: loading, feed: feed),
      if (!loading && friends.length < 3) ...[const SizedBox(height: S.l), _InviteCard(friends: friends.length)],
      if (data != null) _Happening(parties: data.parties, plans: data.plans),
      if (friends.isNotEmpty) ...[
        SectionHeader('Their week', trailing: Text('what friends shared', style: T.caption(bd))),
        _FriendsWeek(friends: friends, feed: feed),
      ],
      _FriendPicks(feed: feed),
      SectionHeader('Feed', trailing: feed.isEmpty ? null : Text('${feed.length} ${feed.length == 1 ? 'pour' : 'pours'}', style: T.caption(bd))),
      if (loading)
        const Column(children: [Skeleton(height: 132), SizedBox(height: S.m), Skeleton(height: 132)])
      else if (feed.isEmpty)
        _QuietFeed(hasFriends: friends.isNotEmpty)
      else
        for (var i = 0; i < feed.length; i++) ...[
          if (i > 0) const SizedBox(height: S.m),
          FeedCard(item: feed[i]),
        ],
    ]);
  }
}

// ── the people row ──────────────────────────────────────────────────────────
/// You, then each friend — an amber ring on anyone who shared something today —
/// then "Add".
class _FriendsRail extends StatelessWidget {
  final List<SocialProfile> friends;
  final Set<String> outTonight;
  final List<FeedEntry> feed;
  final bool loading;
  const _FriendsRail({required this.friends, required this.outTonight, required this.loading, this.feed = const []});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.profile;
    Widget face({required String letter, required String name, required VoidCallback onTap, required String semantics, bool ring = false, bool add = false, bool you = false}) => Semantics(
          button: true,
          label: semantics,
          excludeSemantics: true,
          child: Pressable(
            onTap: onTap,
            child: SizedBox(
              width: 68,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ring ? SweepGradient(colors: [bd.accent, bd.accent.withValues(alpha: .4), bd.accent]) : null,
                    border: ring ? null : Border.all(color: add ? bd.accent.withValues(alpha: .6) : bd.line, width: add ? 1.2 : 1),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: add ? bd.accent.withValues(alpha: .12) : (you ? bd.accent.withValues(alpha: .2) : bd.sheet),
                      border: ring ? Border.all(color: bd.sheet, width: 2) : null,
                    ),
                    child: add ? Icon(Ph.plus, size: 22, color: bd.accentText) : Text(letter, style: T.serif(bd, size: 22, color: you ? bd.accentText : bd.ink)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 12, color: ring ? bd.accentText : bd.muted, weight: ring ? FontWeight.w600 : FontWeight.w400)),
              ]),
            ),
          ),
        );
    if (loading) {
      return SizedBox(height: 86, child: Row(children: [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(right: S.m), child: SizedBox(width: 58, child: Skeleton(height: 58)))]));
    }
    final sorted = [...friends.where((f) => outTonight.contains(f.id)), ...friends.where((f) => !outTonight.contains(f.id))];
    return SizedBox(
      height: 88,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        face(
          letter: (me?.name.isNotEmpty ?? false) ? me!.name[0].toUpperCase() : 'Y',
          name: 'You',
          you: true,
          semantics: 'You — share your invite',
          onTap: () => shareInvite(context),
        ),
        for (final f in sorted)
          face(
            letter: f.initial,
            name: f.name,
            ring: outTonight.contains(f.id),
            semantics: '${f.name}, @${f.handle}${outTonight.contains(f.id) ? ', shared something today' : ''}',
            onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: f, lately: feed.where((e) => e.userId == f.id).toList())),
          ),
        face(letter: '+', name: 'Add', add: true, semantics: 'Add a friend', onTap: () => showAddFriend(context)),
      ]),
    );
  }
}

/// Share "add me" with a link to your profile.
Future<void> shareInvite(BuildContext context) async {
  final h = auth.profile?.handle ?? '';
  final link = h.isEmpty ? Config.siteUrl : '${Config.siteUrl}/u/$h';
  await SharePlus.instance.share(ShareParams(text: h.isEmpty ? 'Keep a drink diary with me on brewdiary — $link' : 'Add me on brewdiary — I\'m @$h. $link'));
}

/// With fewer than three friends: bring your people in.
class _InviteCard extends StatelessWidget {
  final int friends;
  const _InviteCard({required this.friends});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final h = auth.profile?.handle ?? '';
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(friends == 0 ? 'Bring your people' : 'A few more', style: T.serif(bd, size: 24, height: 1.1)),
              const SizedBox(height: 4),
              Text('Together comes alive at three: a feed, a circle, a night to plan.', style: T.caption(bd)),
            ]),
          ),
          const SizedBox(width: S.m),
          _Dots3(filled: friends),
        ]),
        if (h.isNotEmpty) ...[
          const SizedBox(height: S.l),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.m),
            decoration: BoxDecoration(color: bd.accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.accent.withValues(alpha: .35), width: .8)),
            child: Row(children: [
              Text('YOUR HANDLE', style: T.label(bd, color: bd.accentText)),
              const Spacer(),
              Text('@$h', style: T.serif(bd, size: 20, color: bd.ink)),
            ]),
          ),
        ],
        const SizedBox(height: S.m),
        Row(children: [
          Expanded(child: BdButton('Share invite', icon: Ph.shareNetwork, onTap: () => shareInvite(context))),
          const SizedBox(width: S.s),
          Expanded(child: BdButton('Search', kind: BtnKind.secondary, icon: Ph.magnifyingGlass, onTap: () => showAddFriend(context))),
        ]),
      ]),
    );
  }
}

class _Dots3 extends StatelessWidget {
  final int filled;
  const _Dots3({required this.filled});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      label: '$filled of 3 friends',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 26,
            height: 26,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
            decoration: BoxDecoration(
              color: i < filled ? bd.accent : null,
              borderRadius: BorderRadius.circular(7),
              border: i < filled ? null : Border.all(color: bd.lineStrong, width: 1),
            ),
            child: i < filled ? Icon(Ph.check, size: 14, color: bd.accentContrast) : null,
          ),
      ]),
    );
  }
}

// ── what's coming up ────────────────────────────────────────────────────────
class _Happening extends StatelessWidget {
  final List<Party> parties;
  final List<MyPlan> plans;
  const _Happening({required this.parties, required this.plans});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final today = todayKey();
    final cards = <(String, String, String, IconData, VoidCallback)>[
      for (final p in parties.where((p) => p.date.compareTo(today) >= 0))
        (p.date == today ? 'TONIGHT' : _when(p.date), p.name, [?p.venue, '${p.going} going'].join(' · '), Ph.confetti, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: p.id)))),
      for (final p in plans.where((p) => p.date.compareTo(today) >= 0))
        (p.date == today ? 'TONIGHT' : _when(p.date), p.title, [if (p.time != null) p.time!, ?p.city, '${p.going} going', if (p.pending > 0) '${p.pending} asking'].join(' · '), Ph.calendarPlus, () {}),
    ]..sort((a, b) => a.$1 == 'TONIGHT' ? -1 : (b.$1 == 'TONIGHT' ? 1 : 0));
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Coming up'),
      SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: S.m),
          itemBuilder: (_, i) {
            final c = cards[i];
            final tonight = c.$1 == 'TONIGHT';
            return SizedBox(
              width: 240,
              child: Glass(
                onTap: c.$5,
                semanticLabel: '${c.$2}, ${c.$1.toLowerCase()}, ${c.$3}',
                padding: const EdgeInsets.all(S.l),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: tonight ? bd.accent : bd.glassTop, borderRadius: BorderRadius.circular(6)),
                      child: Text(c.$1, style: T.sans(bd, size: 10.5, weight: FontWeight.w700, color: tonight ? bd.accentContrast : bd.muted, spacing: 1)),
                    ),
                    const Spacer(),
                    Icon(c.$4, size: 18, color: bd.accentText),
                  ]),
                  const Spacer(),
                  Text(c.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.serif(bd, size: 22, height: 1.1)),
                  const SizedBox(height: 4),
                  Text(c.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(bd)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  static String _when(String key) {
    final d = parseKey(key);
    final days = d.difference(parseKey(todayKey())).inDays;
    if (days == 1) return 'TOMORROW';
    if (days < 7) return weekdays[mondayIndex(d)].toUpperCase();
    return shortDay(key).toUpperCase();
  }
}

// ── the glance: each friend's last seven days ───────────────────────────────
class _FriendsWeek extends StatelessWidget {
  final List<SocialProfile> friends;
  final List<FeedEntry> feed;
  const _FriendsWeek({required this.friends, required this.feed});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final today = parseKey(todayKey());
    final days = [for (var i = 6; i >= 0; i--) toKey(addDays(today, -i))];
    final by = <String, Map<String, int>>{};
    for (final f in feed) {
      final m = by.putIfAbsent(f.userId, () => {});
      m[f.date] = (m[f.date] ?? 0) + 1;
    }
    final shown = [...friends]..sort((a, b) => (by[b.id]?.length ?? 0).compareTo(by[a.id]?.length ?? 0));
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, S.m),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 120),
          for (final d in days)
            Expanded(child: Center(child: Text(weekdays[mondayIndex(parseKey(d))].substring(0, 1), style: T.sans(bd, size: 11, color: d == days.last ? bd.accentText : bd.faint, weight: FontWeight.w600)))),
        ]),
        const SizedBox(height: 6),
        for (final f in shown.take(6))
          Semantics(
            label: '${f.name}: ${days.where((d) => (by[f.id]?[d] ?? 0) > 0).length} of the last 7 days shared',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(
                  width: 120,
                  child: Row(children: [
                    Initial(f.initial, size: 28),
                    const SizedBox(width: S.s),
                    Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 14))),
                  ]),
                ),
                for (final d in days)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: (by[f.id]?[d] ?? 0) == 0 ? null : bd.ycell(intensityLevel(by[f.id]![d]!)),
                          borderRadius: BorderRadius.circular(rCell),
                          border: (by[f.id]?[d] ?? 0) == 0 ? Border.all(color: bd.line, width: 1) : null,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        if (shown.length > 6) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('and ${shown.length - 6} more', style: T.caption(bd))),
      ]),
    );
  }
}

class _QuietFeed extends StatelessWidget {
  final bool hasFriends;
  const _QuietFeed({required this.hasFriends});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.all(S.xl),
      child: Column(children: [
        Icon(Ph.cheers, size: 30, color: bd.accentText),
        const SizedBox(height: S.m),
        Text(hasFriends ? 'Quiet so far' : 'Your feed lives here', style: T.serif(bd, size: 22)),
        const SizedBox(height: S.s),
        Text(
          hasFriends ? 'Nothing shared to friends yet. Share an entry from your diary — tap a day, then "Share" on the entry — and it lands here.' : 'Add a friend and you\'ll see what they choose to share — never more.',
          textAlign: TextAlign.center,
          style: T.bodyMuted(bd),
        ),
      ]),
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
    Widget action(String text, {IconData? icon, bool active = false, VoidCallback? onTap, String? semantics}) => Semantics(
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
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, size: 18, color: active ? bd.accentText : bd.muted), const SizedBox(width: 6)],
                    Text(text, style: T.sans(bd, size: 14, weight: active ? FontWeight.w600 : FontWeight.w400, color: active ? bd.accentText : bd.muted).copyWith(fontFeatures: T.tnum)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Semantics(
            button: true,
            label: "${item.author.name}'s mosaic",
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => showBdSheet(context, builder: (_) => _FriendSheet(friend: item.author)),
              child: Row(children: [
                Initial(item.author.initial, size: 34),
                const SizedBox(width: S.s + 2),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(item.author.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 15, weight: FontWeight.w600))),
              ]),
            ),
          ),
          const Spacer(),
          Text('${timeOfDayLabel(item.createdAt).toLowerCase()} · ${item.date == todayKey() ? 'today' : shortDay(item.date)}', style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
        ]),
        const SizedBox(height: S.m),
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
                  padding: const EdgeInsets.only(top: S.s),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Ph.mapPin, size: 14, color: bd.accentText),
                    const SizedBox(width: 4),
                    Flexible(child: Text(item.venue!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 13, color: bd.muted))),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: S.m),
        Container(height: .8, color: bd.line),
        Row(children: [
          action(
            item.cheers > 0 ? '${item.cheers}' : 'Cheers',
            icon: item.cheered ? PhFill.cheers : Ph.cheers,
            active: item.cheered,
            semantics: item.cheered ? 'Cheered, ${item.cheers}' : 'Cheers${item.cheers > 0 ? ', ${item.cheers}' : ''}',
            onTap: () => FriendsApi.toggleCheers(item.id, item.cheered),
          ),
          action(item.comments.isNotEmpty ? '${item.comments.length}' : 'Comment', icon: Ph.chatCircle, semantics: item.comments.isNotEmpty ? 'Comments, ${item.comments.length}' : 'Comment', onTap: () => setState(() => _showComments = !_showComments)),
          const Spacer(),
          action(_saved ? 'On your list' : 'To try', icon: _saved ? Ph.check : Ph.plus, active: _saved, semantics: _saved ? 'On your to-try list' : 'Save to your to-try list', onTap: _saved
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

  /// What they shared lately (from the feed) — null asks the server.
  final List<FeedEntry>? lately;
  const _FriendSheet({required this.friend, this.lately});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<(List<String>, List<FeedEntry>)>(
      load: () async {
        final r = await Future.wait<Object>([
          FriendsApi.friendDates(friend.id),
          lately != null ? Future.value(lately!) : FriendsApi.feed().then((f) => f.where((e) => e.userId == friend.id).toList()),
        ]);
        return (r[0] as List<String>, r[1] as List<FeedEntry>);
      },
      builder: (context, data, _) {
        final dates = data?.$1;
        final recent = (data?.$2 ?? const <FeedEntry>[]).take(4).toList();
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
          if (recent.isNotEmpty) ...[
            const SectionHeader('Lately', padding: EdgeInsets.only(top: S.xl, bottom: S.m)),
            _Lately(entries: recent),
          ],
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

/// What a friend shared lately — one tap puts a drink on your to-try list.
class _Lately extends StatelessWidget {
  final List<FeedEntry> entries;
  const _Lately({required this.entries});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Watch(
      to: [entryStore, wishlist],
      builder: (context) {
        final had = {for (final e in entryStore.entries) e.drink.trim().toLowerCase()};
        final listed = {for (final w in wishlist.items) w.drink.trim().toLowerCase()};
        return Glass(
          padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.xs),
          child: Column(children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) Container(height: .8, color: bd.line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.s + 2),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: entries[i].drink, style: T.serif(bd, size: 18, height: 1.2)),
                        if (entries[i].mood != null) TextSpan(text: ' · ${entries[i].mood}', style: T.serif(bd, size: 15, italic: true, color: bd.muted)),
                      ])),
                      Text([entries[i].date == todayKey() ? 'today' : shortDay(entries[i].date), ?entries[i].venue].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(bd)),
                    ]),
                  ),
                  () {
                    final k = entries[i].drink.trim().toLowerCase();
                    if (had.contains(k)) return Text('had it', style: T.caption(bd));
                    if (listed.contains(k)) return Text('on your list', style: T.caption(bd, color: bd.accentText));
                    return TextAction('To try', accent: true, onTap: () => wishlist.add(entries[i].drink));
                  }(),
                ]),
              ),
            ],
          ]),
        );
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
  final List<PointRow>? preview;
  const _FriendsBoard({this.preview});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    return Loader<List<PointRow>>(
      refresh: pointsRev,
      load: preview != null ? () async => preview! : PointsApi.friendsBoard,
      builder: (context, board, loading) {
        if (board == null) return const Padding(padding: EdgeInsets.only(top: S.xxl), child: Skeleton(height: 160));
        if (board.isEmpty) return const Padding(padding: EdgeInsets.only(top: S.l), child: EmptyNote('Quiet board. Sparks come from showing up; vibe is what your table and the bar hand you.', icon: Ph.trophy));
        final top = board.first.sparks;
        final mine = board.indexWhere((r) => r.userId == me);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('You and the friends who opted in'),
          Glass(
            padding: const EdgeInsets.symmetric(horizontal: S.m, vertical: S.s),
            child: Column(children: [
              for (var i = 0; i < board.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: S.s),
                  decoration: BoxDecoration(color: board[i].userId == me ? bd.accent.withValues(alpha: .1) : null, borderRadius: BorderRadius.circular(rCtl)),
                  child: PointsRow(rank: i + 1, name: board[i].userId == me ? 'You' : board[i].name, sparks: board[i].sparks, vibe: board[i].vibe, leads: board[i].sparks > 0 && board[i].sparks == top, top: top),
                ),
            ]),
          ),
          if (mine >= 0) ...[
            const SizedBox(height: S.l),
            BdButton('Share your score', kind: BtnKind.secondary, icon: Ph.shareNetwork, onTap: () => showScoreCard(context, Score(name: 'you', sparks: board[mine].sparks, vibe: board[mine].vibe, context: 'with friends', rank: mine + 1, of: board.length))),
          ],
          const SizedBox(height: S.m),
          Text('Sparks are for variety — a new place, a new drink, a dry day. Nobody is ranked by what they spent. Switch this off any time in You → Settings.', style: T.caption(bd)),
        ]);
      },
    );
  }
}
