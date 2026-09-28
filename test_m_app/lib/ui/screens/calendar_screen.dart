// The home — a port of src/components/calendar/CalendarHome.tsx. Streak strip, a
// gentle "looking back" memory, today's extra counters (month view) or the
// achievement tile (year view), the month grid / year mosaic, and a Ninkasi nudge.
import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/derive.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/plans.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/log_sheet.dart';
import '../widgets/mosaic.dart';

class CalendarScreen extends StatefulWidget {
  final VoidCallback onOpenNinkasi;
  const CalendarScreen({super.key, required this.onOpenNinkasi});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late int _y = DateTime.now().year;
  late int _m = DateTime.now().month - 1;

  void _step(int delta) {
    final d = addMonths(DateTime(_y, _m + 1, 1), delta);
    setState(() {
      _y = d.year;
      _m = d.month - 1;
    });
  }

  void _open(String key, Map<String, PlanDay> planDays) {
    final entries = entryStore.entries;
    showLogSheet(
      context,
      dateKey: key,
      plans: planDays[key]?.items ?? const [],
      recentDrinks: recentDrinks(entries),
      recentMoods: recentMoods(entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<Map<String, PlanDay>>(
      refresh: Listenable.merge([plansRev, auth]),
      load: PlansApi.planDays,
      builder: (context, planDaysData, _) {
        final planDays = planDaysData ?? const <String, PlanDay>{};
        return Watch(
          to: [entryStore, CalendarViewStore.instance, ExtrasStore.instance],
          builder: (context) {
            final entries = entryStore.entries;
            final counts = countsByDate(entries);
            final s = stats(entries);
            final mem = memory(entries);
            final view = CalendarViewStore.instance.view;
            final now = DateTime.now();
            var lastYM = now.year * 12 + now.month - 1;
            for (final k in planDays.keys) {
              final d = parseKey(k);
              final ym = d.year * 12 + d.month - 1;
              if (ym > lastYM) lastYM = ym;
            }
            final canNext = _y * 12 + _m < lastYM;

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StreakStrip(stats: s),
              if (mem != null) ...[
                const SizedBox(height: 16),
                Glass(
                  onTap: () => _open(mem.date, planDays),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    const Label('looking back'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: mem.drink, style: T.sans(bd, size: 14, color: bd.muted)),
                          if (mem.mood != null) TextSpan(text: ' · ${mem.mood}', style: T.sans(bd, size: 14, color: bd.muted).copyWith(fontStyle: FontStyle.italic)),
                        ]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(shortDay(mem.date), style: T.sans(bd, size: 12, color: bd.faint)),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              if (view == CalendarView.month) DayCounters(dateKey: todayKey()) else const AchievementTile(),
              const SizedBox(height: 32),
              if (view == CalendarView.month)
                MonthCalendar(
                  year: _y,
                  month: _m,
                  counts: counts,
                  planKeys: planDays.keys.toSet(),
                  dryKeys: dryDates(entries),
                  onSelect: (k) => _open(k, planDays),
                  onPrev: () => _step(-1),
                  onNext: () => _step(1),
                  canNext: canNext,
                )
              else
                YearMosaic(year: now.year, counts: counts, onSelect: (k) => _open(k, planDays)),
              if (entries.isEmpty) const EmptyNote('Tap a day to log your first drink.'),
              const SizedBox(height: 32),
              Glass(
                onTap: widget.onOpenNinkasi,
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Label('Ninkasi', color: bd.faint),
                      const SizedBox(height: 4),
                      Text('Not sure what to pour tonight?', style: T.sans(bd)),
                    ]),
                  ),
                  Text('Ask →', style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.accent)),
                ]),
              ),
            ]);
          },
        );
      },
    );
  }
}

/// The per-day quick trackers (cigarettes, water…) — each +1 is a REAL entry.
class DayCounters extends StatelessWidget {
  final String dateKey;
  const DayCounters({super.key, required this.dateKey});
  @override
  Widget build(BuildContext context) {
    final counters = ExtrasStore.instance.enabledCounters;
    if (counters.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [for (final c in counters) _DayCounter(dateKey: dateKey, def: c)]);
  }
}

class _DayCounter extends StatelessWidget {
  final String dateKey;
  final ExtraDef def;
  const _DayCounter({required this.dateKey, required this.def});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mine = entryStore.entries.where((e) => e.date == dateKey && e.drink.trim().toLowerCase() == def.entryDrink.toLowerCase()).toList();
    final n = mine.length;
    final volume = def.key == ExtraKey.water ? ExtrasStore.instance.waterVolume(n) : null;
    Widget step(String glyph, String label, VoidCallback? onTap, {bool primary = false}) => Semantics(
          label: label,
          button: true,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: primary ? bd.accent.withValues(alpha: .15) : Colors.transparent),
              child: Text(glyph, style: T.sans(bd, size: 20, color: onTap == null ? bd.faint.withValues(alpha: .4) : (primary ? bd.accent : bd.muted))),
            ),
          ),
        );
    return LayoutBuilder(builder: (context, box) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 160),
        child: Glass(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Label(def.label, color: bd.faint),
              const SizedBox(height: 2),
              Text('$n', style: T.sans(bd, size: 24, height: 1).copyWith(fontFeatures: T.tnum)),
              if (volume != null) Text(volume, style: T.sans(bd, size: 12, color: bd.faint)),
            ]),
            const SizedBox(width: 20),
            step('−', 'One fewer ${def.unit}', n == 0 ? null : () {
              final last = mine.reduce((a, b) => a.createdAt.compareTo(b.createdAt) >= 0 ? a : b);
              entryStore.deleteEntry(last.id);
            }),
            const SizedBox(width: 6),
            step('+', 'One more ${def.unit}', () => entryStore.addEntry(date: dateKey, drink: def.entryDrink, type: def.entryType), primary: true),
          ]),
        ),
      );
    });
  }
}
