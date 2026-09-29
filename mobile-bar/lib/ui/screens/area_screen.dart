// The area — "the kind of people outside", answered with consent. Two reads:
//
//   • the HEAT MAP (048): the ~40 km around the venue as 32 neighbourhoods of ~5 km.
//     A neighbourhood lights up only with 5+ people who said yes to neighbourhood
//     maps, across 3+ venues; every figure is rounded down to 5s. Layers: how many,
//     what kinds of people (taste personas), what they like, when they come out, and
//     — for venues that share their own totals — a typical night's spend as a band.
//   • the TRENDS (041): what people who share their taste log across the whole area.
//
// Never a person, never "who's near you now", never age, gender or anything like it.
// Phones stack it; tablets put the guide beside the map.
import 'package:brewdiary_core/geo.dart';
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import '../../logic/area.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'setup_screen.dart';

// ── the trends (Numbers tab + the bottom of the area screen) ─────────────────
class AreaPreview extends StatelessWidget {
  final Venue venue;
  final int days;
  final bool openButton;
  const AreaPreview({super.key, required this.venue, required this.days, this.openButton = true});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (venue.geohash == null || venue.geohash!.isEmpty) {
      return const EmptyNote('Set your venue\'s location (More › Setup) to see what your area is into.');
    }
    final open = BdButton('Open the area map', icon: Ph.mapTrifold, kind: BtnKind.secondary, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AreaScreen(venue: venue))));
    return Loader<List<AreaTrend>>(
      load: () => Backend.i.areaTrends(venue.geohash!, days: days),
      deps: '${venue.geohash}-$days',
      retry: true,
      builder: (context, trends, loading) {
        if (trends == null) return const Skeleton(height: 120);
        if (trends.isEmpty) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const EmptyNote('Not enough people nearby share their taste yet — a line appears once five or more do.'),
            if (openButton) ...[const SizedBox(height: S.m), open],
          ]);
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
          Text('What people who chose to share their taste log across your ~40 km area, last $days days. Five or more people behind every line; no names.', style: T.caption(bd)),
          if (openButton) ...[const SizedBox(height: S.m), open],
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

// ── the map ───────────────────────────────────────────────────────────────────
enum HeatLayer { people, persona, taste, hours, spend }

const _layerLabel = {
  HeatLayer.people: 'How many',
  HeatLayer.persona: 'Kinds of people',
  HeatLayer.taste: 'What they like',
  HeatLayer.hours: 'When',
  HeatLayer.spend: 'Spend',
};

