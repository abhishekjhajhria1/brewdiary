// Small moments: the restrained motion that makes a log feel like something.
// The day you just logged blooms once as the sheet slides away. In an empty
// diary, today breathes a few times to say "start here". Ninkasi's bubble shows
// her thinking. A streak milestone gets one quiet sheet. All of it steps aside
// when the phone asks for reduced motion.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../theme.dart';
import 'common.dart';
import 'log_sheet.dart';

// ── the log moment ───────────────────────────────────────────────────────────
/// Which day to bloom next. Whoever opened the log sheet fires it; that day's
/// square in the month grid hears it.
class LogBloom {
  static final signal = ValueNotifier<({String key, int seq})?>(null);
  static var _seq = 0;
  static void fire(String dateKey) => signal.value = (key: dateKey, seq: ++_seq);
}

/// Open the log sheet for a day, then mark what happened: if something new was
/// written, the day's square blooms, and if that carried the streak across a
/// milestone, it gets one quiet sheet (`yearLink`: offer "See the year", only
/// where the calendar is on screen). Returns true when an entry was added.
Future<bool> openLog(BuildContext context, String dateKey, {List<({String title, String? time})> plans = const [], bool cheer = true, bool yearLink = true}) async {
  final entries = entryStore.entries;
  final before = {
    for (final e in entries)
      if (e.date == dateKey) e.id,
  };
  final streakBefore = stats(entries).current;
  await showLogSheet(context, dateKey: dateKey, plans: plans, recentDrinks: recentDrinks(entries), recentMoods: recentMoods(entries));
  final added = entryStore.entries.any((e) => e.date == dateKey && !before.contains(e.id));
  if (!added) return false;
  // Let the sheet slide mostly clear first, so the bloom is seen, not covered.
  await Future<void>.delayed(const Duration(milliseconds: 160));
  LogBloom.fire(dateKey);
  if (cheer && context.mounted) {
    final m = crossedMilestone(streakBefore, stats(entryStore.entries).current);
    if (m != null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (context.mounted) await showStreakCheer(context, m, yearLink: yearLink);
    }
  }
  return true;
}

/// A square in the month grid that swells a touch when its day is logged.
class BloomOnLog extends StatefulWidget {
  final String dateKey;
  final Widget child;
  const BloomOnLog({super.key, required this.dateKey, required this.child});
  @override
  State<BloomOnLog> createState() => _BloomOnLogState();
}

class _BloomOnLogState extends State<BloomOnLog> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    LogBloom.signal.addListener(_heard);
  }

  void _heard() {
    final s = LogBloom.signal.value;
    if (s == null || s.key != widget.dateKey || !mounted || MediaQuery.disableAnimationsOf(context)) return;
    final c = _c ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..addListener(() => setState(() {}));
    c.forward(from: 0);
  }

  @override
  void dispose() {
    LogBloom.signal.removeListener(_heard);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _c?.value ?? 0;
    // Up and back in one breath; it stays inside the grid's gap, never over a neighbour.
    final swell = t == 0 || t == 1 ? 0.0 : math.sin(math.pi * Curves.easeOut.transform(t));
    return Transform.scale(scale: 1 + .12 * swell, child: widget.child);
  }
}

/// Rings drawn above the month grid: the ripple from a day just logged, and the
/// slow beckon on today while the diary is still empty. Painted over the whole
/// grid so a ring is never hidden under the square next to it.
class DayRings extends StatefulWidget {
  final List<GridDay> grid;

  /// Today's key while nothing has been logged yet — it breathes three times, then rests.
  final String? beckonKey;
  final Widget child;
  const DayRings({super.key, required this.grid, this.beckonKey, required this.child});
  @override
  State<DayRings> createState() => _DayRingsState();
}

class _DayRingsState extends State<DayRings> with TickerProviderStateMixin {
  late final _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final _beckon = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  String? _rippleKey;
  bool _beckoned = false;
  ScrollPosition? _scroll;

  @override
  void initState() {
    super.initState();
    LogBloom.signal.addListener(_heard);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The beckon waits until the grid is actually on screen — on the landing the
    // calendar sits below the fold, and three breaths nobody sees are wasted.
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _scroll) {
      _scroll?.removeListener(_onScroll);
      _scroll = pos;
      _scroll?.addListener(_onScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBeckon());
  }

  @override
  void didUpdateWidget(covariant DayRings old) {
    super.didUpdateWidget(old);
    if (widget.beckonKey == null && _beckon.isAnimating) _beckon.stop();
  }

