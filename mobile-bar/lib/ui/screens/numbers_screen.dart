// Numbers — what a manager acts on, and a profile of nobody. Counts over this venue's
// own guests; any split under five people comes back hidden ("—", never 0); nothing
// about another venue; no list of who stopped coming. Then the area: what consenting
// drinkers nearby are into, five or more people behind every line.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/insights.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'area_screen.dart';
import 'ninkasi_screen.dart';

const weekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class NumbersScreen extends StatefulWidget {
  final Venue venue;
  const NumbersScreen({super.key, required this.venue});
  @override
  State<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends State<NumbersScreen> {
  int _days = 30;
  Venue get v => widget.venue;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return ScrollPage(
      title: 'Numbers',
      subtitle: v.name,
      onRefresh: () async => venueRev.bump(),
      children: [
        const DemoNote(),
        if (!v.kind.isCounter && s.can(Cap.liveBoard)) ...[
          LiveBoard(venue: v),
          const SectionHeader('Over time'),
        ],
        Segmented<int>(options: const [(7, '7 days'), (30, '30 days'), (90, '90 days')], value: _days, onChanged: (d) => setState(() => _days = d)),
        const SizedBox(height: S.m),
        Loader<VenueInsights?>(
          load: () => Backend.i.insights(v.id, days: _days),
          deps: _days,
          refresh: venueRev,
          retry: true,
          builder: (context, ins, loading) {
            if (ins == null) return loading ? const Skeleton(height: 260) : const EmptyNote('No numbers yet.');
            final read = readInsights(ins);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StatRow([
                StatTile('Guests', '${ins.guests}', hint: trendLine(ins.guests.toDouble(), ins.prevGuests.toDouble(), 'the ${_days}d before')),
                StatTile('New · returning', '${countOrHidden(ins.newGuests)} · ${countOrHidden(ins.returningGuests)}',
                    hint: read.returnRate == null ? 'hidden under 5 guests' : '${read.returnRate}% came back'),
                if (!v.kind.isCounter) StatTile('Tabs', '${ins.tabs}', hint: read.averageTab == null ? null : 'avg ${money(read.averageTab!, v.currency)}'),
                if (!v.kind.isCounter)
                  StatTile('Takings', money(ins.takings, v.currency), hint: trendLine(ins.takings, ins.prevTakings, 'the ${_days}d before')),
                StatTile('Rewards claimed', '${ins.perksClaimed}', hint: ins.perksEarned == null ? null : '${ins.perksEarned} guests have one waiting'),
                StatTile('Your team was thanked', '${ins.kudos}', hint: 'one number for the team — never a ranking'),
              ]),
              const SectionHeader('Visits by weekday'),
              WeekdayBars(visits: ins.visitsByDow, quietNights: v.quietNights),
              if (read.deadest != null)
                Padding(
                  padding: const EdgeInsets.only(top: S.s),
                  child: Text(
                    v.quietNights.contains(read.deadest)
                        ? '${weekdayShort[read.deadest!]} is your quietest and already a quiet night — a visit then counts double toward the card.'
                        : '${weekdayShort[read.deadest!]} is your quietest. Mark it a quiet night (More › Perks) and a visit then counts double toward the card.',
                    style: T.caption(bd),
                  ),
                ),
              if (!v.kind.isCounter && ins.tabs > 0 && read.averageTab == null)
                Padding(padding: const EdgeInsets.only(top: S.s), child: Text('An average over fewer than 5 tabs would point at one person, so it stays hidden.', style: T.caption(bd))),
              if (s.can(Cap.advisor)) ...[
                const SizedBox(height: S.xl),
                BdButton('Ask Ninkasi to read these', icon: Ph.sparkle, kind: BtnKind.accent, onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => NinkasiScreen(venue: v, insights: ins, days: _days)));
                }),
              ],
            ]);
          },
        ),
        if (s.can(Cap.areaInsights)) ...[
          const SectionHeader('Your area'),
          AreaPreview(venue: v, days: _days),
        ],
      ],
    );
  }
}

