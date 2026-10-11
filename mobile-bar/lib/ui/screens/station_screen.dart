// The bar screen and the kitchen screen — tickets, oldest first. A ticket is one tab's
// open lines for this station, with its table and how long it's been waiting (a word
// and a colour as it runs long). Tap a line to move it along: making → ready. "All
// ready" does the whole ticket. Made for a tablet on the pass, readable from a step
// back; it re-reads itself every 15 seconds.
//
// Above the tickets: what's still TO MAKE, item by item (batch the three Negronis), and
// what's OFF TONIGHT (tap to bring it back). Each line's ⋯ opens its spec card, sends a
// line marked ready by mistake back to making, or 86es the item the moment it runs out.
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
import '../widgets/shift_notes.dart';

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
        // The kitchen lands here: tonight's note is for them too.
        if (!widget.pushed) ShiftNotesCard(venue: widget.venue),
        Loader<(List<OrderLine>, List<GuestTonight>, List<MenuItem>)>(
          load: () async {
            final lines = await Backend.i.stationLines(widget.venue.id, widget.station);
            // The bar sees the taste each table shared, so the drink is one they'll like.
            final guests = widget.station == 'bar' && Session.instance.can(Cap.tasteShare)
                ? await Backend.i.guestsTonight(widget.venue.id).catchError((_) => const <GuestTonight>[])
                : const <GuestTonight>[];
            final menu = await Backend.i.menu(widget.venue.id).catchError((_) => const <MenuItem>[]);
            return (lines, guests, menu);
          },
          refresh: floorRev,
          retry: true,
          builder: (context, data, loading) {
            if (data == null) return const Skeleton(height: 280);
            final (lines, guests, menu) = data;
            // The server's word replaces what was only shown.
            _moved.removeWhere((id, st) => lines.any((l) => l.id == id && l.status == st) || !lines.any((l) => l.id == id));
            final shown = [for (final l in lines) _moved[l.id] == null ? l : l.copyWith(status: _moved[l.id]!)];
            final all = tickets(shown);
            _heard(lines, all);
            final items = {for (final m in menu) m.id: m};
            final off = menu.where((m) => !m.available && m.station == widget.station).toList();
            final toMake = allDay(shown);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (toMake.isNotEmpty || off.isNotEmpty) ...[
                _StationStrip(toMake: toMake, off: off),
                const SizedBox(height: S.m),
              ],
              if (all.isEmpty)
                EmptyNote('No ${widget.station} tickets waiting. New orders appear here the moment they\'re sent.')
              else
                LayoutBuilder(builder: (context, c) {
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
                            items: items,
                            tastes: [for (final g in guests) if (g.tableLabel != null && g.tableLabel == t.lines.first.tableLabel) g.taste],
                          ),
                        ),
                      ),
                  ]);
                }),
            ]);
          },
        ),
      ],
    );
    return widget.pushed ? Scaffold(body: Ambient(child: page)) : page;
  }
}

/// What's still to make, item by item, and what's off tonight (tap to bring it back).
class _StationStrip extends StatelessWidget {
  final List<({String name, int qty})> toMake;
  final List<MenuItem> off;
  const _StationStrip({required this.toMake, required this.off});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (toMake.isNotEmpty) ...[
          Text('TO MAKE', style: T.label(bd)),
          const SizedBox(height: S.s),
          Wrap(spacing: S.m, runSpacing: S.xs, children: [
            for (final x in toMake)
              Text.rich(TextSpan(children: [
                TextSpan(text: '${x.qty}× ', style: T.sans(bd, size: 17, weight: FontWeight.w700).copyWith(fontFeatures: T.tnum)),
                TextSpan(text: x.name, style: T.sans(bd, size: 17)),
              ])),
          ]),
        ],
        if (off.isNotEmpty) ...[
          if (toMake.isNotEmpty) const SizedBox(height: S.m),
          Text('OFF TONIGHT', style: T.label(bd)),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final m in off)
              BdChip(m.name, icon: Ph.prohibit, onTap: () async {
                final yes = await confirm(context, title: 'Back on: ${m.name}?', body: 'It can be ordered again.', yes: 'Bring it back');
                if (yes && context.mounted) await runAction(context, () => Backend.i.setItemOff(m.id, false), done: '${m.name} is back on.');
              }),
          ]),
        ],
      ]),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final String station;
  final Ticket ticket;

  /// The menu, by id: a line's spec card and its 86.
  final Map<String, MenuItem> items;

  /// Arrived since the last read: it glows for a moment.
  final bool fresh;
  final ValueChanged<OrderLine> onAdvance;

  /// What the guests at this table shared tonight (bar only).
  final List<GuestTaste> tastes;
  const _TicketCard({required this.station, required this.ticket, required this.onAdvance, this.items = const {}, this.fresh = false, this.tastes = const []});

  Future<void> _more(BuildContext context, OrderLine l) async {
    final m = l.menuItemId == null ? null : items[l.menuItemId];
    final hasSpec = (m?.spec ?? '').trim().isNotEmpty;
    await showActions(context, title: l.name, actions: [
      if (hasSpec) SheetAction('Spec card', icon: Ph.bookOpen, onTap: () => showSpecCard(context, m!)),
      if (l.status == 'ready') SheetAction('Back to making', icon: Ph.arrowCounterClockwise, onTap: () => runAction(context, () => Backend.i.recallLine(l.id), done: '${l.name} is back on the line.')),
      if (m != null && m.available)
        SheetAction('86 ${m.name} — it\'s run out', icon: Ph.prohibit, destructive: true, onTap: () => runAction(context, () => Backend.i.setItemOff(m.id, true), done: '${m.name} is off tonight. Nobody can order it.')),
    ]);
  }

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
                    IconBtn(Ph.dotsThree, tooltip: 'More for ${l.name}', color: bd.muted, onTap: () => _more(context, l)),
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

/// The team's spec card for an item: recipe, glass, garnish, method.
Future<void> showSpecCard(BuildContext context, MenuItem m) => showBdSheet<void>(context, title: m.name, builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('SPEC', style: T.label(bd)),
        const SizedBox(height: S.s),
        Text(m.spec ?? '', style: T.sans(bd, size: 17, height: 1.5)),
        if (m.allergens.isNotEmpty) ...[
          const SizedBox(height: S.l),
          Text('Contains: ${m.allergens.join(', ')}', style: T.sans(bd, size: 15, color: bd.accentText)),
        ],
      ]);
    });