class AreaScreen extends StatefulWidget {
  final Venue venue;
  const AreaScreen({super.key, required this.venue});
  @override
  State<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends State<AreaScreen> {
  int _days = 30;
  HeatLayer _layer = HeatLayer.people;
  String? _pick; // the persona / taste / hour band the map glows by

  Venue get v => Session.instance.venue?.id == widget.venue.id ? Session.instance.venue! : widget.venue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Ambient(
        child: ListenableBuilder(
          listenable: Session.instance,
          builder: (context, _) => ScrollPage(
            title: 'Your area',
            back: true,
            tabBar: false,
            maxWidth: kWideMaxWidth,
            children: [
              Segmented<int>(options: const [(7, '7 days'), (30, '30 days'), (90, '90 days')], value: _days, onChanged: (d) => setState(() => _days = d)),
              const SizedBox(height: S.l),
              _body(context),
              const SectionHeader('What the whole area drinks'),
              AreaPreview(venue: v, days: _days, openButton: false),
              const SectionHeader('How this works'),
              Text(
                'Guests who say yes to "neighbourhood maps" in their diary are counted where they go out — the venue rooms they join. '
                'A neighbourhood shows only with 5 or more of them across 3 or more venues, and every number is rounded down to 5s, so nothing on this map can point at a person or at one venue\'s night. '
                'The kinds of people are what they like to drink — never age, gender or anything like it. Spend is a band, shared only between venues that share their own.',
                style: T.bodyMuted(context.bd),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final venue = v;
    final gh = venue.geohash ?? '';
    if (!venue.verified) {
      return const EmptyNote('The area map opens once your venue is verified — so nobody can open a pretend venue to look at an area.');
    }
    if (gh.length < 5) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const EmptyNote('Set your venue\'s location to open the map — stand in the venue and tap once. We keep a ~1 km cell; your address is public anyway.'),
        if (Session.instance.can(Cap.editSettings)) ...[
          const SizedBox(height: S.m),
          BdButton('Set location', icon: Ph.crosshair, kind: BtnKind.secondary, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupScreen(venue: venue)))),
        ],
      ]);
    }
    return Loader<List<HeatRow>>(
      load: () => Backend.i.areaMap(venue.id, days: _days, tz: venueTimeZone(venue.country, venue.region)),
      deps: '${venue.id}-$_days-${venue.areaShare}-$gh',
      retry: true,
      builder: (context, rows, loading) {
        if (rows == null) return const Skeleton(height: 260);
        final cells = readMap(rows);
        final guide = areaGuide(venueCell: gh, cells: cells, currency: venue.currency, sellsAlcohol: venue.sellsAlcohol, sharing: venue.areaShare);
        final map = _map(context, venue, cells);
        final said = _guide(context, guide);
        return LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 840) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: map),
              const SizedBox(width: S.xl),
              Expanded(flex: 2, child: said),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [map, said]);
        });
      },
    );
  }

  /// The labels a layer can glow by, most common first.
  List<String> _options(Map<String, CellRead> cells) {
    final totals = <String, int>{};
    for (final c in cells.values) {
      final m = switch (_layer) { HeatLayer.persona => c.personas, HeatLayer.taste => c.tastes, HeatLayer.hours => c.hours, _ => const <String, int>{} };
      m.forEach((k, n) => totals[k] = (totals[k] ?? 0) + n);
    }
    final order = switch (_layer) { HeatLayer.persona => personaOrder, HeatLayer.taste => tasteOrder, HeatLayer.hours => hoursOrder, _ => const <String>[] };
    final keys = totals.keys.toList()..sort((a, b) => totals[b] != totals[a] ? totals[b]! - totals[a]! : order.indexOf(a) - order.indexOf(b));
    return _layer == HeatLayer.hours ? (keys..sort((a, b) => order.indexOf(a) - order.indexOf(b))) : keys;
  }

  String _optionLabel(String k) => switch (_layer) {
        HeatLayer.persona => personaLabel[k] ?? k,
        HeatLayer.taste => tasteLabel[k] ?? k,
        HeatLayer.hours => hoursLabel[k] ?? k,
        _ => k,
      };

  Widget _map(BuildContext context, Venue venue, Map<String, CellRead> cells) {
    final bd = context.bd;
    final options = _options(cells);
    final pick = options.contains(_pick) ? _pick : (options.isEmpty ? null : options.first);
    num? value(CellRead? c) {
      if (c == null) return null;
      return switch (_layer) {
        HeatLayer.people => c.people,
        HeatLayer.persona => c.personas[pick],
        HeatLayer.taste => c.tastes[pick],
        HeatLayer.hours => c.hours[pick],
        HeatLayer.spend => c.spendFloor,
      };
    }

    String text(num n) => _layer == HeatLayer.spend ? spendWords(n, venue.currency).replaceFirst('under ', '<') : '$n+';
    final grid = subcells(venue.geohash!);
    final values = {for (final g in grid) g.cell: value(cells[g.cell])};
    final spendLocked = _layer == HeatLayer.spend && !venue.areaShare;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final l in HeatLayer.values)
            Padding(padding: const EdgeInsets.only(right: S.s), child: BdChip(_layerLabel[l]!, active: _layer == l, onTap: () => setState(() {
                  _layer = l;
                  _pick = null;
                }))),
        ]),
      ),
      if (options.isNotEmpty) ...[
        const SizedBox(height: S.s),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final o in options)
              Padding(padding: const EdgeInsets.only(right: S.s), child: BdChip(_optionLabel(o), active: o == pick, onTap: () => setState(() => _pick = o))),
          ]),
        ),
      ],
      const SizedBox(height: S.m),
      if (spendLocked)
        _ShareCard(venue: venue)
      else ...[
        HeatGrid(
          cells: grid,
          values: values,
          mine: venue.geohash!.substring(0, 5),
          text: text,
          onTap: (cell) => _cellSheet(context, venue, cell, cells[cell]),
        ),
        const SizedBox(height: S.s),
        Text(
          switch (_layer) {
            HeatLayer.spend => 'A typical night\'s tab, as a band. Outlined: your neighbourhood. Blank: not enough to show.',
            HeatLayer.people => 'Brighter = more people who said yes. Outlined: your neighbourhood. Blank: fewer than 5 people or 3 venues.',
            _ => 'Brighter = more of them (people, in 5s). Tap a square for the whole picture.',
          },
          style: T.caption(bd),
        ),
      ],
    ]);
  }

  Widget _guide(BuildContext context, List<String> lines) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('What it says'),
      Glass(
        padding: const EdgeInsets.all(S.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 7, right: S.m), child: Container(width: 5, height: 5, decoration: BoxDecoration(color: bd.accent, shape: BoxShape.circle))),
                Expanded(child: Text(l, style: T.sans(bd, size: 14.5, height: 1.45))),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _cellSheet(BuildContext context, Venue venue, String cell, CellRead? c) async {
    final where = directionFrom(venue.geohash!, cell);
    await showBdSheet<void>(context, title: where[0].toUpperCase() + where.substring(1), builder: (ctx) {
      final bd = ctx.bd;
      if (c == null) {
        return Text('Not enough to show here: fewer than 5 people who said yes, or fewer than 3 venues. That keeps a quiet street from pointing at anyone.', style: T.bodyMuted(bd));
      }
      Widget list(String title, Map<String, int> m, Map<String, String> labels, List<String> order) {
        if (m.isEmpty) return const SizedBox.shrink();
        final keys = m.keys.toList()..sort((a, b) => m[b] != m[a] ? m[b]! - m[a]! : order.indexOf(a) - order.indexOf(b));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title),
          Group(children: [for (final k in keys) GroupTile(title: labels[k] ?? k, trailing: Text(crowd(m[k]!), style: T.caption(bd).copyWith(fontFeatures: T.tnum)))]),
        ]);
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        StatRow([
          StatTile('People', '${c.people}+'),
          if (c.spendFloor != null) StatTile('Typical tab', spendWords(c.spendFloor!, venue.currency)),
        ]),
        list('Kinds of people', c.personas, personaLabel, personaOrder),
        list('What they like', c.tastes, tasteLabel, tasteOrder),
        list('When they come out', c.hours, {for (final k in hoursOrder) k: '${hoursLabel[k]} (${hoursSpan[k]})'}, hoursOrder),
        const SizedBox(height: S.m),
        Text('Groups of 5+ people who said yes; rounded down to 5s. No names, no venues.', style: T.caption(bd)),
      ]);
    });
  }
}

