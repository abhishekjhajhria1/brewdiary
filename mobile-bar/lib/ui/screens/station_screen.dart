// The bar screen and the kitchen screen — tickets, oldest first. A ticket is one tab's
// open lines for this station, with its table and how long it's been waiting (a word
// and a colour as it runs long). Tap a line to move it along: making → ready. "All
// ready" does the whole ticket. Made for a tablet on the pass, readable from a step
// back; it re-reads itself every 15 seconds.
//
// Above the tickets: what's still TO MAKE, item by item (batch the three Negronis), and
// what's OFF TONIGHT (tap to bring it back). Each line's ⋯ opens its spec card, sends a
// line marked ready by mistake back to making, or 86es the item the moment it runs out.
//
// Phone orders (059) land here too — marked "phone" — and an order placed at a pickup
// point shows its NUMBER: when it's all ready, "Collected" hands it over. A café's,
// bakery's or shop's one counter sees every station at once (station 'counter'). With a
// ticket printer set up on this tablet, every new order also prints — so a kitchen with
// no screen still gets it. "Pause" holds phone orders in a rush.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../device/awake.dart';
import '../../device/printer.dart';
import '../../logic/kot.dart';
import '../../logic/roles.dart';
import '../../logic/service.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/guest_finder.dart';
import '../widgets/page.dart';
import '../widgets/shift_notes.dart';

/// A station's word on screen and on paper.
String stationWord(String station) => switch (station) { 'kitchen' => 'Kitchen', 'counter' => 'Orders', _ => 'Bar' };

/// Lines already printed (or already on screen when printing started), per venue and
/// station — so coming back to the screen never prints the night again.
final Map<String, Set<String>> _printed = {};

class StationScreen extends StatefulWidget {
  final Venue venue;
  final String station; // bar | kitchen | counter (every station: a counter's one screen)
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
  bool _printFailed = false;

  String get _printKey => '${widget.venue.id}.${widget.station}';

  void _heard(Object read, List<OrderLine> lines, List<Ticket> all) {
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
    _autoPrint(lines);
  }

  /// New lines go to this tablet's printer, a ticket per table or pickup number. What
  /// was already on screen when the screen first opened is taken as printed.
  void _autoPrint(List<OrderLine> lines) {
    final printed = _printed[_printKey];
    if (printed == null) {
      _printed[_printKey] = {for (final l in lines) l.id};
      return;
    }
    final todo = unprinted(lines, printed);
    printed.addAll(lines.map((l) => l.id));
    final address = printerFor(widget.venue.id, widget.station);
    if (todo.isEmpty || address == null || !autoPrint(widget.venue.id, widget.station)) return;
    for (final group in todo.values) {
      _print(address, Ticket(group.first.tabId, group.first.tableLabel ?? group.first.tabName ?? 'Tab', group));
    }
  }

  Future<void> _print(String address, Ticket t, {bool reprint = false}) async {
    try {
      await printSender(address, kotBytes(station: stationWord(widget.station), where: t.where, pickupNo: t.pickupNo, lines: t.lines, at: DateTime.now(), fromPhone: t.fromPhone, reprint: reprint));
      _printFailed = false;
    } on PrinterError catch (e) {
      // Said once, not on every order, until a print gets through again.
      if (!_printFailed && mounted) toast(context, e.message, tone: ToastTone.error);
      _printFailed = true;
    }
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
    // Phone orders land without anyone keying them: look a little more often.
    _tick = Timer.periodic(Duration(seconds: widget.venue.tableService ? 10 : 15), (_) => floorRev.bump());
    keepAwake(true);
  }

  @override
  void dispose() {
    _tick?.cancel();
    keepAwake(false);
    super.dispose();
  }

