// The home — a port of src/components/calendar/CalendarHome.tsx, laid out for a
// phone: the month grid (or year mosaic) comes first so the calendar is the first
// thing you see, then your streak, a gentle "looking back" memory, today's extra
// counters, and a Ninkasi nudge. Month/Year and Discover live in the top bar.
import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/plans.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/moments.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';
import '../widgets/passport.dart';
import 'discover_screen.dart';
import 'morning_after.dart';
import 'taste_card.dart';
import 'tonight_sheet.dart';

class CalendarScreen extends StatefulWidget {
  final VoidCallback onOpenNinkasi;
  const CalendarScreen({super.key, required this.onOpenNinkasi});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late int _y = appNow().year;
  late int _m = appNow().month - 1;

  void _step(int delta) {
    final d = addMonths(DateTime(_y, _m + 1, 1), delta);
    setState(() {
      _y = d.year;
      _m = d.month - 1;
    });
  }

  void _thisMonth() {
    final now = appNow();
    setState(() {
      _y = now.year;
      _m = now.month - 1;
    });
  }

  void _open(String key, Map<String, PlanDay> planDays) => openLog(context, key, plans: planDays[key]?.items ?? const []);

  Future<void> _refresh() async {
    plansRev.bump();
    await entryStore.reload();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollPage(
      barTitle: const Wordmark(),
      actions: [
        AccentPill('Discover', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiscoverScreen()))),
        const SizedBox(width: S.xs),
        ViewSquircle(onToggled: () {
          final c = PrimaryScrollController.maybeOf(context);
          if (c != null && c.hasClients && c.positions.length == 1) c.jumpTo(0);
        }),
        ThemeDot(dark: ThemeStore.instance.isDark, onTap: ThemeStore.instance.toggle),
      ],
      onRefresh: _refresh,
      children: [
        Loader<Map<String, PlanDay>>(
          refresh: Listenable.merge([plansRev, auth]),
          load: PlansApi.planDays,
          builder: (context, planDaysData, _) {
            final planDays = planDaysData ?? const <String, PlanDay>{};
            return Watch(
              to: [entryStore, CalendarViewStore.instance, ExtrasStore.instance],
              builder: (context) => _body(context, planDays),
            );
          },
        ),
      ],
    );
  }

  Widget _body(BuildContext context, Map<String, PlanDay> planDays) {
    final bd = context.bd;
    final entries = entryStore.entries;
    final counts = countsByDate(entries);
    final s = stats(entries);
    final mem = memory(entries);
    final month = CalendarViewStore.instance.view == CalendarView.month;
    final now = appNow();
    // You can page forward as far as your furthest plan, never into an empty future.
    var lastYM = now.year * 12 + now.month - 1;
    for (final k in planDays.keys) {
      final d = parseKey(k);
      final ym = d.year * 12 + d.month - 1;
      if (ym > lastYM) lastYM = ym;
    }
    final canNext = _y * 12 + _m < lastYM;
    final onThisMonth = _y == now.year && _m == now.month - 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (month)
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
          onToday: onThisMonth ? null : _thisMonth,
          beckonToday: entries.isEmpty,
        )
      else
        YearMosaic(year: now.year, counts: counts, onSelect: (k) => _open(k, planDays)),
      if (entries.isEmpty) const EmptyNote('Tap a day to log your first drink — a coffee counts.', icon: Ph.handTap),
      _PassportStrip(year: month ? _y : now.year, month0: month ? _m : null),
      const SizedBox(height: S.xxl),
      if (morningAfterWorthOffering(now)) ...[
        Glass(
          onTap: () => showMorningAfter(context),
          semanticLabel: 'The morning after: a few things that help',
          padding: const EdgeInsets.fromLTRB(S.l, S.l, S.m, S.l),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bd.accent.withValues(alpha: .16)),
              child: Icon(Ph.drop, size: 20, color: bd.accentText),
            ),
            const SizedBox(width: S.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Morning.', style: T.row(bd)),
                const SizedBox(height: 2),
                Text('Water first — and a few kind things for the day after.', style: T.caption(bd)),
              ]),
            ),
            Icon(Ph.caretRight, size: 16, color: bd.faint),
          ]),
        ),
        const SizedBox(height: S.m),
      ],
      if (tonightWorthOffering(now)) ...[
        Glass(
          onTap: () => showTonight(context),
          semanticLabel: 'Out tonight? Pace yourself and get home safe',
          padding: const EdgeInsets.fromLTRB(S.l, S.l, S.m, S.l),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: bd.accent.withValues(alpha: .16)),
              child: Icon(Ph.moonStars, size: 20, color: bd.accentText),
            ),
            const SizedBox(width: S.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Out tonight?', style: T.row(bd)),
                const SizedBox(height: 2),
                Text('Water-break nudges, and a ride or a friend when it\'s time.', style: T.caption(bd)),
              ]),
            ),
            Icon(Ph.caretRight, size: 16, color: bd.faint),
          ]),
        ),
        const SizedBox(height: S.m),
      ],
      StreakStrip(stats: s),
      if (!month) ...[const SizedBox(height: S.m), const AchievementTile()],
      if (month && ExtrasStore.instance.enabledCounters.isNotEmpty) ...[
        const SectionHeader('Today'),
        DayCounters(dateKey: todayKey()),
      ],
      if (mem != null) ...[
        const SectionHeader('Looking back'),
        Glass(
          onTap: () => _open(mem.date, planDays),
          semanticLabel: 'Open ${formatDayLongYear(mem.date)}',
          padding: const EdgeInsets.fromLTRB(S.l, S.m, S.m, S.m),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: mem.drink, style: T.row(bd)),
                    if (mem.mood != null) TextSpan(text: ' · ${mem.mood}', style: T.row(bd, color: bd.muted).copyWith(fontStyle: FontStyle.italic)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(formatDayLongYear(mem.date), style: T.caption(bd)),
              ]),
            ),
            Icon(Ph.caretRight, size: 16, color: bd.faint),
          ]),
        ),
      ],
      const SizedBox(height: S.section),
      Glass(
        onTap: widget.onOpenNinkasi,
        semanticLabel: 'Ask Ninkasi what to pour tonight',
        padding: const EdgeInsets.fromLTRB(S.l, S.l, S.m, S.l),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bd.accent.withValues(alpha: .16)),
            child: Icon(PhFill.martini, size: 20, color: bd.accentText),
          ),
          const SizedBox(width: S.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Not sure what to pour tonight?', style: T.row(bd)),
              const SizedBox(height: 2),
              Text('Ask Ninkasi — she knows your diary.', style: T.caption(bd)),
            ]),
          ),
          Icon(Ph.caretRight, size: 16, color: bd.faint),
        ]),
      ),
    ]);
  }
}

