// A party — ports of src/components/together/PartyRoom.tsx and app/p/[code]/page.tsx.
// RSVP + invite, who's coming, the shared log (squares · who poured what · mood
// cloud · photo wall), tonight's opt-in points, and — in a venue room — the house
// perk, thank-the-bar, and the per-room screen consent.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/money.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/circles.dart' show SharedEntry;
import '../../data/parties.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/photo_viewer.dart';
import 'photo_studio.dart';
import 'tonight_sheet.dart';
import '../widgets/share_card.dart';
import '../widgets/social.dart';

const _pendingKey = 'brewdiary.pendingParty.v1';

/// A code opened while signed out is remembered and joined after sign-in.
void rememberPartyCode(String code) => Prefs.setString(_pendingKey, code.trim());
String? consumePendingPartyCode() {
  final c = Prefs.getString(_pendingKey);
  if (c != null) Prefs.remove(_pendingKey);
  return c;
}

void openMaps(String query) => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}'), mode: LaunchMode.externalApplication);

class PartyRoomScreen extends StatelessWidget {
  final String partyId;
  const PartyRoomScreen({super.key, required this.partyId});

  @override
  Widget build(BuildContext context) {
    return Loader<PartyDetail>(
      failed: (context, retry) => SubPage(title: 'Party', child: LoadError(onRetry: retry)),
      refresh: partiesRev,
      load: () => PartiesApi.detail(partyId),
      builder: (context, d, loading) {
        final party = d?.party;
        String? subtitle;
        if (party != null) {
          final past = party.date.compareTo(todayKey()) < 0;
          subtitle = '${past ? 'The recap · ' : ''}${party.date == todayKey() ? 'Tonight' : formatDayLongYear(party.date)}${party.venue != null ? ' · ${party.venue}' : ''}';
        }
        return SubPage(
          title: party?.name ?? 'Party',
          subtitle: subtitle,
          onRefresh: () async => partiesRev.bump(),
          child: d == null
              ? const Column(children: [Skeleton(height: 96), SizedBox(height: S.m), Skeleton(height: 160)])
              : (party == null ? const EmptyNote("This party isn't yours to see — maybe you left, or the link is stale.", icon: Ph.confetti) : PartyBody(detail: d)),
        );
      },
    );
  }
}

