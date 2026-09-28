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
import '../widgets/sub_page.dart';
import 'bartender_screen.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SubPage(
      title: 'discover',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Discover', style: T.serif(bd, size: 54, height: .92)),
        const SizedBox(height: 8),
        Text('Point the compass, find a place near you, ask Ninkasi.', style: T.sans(bd, color: bd.muted)),
        const SizedBox(height: 24),
        Glass(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubPage(title: 'ninkasi', scroll: false, child: BartenderScreen(inShell: false)))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ask Ninkasi', style: T.serif(bd, size: 20)),
                Text("What should I pour tonight? — she knows what you've been logging.", style: T.sans(bd, size: 14, color: bd.muted)),
              ]),
            ),
            Text('→', style: T.sans(bd, color: bd.accent)),
          ]),
        ),
        const SizedBox(height: 24),
        const _DiscoverLive(),
        const _VenuesNearby(),
        if (auth.isAuthed && db != null) ...[const _NearbyTrends(), const _Trends()],
        const SizedBox(height: 32),
        Text(
          'Nothing here is paid for, and no bar can pay to appear. Location is opt-in and never leaves your device — the compass and “near me” search hand your maps app a query, nothing more.',
          style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
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
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(children: [
        Container(
          width: 144,
          height: 144,
          decoration: BoxDecoration(color: bd.glass, shape: BoxShape.circle, border: Border.all(color: bd.glassBorder)),
          child: Stack(alignment: Alignment.center, children: [
            AnimatedRotation(
              turns: has ? -_heading! / 360 : 0,
              duration: const Duration(milliseconds: 150),
              child: SizedBox.expand(
                child: Stack(children: [
                  Align(alignment: const Alignment(0, -.85), child: Label('N', color: bd.accent)),
                  const Align(alignment: Alignment(0, .85), child: Label('S')),
                  const Align(alignment: Alignment(-.85, 0), child: Label('W')),
                  const Align(alignment: Alignment(.85, 0), child: Label('E')),
                ]),
              ),
            ),
            CustomPaint(size: const Size(14, 104), painter: _NeedlePainter(bd)),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: bd.ink, shape: BoxShape.circle)),
          ]),
        ),
        const SizedBox(height: 20),
        Label(has ? 'facing' : 'compass'),
        Text(has ? '${_heading!.round()}°' : '—', style: T.serif(bd, size: 26)),
        const SizedBox(height: 20),
        if (_geo != 'ok')
          Glass(radius: rCtl, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), onTap: _enable, child: Text(_geo == 'loading' ? 'Locating…' : 'Find places near me', style: T.sans(bd, size: 14)))
        else
          Label('near you', color: bd.faint),
        if (_geo == 'denied')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Location is off — the links below still open your maps app; allow location for closer results.', textAlign: TextAlign.center, style: T.sans(bd, size: 12, color: bd.faint)),
          ),
        const SizedBox(height: 20),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final c in _categories)
            Glass(
              radius: rCtl,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              onTap: () => launchUrl(_near(c.$2), mode: LaunchMode.externalApplication),
              child: Text(c.$1, style: T.sans(bd, size: 14, color: bd.muted)),
            ),
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
        return Padding(
          padding: const EdgeInsets.only(top: 36),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label('On brewdiary', color: bd.faint),
            const SizedBox(height: 12),
            for (final v in venues)
              Glass(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v.name, overflow: TextOverflow.ellipsis, style: T.sans(bd)),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: v.isStore ? 'Bottle shop${v.city != null ? ' · ${v.city}' : ''}' : (v.city ?? 'A brewdiary venue'), style: T.sans(bd, size: 12, color: bd.muted)),
                        if (v.openTonight) TextSpan(text: ' · a room is open', style: T.sans(bd, size: 12, color: bd.accent)),
                      ])),
                    ]),
                  ),
                  Glass(
                    radius: rCtl,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    onTap: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${v.name} ${v.city ?? ''}'.trim())}'), mode: LaunchMode.externalApplication),
                    child: Text('DIRECTIONS', style: T.sans(bd, size: 11, spacing: 1.3, color: bd.muted)),
                  ),
                ]),
              ),
            Text('Verified bars using brewdiary. If one is running a room, you can join it when you get there — ask for the code or scan the card on the table.',
                style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
          ]),
        );
      },
    );
  }
}

Widget _trendList(BD bd, List<Trend> trends, {required String unit, required String moodLead, required String foot}) {
  final drinks = trends.where((t) => t.kind == 'drink').toList();
  final moods = trends.where((t) => t.kind == 'mood').toList();
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Hairlines(children: [
      for (final t in drinks)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(child: Text(t.name, style: T.sans(bd))),
            Text('${t.users} ${t.users == 1 ? unit : (unit == 'person' ? 'people' : '${unit}s')} · ${t.logs} pours', style: T.sans(bd, size: 12, color: bd.faint)),
          ]),
        ),
    ]),
    if (moods.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$moodLead ', style: T.sans(bd, size: 14, color: bd.muted)),
          for (var i = 0; i < moods.length; i++) ...[
            if (i > 0) TextSpan(text: ' · ', style: T.sans(bd, size: 14, color: bd.faint)),
            TextSpan(text: moods[i].name, style: T.sans(bd, size: 14, color: bd.muted).copyWith(fontStyle: FontStyle.italic)),
          ],
        ])),
      ),
    const SizedBox(height: 12),
    Text(foot, style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
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
        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label('Near you · last 30 days', color: bd.faint),
            const SizedBox(height: 12),
            if (!hasArea)
              Glass(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('See what your neighbourhood is drinking.', style: T.sans(bd)),
                  const SizedBox(height: 6),
                  Text(
                    "Set your area from your location — a rough ~40 km cell, never your exact spot — and you'll see the local taste. It also turns on anonymous trends (counts only, never your name or notes).",
                    style: T.sans(bd, size: 14, color: bd.muted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: 150, child: InkButton(_busy ? 'Locating…' : 'Set my area', height: 40, uppercase: false, busy: _busy, onTap: _optIn)),
                  if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: T.sans(bd, size: 12, color: bd.accent))),
                ]),
              )
            else if (drinks.isEmpty)
              Text('Quiet in your area so far — local trends appear once at least five people near you have opted in.', style: T.sans(bd, size: 14, color: bd.faint, height: 1.5))
            else
              _trendList(bd, data.$2, unit: 'person', moodLead: 'The mood nearby:', foot: 'Anonymous counts from people near you who opted in — a rough area, never an exact spot, never who.'),
          ]),
        );
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
        return Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Label("What's pouring · last two weeks", color: bd.faint),
            const SizedBox(height: 12),
            if (trends == null)
              const Skeleton(height: 64)
            else if (drinks.isEmpty)
              Text('Quiet so far — trends appear once enough guests opt in (You → Settings → anonymous taste trends).', style: T.sans(bd, size: 14, color: bd.faint, height: 1.5))
            else
              _trendList(bd, trends, unit: 'guest', moodLead: 'The mood around the bar:', foot: 'Anonymous counts from guests who opted in — never who poured what.'),
          ]),
        );
      },
    );
  }
}
