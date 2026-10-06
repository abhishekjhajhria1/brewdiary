// The calendar surfaces — MonthCalendar, YearMosaic, RecentMosaic, StreakStrip,
// MilestoneMeter, AchievementTile. Ports of src/components/calendar/* and friends.
// Everything is drawn from counts derived in core/derive.dart.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../../data/settings.dart';
import '../theme.dart';
import 'common.dart';
import 'moments.dart';

// ── month grid ───────────────────────────────────────────────────────────────
class MonthCalendar extends StatefulWidget {
  final int year;
  final int month; // 0-based
  final Map<String, int> counts;
  final Set<String> planKeys;
  final Set<String> dryKeys;
  final ValueChanged<String> onSelect;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool canNext;

  /// Shown as a "Today" shortcut while you're looking at another month.
  final VoidCallback? onToday;

  /// An empty diary: today's square breathes a few times to say "start here".
  final bool beckonToday;

  const MonthCalendar({
    super.key,
    required this.year,
    required this.month,
    required this.counts,
    this.planKeys = const {},
    this.dryKeys = const {},
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
    required this.canNext,
    this.onToday,
    this.beckonToday = false,
  });

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

/// The month turns like a page: the days follow a sideways drag (and give only a
/// little toward a month you can't open yet); let go past the point, or flick, and
/// the next month slides in from that side. The arrows and "Today" slide it the
/// same way, so you always know which way you went.
class _MonthCalendarState extends State<MonthCalendar> with SingleTickerProviderStateMixin {
  // How far the days are dragged, in points (springs back to 0).
  late final AnimationController _shift = AnimationController.unbounded(vsync: this);
  static final _settle = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: .86);
  double _dx = 0;
  double _width = 320;
  bool _armed = false;
  int _dir = 1;

  int get _ym => widget.year * 12 + widget.month;

  @override
  void didUpdateWidget(covariant MonthCalendar old) {
    super.didUpdateWidget(old);
    final was = old.year * 12 + old.month;
    if (was != _ym) _dir = _ym > was ? 1 : -1;
  }

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  double get _turnAt => _width * .22;

  /// The drag as drawn: it follows the finger with a little weight, and barely
  /// moves toward a month that can't be opened.
  double _rubber(double dx) {
    final blocked = dx < 0 && !widget.canNext;
    final shown = dx * (blocked ? .12 : .55);
    return shown.clamp(-_width * .45, _width * .45);
  }

  bool _canTurn(double dx) => dx > 0 || widget.canNext;

  void _update(DragUpdateDetails d) {
    _dx += d.delta.dx;
    if (!context.reduceMotion) _shift.value = _rubber(_dx);
    // A detent: past this point, letting go turns the month.
    final armed = _dx.abs() > _turnAt && _canTurn(_dx);
    if (armed != _armed) {
      _armed = armed;
      if (armed) Haptics.tick();
    }
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final next = (v < -300 || (_dx < -_turnAt && v <= 300)) && widget.canNext;
    final prev = !next && (v > 300 || (_dx > _turnAt && v >= -300));
    if ((next || prev) && !_armed) Haptics.tick(); // a flick that never reached the detent
    _dx = 0;
    _armed = false;
    if (next) widget.onNext();
    if (prev) widget.onPrev();
    _shift.animateWith(SpringSimulation(_settle, _shift.value, 0, 0));
  }