class PartyBody extends StatelessWidget {
  final PartyDetail detail;
  const PartyBody({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final party = detail.party!;
    final me = auth.meId;
    final past = party.date.compareTo(todayKey()) < 0;
    final mine = party.hostId == me;
    final meMember = detail.guests.where((g) => g.id == me).firstOrNull;
    final iAmPending = !mine && (meMember?.pending ?? false);
    final approved = detail.guests.where((g) => !g.pending).toList();
    final pending = detail.guests.where((g) => g.pending).toList();
    final coming = approved.where((g) => g.rsvp == Rsvp.going).toList();
    final maybes = approved.where((g) => g.rsvp == Rsvp.maybe).toList();
    String nm(PartyGuest g) => g.id == me ? 'You' : g.name;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (party.venue != null)
        Align(alignment: Alignment.centerLeft, child: TextAction('Directions to ${party.venue}', icon: Ph.mapPin, onTap: () => openMaps(party.venue!))),
      if (party.date == todayKey())
        Align(alignment: Alignment.centerLeft, child: TextAction('Pace yourself · getting home', icon: Ph.moonStars, onTap: () => showTonight(context))),
      Align(
        alignment: Alignment.centerLeft,
        child: TextAction('Share the night with a photo', icon: Ph.camera, onTap: () {
          final photo = detail.entries.expand((e) => e.photoUrls).firstOrNull;
          showPhotoStudio(context, NightStory(dateKey: party.date, title: party.name, venue: party.venue, withPeople: approved.where((g) => g.id != me).length), photo: photo);
        }),
      ),

      if (mine && pending.isNotEmpty) ...[
        SectionHeader('Requests to join', trailing: Text('${pending.length}', style: T.caption(bd))),
        Group(children: [
          for (final g in pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.s),
              child: Row(children: [
                Initial(g.name.isEmpty ? '?' : g.name[0].toUpperCase(), size: 40),
                const SizedBox(width: S.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.row(bd)),
                    Text('@${g.handle}', style: T.caption(bd)),
                  ]),
                ),
                TextAction('Let in', accent: true, onTap: () => attempt(context, () => PartiesApi.approveGuest(party.id, g.id), done: '${g.name} is in.')),
                IconBtn(Ph.x, tooltip: 'Decline ${g.name}', size: 18, color: bd.faint, onTap: () => attempt(context, () => PartiesApi.declineGuest(party.id, g.id))),
              ]),
            ),
        ]),
      ],

      if (iAmPending) ...[
        const SizedBox(height: S.l),
        Glass(
          padding: const EdgeInsets.all(S.xl),
          child: Column(children: [
            Icon(Ph.clock, size: 28, color: bd.accentText),
            const SizedBox(height: S.s),
            Text('Your request is in.', style: T.serif(bd, size: 24)),
            const SizedBox(height: S.s),
            Text("Waiting for the host to let you in — you'll see the night once they do.", textAlign: TextAlign.center, style: T.bodyMuted(bd)),
          ]),
        ),
      ] else ...[
        if (!past) ...[
          const SectionHeader('Are you going?'),
          Segmented<Rsvp?>(
            options: [for (final r in Rsvp.values) (r, rsvpLabel[r]!)],
            value: meMember?.rsvp,
            onChanged: (r) {
              if (r != null) PartiesApi.setRsvp(party.id, r);
            },
          ),
          const SizedBox(height: S.m),
          InviteCodeCard(label: 'Invite with the code', code: party.inviteCode, link: '${Config.siteUrl}/p/${party.inviteCode}', shareText: "You're invited to ${party.name} — ${Config.siteUrl}/p/${party.inviteCode}"),
        ],
        SectionHeader(past ? 'Who came' : "Who's coming", trailing: coming.isEmpty ? null : Text('${coming.length}', style: T.caption(bd))),
        if (coming.isEmpty && maybes.isEmpty)
          Text('No one yet${meMember?.rsvp != Rsvp.going ? ' — you could be first.' : '.'}', style: T.bodyMuted(bd))
        else
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final g in coming) _GuestChip(name: nm(g)),
            for (final g in maybes) _GuestChip(name: nm(g), maybe: true),
          ]),
        if (detail.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.x3),
            child: EmptyNote(
              past ? 'Nothing was shared in — the night lives on in memory alone.' : 'As people log the night, what they share lands here — open the day in your diary, tap ⋯, then Share.',
              icon: Ph.cheers,
            ),
          )
        else
          _PartyLog(entries: detail.entries),
        _PointsBoard(party: party, members: approved),
        if (party.venueId != null) ...[
          _PerkCard(venueId: party.venueId!, date: party.date),
          _ThankStaff(partyId: party.id),
          _ScreenConsent(partyId: party.id),
        ],
      ],

      const SizedBox(height: S.section),
      if (mine)
        BdButton('Delete party', kind: BtnKind.secondary, icon: Ph.trash, onTap: () async {
          if (await confirm(context, title: 'Delete for everyone?', body: 'The party and its recap go for every guest.', yes: 'Delete')) {
            await PartiesApi.delete(party.id);
            if (context.mounted) Navigator.pop(context);
          }
        })
      else
        BdButton(iAmPending ? 'Cancel my request' : 'Leave party', kind: BtnKind.secondary, icon: Ph.signOut, onTap: () async {
          if (!iAmPending && !await confirm(context, title: 'Leave ${party.name}?', body: 'You can ask to come back with the code.', yes: 'Leave')) return;
          await PartiesApi.leave(party.id);
          if (context.mounted) Navigator.pop(context);
        }),
    ]);
  }
}

