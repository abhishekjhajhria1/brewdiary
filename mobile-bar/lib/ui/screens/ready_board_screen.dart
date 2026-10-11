// The ready board — a tablet or a TV by the counter, facing the guests: the pickup
// numbers being made, and the ones ready to collect, big enough to read from across the
// room. Numbers only (pickup_board(), 059): never a name, never what was ordered. It
// re-reads itself every 5 seconds and keeps the screen on while it's open.
//
// The same board is on the web (bwdy.site/ready/<code>) for a smart TV's browser.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../device/awake.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';

class ReadyBoardScreen extends StatefulWidget {
  final String venueName;

  /// Any of the venue's pickup points' codes.
  final String code;
  const ReadyBoardScreen({super.key, required this.venueName, required this.code});
  @override
  State<ReadyBoardScreen> createState() => _ReadyBoardScreenState();
}

class _ReadyBoardScreenState extends State<ReadyBoardScreen> {
  Timer? _tick;
  List<PickupNumber>? _board;
  bool _offline = false;
  Set<int> _ready = const {};
  Set<int> _fresh = const {};

  Future<void> _read() async {
    try {
      final b = await Backend.i.pickupBoard(widget.code);
      if (!mounted) return;
      final ready = {for (final n in b) if (n.ready) n.no};
      // A number that just turned ready glows (and the tablet buzzes once).
      final fresh = _board == null ? <int>{} : ready.difference(_ready);
      if (fresh.isNotEmpty) Haptics.success();
      setState(() {
        _board = b;
        _ready = ready;
        _fresh = fresh;
        _offline = false;
      });
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    }
  }

  @override
  void initState() {
    super.initState();
    keepAwake(true);
    _read();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _read());
  }

  @override
  void dispose() {
    _tick?.cancel();
    keepAwake(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final b = _board;
    final making = [for (final n in b ?? const <PickupNumber>[]) if (!n.ready) n.no];
    final ready = [for (final n in b ?? const <PickupNumber>[]) if (n.ready) n]..sort((a, c) => c.since.compareTo(a.since));
    return Scaffold(
      body: Ambient(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(S.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                IconBtn(Ph.x, tooltip: 'Close the board', color: bd.faint, onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: S.s),
                Expanded(child: Text(widget.venueName, style: T.serif(bd, size: 30), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (_offline) const ToneTag('reconnecting', Tone.wait),
              ]),
              const SizedBox(height: S.l),
              Expanded(
                child: b == null
                    ? const Center(child: Skeleton(height: 240))
                    : LayoutBuilder(builder: (context, c) {
                        final wide = c.maxWidth >= 700;
                        final readyPane = _Pane(
                          title: 'READY — COME AND COLLECT',
                          empty: 'Nothing waiting.',
                          accent: true,
                          numbers: [for (final n in ready) n.no],
                          fresh: _fresh,
                          size: wide ? 96 : 72,
                        );
                        final makingPane = _Pane(title: 'BEING MADE', empty: 'Nothing on the go.', numbers: making, size: wide ? 56 : 44);
                        return wide
                            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(flex: 2, child: makingPane),
                                const SizedBox(width: S.xl),
                                Expanded(flex: 3, child: readyPane),
                              ])
                            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(flex: 3, child: readyPane),
                                const SizedBox(height: S.l),
                                Expanded(flex: 2, child: makingPane),
                              ]);
                      }),
              ),
              const SizedBox(height: S.m),
              Text('Order from your phone: scan the QR on the counter. Your number shows here when it\'s ready.', textAlign: TextAlign.center, style: T.sans(bd, size: 16, color: bd.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  final String title;
  final String empty;
  final List<int> numbers;
  final Set<int> fresh;
  final bool accent;
  final double size;
  const _Pane({required this.title, required this.empty, required this.numbers, required this.size, this.fresh = const {}, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.all(S.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: T.label(bd).copyWith(color: accent ? bd.accentText : null)),
        const SizedBox(height: S.l),
        Expanded(
          child: numbers.isEmpty
              ? Text(empty, style: T.sans(bd, size: 18, color: bd.faint))
              : SingleChildScrollView(
                  child: Wrap(spacing: S.xl, runSpacing: S.m, children: [
                    for (final n in numbers)
                      Pulse(
                        key: ValueKey('$title$n'),
                        active: fresh.contains(n),
                        color: bd.accent,
                        child: Semantics(
                          label: accent ? 'Number $n is ready' : 'Number $n is being made',
                          excludeSemantics: true,
                          child: Text('$n', style: T.serif(bd, size: size, color: accent ? bd.accentText : bd.muted).copyWith(fontFeatures: T.tnum, height: 1)),
                        ),
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }
}
