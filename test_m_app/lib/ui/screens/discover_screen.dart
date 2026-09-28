// Discover — a port of src/app/discover/page.tsx and components/discover/*. A real
// compass, "find places near me" (hands your maps app a query — no Places API bill),
// the verified venues on brewdiary (a LISTING, never an offer), and anonymous taste
// trends: your area first, then everywhere. Nothing here is paid for.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/misc.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/safety.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'bartender_screen.dart';

class DiscoverScreen extends StatelessWidget {
  /// Off in widget tests, where the sensor plugin doesn't exist.
  static bool sensors = true;
  const DiscoverScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SubPage(
      title: 'Discover',
      subtitle: 'Point the compass, find a place near you, ask Ninkasi.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Glass(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BartenderPage())),
          semanticLabel: 'Ask Ninkasi',
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
                Text('Ask Ninkasi', style: T.row(bd)),
                const SizedBox(height: 2),
                Text("What should I pour tonight? She knows what you've been logging.", style: T.caption(bd)),
              ]),
            ),
            Icon(Ph.caretRight, size: 16, color: bd.faint),
          ]),
        ),
        const SectionHeader('Near you'),
        const _DiscoverLive(),
        const _VenuesNearby(),
        if (auth.isAuthed && db != null) ...[const _NearbyTrends(), const _Trends()],
        const SizedBox(height: S.x3),
        Text(
          'Nothing here is paid for, and no bar can pay to appear. Location is opt-in and never leaves your device — the compass and “near me” search hand your maps app a query, nothing more.',
          style: T.caption(bd),
        ),
      ]),
    );
  }
}

const _categories = [
  ('Cocktail bars', 'cocktail bar'),
  ('Bars & pubs', 'bar pub'),
  ('Bottle shops', 'liquor store bottle shop'),
  ('Clubs', 'night club'),
  ('Cafés', 'coffee cafe'),
  ('Wine bars', 'wine bar'),
];

class _DiscoverLive extends StatefulWidget {
  const _DiscoverLive();
  @override
  State<_DiscoverLive> createState() => _DiscoverLiveState();
}

class _DiscoverLiveState extends State<_DiscoverLive> {
  double? _heading;
  StreamSubscription<MagnetometerEvent>? _mag;
  Position? _pos;
  String _geo = 'idle'; // idle | loading | denied | ok

