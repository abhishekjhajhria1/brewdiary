// Ninkasi for hosts — for everyone on the team, not just the manager. A short "before
// your shift" card on Tonight and the Till, and a screen to ask her things mid-shift.
//
// The brief is built here from what THIS person's role can already load: tonight's
// room (and, if the role may see who's in, just the count), the menu, the card, public
// facts about the area, and — for a manager — the area map's guide. Counts and titles
// only; no guest's name ever leaves the phone. The briefing itself is worked out on the
// phone (logic/host_brief.dart), so it's instant, free and works offline; the AI is
// asked only when someone asks a question.
import 'dart:async';

import 'package:brewdiary_core/geo.dart';
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/area.dart';
import '../../logic/host_brief.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

/// Everything the briefing needs, loaded with this person's own permissions. Each part
/// is optional: a failure just leaves it out.
Future<HostBrief> loadHostBrief(Venue v) async {
  final s = Session.instance;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayKey = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  Future<R?> safe<R>(Future<R> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  final counter = v.kind.isCounter;
  final gh = v.geohash ?? '';
  final results = await Future.wait<Object?>([
    counter ? Future.value(null) : safe(() => Backend.i.rooms(v.id)),
    safe(() => Backend.i.menu(v.id)),
    safe(() => Backend.i.perks(v.id)),
    v.verified ? safe(() => Backend.i.areaSignals(v.id)) : Future.value(null),
    (s.can(Cap.areaInsights) && v.verified && gh.length >= 5) ? safe(() => Backend.i.areaMap(v.id, tz: venueTimeZone(v.country, v.region))) : Future.value(null),
  ]);
  final rooms = (results[0] as List<Room>?) ?? const [];
  final menu = (results[1] as List<MenuItem>?) ?? const [];
  final perks = (results[2] as List<PerkTier>?) ?? const [];
  final signals = (results[3] as List<AreaSignal>?) ?? const [];
  final map = results[4] as List<HeatRow>?;

  final tonight = rooms.where((r) => r.date == todayKey).toList();
  int? guestsIn;
  if (tonight.isNotEmpty && s.can(Cap.guestsAtTables)) {
    guestsIn = (await safe(() => Backend.i.roomGuests(tonight.first.id)))?.length;
  }

  return HostBrief(
    venueName: v.name,
    kind: v.kind.db,
    role: v.myRole.db,
    sellsAlcohol: v.sellsAlcohol,
    counter: counter,
    today: today,
    roomOpen: tonight.isNotEmpty,
    canOpenRoom: s.can(Cap.openRoom),
    guestsIn: guestsIn,
    quietTonight: v.quietNights.contains(today.weekday % 7),
    soldOut: [for (final m in menu) if (!m.available) m.name],
    alcoholFree: [for (final m in menu) if (m.available && m.noAlcohol && m.kind != 'food') m.name],
    menuItems: menu.length,
    perks: [for (final p in perks) (reward: p.reward, at: p.kind == PerkKind.spend ? '${p.threshold.toStringAsFixed(0)} ${p.currency} spent' : '${p.threshold.toStringAsFixed(0)} visits')],
    signals: [
      for (final x in signals)
        (kind: x.kind, title: x.title, startsOn: x.startsOn, endsOn: x.endsOn, where: x.cell != null && gh.length >= 5 ? directionFrom(gh, x.cell!) : ''),
    ],
    area: map == null ? const [] : areaGuide(venueCell: gh, cells: readMap(map), currency: v.currency, sellsAlcohol: v.sellsAlcohol, sharing: v.areaShare).take(3).toList(),
  );
}

/// "Before your shift" — the top of Tonight and the Till.
class ShiftCard extends StatelessWidget {
  final Venue venue;
  const ShiftCard({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<HostBrief>(
      load: () => loadHostBrief(venue),
      refresh: Listenable.merge([roomsRev, menuRev, perksRev, venueRev]),
      deps: venue.id,
      builder: (context, brief, loading) {
        if (brief == null) return const Skeleton(height: 110);
        final lines = hostBriefing(brief);
        return Padding(
          padding: const EdgeInsets.only(bottom: S.l),
          child: Pressable(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostScreen(venue: venue, brief: brief))),
            child: Glass(
              padding: const EdgeInsets.all(S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Ph.sparkle, size: 18, color: bd.accentText),
                  const SizedBox(width: S.s),
                  Expanded(child: Text('BEFORE YOUR SHIFT', style: T.label(bd))),
                  Text('Ask Ninkasi', style: T.sans(bd, size: 13.5, weight: FontWeight.w600, color: bd.accentText)),
                ]),
                const SizedBox(height: S.s),
                for (final l in lines.take(3)) _Bullet(l),
                if (lines.length > 3) Padding(padding: const EdgeInsets.only(top: 4), child: Text('+ ${lines.length - 3} more', style: T.caption(bd))),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 7, right: S.m), child: Container(width: 5, height: 5, decoration: BoxDecoration(color: bd.accent, shape: BoxShape.circle))),
        Expanded(child: Text(text, style: T.sans(bd, size: 14.5, height: 1.45))),
      ]),
    );
  }
}

