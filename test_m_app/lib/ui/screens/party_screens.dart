// A party — ports of src/components/together/PartyRoom.tsx and app/p/[code]/page.tsx.
// RSVP + invite, who's coming, the shared log (squares · who poured what · mood
// cloud · photo wall), tonight's opt-in points, and — in a venue room — the house
// perk, thank-the-bar, and the per-room screen consent.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../core/date.dart';
import '../../core/money.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/circles.dart' show SharedEntry;
import '../../data/parties.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/share_card.dart';
import '../widgets/page.dart';
import 'together_screen.dart' show pointRow;

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
    return SubPage(
      title: 'Party',
      large: false,
      child: Loader<PartyDetail>(
        refresh: partiesRev,
        load: () => PartiesApi.detail(partyId),
        builder: (context, d, loading) {
          if (d == null) return const Column(children: [Skeleton(height: 96), SizedBox(height: 12), Skeleton(height: 160)]);
          if (d.party == null) return const EmptyNote("This party isn't yours to see — maybe you left, or the link is stale.");
          return _PartyBody(detail: d);
        },
      ),
    );
  }
}

class _PartyBody extends StatelessWidget {
  final PartyDetail detail;
  const _PartyBody({required this.detail});

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
    final d = parseKey(party.date);
    String nm(PartyGuest g) => g.id == me ? 'you' : g.name;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.only(bottom: 20),
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Label(past ? 'The recap' : 'A party', color: bd.faint),
          const SizedBox(height: 4),
          Text(party.name, style: T.serif(bd, size: 36, height: 1.1)),
          const SizedBox(height: 8),
          Wrap(children: [
            Text('${monthNames[d.month - 1]} ${d.day}', style: T.sans(bd, color: bd.muted)),
            if (party.venue != null) ...[
              Text(' · ', style: T.sans(bd, color: bd.muted)),
              GestureDetector(
                onTap: () => openMaps(party.venue!),
                child: Text(party.venue!, style: T.sans(bd, color: bd.muted).copyWith(decoration: TextDecoration.underline, decorationColor: bd.lineStrong)),
              ),
            ],
          ]),
        ]),
      ),

      if (mine && pending.isNotEmpty) ...[
        Label('Requests to join · ${pending.length}', color: bd.faint),
        const SizedBox(height: 8),
        for (final g in pending)
          Glass(
            margin: const EdgeInsets.only(bottom: 8),
            radius: rCtl,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${g.name} ', style: T.sans(bd)),
                  TextSpan(text: '@${g.handle}', style: T.sans(bd, color: bd.faint)),
                ])),
              ),
              TextAction('Let in', accent: true, onTap: () => PartiesApi.approveGuest(party.id, g.id)),
              const SizedBox(width: 12),
              TextAction('Decline', faint: true, onTap: () => PartiesApi.declineGuest(party.id, g.id)),
            ]),
          ),
        const SizedBox(height: 16),
      ],

      if (iAmPending)
        Glass(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text('Your request is in.', style: T.serif(bd, size: 22)),
            const SizedBox(height: 6),
            Text("Waiting for the host to let you in — you'll see the night once they do.", textAlign: TextAlign.center, style: T.sans(bd, size: 14, color: bd.muted)),
          ]),
        )
      else ...[
        if (!past) ...[
          Row(children: [
            for (final r in Rsvp.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: meMember?.rsvp == r
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(color: bd.ink, borderRadius: BorderRadius.circular(rCtl)),
                        child: Text(rsvpLabel[r]!, style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.base)),
                      )
                    : Glass(
                        radius: rCtl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        onTap: () => PartiesApi.setRsvp(party.id, r),
                        child: Text(rsvpLabel[r]!, style: T.sans(bd, size: 14, color: bd.muted)),
                      ),
              ),
          ]),
          const SizedBox(height: 16),
          Glass(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label('Invite', color: bd.faint),
                  const SizedBox(height: 2),
                  SelectableText(party.inviteCode, style: T.sans(bd, spacing: 2)),
                ]),
              ),
              TextAction('Copy code', onTap: () {
                Clipboard.setData(ClipboardData(text: party.inviteCode));
                toast(context, 'Copied');
              }),
              const SizedBox(width: 12),
              TextAction('Share link', onTap: () => SharePlus.instance.share(ShareParams(text: "You're invited to ${party.name} — ${Config.siteUrl}/p/${party.inviteCode}"))),
            ]),
          ),
          const SizedBox(height: 28),
        ],
        Label(past ? 'Who came' : "Who's coming", color: bd.faint),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          if (coming.isEmpty)
            TextSpan(text: 'No one yet${meMember?.rsvp != Rsvp.going ? ' — you could be first.' : '.'}', style: T.sans(bd, color: bd.faint))
          else
            TextSpan(text: coming.map(nm).join(', '), style: T.sans(bd, height: 1.6)),
          if (maybes.isNotEmpty) TextSpan(text: ' · maybe ${maybes.map(nm).join(', ')}', style: T.sans(bd, color: bd.faint)),
        ])),
        const SizedBox(height: 28),
        if (detail.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Text(
              past ? 'Nothing was shared in — the night lives on in memory alone.' : 'As people log the night, what they share lands here — tap an entry in your diary, then Share.',
              style: T.sans(bd, size: 14, color: bd.faint, height: 1.5),
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

      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: bd.line))),
        alignment: Alignment.centerLeft,
        child: mine
            ? TextAction('Delete party', faint: true, onTap: () async {
                if (await confirm(context, title: 'Delete for everyone?', body: 'The party and its recap go for every guest.', yes: 'Delete')) {
                  await PartiesApi.delete(party.id);
                  if (context.mounted) Navigator.pop(context);
                }
              })
            : TextAction(iAmPending ? 'Cancel request' : 'Leave party', faint: true, onTap: () async {
                await PartiesApi.leave(party.id);
                if (context.mounted) Navigator.pop(context);
              }),
      ),
    ]);
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
      Label('The night in squares · ${entries.length}', color: bd.faint),
      const SizedBox(height: 8),
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (final e in entries) Tooltip(message: e.drink, child: Container(width: 16, height: 16, decoration: BoxDecoration(color: bd.ycell(3), borderRadius: BorderRadius.circular(2)))),
      ]),
      const SizedBox(height: 28),
      Label('Who poured what', color: bd.faint),
      const SizedBox(height: 8),
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
              Text('${e.userId == me ? 'you' : e.authorName} · ${timeOfDayLabel(e.createdAt).toLowerCase()}', style: T.sans(bd, size: 12, color: bd.faint)),
            ]),
          ),
      ]),
      if (moodList.isNotEmpty) ...[
        const SizedBox(height: 28),
        Label('How it felt', color: bd.faint),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          for (var i = 0; i < moodList.length; i++) ...[
            if (i > 0) TextSpan(text: ' · ', style: T.sans(bd, color: bd.faint)),
            TextSpan(
              text: moodList[i].key,
              style: T.serif(bd, italic: true, size: moodList[i].value >= 3 ? 24 : (moodList[i].value == 2 ? 18 : 15), color: moodList[i].value >= 2 ? bd.ink : bd.muted),
            ),
          ],
        ])),
      ],
      if (photos.isNotEmpty) ...[
        const SizedBox(height: 28),
        Label('The wall', color: bd.faint),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final p in photos) ClipRRect(borderRadius: BorderRadius.circular(rCtl), child: Image.network(p.$1, fit: BoxFit.cover, semanticLabel: p.$2)),
          ],
        ),
      ],
      const SizedBox(height: 28),
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
            .map((m) => (id: m.id, name: m.id == me ? 'you' : m.name, sparks: byId[m.id]?.sparks ?? 0, vibe: byId[m.id]?.vibe ?? 0, isMe: m.id == me))
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label("Tonight's points · opt-in", color: bd.faint),
            const SizedBox(height: 6),
            Text(
              "Sparks are for trying something new — a new place, a new drink, a dry day. Coming back to your local doesn't score (that's what the house perk is for). Vibe is what your table and the bar hand you for good company.",
              style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Glass(
                radius: rCtl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                onTap: checkedIn
                    ? null
                    : () {
                        setState(() => _checkedIn = true);
                        PointsApi.checkIn(widget.party.id);
                      },
                child: Text(checkedIn ? 'Checked in' : 'Check in', style: T.sans(bd, size: 14, color: checkedIn ? bd.faint : bd.ink)),
              ),
            ),
            const SizedBox(height: 16),
            Hairlines(children: [
              for (var i = 0; i < rows.length; i++)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  pointRow(bd, i + 1, rows[i].name, rows[i].sparks, rows[i].vibe, rows[i].sparks > 0 && rows[i].sparks == top,
                      trailing: rows[i].isMe ? null : TextAction('Vibe', accent: _openVibe == rows[i].id, faint: _openVibe != rows[i].id, onTap: () => setState(() => _openVibe = _openVibe == rows[i].id ? null : rows[i].id))),
                  if (_openVibe == rows[i].id)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
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
              const SizedBox(height: 16),
              LineButton('Share your score', onTap: () => showScoreCard(context, Score(name: 'you', sparks: rows[myRank].sparks, vibe: rows[myRank].vibe, context: widget.party.name, rank: myRank + 1, of: rows.length))),
            ],
          ]),
        );
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label(tiers.length > 1 ? 'House perks' : 'House perk', color: bd.faint),
            const SizedBox(height: 8),
            for (final t in tiers)
              Glass(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (t.earned) ...[
                    Text.rich(TextSpan(children: [
                      TextSpan(text: "You've earned ", style: T.sans(bd)),
                      TextSpan(text: t.reward, style: T.sans(bd, weight: FontWeight.w500, color: bd.accent)),
                      TextSpan(text: '.', style: T.sans(bd)),
                    ])),
                    const SizedBox(height: 4),
                    Text("Ask the bar for it — they'll mark it claimed, and this one starts again from zero.", style: T.sans(bd, size: 12, color: bd.faint)),
                  ] else ...[
                    Text(t.reward, style: T.sans(bd)),
                    const SizedBox(height: 4),
                    Text(
                      t.isSpend
                          ? '${formatMoney(t.progress, t.currency, true)} of ${formatMoney(t.threshold, t.currency, true)} — ${formatMoney((t.threshold - t.progress).clamp(0, double.infinity), t.currency, true)} to go.'
                          : '${t.progress.round()} of ${t.threshold.round()} visits — ${(t.threshold - t.progress).clamp(0, double.infinity).round()} to go.',
                      style: T.sans(bd, size: 12, color: bd.faint),
                    ),
                  ],
                  if (t.claims > 0) ...[
                    const SizedBox(height: 8),
                    Divider(height: 1, color: bd.line),
                    const SizedBox(height: 8),
                    Text('Claimed ${t.claims == 1 ? 'once' : '${t.claims} times'} already.', style: T.sans(bd, size: 12, color: bd.faint)),
                  ],
                ]),
              ),
            if (anyVisits && quietTonight) Text("Tonight's a quiet night here — this visit counts double.", style: T.sans(bd, size: 12, color: bd.accent)),
          ]),
        );
      },
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label('Thank the bar', color: bd.faint),
            const SizedBox(height: 6),
            Text(
              "Say thanks to whoever looked after you. They see it; their manager only ever sees that the team was thanked, never who by or how often. There's no way to complain about someone here — that's deliberate.",
              style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
            ),
            const SizedBox(height: 12),
            Hairlines(children: [
              for (final s in staff)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(s.name, style: T.sans(bd))),
                      TextAction('Thank', accent: _open == s.id, faint: _open != s.id, onTap: () => setState(() => _open = _open == s.id ? null : s.id)),
                    ]),
                    if (_open == s.id)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [
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
                                toast(this.context, err);
                              }
                            }),
                        ]),
                      ),
                  ]),
                ),
            ]),
          ]),
        );
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
    Widget row(String text, bool on, VoidCallback onTap) => Glass(
          radius: rCtl,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onTap: onTap,
          child: Row(children: [
            Expanded(child: Text(text, style: T.sans(bd, size: 14, color: on ? bd.ink : bd.muted))),
            Text(on ? 'On' : 'Off', style: T.sans(bd, size: 12, color: on ? bd.accent : bd.faint)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Label("The bar's screen · tonight only", color: bd.faint),
        const SizedBox(height: 6),
        row('Show me on the screen', onBoard, () => _set(!onBoard, showTab)),
        if (onBoard) row('…and show my tab', showTab, () => _set(onBoard, !showTab)),
        Text(
          onBoard
              ? "Your name and points are on the bar's screen until this night ends — then you're off it automatically."
              : "Nothing of yours is on the bar's screen. This choice is for this room only.",
          style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
        ),
      ]),
    );
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

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SubPage(
      title: 'Invite',
      large: false,
      child: Loader<PartyPreview?>(
        load: () => PartiesApi.preview(widget.code),
        builder: (context, p, loading) {
          if (loading && p == null) return const Skeleton(height: 160);
          if (p == null) {
            return Column(children: [
              const SizedBox(height: 40),
              Text('No party here.', style: T.serif(bd, size: 26)),
              const SizedBox(height: 8),
              Text('The link may be stale, or the party was called off.', style: T.sans(bd, size: 14, color: bd.muted)),
            ]);
          }
          final signedIn = auth.isAuthed;
          if (!signedIn) rememberPartyCode(widget.code);
          final d = parseKey(p.date);
          return Glass(
            strong: true,
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              Label("You're invited", color: bd.faint),
              const SizedBox(height: 8),
              Text(p.name, textAlign: TextAlign.center, style: T.serif(bd, size: 30, height: 1.1)),
              const SizedBox(height: 12),
              Text('${monthNames[d.month - 1]} ${d.day}${p.venue != null ? ' · ${p.venue}' : ''}', style: T.sans(bd, color: bd.muted)),
              const SizedBox(height: 4),
              Text('hosted by ${p.hostName}${p.going > 0 ? ' · ${p.going} going' : ''}', style: T.sans(bd, size: 12, color: bd.faint)),
              const SizedBox(height: 24),
              if (signedIn) ...[
                InkButton(_busy ? 'Sending…' : 'Ask to join', uppercase: false, busy: _busy, onTap: () async {
                  setState(() => _busy = true);
                  final r = await PartiesApi.join(widget.code);
                  if (!context.mounted) return;
                  if (r.error != null) {
                    setState(() {
                      _busy = false;
                      _error = r.error;
                    });
                  } else {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: r.id!)));
                  }
                }),
                const SizedBox(height: 12),
                Text("The host approves who comes in — you'll be let in once they do.", textAlign: TextAlign.center, style: T.sans(bd, size: 12, color: bd.faint)),
              ] else ...[
                InkButton('Start your diary to RSVP', uppercase: false, onTap: () => Navigator.of(context).popUntil((r) => r.isFirst)),
                const SizedBox(height: 12),
                Text("Sign in and you'll land right in this party — the invite is remembered.", textAlign: TextAlign.center, style: T.sans(bd, size: 12, color: bd.faint)),
              ],
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.muted))),
            ]),
          );
        },
      ),
    );
  }
}