class _GuestChip extends StatelessWidget {
  final String name;
  final bool maybe;
  const _GuestChip({required this.name, this.maybe = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(color: maybe ? Colors.transparent : bd.glass, borderRadius: BorderRadius.circular(999), border: Border.all(color: maybe ? bd.line : bd.glassBorder, width: .8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Initial(name.isEmpty ? '?' : name[0].toUpperCase(), size: 26),
        const SizedBox(width: 8),
        Text(maybe ? '$name · maybe' : name, style: T.sans(bd, size: 14, color: maybe ? bd.muted : bd.ink)),
      ]),
    );
  }
}

class _PartyLog extends StatelessWidget {
  final List<SharedEntry> entries;
  const _PartyLog({required this.entries});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    final moods = <String, int>{};
    for (final e in entries) {
      final w = e.mood?.trim().toLowerCase();
      if (w != null && w.isNotEmpty) moods[w] = (moods[w] ?? 0) + 1;
    }
    final moodList = moods.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final photos = [for (final e in entries) for (final u in e.photoUrls) (u, e.drink)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('The night in squares', trailing: Text('${entries.length}', style: T.caption(bd))),
      Semantics(
        label: '${entries.length} drinks shared tonight',
        excludeSemantics: true,
        child: Wrap(spacing: 5, runSpacing: 5, children: [
          for (final e in entries) Tooltip(message: e.drink, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: bd.ycell(3), borderRadius: BorderRadius.circular(4)))),
        ]),
      ),
      const SectionHeader('Who poured what'),
      PourList([
        for (final e in entries) PourRow(author: e.authorName, drink: e.drink, mood: e.mood, meta: '${e.userId == me ? 'you' : e.authorName} · ${timeOfDayLabel(e.createdAt).toLowerCase()}'),
      ]),
      if (moodList.isNotEmpty) ...[
        const SectionHeader('How it felt'),
        Wrap(spacing: S.m, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.end, children: [
          for (final m in moodList)
            Text(m.key, style: T.serif(bd, italic: true, size: m.value >= 3 ? 28 : (m.value == 2 ? 22 : 17), color: m.value >= 2 ? bd.ink : bd.muted)),
        ]),
      ],
      if (photos.isNotEmpty) ...[
        const SectionHeader('The wall'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final (i, p) in photos.indexed)
              Semantics(
                button: true,
                label: p.$2,
                excludeSemantics: true,
                child: Pressable(
                  haptic: false,
                  onTap: () => showPhotoViewer(context, [for (final x in photos) (url: x.$1, label: x.$2)], initial: i, scope: 'wall'),
                  child: Hero(
                    tag: photoHeroTag(p.$1, 'wall'),
                    child: ClipRRect(borderRadius: BorderRadius.circular(rCtl), child: ColoredBox(color: bd.glass, child: PhotoImage(p.$1, semanticLabel: p.$2))),
                  ),
                ),
              ),
          ],
        ),
      ],
    ]);
  }
}

class _PointsBoard extends StatefulWidget {
  final Party party;
  final List<PartyGuest> members;
  const _PointsBoard({required this.party, required this.members});
  @override
  State<_PointsBoard> createState() => _PointsBoardState();
}

