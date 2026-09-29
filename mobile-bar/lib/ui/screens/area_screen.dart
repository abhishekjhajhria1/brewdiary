// The area — what consenting drinkers around this venue are into. Counts only, at least
// five different people behind every line, matched by a coarse (~40 km) cell that each
// person chose to share. Never a person, never "who's near you now", never demographics.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

class AreaPreview extends StatelessWidget {
  final Venue venue;
  final int days;
  const AreaPreview({super.key, required this.venue, required this.days});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (venue.geohash == null || venue.geohash!.isEmpty) {
      return const EmptyNote('Set your venue\'s location (More › Setup) to see what your area is into.');
    }
    return Loader<List<AreaTrend>>(
      load: () => Backend.i.areaTrends(venue.geohash!, days: days),
      deps: '${venue.geohash}-$days',
      retry: true,
      builder: (context, trends, loading) {
        if (trends == null) return const Skeleton(height: 120);
        if (trends.isEmpty) {
          return const EmptyNote('Not enough people nearby share their taste yet — a line appears once five or more do.');
        }
        final drinks = trends.where((t) => t.kind == 'drink').toList();
        final moods = trends.where((t) => t.kind == 'mood').toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Glass(
            padding: const EdgeInsets.all(S.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final t in drinks) _TrendLine(t, max: drinks.first.users),
              if (moods.isNotEmpty) ...[
                const SizedBox(height: S.m),
                Text('The mood: ${moods.map((m) => m.name).join(', ')}', style: T.caption(bd)),
              ],
            ]),
          ),
          const SizedBox(height: S.s),
          Text('What people who chose to share their taste log around here, last $days days. Five or more people behind every line; no names.', style: T.caption(bd)),
          const SizedBox(height: S.m),
          BdButton('Open the area', icon: Ph.mapTrifold, kind: BtnKind.secondary, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AreaScreen(venue: venue)))),
        ]);
      },
    );
  }
}

class _TrendLine extends StatelessWidget {
  final AreaTrend t;
  final int max;
  const _TrendLine(this.t, {required this.max});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 130, child: Text(t.name, style: T.sans(bd, size: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 8,
                width: c.maxWidth * (max == 0 ? 0 : t.users / max),
                decoration: BoxDecoration(color: bd.accent.withValues(alpha: .7), borderRadius: BorderRadius.circular(99)),
              ),
            );
          }),
        ),
        const SizedBox(width: S.s),
        Text('${t.users}', style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
      ]),
    );
  }
}

class AreaScreen extends StatefulWidget {
  final Venue venue;
  const AreaScreen({super.key, required this.venue});
  @override
  State<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends State<AreaScreen> {
  int _days = 30;
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Your area',
          back: true,
          tabBar: false,
          children: [
            Segmented<int>(options: const [(30, '30 days'), (90, '90 days')], value: _days, onChanged: (d) => setState(() => _days = d)),
            const SizedBox(height: S.m),
            AreaPreview(venue: widget.venue, days: _days),
            const SectionHeader('How this works'),
            Text(
              'People who switch on "share my taste" in their diary let brewdiary count what they log, grouped by a coarse area of about 40 km that they chose. '
              'You see a drink here only when at least five different people logged it — so no line can point at anyone. '
              'You never see who they are, where they are, or anything about one person.',
              style: T.bodyMuted(bd),
            ),
          ],
        ),
      ),
    );
  }
}