  Future<void> _printerSheet() async {
    final v = widget.venue;
    final ctl = TextEditingController(text: printerFor(v.id, widget.station) ?? '');
    var auto = printerFor(v.id, widget.station) == null || autoPrint(v.id, widget.station);
    await showBdSheet<void>(context, title: '${stationWord(widget.station)} printer', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final bd = ctx.bd;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('A receipt printer on your Wi-Fi (most 58/80 mm thermal printers). Its address is on the page it prints when you hold the feed button as it turns on.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.m),
          LineField(controller: ctl, label: 'Printer address', hint: '192.168.1.50', keyboard: TextInputType.url, maxLength: 60),
          SettingRow(
            title: 'Print every new order',
            hint: 'While this screen is open on this tablet. Keep it plugged in by the printer.',
            trailing: BdToggle(on: auto, label: 'Print every new order', onChanged: (x) => set(() => auto = x)),
          ),
          const SizedBox(height: S.l),
          BdButton('Print a test ticket', icon: Ph.printer, kind: BtnKind.secondary, onTap: () async {
            try {
              await sendToPrinter(ctl.text, testPageBytes(v.name, stationWord(widget.station)));
              if (ctx.mounted) toast(ctx, 'Sent — check the printer.');
            } on PrinterError catch (e) {
              if (ctx.mounted) toast(ctx, e.message, tone: ToastTone.error);
            }
          }),
          const SizedBox(height: S.s),
          BdButton('Save', onTap: () async {
            if (ctl.text.trim().isNotEmpty && parsePrinter(ctl.text) == null) return toast(ctx, 'That doesn\'t look like a printer\'s address — it\'s like 192.168.1.50.', tone: ToastTone.error);
            final said = ctl.text.trim().isEmpty ? 'No printer for the ${stationWord(widget.station).toLowerCase()} on this tablet.' : 'New orders print at ${ctl.text.trim()}.';
            await setPrinter(v.id, widget.station, ctl.text, auto: auto);
            if (!ctx.mounted) return;
            toast(ctx, said);
            Navigator.pop(ctx);
          }),
          if (printerFor(v.id, widget.station) != null) ...[
            const SizedBox(height: S.s),
            BdButton('Forget this printer', kind: BtnKind.quiet, onTap: () async {
              await setPrinter(v.id, widget.station, null);
              if (ctx.mounted) Navigator.pop(ctx);
            }),
          ],
        ]);
      });
    });
    ctl.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final page = ScrollPage(
      title: stationWord(widget.station),
      subtitle: widget.venue.name,
      back: widget.pushed,
      tabBar: !widget.pushed,
      maxWidth: kWideMaxWidth,
      onRefresh: () async => floorRev.bump(),
      children: [
        // The kitchen lands here: tonight's note is for them too.
        if (!widget.pushed) ShiftNotesCard(venue: widget.venue),
        _StationBar(venue: widget.venue, station: widget.station, onPrinter: _printerSheet),
        const SizedBox(height: S.m),
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
            _heard(lines, lines, all);
            final items = {for (final m in menu) m.id: m};
            final off = menu.where((m) => !m.available && m.station == widget.station).toList();
            final toMake = allDay(shown);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (toMake.isNotEmpty || off.isNotEmpty) ...[
                _StationStrip(toMake: toMake, off: off),
                const SizedBox(height: S.m),
              ],
              if (all.isEmpty)
                EmptyNote(widget.station == 'counter'
                    ? 'No orders waiting. Phone orders from your counter\'s QR appear here, with a number to call.'
                    : 'No ${widget.station} tickets waiting. New orders appear here the moment they\'re sent.')
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
                            venue: widget.venue,
                            ticket: t,
                            fresh: _fresh.contains(t.tabId),
                            onAdvance: _advance,
                            onPrint: printerFor(widget.venue.id, widget.station) == null ? null : () => _print(printerFor(widget.venue.id, widget.station)!, t, reprint: true),
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

/// Phone orders at a glance: how they come in, a pause for the rush, this tablet's printer.
class _StationBar extends StatelessWidget {
  final Venue venue;
  final String station;
  final VoidCallback onPrinter;
  const _StationBar({required this.venue, required this.station, required this.onPrinter});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final v = Session.instance.venue?.id == venue.id ? Session.instance.venue! : venue;
        final printer = printerFor(v.id, station);
        return Wrap(spacing: S.s, runSpacing: S.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (v.tableService) ...[
            ToneTag(v.ordersPaused ? 'phone orders paused' : (v.ordersDirect ? 'phone orders come straight in' : 'phone orders wait for an OK'), v.ordersPaused ? Tone.wait : Tone.info),
            BdChip(
              v.ordersPaused ? 'Take phone orders again' : 'Pause phone orders',
              icon: v.ordersPaused ? Ph.play : Ph.pause,
              active: v.ordersPaused,
              onTap: () => runAction(context, () => Backend.i.pausePhoneOrders(v.id, !v.ordersPaused),
                  done: v.ordersPaused ? 'Phone orders are on again.' : 'Paused — guests are asked to order at the bar.'),
            ),
          ],
          BdChip(printer == null ? 'Ticket printer' : 'Printing at $printer', icon: Ph.printer, active: printer != null && autoPrint(v.id, station), onTap: onPrinter),
        ]);
      },
    );
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
  final Venue venue;
  final Ticket ticket;

  /// Reprint this ticket on the tablet's printer (null without one).
  final VoidCallback? onPrint;

  /// The menu, by id: a line's spec card and its 86.
  final Map<String, MenuItem> items;

  /// Arrived since the last read: it glows for a moment.
  final bool fresh;
  final ValueChanged<OrderLine> onAdvance;

  /// What the guests at this table shared tonight (bar only).
  final List<GuestTaste> tastes;
  const _TicketCard({required this.station, required this.venue, required this.ticket, required this.onAdvance, this.onPrint, this.items = const {}, this.fresh = false, this.tastes = const []});

  Future<void> _more(BuildContext context, OrderLine l) async {
    final m = l.menuItemId == null ? null : items[l.menuItemId];
    final hasSpec = (m?.spec ?? '').trim().isNotEmpty;
    await showActions(context, title: l.name, actions: [
      if (hasSpec) SheetAction('Spec card', icon: Ph.bookOpen, onTap: () => showSpecCard(context, m!)),
      if (onPrint != null) SheetAction('Print this ticket again', icon: Ph.printer, onTap: onPrint!),
      if (l.status == 'ready') SheetAction('Back to making', icon: Ph.arrowCounterClockwise, onTap: () => runAction(context, () => Backend.i.recallLine(l.id), done: '${l.name} is back on the line.')),
      if (m != null && m.available)
        SheetAction('86 ${m.name} — it\'s run out', icon: Ph.prohibit, destructive: true, onTap: () => runAction(context, () => Backend.i.setItemOff(m.id, true), done: '${m.name} is off tonight. Nobody can order it.')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mins = ticket.minutes(DateTime.now());
    final late = lateness(station == 'counter' ? 'bar' : station, mins);
    final tone = [Tone.calm, Tone.wait, Tone.late][late];
    final pickup = ticket.pickupNo;
    // Handing alcohol over at a counter: the ID check is the server's word, at the counter.
    final alcohol = venue.sellsAlcohol && ticket.lines.any((l) => l.menuItemId != null && items[l.menuItemId] != null && !items[l.menuItemId]!.noAlcohol);
    return Pulse(
      active: fresh,
      color: bd.accent,
      child: Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: pickup == null
                ? Text(ticket.where, style: T.serif(bd, size: 26))
                : Semantics(
                    label: 'Pickup number $pickup',
                    excludeSemantics: true,
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: 'No. ', style: T.sans(bd, size: 15, weight: FontWeight.w600, color: bd.muted)),
                      TextSpan(text: '$pickup', style: T.serif(bd, size: 34).copyWith(fontFeatures: T.tnum)),
                    ])),
                  ),
          ),
          if (ticket.fromPhone) ...[
            Icon(Ph.deviceMobile, size: 18, color: bd.muted, semanticLabel: 'ordered from a phone'),
            const SizedBox(width: S.xs),
          ],
          ToneTag('${mins}m${late == 2 ? ' · late' : ''}', tone),
        ]),
        if (pickup != null)
          Text(alcohol ? 'to collect · check ID when you hand it over' : 'to collect at the counter', style: T.caption(bd).copyWith(color: alcohol ? bd.accentText : null)),
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
              }, done: pickup == null ? '${ticket.where} is ready.' : 'Number $pickup is ready — it\'s on the board.')),
        ] else if (pickup != null) ...[
          const SizedBox(height: S.s),
          BdButton('Collected', icon: Ph.handTap, onTap: () => runAction(context, () => Backend.i.collectPickup(ticket.tabId), done: 'Number $pickup collected.')),
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