/// Spend is give-to-get: a venue sees the area's spend only if it shares its own.
class _ShareCard extends StatelessWidget {
  final Venue venue;
  const _ShareCard({required this.venue});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final can = Session.instance.can(Cap.editSettings);
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Spend is shared between venues that share', style: T.sans(bd, size: 16, weight: FontWeight.w600)),
        const SizedBox(height: S.s),
        Text(
          'Share your own totals — counts and bands only, from guests who said yes, in groups of 5+ across 3+ venues — and you\'ll see the typical night\'s tab around you. No venue\'s figures are ever shown, yours included.',
          style: T.bodyMuted(bd),
        ),
        const SizedBox(height: S.l),
        if (can)
          BdButton('Share and see spend', icon: Ph.wallet, onTap: () => runAction(context, () => Backend.i.updateVenue(venue.id, areaShare: true), done: 'Sharing — spend shows once 3 venues around you share.'))
        else
          Text('An owner or manager can switch this on in Setup.', style: T.caption(bd)),
      ]),
    );
  }
}

/// 8 × 4 neighbourhoods, north at the top, glowing amber by value. Colour is never
/// the only signal: each lit square carries its figure, and screen readers read all.
class HeatGrid extends StatelessWidget {
  final List<GridCell> cells;
  final Map<String, num?> values;
  final String mine;
  final String Function(num) text;
  final ValueChanged<String> onTap;
  const HeatGrid({super.key, required this.cells, required this.values, required this.mine, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final lit = values.values.whereType<num>().toList();
    final max = lit.isEmpty ? 0 : lit.reduce((a, b) => a > b ? a : b);
    return Glass(
      padding: const EdgeInsets.all(S.s),
      child: AspectRatio(
        aspectRatio: 2,
        child: LayoutBuilder(builder: (context, box) {
          final showText = box.maxWidth / 8 >= 34;
          return Column(children: [
            for (var row = 0; row < 4; row++)
              Expanded(
                child: Row(children: [
                  for (final g in cells.where((g) => g.row == row))
                    Expanded(child: _square(context, bd, g.cell, values[g.cell], max, showText)),
                ]),
              ),
          ]);
        }),
      ),
    );
  }

  Widget _square(BuildContext context, BD bd, String cell, num? v, num max, bool showText) {
    final isMine = cell == mine;
    final h = v == null || max <= 0 ? null : (v <= 0 ? .08 : v / max);
    final fill = h == null ? bd.ink.withValues(alpha: .05) : bd.accent.withValues(alpha: .14 + .76 * h);
    final onFill = h != null && h > .55 ? bd.accentContrast : bd.ink;
    return Semantics(
      button: true,
      label: '${isMine ? 'Your neighbourhood' : directionFrom(mine, cell)}: ${v == null ? 'not enough to show' : text(v)}',
      child: GestureDetector(
        onTap: () => onTap(cell),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(6),
            border: isMine ? Border.all(color: bd.ink, width: 2) : null,
          ),
          alignment: Alignment.center,
          child: showText && v != null
              ? FittedBox(child: Padding(padding: const EdgeInsets.all(2), child: Text(text(v), style: T.sans(bd, size: 11, weight: FontWeight.w600, color: onFill).copyWith(fontFeatures: T.tnum))))
              : null,
        ),
      ),
    );
  }
}
