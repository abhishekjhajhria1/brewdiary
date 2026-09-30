// Ninkasi, keeping the books — the manager's advisor. She is handed ONLY what this
// manager can already see: the totals on the Numbers tab, the venue's own perk and
// quiet-night settings, and the area's anonymous taste (5+ people per line). Never a
// guest, a name, or what one person spent. Streams from the website (/api/venue-ai),
// which holds the AI key; with no key there it answers from a script.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'numbers_screen.dart';

const _starters = [
  'How do I fill my quietest night?',
  'Are regulars coming back?',
  'What should I feature for my area?',
];

class NinkasiScreen extends StatefulWidget {
  final Venue venue;
  final VenueInsights insights;
  final int days;
  const NinkasiScreen({super.key, required this.venue, required this.insights, required this.days});
  @override
  State<NinkasiScreen> createState() => _NinkasiScreenState();
}

class _NinkasiScreenState extends State<NinkasiScreen> {
  final _input = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _busy = false;
  List<PerkTier> _perks = const [];
  List<AreaTrend> _area = const [];

  Venue get v => widget.venue;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _prime() async {
    try {
      _perks = await Backend.i.perks(v.id);
      if (v.geohash != null && v.geohash!.isNotEmpty) _area = await Backend.i.areaTrends(v.geohash!, days: widget.days);
    } catch (_) {}
    await _ask(null);
  }

  /// Everything here is the venue's OWN aggregate numbers and settings.
  Map<String, dynamic> get _brief {
    final i = widget.insights;
    return {
      'venueName': v.name,
      'kind': v.kind.isCounter ? 'store' : 'bar',
      'days': widget.days,
      'currency': v.currency,
      'quietNightLabels': [for (final d in v.quietNights) weekdayShort[d]],
      'perks': [
        for (final p in _perks) {'reward': p.reward, 'at': p.kind == PerkKind.spend ? money(p.threshold, p.currency) : '${p.threshold.toStringAsFixed(0)} visits'},
      ],
      'insights': {
        'rooms': i.rooms,
        'guests': i.guests,
        'newGuests': i.newGuests,
        'returningGuests': i.returningGuests,
        'quietVisits': i.quietVisits,
        'otherVisits': i.otherVisits,
        'perksEarned': i.perksEarned,
        'perksClaimed': i.perksClaimed,
        'tabs': i.tabs,
        'takings': i.takings,
        'kudos': i.kudos,
        'visitsByDow': i.visitsByDow,
        'prevGuests': i.prevGuests,
        'prevTakings': i.prevTakings,
      },
      if (v.city != null) 'areaLabel': v.city,
      'areaTrends': [for (final t in _area) {'kind': t.kind, 'name': t.name, 'users': t.users}],
    };
  }

  Future<void> _ask(String? question) async {
    if (_busy) return;
    final sent = [..._messages, if (question != null) {'role': 'user', 'content': question}];
    setState(() {
      _messages
        ..clear()
        ..addAll(sent)
        ..add({'role': 'assistant', 'content': ''});
      _busy = true;
    });
    var acc = '';
    try {
      await for (final chunk in Backend.i.advise(_brief, sent)) {
        acc += chunk;
        if (!mounted) return;
        setState(() => _messages[_messages.length - 1] = {'role': 'assistant', 'content': acc});
      }
    } on BackendError catch (e) {
      if (mounted) setState(() => _messages[_messages.length - 1] = {'role': 'assistant', 'content': e.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Ninkasi',
          subtitle: 'reads your numbers — never a guest',
          back: true,
          tabBar: false,
          children: [
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
            if (!_busy && _messages.length <= 1)
              Wrap(spacing: S.s, runSpacing: S.s, children: [for (final q in _starters) BdChip(q, onTap: () => _ask(q))]),
            const SizedBox(height: S.l),
            Row(children: [
              Expanded(child: GlassField(controller: _input, hint: 'Ask about your numbers', action: TextInputAction.send, onSubmitted: (_) => _send())),
              const SizedBox(width: S.s),
              IconBtn(PhBold.arrowUp, tooltip: 'Ask', glass: true, onTap: _busy ? null : _send),
            ]),
            const SizedBox(height: S.s),
            Text('She sees only these totals and your area\'s anonymous taste. She never advises anything that rewards drinking more.', style: T.caption(bd)),
          ],
        ),
      ),
    );
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    unawaited(_ask(q));
  }
}