/// Seven bars, one per weekday. The busiest in amber; quiet nights marked with a word,
/// not only a colour.
class WeekdayBars extends StatelessWidget {
  final List<int> visits;
  final List<int> quietNights;
  const WeekdayBars({super.key, required this.visits, required this.quietNights});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final max = visits.fold<int>(0, (m, x) => x > m ? x : m);
    final peak = max == 0 ? -1 : visits.indexOf(max);
    return Semantics(
      label: 'Visits by weekday: ${[for (var i = 0; i < 7; i++) '${weekdayShort[i]} ${visits.length > i ? visits[i] : 0}'].join(', ')}',
      child: Glass(
        padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.m),
        child: SizedBox(
          height: 150,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${visits.length > i ? visits[i] : 0}', style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
                  const SizedBox(height: 4),
                  Container(
                    height: max == 0 ? 2 : 2 + 88 * (visits.length > i ? visits[i] : 0) / max,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: i == peak ? bd.accent : bd.ink.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(weekdayShort[i], style: T.label(bd, color: quietNights.contains(i) ? bd.tone(Tone.info) : null)),
                  SizedBox(height: 12, child: quietNights.contains(i) ? Text('quiet', style: T.sans(bd, size: 9.5, color: bd.tone(Tone.info))) : null),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Right now: open tabs, covers, today's sales and tips, how long the bar and kitchen
/// are taking, what's waiting, and how people paid (the staff's words). Business
/// numbers only — no guest, and no ranking of staff.
class LiveBoard extends StatelessWidget {
  final Venue venue;
  const LiveBoard({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<ServiceBoard>(
      load: () => Backend.i.serviceBoard(venue.id),
      refresh: floorRev,
      retry: true,
      builder: (context, b, loading) {
        if (b == null) return const Skeleton(height: 180);
        String mins(double? m) => m == null ? '—' : '${m.toStringAsFixed(m < 10 ? 1 : 0)}m';
        final methods = b.methods.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
        final paid = methods.fold<double>(0, (s, e) => s + e.value);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('RIGHT NOW', style: T.label(bd)),
            const Spacer(),
            if (b.requests + b.calls > 0) ToneTag('${b.requests + b.calls} asking', Tone.late),
          ]),
          const SizedBox(height: S.s),
          StatRow([
            StatTile('Open tabs', '${b.openTabs}', hint: '${b.covers} guests seated'),
            StatTile('Sales today', money(b.sales, venue.currency), hint: '${b.bills} bills · tips ${money(b.tips, venue.currency)}'),
            StatTile('Bar', '${b.barWaiting} waiting', hint: 'avg ${mins(b.barMinutes)} to ready'),
            StatTile('Kitchen', '${b.kitchenWaiting} waiting', hint: 'avg ${mins(b.kitchenMinutes)} to ready'),
            StatTile('Waitlist', '${b.waiting}', hint: b.voids == 0 ? 'no voids today' : '${b.voids} ${b.voids == 1 ? 'void' : 'voids'} today'),
          ]),
          if (methods.isNotEmpty) ...[
            const SizedBox(height: S.m),
            Glass(
              padding: const EdgeInsets.all(S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('How people paid today', style: T.label(bd)),
                const SizedBox(height: S.s),
                for (final e in methods)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 70, child: Text(e.key.toUpperCase().length <= 4 ? e.key.toUpperCase() : e.key, style: T.sans(bd, size: 14))),
                      Expanded(
                        child: LayoutBuilder(builder: (context, c) => Align(
                              alignment: Alignment.centerLeft,
                              child: Container(height: 8, width: c.maxWidth * (paid == 0 ? 0 : e.value / paid), decoration: BoxDecoration(color: bd.accent.withValues(alpha: .7), borderRadius: BorderRadius.circular(99))),
                            )),
                      ),
                      const SizedBox(width: S.s),
                      Text(money(e.value, venue.currency), style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
                    ]),
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}