  @override
  void initState() {
    super.initState();
    if (!DiscoverScreen.sensors) return;
    try {
      _mag = magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        // Phone held flat: heading from the horizontal field components.
        var h = math.atan2(e.y, e.x) * 180 / math.pi;
        h = (90 - h + 360) % 360;
        if (mounted) setState(() => _heading = h);
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _mag?.cancel();
    super.dispose();
  }

  Future<void> _enable() async {
    setState(() => _geo = 'loading');
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _geo = 'denied');
        return;
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      setState(() {
        _pos = p;
        _geo = 'ok';
      });
    } catch (_) {
      setState(() => _geo = 'denied');
    }
  }

  Uri _near(String q) => _pos != null
      ? Uri.parse('https://www.google.com/maps/search/${Uri.encodeComponent(q)}/@${_pos!.latitude},${_pos!.longitude},15z')
      : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}');

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final has = _heading != null;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.xxl, S.l, S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Semantics(
            label: has ? 'Compass: facing ${_heading!.round()} degrees' : 'Compass',
            excludeSemantics: true,
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(color: bd.ink.withValues(alpha: .04), shape: BoxShape.circle, border: Border.all(color: bd.glassBorder, width: .8)),
              child: Stack(alignment: Alignment.center, children: [
                AnimatedRotation(
                  turns: has ? -_heading! / 360 : 0,
                  duration: Motion.fast,
                  child: SizedBox.expand(
                    child: Stack(children: [
                      Align(alignment: const Alignment(0, -.82), child: Text('N', style: T.sans(bd, size: 13, weight: FontWeight.w700, color: bd.accentText))),
                      Align(alignment: const Alignment(0, .82), child: Text('S', style: T.sans(bd, size: 12, weight: FontWeight.w600, color: bd.faint))),
                      Align(alignment: const Alignment(-.82, 0), child: Text('W', style: T.sans(bd, size: 12, weight: FontWeight.w600, color: bd.faint))),
                      Align(alignment: const Alignment(.82, 0), child: Text('E', style: T.sans(bd, size: 12, weight: FontWeight.w600, color: bd.faint))),
                    ]),
                  ),
                ),
                CustomPaint(size: const Size(14, 104), painter: _NeedlePainter(bd)),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: bd.ink, shape: BoxShape.circle)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: S.m),
        Text(has ? 'Facing ${_heading!.round()}°' : 'Hold your phone flat to use the compass', textAlign: TextAlign.center, style: has ? T.serif(bd, size: 24) : T.caption(bd)),
        const SizedBox(height: S.xl),
        if (_geo == 'ok')
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(PhFill.mapPin, size: 16, color: bd.accentText),
            const SizedBox(width: 6),
            Text('Searching near you', style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.accentText)),
          ])
        else
          BdButton(_geo == 'loading' ? 'Locating…' : 'Find places near me', kind: BtnKind.secondary, icon: Ph.navigationArrow, busy: _geo == 'loading', onTap: _enable),
        if (_geo == 'denied')
          Padding(
            padding: const EdgeInsets.only(top: S.s),
            child: Text('Location is off — the places below still open your maps app; allow location for closer results.', textAlign: TextAlign.center, style: T.caption(bd)),
          ),
        const SizedBox(height: S.m),
        Wrap(alignment: WrapAlignment.center, spacing: S.s, children: [
          for (final c in _categories) BdChip(c.$1, icon: Ph.arrowUpRight, onTap: () => launchUrl(_near(c.$2), mode: LaunchMode.externalApplication)),
        ]),
      ]),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  final BD bd;
  _NeedlePainter(this.bd);
  @override
  void paint(Canvas canvas, Size s) {
    final up = Path()
      ..moveTo(7, 4)
      ..lineTo(12, 54)
      ..lineTo(7, 46)
      ..lineTo(2, 54)
      ..close();
    final down = Path()
      ..moveTo(7, 100)
      ..lineTo(12, 50)
      ..lineTo(7, 58)
      ..lineTo(2, 50)
      ..close();
    canvas.drawPath(up, Paint()..color = bd.accent);
    canvas.drawPath(down, Paint()..color = bd.lineStrong);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.bd != bd;
}

/// Bars that are actually ON brewdiary — a name, a city, whether a room is running.
/// Never the perk, the reward, a price or a discount: that line is the law in India
/// and much of the world, and the database backs it up.
class _VenuesNearby extends StatelessWidget {
  const _VenuesNearby();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<DiscoverVenue>>(
      load: () => DiscoverApi.venues(PlaceStore.instance.country),
      builder: (context, venues, loading) {
        if (venues == null || venues.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('On brewdiary'),
          Group(
            footer: 'Verified bars using brewdiary. If one is running a room, you can join it when you get there — ask for the code or scan the card on the table.',
            children: [
              for (final v in venues)
                GroupTile(
                  icon: v.isStore ? Ph.storefront : Ph.beerStein,
                  title: v.name,
                  subtitle: '${v.isStore ? 'Bottle shop${v.city != null ? ' · ${v.city}' : ''}' : (v.city ?? 'A brewdiary venue')}${v.openTonight ? ' · a room is open' : ''}',
                  trailing: IconBtn(
                    Ph.navigationArrow,
                    tooltip: 'Directions to ${v.name}',
                    color: bd.muted,
                    onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${v.name} ${v.city ?? ''}'.trim())}'), mode: LaunchMode.externalApplication),
                  ),
                ),
            ],
          ),
        ]);
      },
    );
  }
}

