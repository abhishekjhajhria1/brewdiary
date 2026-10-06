// The bar screen and the kitchen screen — tickets, oldest first. A ticket is one tab's
// open lines for this station, with its table and how long it's been waiting (a word
// and a colour as it runs long). Tap a line to move it along: making → ready. "All
// ready" does the whole ticket. Made for a tablet on the pass, readable from a step
// back; it re-reads itself every 15 seconds.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/service.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/guest_finder.dart';
import '../widgets/page.dart';

class StationScreen extends StatefulWidget {
  final Venue venue;
  final String station; // bar | kitchen
  final bool pushed;
  const StationScreen({super.key, required this.venue, required this.station, this.pushed = true});
  @override
  State<StationScreen> createState() => _StationScreenState();
}

class _StationScreenState extends State<StationScreen> {
  Timer? _tick;

  /// Tickets on screen at the last read: one that wasn't arrives with a glow and a
  /// buzz, so a new order is noticed from a step back.
  Set<String>? _known;
  Set<String> _fresh = const {};

  /// Lines moved on here but not yet read back: they show their new step at once.
  final Map<String, String> _moved = {};

  Object? _lastRead;

  void _heard(Object read, List<Ticket> all) {
    // Once per read from the server, not on every rebuild in between.
    if (identical(read, _lastRead)) return;
    _lastRead = read;
    final ids = {for (final t in all) t.tabId};
    if (_known != null) {
      final fresh = ids.difference(_known!);
      if (fresh.isNotEmpty) Haptics.warning();
      _fresh = fresh;
    }
    _known = ids;
  }

  Future<void> _advance(OrderLine l) async {
    final next = nextStationStatus(_moved[l.id] ?? l.status);
    if (next == null) return;
    setState(() => _moved[l.id] = next);
    final ok = await runAction(context, () => Backend.i.setLineStatus(l.id, next));
    if (!mounted) return;
    if (!ok) setState(() => _moved.remove(l.id));
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => floorRev.bump());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = ScrollPage(
      title: widget.station == 'kitchen' ? 'Kitchen' : 'Bar',
      subtitle: widget.venue.name,
      back: widget.pushed,
      tabBar: !widget.pushed,
      maxWidth: kWideMaxWidth,
      onRefresh: () async => floorRev.bump(),
      children: [
        Loader<(List<OrderLine>, List<GuestTonight>)>(
          load: () async {
            final lines = await Backend.i.stationLines(widget.venue.id, widget.station);
            // The bar sees the taste each table shared, so the drink is one they'll like.
            final guests = widget.station == 'bar' && Session.instance.can(Cap.tasteShare)
                ? await Backend.i.guestsTonight(widget.venue.id).catchError((_) => const <GuestTonight>[])
                : const <GuestTonight>[];
            return (lines, guests);
          },
          refresh: floorRev,
          retry: true,
          builder: (context, data, loading) {
            if (data == null) return const Skeleton(height: 280);
            final (lines, guests) = data;
            // The server's word replaces what was only shown.
            _moved.removeWhere((id, st) => lines.any((l) => l.id == id && l.status == st) || !lines.any((l) => l.id == id));
            final all = tickets([for (final l in lines) _moved[l.id] == null ? l : l.copyWith(status: _moved[l.id]!)]);
            _heard(lines, all);
            if (all.isEmpty) return EmptyNote('No ${widget.station} tickets waiting. New orders appear here the moment they\'re sent.');
            return LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
              final w = (c.maxWidth - S.m * (cols - 1)) / cols;
              return Wrap(spacing: S.m, runSpacing: S.m, children: [
                for (final t in all)
                  SizedBox(
                    key: ValueKey(t.tabId),
                    width: w,
                    child: Reveal(
                      child: _TicketCard(
                        station: widget.station,
                        ticket: t,
                        fresh: _fresh.contains(t.tabId),
                        onAdvance: _advance,
                        tastes: [for (final g in guests) if (g.tableLabel != null && g.tableLabel == t.lines.first.tableLabel) g.taste],
                      ),
                    ),
                  ),
              ]);
            });
          },
        ),
      ],
    );
    return widget.pushed ? Scaffold(body: Ambient(child: page)) : page;
  }
}

class _TicketCard extends StatelessWidget {
  final String station;
  final Ticket ticket;

  /// Arrived since the last read: it glows for a moment.
  final bool fresh;
  final ValueChanged<OrderLine> onAdvance;

  /// What the guests at this table shared tonight (bar only).
  final List<GuestTaste> tastes;
  const _TicketCard({required this.station, required this.ticket, required this.onAdvance, this.fresh = false, this.tastes = const []});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mins = ticket.minutes(DateTime.now());
    final late = lateness(station, mins);
    final tone = [Tone.calm, Tone.wait, Tone.late][late];
    return Pulse(
      active: fresh,
      color: bd.accent,
      child: Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(ticket.where, style: T.serif(bd, size: 26))),
          ToneTag('${mins}m${late == 2 ? ' · late' : ''}', tone),
        ]),
        for (final taste in tastes) ...[
          const SizedBox(height: S.s),
          TasteChips(taste, compact: true),
        ],
        const SizedBox(height: S.s),
        for (final l in ticket.lines)
          Semantics(
            button: nextStationStatus(l.status) != null,
            label: '${l.qty} ${l.name}, ${l.status}',
            // A tap moves the line on at once (new → making → ready); the server catches up.
            child: Pressable(
              enabled: nextStationStatus(l.status) != null,
              scale: .98,
              onTap: () => onAdvance(l),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: S.tap),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 36, child: Text('${l.qty}×', style: T.sans(bd, size: 18, weight: FontWeight.w700).copyWith(fontFeatures: T.tnum))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: T.sans(bd, size: 18, weight: FontWeight.w600, color: l.status == 'ready' ? bd.faint : bd.ink).copyWith(decoration: l.status == 'ready' ? TextDecoration.lineThrough : null)),
                        if (l.note != null || l.seat != null)
                          Text([if (l.seat != null) 'seat ${l.seat}', if (l.note != null) l.note!].join(' · '), style: T.sans(bd, size: 15, color: bd.accentText)),
                      ]),
                    ),
                    AnimatedSwitcher(
                      duration: Motion.med,
                      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .8, end: 1.0).animate(a), child: c)),
                      child: ToneTag(
                        key: ValueKey(l.status),
                        switch (l.status) { 'sent' => 'new', 'preparing' => 'making', _ => 'ready' },
                        switch (l.status) { 'sent' => Tone.wait, 'preparing' => Tone.info, _ => Tone.good },
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        if (!ticket.allReady) ...[
          const SizedBox(height: S.s),
          BdButton('All ready', icon: Ph.checkCircle, kind: BtnKind.secondary, onTap: () => runAction(context, () async {
                for (final l in ticket.lines.where((l) => l.status != 'ready')) {
                  await Backend.i.setLineStatus(l.id, 'ready');
                }
              }, done: '${ticket.where} is ready.')),
        ],
      ]),
      ),
    );
  }
}