class _PointsBoardState extends State<_PointsBoard> {
  String? _openVibe;
  final Set<String> _given = {};
  bool _checkedIn = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = auth.meId;
    return Loader<(List<PointRow>, bool)>(
      refresh: pointsRev,
      load: () async => (await PointsApi.partyBoard(widget.party.id), await PointsApi.hasCheckedIn(widget.party.id)),
      builder: (context, data, loading) {
        final byId = {for (final r in data?.$1 ?? const <PointRow>[]) r.userId: r};
        final rows = widget.members
            .map((m) => (id: m.id, name: m.id == me ? 'You' : m.name, sparks: byId[m.id]?.sparks ?? 0, vibe: byId[m.id]?.vibe ?? 0, isMe: m.id == me))
            .toList()
          ..sort((a, b) {
            var c = b.sparks.compareTo(a.sparks);
            if (c != 0) return c;
            c = b.vibe.compareTo(a.vibe);
            return c != 0 ? c : a.name.compareTo(b.name);
          });
        final top = rows.fold<int>(0, (m, r) => r.sparks > m ? r.sparks : m);
        final checkedIn = _checkedIn || (data?.$2 ?? false);
        final myRank = rows.indexWhere((r) => r.isMe);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader("Tonight's points", trailing: Text('Opt-in', style: T.caption(bd))),
          Text(
            "Sparks are for trying something new — a new place, a new drink, a dry day. Coming back to your local doesn't score (that's what the house perk is for). Vibe is what your table and the bar hand you for good company.",
            style: T.caption(bd),
          ),
          const SizedBox(height: S.m),
          Align(
            alignment: Alignment.centerLeft,
            child: BdButton(
              checkedIn ? 'Checked in' : 'Check in',
              kind: BtnKind.secondary,
              expand: false,
              height: 44,
              icon: checkedIn ? PhBold.check : Ph.mapPin,
              onTap: checkedIn
                  ? null
                  : () {
                      setState(() => _checkedIn = true);
                      PointsApi.checkIn(widget.party.id);
                    },
            ),
          ),
          const SizedBox(height: S.m),
          Group(children: [
            for (var i = 0; i < rows.length; i++)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PointsRow(
                  rank: i + 1,
                  name: rows[i].name,
                  sparks: rows[i].sparks,
                  vibe: rows[i].vibe,
                  leads: rows[i].sparks > 0 && rows[i].sparks == top,
                  top: top,
                  trailing: rows[i].isMe ? null : TextAction('Vibe', accent: _openVibe == rows[i].id, onTap: () => setState(() => _openVibe = _openVibe == rows[i].id ? null : rows[i].id)),
                ),
                if (_openVibe == rows[i].id)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.s),
                    child: Wrap(spacing: S.s, children: [
                      for (final reason in vibeReasons)
                        GlassChip(reason, done: _given.contains('${rows[i].id}:$reason'), onTap: () async {
                          final key = '${rows[i].id}:$reason';
                          setState(() {
                            _given.add(key);
                            _openVibe = null;
                          });
                          final err = await PointsApi.giveVibe(widget.party.id, rows[i].id, reason);
                          if (err != null && mounted) setState(() => _given.remove(key));
                        }),
                    ]),
                  ),
              ]),
          ]),
          if (myRank >= 0 && (rows[myRank].sparks > 0 || rows[myRank].vibe > 0)) ...[
            const SizedBox(height: S.m),
            BdButton('Share your score', kind: BtnKind.secondary, icon: Ph.shareNetwork, onTap: () => showScoreCard(context, Score(name: 'you', sparks: rows[myRank].sparks, vibe: rows[myRank].vibe, context: widget.party.name, rank: myRank + 1, of: rows.length))),
          ],
        ]);
      },
    );
  }
}