  void _cancel() {
    _dx = 0;
    _armed = false;
    _shift.animateWith(SpringSimulation(_settle, _shift.value, 0, 0));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final grid = monthGrid(widget.year, widget.month);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: S.m),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Semantics(
              header: true,
              label: '${monthNames[widget.month]} ${widget.year}',
              excludeSemantics: true,
              child: SlideSwitcher(
                direction: _dir,
                shift: .08,
                child: Column(key: ValueKey(_ym), crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${widget.year}', style: T.sans(bd, size: 13, weight: FontWeight.w500, color: bd.muted).copyWith(fontFeatures: T.tnum)),
                  const SizedBox(height: 2),
                  // Scales down rather than wrapping, so "September" never breaks at large text sizes.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(monthNames[widget.month], maxLines: 1, style: T.serif(bd, size: 40, height: 1.05)),
                  ),
                ]),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: context.reduceMotion ? Duration.zero : Motion.med,
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .85, end: 1.0).animate(a), child: c)),
            child: widget.onToday != null ? TextAction('Today', key: const ValueKey('today'), accent: true, onTap: widget.onToday) : const SizedBox.shrink(key: ValueKey('none')),
          ),
          IconBtn(Ph.caretLeft, tooltip: 'Previous month', onTap: widget.onPrev),
          IconBtn(Ph.caretRight, tooltip: 'Next month', onTap: widget.canNext ? widget.onNext : null),
        ]),
      ),
      GestureDetector(
        // Swipe the grid sideways to change month, as in a phone's own calendar.
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: _end,
        onHorizontalDragCancel: _cancel,
        child: Glass(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          // Day numbers live in fixed squares: let them grow only a little with the text size.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.1,
            child: Column(children: [
              Row(children: [
                for (final w in weekdays)
                  Expanded(child: Center(child: Text(w.substring(0, 1), style: T.sans(bd, size: 12, weight: FontWeight.w600, color: bd.faint)))),
              ]),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (context, box) {
                _width = box.maxWidth;
                // The days slide under the card's edge, never across the page.
                return ClipRect(
                  clipper: const _InsetClip(EdgeInsets.fromLTRB(10, 12, 10, 10)),
                  child: AnimatedBuilder(
                    animation: _shift,
                    builder: (context, child) {
                      final x = _shift.value;
                      return Opacity(opacity: (1 - x.abs() / _width * .6).clamp(.4, 1.0), child: Transform.translate(offset: Offset(x, 0), child: child));
                    },
                    child: SlideSwitcher(
                      direction: _dir,
                      shift: .14,
                      child: KeyedSubtree(
                        key: ValueKey(_ym),
                        child: DayRings(
                          grid: grid,
                          beckonKey: widget.beckonToday ? todayKey() : null,
                          child: GridView.count(
                            crossAxisCount: 7,
                            shrinkWrap: true,
                            primary: false,
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 5,
                            crossAxisSpacing: 5,
                            children: [
                              for (final d in grid)
                                DayCell(
                                  day: d,
                                  count: widget.counts[d.key] ?? 0,
                                  hasPlan: widget.planKeys.contains(d.key),
                                  dry: widget.dryKeys.contains(d.key),
                                  onSelect: widget.onSelect,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Clips to its box grown by [inset] — the padding of the card around it, so a day's
/// ripple (which reaches past its square) still shows, but nothing leaves the card.
class _InsetClip extends CustomClipper<Rect> {
  final EdgeInsets inset;
  const _InsetClip(this.inset);
  @override
  Rect getClip(Size size) => inset.inflateRect(Offset.zero & size);
  @override
  bool shouldReclip(_InsetClip old) => old.inset != inset;
}

class DayCell extends StatelessWidget {
  final GridDay day;
  final int count;
  final bool hasPlan;
  final bool dry;
  final ValueChanged<String> onSelect;
  const DayCell({super.key, required this.day, required this.count, this.hasPlan = false, this.dry = false, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final level = intensityLevel(count);
    final interactive = !day.isFuture || hasPlan;
    final numColor = !day.inMonth ? bd.faint.withValues(alpha: .7) : (day.isFuture ? bd.faint : bd.ink);
    final cell = AnimatedContainer(
      duration: Motion.med,
      decoration: BoxDecoration(
        color: bd.cell(level),
        borderRadius: BorderRadius.circular(rCell + 2),
        border: day.isToday
            ? Border.all(color: bd.accent, width: 1.6)
            : (level == 0 && day.inMonth ? Border.all(color: bd.line, width: .8) : null),
      ),
      child: Stack(children: [
        Center(
          child: Text(
            '${day.date.day}',
            style: T.sans(bd, size: 13.5, color: numColor, weight: day.isToday ? FontWeight.w700 : FontWeight.w500).copyWith(fontFeatures: T.tnum),
          ),
        ),
        if (count > 1)
          Positioned(right: 3, top: 1, child: Text('$count', style: T.sans(bd, size: 9, weight: FontWeight.w600, color: bd.ink.withValues(alpha: .72)).copyWith(fontFeatures: T.tnum))),
        if (hasPlan || (dry && count == 0))
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: hasPlan
                    ? BoxDecoration(color: bd.accent, shape: BoxShape.circle)
                    : BoxDecoration(shape: BoxShape.circle, border: Border.all(color: bd.muted, width: 1)),
              ),
            ),
          ),
      ]),
    );
    return Semantics(
      button: interactive,
      label: '${formatDayLong(day.key)}${count > 0 ? ', $count logged' : (dry ? ', a dry day' : ', nothing logged yet')}${hasPlan ? ', a plan' : ''}${day.isToday ? ', today' : ''}',
      excludeSemantics: true,
      child: BloomOnLog(dateKey: day.key, child: interactive ? Pressable(onTap: () => onSelect(day.key), child: cell) : cell),
    );
  }
}

/// The month ⇄ year switch, after the website's top-bar squircle. Its face hints
/// at where it takes you: in month view a tiny 3×3 mosaic (the year in miniature),
/// in year view this month's name (the grid you'd go back to).
class ViewSquircle extends StatelessWidget {
  final VoidCallback? onToggled;
  const ViewSquircle({super.key, this.onToggled});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: CalendarViewStore.instance,
      builder: (context, _) {
        final month = CalendarViewStore.instance.view == CalendarView.month;
        return IconBtnFrame(
          tooltip: month ? 'Show the year' : 'Show the month',
          onTap: () {
            CalendarViewStore.instance.toggle();
            onToggled?.call();
          },
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bd.glass, borderRadius: BorderRadius.circular(12), border: Border.all(color: bd.glassBorder, width: .8)),
            child: AnimatedSwitcher(
              duration: Motion.med,
              transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: .6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
              child: month
                  ? SizedBox(
                      key: const ValueKey('mosaic'),
                      width: 16,
                      height: 16,
                      child: GridView.count(
                        crossAxisCount: 3,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        primary: false,
                        children: [for (final l in const [3, 1, 4, 2, 4, 1, 4, 2, 3]) DecoratedBox(decoration: BoxDecoration(color: bd.ycell(l), borderRadius: BorderRadius.circular(1.2)))],
                      ),
                    )
                  : Text(
                      monthNames[appNow().month - 1].substring(0, 3).toUpperCase(),
                      key: const ValueKey('month'),
                      style: T.sans(bd, size: 9.5, weight: FontWeight.w700, spacing: 1, color: bd.ink),
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ── year mosaic ──────────────────────────────────────────────────────────────
typedef _YearDay = ({String key, bool inYear, bool future, bool isToday, int count});

/// GitHub-style contribution grid for the whole year — the collectible view. It is
/// painted in one pass (371 squares, one layer) and, when you turn to it, fills in
/// left to right across what you can see, like ink taking to paper.
class YearMosaic extends StatefulWidget {
  final int year;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;
  const YearMosaic({super.key, required this.year, required this.counts, required this.onSelect});

  static const cell = 11.0, gap = 3.0;

  @override
  State<YearMosaic> createState() => _YearMosaicState();
}

class _YearMosaicState extends State<YearMosaic> with SingleTickerProviderStateMixin {
  static const _step = YearMosaic.cell + YearMosaic.gap;
  late final ScrollController _scroll;
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
  late int _firstVisible;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Start scrolled so today's week is in view.
    final todayWeek = _weeks().indexWhere((c) => c.any((d) => d.isToday));
    _firstVisible = math.max(0, todayWeek - 18);
    _scroll = ScrollController(initialScrollOffset: _firstVisible * _step);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _sweep.value = 1;
    } else {
      _sweep.forward();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sweep.dispose();
    super.dispose();
  }

  List<List<_YearDay>> _weeks() {
    final jan1 = DateTime(widget.year, 1, 1);
    final gridStart = addDays(jan1, -mondayIndex(jan1));
    final now = appNow();
    final today = DateTime(now.year, now.month, now.day);
    final todayK = todayKey();
    final weeks = <List<_YearDay>>[];
    var cursor = gridStart;
    for (var w = 0; w < 53; w++) {
      final col = <_YearDay>[];
      for (var d = 0; d < 7; d++) {
        final key = toKey(cursor);
        col.add((key: key, inYear: cursor.year == widget.year, future: cursor.isAfter(today), isToday: key == todayK, count: widget.counts[key] ?? 0));
        cursor = addDays(cursor, 1);
      }
      weeks.add(col);
    }
    return weeks;
  }

  void _tap(List<List<_YearDay>> weeks, Offset at) {
    final wi = (at.dx / _step).floor(), di = (at.dy / _step).floor();
    if (wi < 0 || wi >= weeks.length || di < 0 || di > 6) return;
    final d = weeks[wi][di];
    if (!d.inYear || d.future) return;
    Haptics.tick();
    widget.onSelect(d.key);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    const cell = YearMosaic.cell;
    final weeks = _weeks();
    final ticks = <int, String>{};
    for (var wi = 0; wi < weeks.length; wi++) {
      final first = weeks[wi].where((d) => d.inYear).firstOrNull;
      if (first != null) {
        final dt = parseKey(first.key);
        if (dt.day <= 7) ticks[wi] = monthNames[dt.month - 1].substring(0, 3);
      }
    }
    final nights = weeks.expand((w) => w).where((d) => d.inYear && d.count > 0).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: S.m),
        child: Semantics(
          header: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The year so far', style: T.sans(bd, size: 13, weight: FontWeight.w500, color: bd.muted)),
            const SizedBox(height: 2),
            Text('${widget.year}', style: T.serif(bd, size: 40, height: 1.05)),
          ]),
        ),
      ),
      Glass(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var wi = 0; wi < weeks.length; wi++)
                SizedBox(
                  width: _step,
                  child: Text(ticks[wi] ?? '', overflow: TextOverflow.visible, softWrap: false, style: T.sans(bd, size: 9, color: bd.faint)),
                ),
            ]),
            const SizedBox(height: 4),
            Semantics(
              label: '${widget.year}: $nights ${nights == 1 ? 'night' : 'nights'} written in. Darker squares hold more.',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tap(weeks, d.localPosition),
                child: CustomPaint(
                  size: Size(weeks.length * _step, 7 * _step),
                  painter: _YearPainter(weeks: weeks, bd: bd, sweep: _sweep, firstVisible: _firstVisible),
                ),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('Less', style: T.caption(bd)),
        const SizedBox(width: 8),
        for (var l = 0; l <= 4; l++)
          Container(
            margin: const EdgeInsets.only(right: 3),
            width: cell,
            height: cell,
            decoration: BoxDecoration(color: bd.ycell(l), borderRadius: BorderRadius.circular(2), border: l == 0 ? Border.all(color: bd.line) : null),
          ),
        const SizedBox(width: 5),
        Text('More', style: T.caption(bd)),
      ]),
    ]);
  }
}

class _YearPainter extends CustomPainter {
  final List<List<_YearDay>> weeks;
  final BD bd;
  final Animation<double> sweep;
  final int firstVisible;
  _YearPainter({required this.weeks, required this.bd, required this.sweep, required this.firstVisible}) : super(repaint: sweep);

  // The wave's soft front, in columns, and how many columns it crosses (about a
  // phone's width of weeks, starting from the first one in view).
  static const _front = 7.0, _span = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = YearMosaic.cell, step = YearMosaic.cell + YearMosaic.gap;
    final t = Curves.easeOutCubic.transform(sweep.value);
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var wi = 0; wi < weeks.length; wi++) {
      final reach = t * (_span + _front) - (wi - firstVisible);
      final alpha = sweep.value >= 1 ? 1.0 : (reach / _front).clamp(0.0, 1.0);
      if (alpha <= 0) continue;
      for (var di = 0; di < 7; di++) {
        final d = weeks[wi][di];
        if (!d.inYear) continue;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(wi * step, di * step, cell, cell), const Radius.circular(2));
        final level = intensityLevel(d.count);
        if (level > 0) {
          final c = bd.ycell(level);
          fill.color = c.withValues(alpha: c.a * alpha);
          canvas.drawRRect(r, fill);
        }
        if (d.isToday) {
          edge
            ..strokeWidth = 1.5
            ..color = bd.ink.withValues(alpha: alpha);
          canvas.drawRRect(r.deflate(.75), edge);
        } else if (d.count == 0) {
          edge
            ..strokeWidth = 1
            ..color = bd.line.withValues(alpha: bd.line.a * alpha);
          canvas.drawRRect(r.deflate(.5), edge);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_YearPainter old) => old.weeks != weeks || old.bd != bd || old.firstVisible != firstVisible;
}

// ── 12-week read-only mosaic ─────────────────────────────────────────────────
class RecentMosaic extends StatelessWidget {
  final Map<String, int> counts;
  final int weeks;
  const RecentMosaic({super.key, required this.counts, this.weeks = 12});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final today = parseKey(todayKey());
    final end = addDays(today, 6 - mondayIndex(today));
    final start = addDays(end, -(weeks * 7 - 1));
    return Row(children: [
      for (var w = 0; w < weeks; w++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : 4),
            child: Column(children: [
              for (var d = 0; d < 7; d++)
                () {
                  final date = addDays(start, w * 7 + d);
                  final key = toKey(date);
                  final future = date.isAfter(today);
                  final level = intensityLevel(counts[key] ?? 0);
                  return Padding(
                    padding: EdgeInsets.only(bottom: d == 6 ? 0 : 4),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Opacity(
                        opacity: future ? 0 : 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: bd.ycell(level),
                            borderRadius: BorderRadius.circular(2),
                            border: level == 0 ? Border.all(color: bd.line) : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
            ]),
          ),
        ),
    ]);
  }
}

// ── streak strip + milestone meter ───────────────────────────────────────────
/// The streak, the nights you kept the diary (dry ones too) and the kinds you've
/// tried. The meter counts NIGHTS, never drinks — nothing rewards drinking more.
class StreakStrip extends StatelessWidget {
  final Stats stats;
  final int nights;
  const StreakStrip({super.key, required this.stats, required this.nights});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget stat(int v, String label, {bool accent = false}) => Expanded(
          child: Column(children: [
            CountUp(v, style: T.sans(bd, size: 30, weight: FontWeight.w600, color: accent ? bd.accent : bd.ink, height: 1)),
            const SizedBox(height: 6),
            Label(label, align: TextAlign.center),
          ]),
        );
    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [stat(stats.current, 'night streak', accent: true), stat(nights, 'nights kept'), stat(stats.kinds, 'kinds')]),
        if (nights > 0) ...[
          const SizedBox(height: 16),
          Divider(height: 1, color: bd.line),
          const SizedBox(height: 16),
          MilestoneMeter(total: nights),
        ],
      ]),
    );
  }
}

