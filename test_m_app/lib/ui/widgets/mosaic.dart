// The calendar surfaces — MonthCalendar, YearMosaic, RecentMosaic, StreakStrip,
// MilestoneMeter, AchievementTile. Ports of src/components/calendar/* and friends.
// Everything is drawn from counts derived in core/derive.dart.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../../data/settings.dart';
import '../theme.dart';
import 'common.dart';
import 'moments.dart';

// ── month grid ───────────────────────────────────────────────────────────────
class MonthCalendar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final bd = context.bd;
    final grid = monthGrid(year, month);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: S.m),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Semantics(
              header: true,
              label: '${monthNames[month]} $year',
              excludeSemantics: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$year', style: T.sans(bd, size: 13, weight: FontWeight.w500, color: bd.muted).copyWith(fontFeatures: T.tnum)),
                const SizedBox(height: 2),
                // Scales down rather than wrapping, so "September" never breaks at large text sizes.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(monthNames[month], maxLines: 1, style: T.serif(bd, size: 40, height: 1.05)),
                ),
              ]),
            ),
          ),
          if (onToday != null) TextAction('Today', accent: true, onTap: onToday),
          IconBtn(Ph.caretLeft, tooltip: 'Previous month', onTap: onPrev),
          IconBtn(Ph.caretRight, tooltip: 'Next month', onTap: canNext ? onNext : null),
        ]),
      ),
      GestureDetector(
        // Swipe the grid sideways to change month, as in a phone's own calendar.
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300 && canNext) onNext();
          if (v > 300) onPrev();
        },
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
            DayRings(
              grid: grid,
              beckonKey: beckonToday ? todayKey() : null,
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
                      count: counts[d.key] ?? 0,
                      hasPlan: planKeys.contains(d.key),
                      dry: dryKeys.contains(d.key),
                      onSelect: onSelect,
                    ),
                ],
              ),
            ),
          ]),
          ),
        ),
      ),
    ]);
  }
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
/// GitHub-style contribution grid for the whole year — the collectible view.
class YearMosaic extends StatelessWidget {
  final int year;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;
  const YearMosaic({super.key, required this.year, required this.counts, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final jan1 = DateTime(year, 1, 1);
    final gridStart = addDays(jan1, -mondayIndex(jan1));
    final now = appNow();
    final today = DateTime(now.year, now.month, now.day);
    final todayK = todayKey();
    const cell = 11.0, gap = 3.0;

    final weeks = <List<({String key, bool inYear, bool future, bool isToday, int count})>>[];
    var cursor = gridStart;
    for (var w = 0; w < 53; w++) {
      final col = <({String key, bool inYear, bool future, bool isToday, int count})>[];
      for (var d = 0; d < 7; d++) {
        final key = toKey(cursor);
        col.add((key: key, inYear: cursor.year == year, future: cursor.isAfter(today), isToday: key == todayK, count: counts[key] ?? 0));
        cursor = addDays(cursor, 1);
      }
      weeks.add(col);
    }
    final ticks = <int, String>{};
    for (var wi = 0; wi < weeks.length; wi++) {
      final first = weeks[wi].where((d) => d.inYear).firstOrNull;
      if (first != null) {
        final dt = parseKey(first.key);
        if (dt.day <= 7) ticks[wi] = monthNames[dt.month - 1].substring(0, 3);
      }
    }
    // Start scrolled so today's week is in view.
    final todayWeek = weeks.indexWhere((c) => c.any((d) => d.isToday));
    final controller = ScrollController(initialScrollOffset: math.max(0, (todayWeek - 18) * (cell + gap)));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: S.m),
        child: Semantics(
          header: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The year so far', style: T.sans(bd, size: 13, weight: FontWeight.w500, color: bd.muted)),
            const SizedBox(height: 2),
            Text('$year', style: T.serif(bd, size: 40, height: 1.05)),
          ]),
        ),
      ),
      Glass(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var wi = 0; wi < weeks.length; wi++)
                SizedBox(
                  width: cell + gap,
                  child: Text(ticks[wi] ?? '', overflow: TextOverflow.visible, softWrap: false, style: T.sans(bd, size: 9, color: bd.faint)),
                ),
            ]),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final col in weeks)
                Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: Column(children: [
                    for (final d in col)
                      Padding(
                        padding: const EdgeInsets.only(bottom: gap),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: d.inYear && !d.future ? () => onSelect(d.key) : null,
                          child: Opacity(
                            opacity: d.inYear ? 1 : 0,
                            child: Container(
                              width: cell,
                              height: cell,
                              decoration: BoxDecoration(
                                color: bd.ycell(intensityLevel(d.count)),
                                borderRadius: BorderRadius.circular(2),
                                border: d.isToday
                                    ? Border.all(color: bd.ink, width: 1.5)
                                    : (d.count == 0 ? Border.all(color: bd.line) : null),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
            ]),
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
            Text('$v', style: T.sans(bd, size: 30, weight: FontWeight.w600, color: accent ? bd.accent : bd.ink, height: 1).copyWith(fontFeatures: T.tnum)),
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