class HostScreen extends StatefulWidget {
  final Venue venue;
  final HostBrief brief;
  const HostScreen({super.key, required this.venue, required this.brief});
  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  final _input = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    if (_busy) return;
    final sent = [..._messages, {'role': 'user', 'content': question}];
    setState(() {
      _messages
        ..clear()
        ..addAll(sent)
        ..add({'role': 'assistant', 'content': ''});
      _busy = true;
    });
    var acc = '';
    try {
      await for (final chunk in Backend.i.askHost(widget.brief, sent)) {
        acc += chunk;
        if (!mounted) return;
        setState(() => _messages[_messages.length - 1] = {'role': 'assistant', 'content': acc});
      }
    } on BackendError {
      // Out of reach: answer from the same rules, on the phone.
      acc = hostFallbackAnswer(widget.brief, question);
      if (mounted) setState(() => _messages[_messages.length - 1] = {'role': 'assistant', 'content': acc});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    unawaited(_ask(q));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final lines = hostBriefing(widget.brief);
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Ninkasi',
          subtitle: 'for the team — never about a guest',
          back: true,
          tabBar: false,
          children: [
            Glass(
              padding: const EdgeInsets.all(S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('THIS SHIFT', style: T.label(bd)),
                const SizedBox(height: S.s),
                for (final l in lines) _Bullet(l),
              ]),
            ),
            const SizedBox(height: S.l),
            for (final m in _messages)
              Padding(
                padding: const EdgeInsets.only(bottom: S.m),
                child: m['role'] == 'user'
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.m),
                          decoration: BoxDecoration(color: bd.ink, borderRadius: BorderRadius.circular(rTile)),
                          child: Text(m['content']!, style: T.body(bd, color: bd.base)),
                        ),
                      )
                    : Glass(
                        padding: const EdgeInsets.all(S.l),
                        child: Text(m['content']!.isEmpty ? '…' : m['content']!, style: T.serif(bd, size: 18, height: 1.45)),
                      ),
              ),
            if (!_busy && _messages.isEmpty)
              Wrap(spacing: S.s, runSpacing: S.s, children: [for (final q in hostStarters(widget.brief)) BdChip(q, onTap: () => _ask(q))]),
            const SizedBox(height: S.l),
            Row(children: [
              Expanded(child: GlassField(controller: _input, hint: 'Ask about the shift', action: TextInputAction.send, onSubmitted: (_) => _send())),
              const SizedBox(width: S.s),
              IconBtn(PhBold.arrowUp, tooltip: 'Ask', glass: true, onTap: _busy ? null : _send),
            ]),
            const SizedBox(height: S.s),
            Text('She knows tonight\'s room, the menu, the card and public facts about the area — never anything about a guest. She never suggests selling more.', style: T.caption(bd)),
          ],
        ),
      ),
    );
  }
}