class MilestoneMeter extends StatelessWidget {
  final int total;
  const MilestoneMeter({super.key, required this.total});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = milestoneProgress(total);
    if (p.next == null) return Label('Every milestone — $total nights kept', color: bd.accent);
    final from = p.reached ?? 0;
    final pct = math.max(.04, (total - from) / (p.next! - from));
    return Column(children: [
      Row(children: [
        Expanded(child: Label('to ${p.next} nights')),
        Text.rich(TextSpan(children: [
          TextSpan(text: '$total', style: T.sans(bd, size: 14, weight: FontWeight.w500)),
          TextSpan(text: '/${p.next}', style: T.sans(bd, size: 14, color: bd.faint)),
        ])),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Stack(children: [
          Container(height: 6, color: bd.ink.withValues(alpha: .1)),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 500),
            builder: (c, v, _) => FractionallySizedBox(widthFactor: v, child: Container(height: 6, decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(99)))),
          ),
        ]),
      ),
    ]);
  }
}

// ── the rotating achievement tile (year view) ────────────────────────────────
class AchievementTile extends StatefulWidget {
  /// Pin the starting design (tests/screenshots); null = random, like the web.
  static int? fixedDesign;
  const AchievementTile({super.key});
  @override
  State<AchievementTile> createState() => _AchievementTileState();
}

