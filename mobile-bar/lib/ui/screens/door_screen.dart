// The door — how many are inside tonight, against the licensed capacity. A shared
// clicker for everyone on the door: tap In or Out (or a group), and the count, the
// room left and the state (colour, a mark and a word) update for every phone on it.
// It counts, never people: no name, no face, no ID.
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
import '../widgets/page.dart';

class DoorScreen extends StatefulWidget {
  final Venue venue;
  const DoorScreen({super.key, required this.venue});
  @override
  State<DoorScreen> createState() => _DoorScreenState();
}

class _DoorScreenState extends State<DoorScreen> {
  DoorCount? _count;
  bool _failed = false;

  /// Taps sent but not yet read back, so the number moves the moment you tap.
  int _pending = 0;

  /// This phone's taps tonight, newest last — "Undo" takes back the last one.
  final _mine = <int>[];
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    doorRev.addListener(_load);
    // Other phones on the door: re-read every 10 seconds while this is on screen.
    _tick = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    doorRev.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await Backend.i.doorCount(widget.venue.id);
      if (mounted) {
        setState(() {
          _count = c;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && _count == null) setState(() => _failed = true);
    }
  }

  Future<void> _tap(int n, {bool undo = false}) async {
    final c = _count;
    // Reaching capacity is worth a "look up", once, as it happens.
    if (c != null && n > 0 && doorState((c.inside + _pending).clamp(0, 1 << 30), c.capacity) != DoorState.full && doorState(c.inside + _pending + n, c.capacity) == DoorState.full) Haptics.warning();
    setState(() => _pending += n);
    final ok = await runAction(context, () => Backend.i.doorTick(widget.venue.id, n));
    if (!mounted) return;
    if (ok) {
      if (undo) {
        _mine.removeLast();
      } else {
        _mine.add(n);
      }
      await _load();
    }
    if (mounted) setState(() => _pending -= n);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final can = Session.instance.can(Cap.seatGuests);
    final c = _count;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Door',
          subtitle: widget.venue.name,
          back: true,
          tabBar: false,
          onRefresh: _load,
          children: [
            if (c == null)
              _failed
                  ? LoadError(onRetry: () {
                      setState(() => _failed = false);
                      _load();
                    })
                  : const Skeleton(height: 220)
            else ...[
              _Count(inside: (c.inside + _pending).clamp(0, 1 << 30), cameIn: c.cameIn + (_pending > 0 ? _pending : 0), capacity: c.capacity),
              const SizedBox(height: S.l),
              if (can) ...[
                Row(children: [
                  Expanded(child: _BigTap(label: 'In', icon: Ph.plus, onTap: () => _tap(1))),
                  const SizedBox(width: S.m),
                  Expanded(child: _BigTap(label: 'Out', icon: Ph.minus, onTap: () => _tap(-1))),
                ]),
                const SizedBox(height: S.m),
                Text('A group', style: T.label(bd)),
                const SizedBox(height: S.s),
                Wrap(spacing: S.s, runSpacing: S.s, children: [
                  for (final n in const [2, 3, 4, 6]) BdChip('+$n in', onTap: () => _tap(n)),
                  for (final n in const [2, 4]) BdChip('$n out', onTap: () => _tap(-n)),
                ]),
                if (_mine.isNotEmpty) ...[
                  const SizedBox(height: S.m),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextAction(
                      'Undo ${_mine.last > 0 ? '+${_mine.last} in' : '${-_mine.last} out'}',
                      icon: Ph.arrowUUpLeft,
                      onTap: () => _tap(-_mine.last, undo: true),
                    ),
                  ),
                ],
              ] else
                Text('Your role sees the door; the host and floor staff count it.', style: T.caption(bd)),
              if (c.capacity == null) ...[
                const SizedBox(height: S.l),
                Text(
                  Session.instance.can(Cap.editSettings)
                      ? 'No capacity set — add your licensed number under More › Floor setup, and the door turns amber at 90% and red at full.'
                      : 'No capacity set — a manager adds it under More › Floor setup.',
                  style: T.caption(bd),
                ),
              ],
            ],
            const SizedBox(height: S.xl),
            Text('Counts only — nobody\'s name, face or ID. Tonight starts at 6 in the morning, so a night past midnight is one night.', style: T.caption(bd)),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int inside;
  final int cameIn;
  final int? capacity;
  const _Count({required this.inside, required this.cameIn, required this.capacity});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final state = doorState(inside, capacity);
    final (tone, icon) = switch (state) {
      DoorState.open => (Tone.good, Ph.checkCircle),
      DoorState.nearly => (Tone.wait, Ph.warning),
      DoorState.full => (Tone.late, Ph.prohibit),
    };
    final color = capacity == null ? bd.muted : bd.tone(tone);
    final word = doorStateWord(state, inside, capacity);
    return Semantics(
      liveRegion: true,
      label: '$inside inside${capacity == null ? '' : ' of $capacity'}, $word. $cameIn came in tonight.',
      child: ExcludeSemantics(
        child: Glass(
          strong: true,
          padding: const EdgeInsets.all(S.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Label('INSIDE NOW'),
            const SizedBox(height: S.s),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              // The clicker: each tap rolls the number up (or down).
              RollingNumber(inside, style: T.serif(bd, size: 72, color: state == DoorState.full ? color : bd.ink)),
              if (capacity != null) ...[
                const SizedBox(width: S.s),
                Text('of $capacity', style: T.sans(bd, size: 18, color: bd.muted)),
              ],
            ]),
            if (capacity != null) ...[
              const SizedBox(height: S.m),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Stack(children: [
                    Container(color: bd.line),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: (inside / capacity!).clamp(0.0, 1.0)),
                      duration: Motion.slow,
                      curve: Motion.curve,
                      builder: (context, v, _) => FractionallySizedBox(widthFactor: v, child: AnimatedContainer(duration: Motion.slow, color: color)),
                    ),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: S.m),
            Row(children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(word, style: T.sans(bd, size: 15, weight: FontWeight.w500, color: color))),
            ]),
            const SizedBox(height: 4),
            Text('$cameIn came in tonight', style: T.caption(bd)),
          ]),
        ),
      ),
    );
  }
}

class _BigTap extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _BigTap({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    // A clicker button: every tap ticks under the thumb, so the door can count
    // without looking down.
    return Semantics(
      button: true,
      label: '1 $label',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: .95,
        child: Glass(
          padding: const EdgeInsets.symmetric(vertical: S.xl),
          child: Column(children: [
            Icon(icon, size: 32, color: bd.accentText),
            const SizedBox(height: S.s),
            Text(label, style: T.sans(bd, size: 18, weight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