  // A scroll lands before the frame that lays it out; look once that frame is done.
  bool _checkQueued = false;
  void _onScroll() {
    if (_beckoned || _checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      _maybeBeckon();
    });
  }

  void _maybeBeckon() {
    if (_beckoned || !mounted || widget.beckonKey == null || MediaQuery.disableAnimationsOf(context)) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    // Most of the grid showing, clear of the tab bar.
    if (top + box.size.height * .6 > MediaQuery.sizeOf(context).height - 96 || bottom < 0) return;
    _beckoned = true;
    _scroll?.removeListener(_onScroll);
    _beckon.repeat(count: 3);
  }

  void _heard() {
    final s = LogBloom.signal.value;
    if (s == null || !mounted || MediaQuery.disableAnimationsOf(context)) return;
    if (!widget.grid.any((d) => d.key == s.key)) return;
    setState(() => _rippleKey = s.key);
    _ripple.forward(from: 0);
  }

  @override
  void dispose() {
    LogBloom.signal.removeListener(_heard);
    _scroll?.removeListener(_onScroll);
    _ripple.dispose();
    _beckon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int index(String? k) => k == null ? -1 : widget.grid.indexWhere((d) => d.key == k);
    return CustomPaint(
      foregroundPainter: _RingPainter(ripple: _ripple, beckon: _beckon, rippleIndex: index(_rippleKey), beckonIndex: index(widget.beckonKey), color: context.bd.accent),
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Animation<double> ripple;
  final Animation<double> beckon;
  final int rippleIndex;
  final int beckonIndex;
  final Color color;
  _RingPainter({required this.ripple, required this.beckon, required this.rippleIndex, required this.beckonIndex, required this.color}) : super(repaint: Listenable.merge([ripple, beckon]));

  // Mirrors the month grid: 7 columns of squares, 5pt apart.
  static const _gap = 5.0;
  Rect _cell(Size size, int i) {
    final w = (size.width - _gap * 6) / 7;
    return Rect.fromLTWH((i % 7) * (w + _gap), (i ~/ 7) * (w + _gap), w, w);
  }

  void _ring(Canvas canvas, Rect r, double grow, double alpha, double stroke) {
    if (alpha <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: alpha);
    canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(grow), Radius.circular(rCell + 2 + grow)), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final b = beckon.value;
    if (beckonIndex >= 0 && b > 0 && b < 1) {
      final t = Curves.easeOut.transform(b);
      _ring(canvas, _cell(size, beckonIndex), 1 + 7 * t, .6 * (1 - t), 1.5);
    }
    final v = ripple.value;
    if (rippleIndex >= 0 && v > 0 && v < 1) {
      final t = Curves.easeOutCubic.transform(v);
      final r = _cell(size, rippleIndex);
      _ring(canvas, r, 1 + 11 * t, .85 * (1 - t), 2.2 - t);
      // A second, softer ring a beat behind — a drop in still water.
      final t2 = Curves.easeOutCubic.transform(((v - .22) / .78).clamp(0, 1));
      if (v > .22) _ring(canvas, r, 1 + 8 * t2, .45 * (1 - t2), 1.2);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.rippleIndex != rippleIndex || o.beckonIndex != beckonIndex || o.color != color;
}

// ── Ninkasi thinking ─────────────────────────────────────────────────────────
/// Three dots that rise and dim in turn while a reply is on its way.
class TypingDots extends StatefulWidget {
  final Color color;
  const TypingDots({super.key, required this.color});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ninkasi is writing',
      liveRegion: true,
      child: SizedBox(
        height: 22,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                () {
                  // Each dot peaks a third of a beat after the one before it.
                  final phase = ((_c.value - i * .18) % 1 + 1) % 1;
                  final lift = phase < .5 ? math.sin(phase * 2 * math.pi).clamp(0.0, 1.0) : 0.0;
                  return Transform.translate(
                    offset: Offset(0, -3 * lift),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color.withValues(alpha: .35 + .55 * lift),
                      ),
                    ),
                  );
                }(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── streak milestones ────────────────────────────────────────────────────────
/// A week, a month, a hundred nights, a year. The streak counts nights you kept
/// the diary, dry ones included, so this celebrates the habit, never the drinking.
const streakMilestones = [7, 30, 100, 365];

/// The highest milestone this log carried the streak across, if any.
int? crossedMilestone(int before, int after) {
  int? hit;
  for (final m in streakMilestones) {
    if (before < m && after >= m) hit = m;
  }
  return hit;
}

const _cheerKey = 'brewdiary.streak.cheer.v1';

/// Show the milestone sheet once per milestone per day (deleting and re-adding
/// an entry doesn't replay it).
Future<void> showStreakCheer(BuildContext context, int milestone, {bool yearLink = true}) async {
  final stamp = '$milestone@${todayKey()}';
  if (Prefs.getString(_cheerKey) == stamp) return;
  await Prefs.setString(_cheerKey, stamp);
  HapticFeedback.mediumImpact();
  if (!context.mounted) return;
  final seeYear = await showBdSheet<bool>(context, builder: (_) => _StreakCheer(milestone: milestone, yearLink: yearLink && CalendarViewStore.instance.view == CalendarView.month));
  if (seeYear == true && CalendarViewStore.instance.view == CalendarView.month) CalendarViewStore.instance.toggle();
}

class _StreakCheer extends StatelessWidget {
  final int milestone;
  final bool yearLink;
  const _StreakCheer({required this.milestone, required this.yearLink});

  static const _copy = {
    7: ('A week of nights', 'Seven nights in a row.', 'Seven nights of writing it down, and the dry ones count just the same. The habit is the diary, not the drink.'),
    30: ('A month of nights', 'Thirty nights in a row.', "A month kept, night by night. Coffee nights, dry nights, late ones: the diary doesn't mind which."),
    100: ('A hundred nights', 'A hundred nights in a row.', "Most diaries don't make it past page ten. Yours has a hundred nights in it."),
    365: ('A whole year', 'A year of nights.', 'Every night of a year, written down. Go and look at your mosaic. You made that.'),
  };

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final (label, title, body) = _copy[milestone]!;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: S.s),
          Label(label, align: TextAlign.center, color: bd.accentText),
          const SizedBox(height: S.xs),
          Text(
            '$milestone',
            textAlign: TextAlign.center,
            style: T.serif(bd, size: 88, height: 1, color: bd.accent).copyWith(fontFeatures: T.tnum),
          ),
          const SizedBox(height: S.m),
          Text(title, textAlign: TextAlign.center, style: T.serif(bd, size: 26, height: 1.15)),
          const SizedBox(height: S.s),
          Text(body, textAlign: TextAlign.center, style: T.bodyMuted(bd)),
          const SizedBox(height: S.xl),
          _Run(nights: milestone),
          const SizedBox(height: S.xxl),
          BdButton('Lovely', onTap: () => Navigator.of(context).pop(false)),
          if (yearLink) ...[
            const SizedBox(height: S.xs),
            Center(child: TextAction('See the year', accent: true, onTap: () => Navigator.of(context).pop(true))),
          ],
        ],
      ),
    );
  }
}