class _PerkCard extends StatelessWidget {
  final String venueId;
  final String date;
  const _PerkCard({required this.venueId, required this.date});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<(List<PerkTier>, List<int>)>(
      refresh: pointsRev,
      load: () async => (await PointsApi.perkTiers(venueId), await PointsApi.quietNights(venueId)),
      builder: (context, data, loading) {
        final tiers = data?.$1 ?? const <PerkTier>[];
        if (tiers.isEmpty) return const SizedBox.shrink();
        // quiet_nights uses the JS weekday (0 = Sun); Dart's weekday % 7 matches it.
        final quietTonight = (data?.$2 ?? const <int>[]).contains(parseKey(date).weekday % 7);
        final anyVisits = tiers.any((t) => !t.isSpend);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(tiers.length > 1 ? 'House perks' : 'House perk'),
          for (var i = 0; i < tiers.length; i++) ...[
            if (i > 0) const SizedBox(height: S.s),
            _perkTile(bd, tiers[i]),
          ],
          if (anyVisits && quietTonight)
            Padding(
              padding: const EdgeInsets.only(top: S.s),
              child: Row(children: [
                Icon(Ph.moonStars, size: 16, color: bd.accentText),
                const SizedBox(width: 6),
                Expanded(child: Text("Tonight's a quiet night here — this visit counts double.", style: T.caption(bd, color: bd.accentText))),
              ]),
            ),
        ]);
      },
    );
  }

  Widget _perkTile(BD bd, PerkTier t) {
    final pct = t.threshold <= 0 ? 0.0 : (t.progress / t.threshold).clamp(0.0, 1.0);
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(t.earned ? PhFill.gift : Ph.gift, size: 20, color: t.earned ? bd.accentText : bd.muted),
          const SizedBox(width: S.s),
          Expanded(child: Text(t.earned ? "You've earned ${t.reward}" : t.reward, style: T.sans(bd, size: 16, weight: FontWeight.w600, color: t.earned ? bd.accentText : bd.ink))),
        ]),
        const SizedBox(height: S.s),
        if (t.earned)
          Text("Ask the bar for it — they'll mark it claimed, and this one starts again from zero.", style: T.caption(bd))
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(children: [
              Container(height: 6, color: bd.ink.withValues(alpha: .1)),
              FractionallySizedBox(widthFactor: pct, child: Container(height: 6, color: bd.accent)),
            ]),
          ),
          const SizedBox(height: 6),
          Text(
            t.isSpend
                ? '${formatMoney(t.progress, t.currency, true)} of ${formatMoney(t.threshold, t.currency, true)} — ${formatMoney((t.threshold - t.progress).clamp(0, double.infinity), t.currency, true)} to go.'
                : '${t.progress.round()} of ${t.threshold.round()} visits — ${(t.threshold - t.progress).clamp(0, double.infinity).round()} to go.',
            style: T.caption(bd),
          ),
        ],
        if (t.claims > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Claimed ${t.claims == 1 ? 'once' : '${t.claims} times'} already.', style: T.caption(bd))),
      ]),
    );
  }
}

class _ThankStaff extends StatefulWidget {
  final String partyId;
  const _ThankStaff({required this.partyId});
  @override
  State<_ThankStaff> createState() => _ThankStaffState();
}

class _ThankStaffState extends State<_ThankStaff> {
  String? _open;
  final Set<String> _sent = {};
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<({String id, String name})>>(
      load: () => PointsApi.roomStaff(widget.partyId),
      builder: (context, staff, loading) {
        if (staff == null || staff.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('Thank the bar'),
          Text(
            "Say thanks to whoever looked after you. They see it; their manager only ever sees that the team was thanked, never who by or how often. There's no way to complain about someone here — that's deliberate.",
            style: T.caption(bd),
          ),
          const SizedBox(height: S.m),
          Group(children: [
            for (final s in staff)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GroupTile(
                  icon: Ph.handHeart,
                  title: s.name,
                  trailing: TextAction('Thank', accent: true, onTap: () => setState(() => _open = _open == s.id ? null : s.id)),
                ),
                if (_open == s.id)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.s),
                    child: Wrap(spacing: S.s, children: [
                      for (final reason in kudosReasons)
                        GlassChip(reason, done: _sent.contains('${s.id}:$reason'), onTap: () async {
                          final key = '${s.id}:$reason';
                          setState(() {
                            _sent.add(key);
                            _open = null;
                          });
                          final err = await PointsApi.thankStaff(widget.partyId, s.id, reason);
                          if (err != null && mounted) {
                            setState(() => _sent.remove(key));
                            toast(this.context, err, tone: ToastTone.error);
                          }
                        }),
                    ]),
                  ),
              ]),
          ]),
        ]);
      },
    );
  }
}

/// The bar's wall screen — per room, off by default, and a tab can never show for
/// someone who isn't on the board. (A flexed tab is always a BAND, never the figure.)
class _ScreenConsent extends StatefulWidget {
  final String partyId;
  const _ScreenConsent({required this.partyId});
  @override
  State<_ScreenConsent> createState() => _ScreenConsentState();
}

class _ScreenConsentState extends State<_ScreenConsent> {
  bool? _onBoard;
  bool? _showTab;