Widget _trendList(BD bd, List<Trend> trends, {required String unit, required String moodLead, required String foot}) {
  final drinks = trends.where((t) => t.kind == 'drink').toList();
  final moods = trends.where((t) => t.kind == 'mood').toList();
  String people(int n) => '$n ${n == 1 ? unit : (unit == 'person' ? 'people' : '${unit}s')}';
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Group(children: [
      for (final t in drinks) GroupTile(title: t.name, trailing: Text('${people(t.users)} · ${t.logs} pours', style: T.caption(bd))),
    ]),
    if (moods.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: S.m, left: S.xs),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$moodLead ', style: T.body(bd, color: bd.muted)),
          for (var i = 0; i < moods.length; i++) ...[
            if (i > 0) TextSpan(text: ' · ', style: T.body(bd, color: bd.faint)),
            TextSpan(text: moods[i].name, style: T.body(bd, color: bd.muted).copyWith(fontStyle: FontStyle.italic)),
          ],
        ])),
      ),
    Padding(padding: const EdgeInsets.fromLTRB(S.xs, S.s, S.xs, 0), child: Text(foot, style: T.caption(bd))),
  ]);
}

class _NearbyTrends extends StatefulWidget {
  const _NearbyTrends();
  @override
  State<_NearbyTrends> createState() => _NearbyTrendsState();
}

class _NearbyTrendsState extends State<_NearbyTrends> {
  bool _busy = false;
  String? _msg;

  /// Reduce a one-time position to a coarse cell ON DEVICE — raw coordinates never leave.
  Future<void> _optIn() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() {
          _busy = false;
          _msg = 'Location permission was declined — no worries, it stays off.';
        });
        return;
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)));
      await ProfileApi.setShareTrends(true);
      await ProfileApi.setTrendsGeo(encodeGeohash(p.latitude, p.longitude));
    } catch (_) {
      setState(() => _msg = "Couldn't read a location just now. Try again.");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<(ProfileSettings, List<Trend>)>(
      refresh: profileRev,
      load: () async {
        final s = await ProfileApi.settings();
        final t = s.trendsGeo == null ? <Trend>[] : await DiscoverApi.areaTrends(s.trendsGeo!);
        return (s, t);
      },
      builder: (context, data, loading) {
        if (data == null) return const SizedBox.shrink();
        final hasArea = data.$1.trendsGeo != null;
        final drinks = data.$2.where((t) => t.kind == 'drink').toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader('Pouring near you', trailing: Text('Last 30 days', style: T.caption(bd))),
          if (!hasArea)
            Glass(
              padding: const EdgeInsets.all(S.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('See what your neighbourhood is drinking.', style: T.row(bd)),
                const SizedBox(height: S.s),
                Text(
                  "Set your area from your location — a rough ~40 km cell, never your exact spot — and you'll see the local taste. It also turns on anonymous trends (counts only, never your name or notes).",
                  style: T.body(bd, color: bd.muted),
                ),
                const SizedBox(height: S.l),
                BdButton(_busy ? 'Locating…' : 'Set my area', kind: BtnKind.secondary, icon: Ph.mapPin, busy: _busy, onTap: _optIn),
                if (_msg != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(_msg!, style: T.sans(bd, size: 14, color: bd.accentText))),
              ]),
            )
          else if (drinks.isEmpty)
            const EmptyNote('Quiet in your area so far — local trends appear once at least five people near you have opted in.')
          else
            _trendList(bd, data.$2, unit: 'person', moodLead: 'The mood nearby:', foot: 'Anonymous counts from people near you who opted in — a rough area, never an exact spot, never who.'),
        ]);
      },
    );
  }
}

class _Trends extends StatelessWidget {
  const _Trends();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<Trend>>(
      load: DiscoverApi.tasteTrends,
      builder: (context, trends, loading) {
        final drinks = (trends ?? const <Trend>[]).where((t) => t.kind == 'drink').toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader("What's pouring", trailing: Text('Last two weeks', style: T.caption(bd))),
          if (trends == null)
            const Skeleton(height: 120)
          else if (drinks.isEmpty)
            const EmptyNote('Quiet so far — trends appear once enough guests opt in (You → Settings → anonymous taste trends).')
          else
            _trendList(bd, trends, unit: 'guest', moodLead: 'The mood around the bar:', foot: 'Anonymous counts from guests who opted in — never who poured what.'),
        ]);
      },
    );
  }
}
