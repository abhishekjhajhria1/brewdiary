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
import '../../logic/service.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
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
        Loader<List<OrderLine>>(
          load: () => Backend.i.stationLines(widget.venue.id, widget.station),
          refresh: floorRev,
          retry: true,
          builder: (context, lines, loading) {
            if (lines == null) return const Skeleton(height: 280);
            final all = tickets(lines);
            if (all.isEmpty) return EmptyNote('No ${widget.station} tickets waiting. New orders appear here the moment they\'re sent.');
            return LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
              final w = (c.maxWidth - S.m * (cols - 1)) / cols;
              return Wrap(spacing: S.m, runSpacing: S.m, children: [for (final t in all) SizedBox(width: w, child: _TicketCard(station: widget.station, ticket: t))]);
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
  const _TicketCard({required this.station, required this.ticket});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mins = ticket.minutes(DateTime.now());
    final late = lateness(station, mins);
    final tone = [Tone.calm, Tone.wait, Tone.late][late];
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(ticket.where, style: T.serif(bd, size: 26))),
          ToneTag('${mins}m${late == 2 ? ' · late' : ''}', tone),
        ]),
        const SizedBox(height: S.s),
        for (final l in ticket.lines)
          Semantics(
            button: nextStationStatus(l.status) != null,
            label: '${l.qty} ${l.name}, ${l.status}',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: nextStationStatus(l.status) == null ? null : () => runAction(context, () => Backend.i.setLineStatus(l.id, nextStationStatus(l.status)!)),
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
                    ToneTag(switch (l.status) { 'sent' => 'new', 'preparing' => 'making', _ => 'ready' }, switch (l.status) { 'sent' => Tone.wait, 'preparing' => Tone.info, _ => Tone.good }),
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
    );
  }
}