  @override
  void initState() {
    super.initState();
    PointsApi.roomConsent(widget.partyId).then((c) {
      if (mounted) {
        setState(() {
          _onBoard = c.onBoard;
          _showTab = c.showTab;
        });
      }
    });
  }

  void _set(bool onBoard, bool showTab) {
    final tab = onBoard && showTab;
    setState(() {
      _onBoard = onBoard;
      _showTab = tab;
    });
    PointsApi.setRoomConsent(widget.partyId, onBoard: onBoard, showTab: tab);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final onBoard = _onBoard ?? false;
    final showTab = _showTab ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader("The bar's screen", trailing: Text('Tonight only', style: T.caption(bd))),
      Group(
        footer: onBoard
            ? "Your name and points are on the bar's screen until this night ends — then you're off it automatically."
            : "Nothing of yours is on the bar's screen. This choice is for this room only.",
        children: [
          SettingRow(title: 'Show me on the screen', trailing: BdToggle(on: onBoard, label: 'Show me on the screen', onChanged: (v) => _set(v, showTab))),
          if (onBoard) SettingRow(title: 'Show my tab', hint: 'As a band like “₹2,500+”, never the figure.', trailing: BdToggle(on: showTab, label: 'Show my tab', onChanged: (v) => _set(onBoard, v))),
        ],
      ),
    ]);
  }
}

// ── invite link: /p/<code> ───────────────────────────────────────────────────
class PartyInviteScreen extends StatefulWidget {
  final String code;
  const PartyInviteScreen({super.key, required this.code});
  @override
  State<PartyInviteScreen> createState() => _PartyInviteScreenState();
}

class _PartyInviteScreenState extends State<PartyInviteScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await PartiesApi.join(widget.code);
    if (!mounted) return;
    if (r.error != null || r.id == null) {
      setState(() {
        _busy = false;
        _error = r.error ?? "Couldn't join just now.";
      });
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: r.id!)));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SubPage(
      title: 'Invitation',
      large: false,
      child: Loader<PartyPreview?>(
        load: () => PartiesApi.preview(widget.code),
        builder: (context, p, loading) {
          if (loading && p == null) return const Skeleton(height: 240);
          if (p == null) return const EmptyNote('No party here — the link may be stale, or the party was called off.', icon: Ph.confetti);
          final signedIn = auth.isAuthed;
          if (!signedIn) rememberPartyCode(widget.code);
          return Glass(
            strong: true,
            radius: rSheet,
            padding: const EdgeInsets.fromLTRB(S.xxl, S.x3, S.xxl, S.xxl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Ph.confetti, size: 32, color: bd.accentText),
              const SizedBox(height: S.m),
              Text("You're invited", textAlign: TextAlign.center, style: T.caption(bd)),
              const SizedBox(height: S.s),
              Text(p.name, textAlign: TextAlign.center, style: T.serif(bd, size: 32, height: 1.1)),
              const SizedBox(height: S.m),
              Text('${formatDayLongYear(p.date)}${p.venue != null ? ' · ${p.venue}' : ''}', textAlign: TextAlign.center, style: T.body(bd, color: bd.muted)),
              const SizedBox(height: 2),
              Text('Hosted by ${p.hostName}${p.going > 0 ? ' · ${p.going} going' : ''}', textAlign: TextAlign.center, style: T.caption(bd)),
              const SizedBox(height: S.xxl),
              if (signedIn) ...[
                BdButton('Ask to join', busy: _busy, onTap: _join),
                const SizedBox(height: S.m),
                Text("The host approves who comes in — you'll be let in once they do.", textAlign: TextAlign.center, style: T.caption(bd)),
              ] else ...[
                BdButton('Start your diary to RSVP', onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
                const SizedBox(height: S.m),
                Text("Sign in and you'll land right in this party — the invite is remembered.", textAlign: TextAlign.center, style: T.caption(bd)),
              ],
              if (_error != null) ErrorLine(_error!, padding: const EdgeInsets.only(top: S.m), style: T.sans(bd, size: 14, color: bd.accentText)),
            ]),
          );
        },
      ),
    );
  }
}