class _AchievementTileState extends State<AchievementTile> {
  int _i = AchievementTile.fixedDesign ?? math.Random().nextInt(3);
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.all(S.l),
      onTap: () => setState(() => _i = (_i + 1) % 3),
      semanticLabel: 'Achievement pattern ${_i + 1} of 3. Tap for the next.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(rCtl),
          child: SizedBox(height: 96, width: double.infinity, child: CustomPaint(painter: _PatternPainter(bd, _i))),
        ),
        const SizedBox(height: 12),
        Row(children: [
          for (var d = 0; d < 3; d++)
            AnimatedContainer(
              duration: Motion.slow,
              margin: const EdgeInsets.only(right: 6),
              height: 6,
              width: d == _i ? 20 : 6,
              decoration: BoxDecoration(color: d == _i ? bd.accent : bd.ink.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
            ),
        ]),
      ]),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final BD bd;
  final int kind;
  _PatternPainter(this.bd, this.kind);
  @override
  void paint(Canvas canvas, Size size) {
    if (kind == 0) {
      // Rings
      final p = Paint()
        ..color = bd.accent.withValues(alpha: .22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final c = Offset(size.width * .2, size.height * 1.3);
      for (var r = 12.0; r < size.width * 1.3; r += 24) {
        canvas.drawCircle(c, r, p);
      }
    } else if (kind == 1) {
      // Weave
      const cols = 12, rowsN = 4, gap = 4.0;
      final w = (size.width - gap * (cols - 1)) / cols;
      final h = (size.height - gap * (rowsN - 1)) / rowsN;
      for (var i = 0; i < 48; i++) {
        final x = (i % cols) * (w + gap);
        final y = (i ~/ cols) * (h + gap);
        final level = ((i * 5 + (i % 3)) % 4) + 1;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(2)), Paint()..color = bd.ycell(level));
      }
    } else {
      // Waves
      final p = Paint()
        ..color = bd.accent.withValues(alpha: .16)
        ..strokeWidth = 5;
      for (var x = -size.height; x < size.width + size.height; x += 18) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height * .47, 0), p);
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.kind != kind || old.bd != bd;
}

/// A decorative year preview for the landing — stable pseudo-random levels.
class YearPreview extends StatelessWidget {
  const YearPreview({super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    const cols = 26, rowsN = 7;
    int level(int i) {
      final n = (i * 2654435761) & 0xFFFFFFFF;
      final r = (n % 100) / 100;
      if (r < .34) return 0;
      if (r < .62) return 1;
      if (r < .82) return 2;
      if (r < .94) return 3;
      return 4;
    }

    return ExcludeSemantics(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (c, box) {
          final s = (box.maxWidth - 4 * (cols - 1)) / cols;
          return Wrap(spacing: 4, runSpacing: 4, children: [
            for (var i = 0; i < cols * rowsN; i++)
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(color: level(i) == 0 ? bd.line : bd.ycell(level(i)), borderRadius: BorderRadius.circular(2)),
              ),
          ]);
        }),
        const SizedBox(height: 12),
        Text('A YEAR OF NIGHTS — DARKER IS MORE', style: T.section(bd).copyWith(fontSize: 10.5)),
      ]),
    );
  }
}