/// The run itself, in miniature: every night kept lights the same warm square,
/// a drink night and a dry night alike. Grace gaps stay empty.
class _Run extends StatefulWidget {
  final int nights;
  const _Run({required this.nights});
  @override
  State<_Run> createState() => _RunState();
}

class _RunState extends State<_Run> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final logged = loggedDates(entryStore.entries);
    // Walk back from the newest kept night until the run holds `nights` of them.
    var cursor = parseKey(todayKey());
    if ((logged[toKey(cursor)] ?? 0) == 0) cursor = addDays(cursor, -1);
    final days = <bool>[];
    var kept = 0;
    while (kept < widget.nights && days.length < widget.nights + 60) {
      final on = (logged[toKey(cursor)] ?? 0) > 0;
      days.add(on);
      if (on) kept++;
      cursor = addDays(cursor, -1);
    }
    final run = days.reversed.toList();
    // A week reads as a row; a month or a hundred as rows of ten; a year as weeks.
    final cols = run.length <= 10 ? run.length : (widget.nights >= 365 ? (run.length / 7).ceil() : 10);
    final rows = (run.length / cols).ceil();
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final gap = cols > 30 ? 1.5 : 4.0;
          final size = math.min(cols <= 10 ? 26.0 : 18.0, (box.maxWidth - gap * (cols - 1)) / cols);
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Center(
              child: SizedBox(
                width: cols * size + (cols - 1) * gap,
                height: rows * size + (rows - 1) * gap,
                child: Stack(
                  children: [
                    for (var i = 0; i < run.length; i++)
                      Positioned(
                        left: (cols > 30 ? i ~/ 7 : i % cols) * (size + gap),
                        top: (cols > 30 ? i % 7 : i ~/ cols) * (size + gap),
                        child: Opacity(
                          // The squares light up in order, oldest first.
                          opacity: run[i] ? ((_c.value - i / run.length * .7) / .3).clamp(0.0, 1.0) : 1,
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: run[i] ? bd.accent.withValues(alpha: .9) : null,
                              border: run[i] ? null : Border.all(color: bd.line),
                              borderRadius: BorderRadius.circular(math.min(rCell, size / 4)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