/// The taste passport for what you're looking at: this month's visa page under
/// the month grid, the year's under the mosaic. Tap to open the whole book there.
class _PassportStrip extends StatelessWidget {
  final int year;
  final int? month0; // null = the whole year
  const _PassportStrip({required this.year, this.month0});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final entries = entryStore.entries;
    final yearView = month0 == null;
    final (from, to) = yearView ? ('$year-01-01', '$year-12-31') : monthRange(year, month0!);
    final stamps = stampsBetween(entries, from, to);
    final id = yearView ? '$year' : from.substring(0, 7);
    final title = yearView ? '$year' : '${monthNames[month0!]} $year';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Passport', action: 'Open', onAction: () => showTasteCard(context, open: id)),
      Semantics(
        button: true,
        label: 'Open the taste passport at $title, ${stamps.length} stamps',
        child: Pressable(
          onTap: () => showTasteCard(context, open: id),
          child: VisaPage(
            title: title,
            stamps: stamps,
            scale: .72,
            max: yearView ? 8 : 5,
            empty: yearView ? 'A year of stamps starts with one night.' : 'No stamps this month yet — a new place, a first taste or a dry night earns one.',
          ),
        ),
      ),
      const SizedBox(height: S.m),
      StampTally(stamps),
      if (yearView) ...[
        const SizedBox(height: S.m),
        _YearStrip(year: year, entries: entries),
      ],
      if (stamps.isEmpty && entries.isNotEmpty) ...[
        const SizedBox(height: S.s),
        Text('Try somewhere new or something you have never had — or keep a night dry.', style: T.caption(bd)),
      ],
    ]);
  }
}

/// Twelve little columns: how many stamps each month of the year added.
class _YearStrip extends StatelessWidget {
  final int year;
  final List<Entry> entries;
  const _YearStrip({required this.year, required this.entries});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final counts = [
      for (var m = 0; m < 12; m++)
        () {
          final (f, t) = monthRange(year, m);
          return stampsBetween(entries, f, t).length;
        }(),
    ];
    final top = counts.fold<int>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 54,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var m = 0; m < 12; m++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                AnimatedContainer(
                  duration: Motion.med,
                  height: counts[m] == 0 ? 3 : 4 + 30 * counts[m] / top,
                  decoration: BoxDecoration(color: counts[m] == 0 ? bd.line : bd.accent.withValues(alpha: .35 + .65 * counts[m] / top), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(height: 4),
                Text(monthNames[m].substring(0, 1), style: T.caption(bd).copyWith(fontSize: 10)),
              ]),
            ),
          ),
      ]),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < counters.length; i++) ...[
        if (i > 0) const SizedBox(height: S.s),
        _DayCounter(dateKey: dateKey, def: counters[i]),
      ],
    ]);
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
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.s, S.s, S.s),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(def.label, style: T.row(bd)),
            if (volume != null) Text(volume, style: T.caption(bd)),
          ]),
        ),
        IconBtn(Ph.minus, tooltip: 'One fewer ${def.unit}', glass: true, onTap: n == 0
            ? null
            : () {
                final last = mine.reduce((a, b) => a.createdAt.compareTo(b.createdAt) >= 0 ? a : b);
                entryStore.deleteEntry(last.id);
              }),
        SizedBox(
          width: 40,
          child: Text('$n', textAlign: TextAlign.center, style: T.sans(bd, size: 20, weight: FontWeight.w600).copyWith(fontFeatures: T.tnum)),
        ),
        IconBtn(Ph.plus, tooltip: 'One more ${def.unit}', glass: true, color: bd.accentText, onTap: () => entryStore.addEntry(date: dateKey, drink: def.entryDrink, type: def.entryType)),
      ]),
    );
  }
}
