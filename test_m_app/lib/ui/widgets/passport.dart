// The taste passport, drawn: rubber stamps in four inks, visa pages on guilloché
// paper, the leather cover and the identity page with its machine-readable strip.
// Used by the full passport (screens/taste_card.dart) and by the calendar's
// month and year cards.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../theme.dart';

// ── inks and paper ──────────────────────────────────────────────────────────
class PassportInk {
  static const paper = Color(0xFFF4EEE2);
  static const paperEdge = Color(0xFFE6DCC8);
  static const ink = Color(0xFF231C18);
  static const soft = Color(0xFF7A6E62);
  static const guilloche = Color(0x1FB8742A);
  static const place = Color(0xFFB0632A); // amber-brown
  static const taste = Color(0xFFA03A2C); // stamp red
  static const kind = Color(0xFF2E6467); // deep teal
  static const dry = Color(0xFF34466B); // night blue
  static const leather = Color(0xFF3A1D22);
  static const leatherDeep = Color(0xFF1F1013);
  static const gold = Color(0xFFE2B262);

  static Color of(StampKind k) => switch (k) {
        StampKind.place => place,
        StampKind.firstTaste => taste,
        StampKind.newKind => kind,
        StampKind.dry => dry,
      };
}

const kindWords = {
  'cocktail': 'Cocktails',
  'beer': 'Beer',
  'wine': 'Wine',
  'spirit': 'Spirits',
  'coffee': 'Coffee',
  'tea': 'Tea',
  'soft': 'Soft drinks',
  'other': 'Something else',
};

String _shortDate(String key) {
  final d = parseKey(key);
  return '${d.day.toString().padLeft(2, '0')} ${monthNames[d.month - 1].substring(0, 3).toUpperCase()} ${(d.year % 100).toString().padLeft(2, '0')}';
}

TextStyle _sans(double size, Color color, {FontWeight weight = FontWeight.w700, double spacing = 1}) =>
    TextStyle(fontFamily: T.sansFamily, fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing, height: 1.1);
TextStyle _serif(double size, Color color, {bool italic = false, double height = 1.1}) =>
    TextStyle(fontFamily: T.serifFamily, fontSize: size, color: color, fontStyle: italic ? FontStyle.italic : FontStyle.normal, height: height);

// ── one rubber stamp ────────────────────────────────────────────────────────
/// A stamp, shaped by what it's for: a round entry stamp for a place, a framed
/// one for a first taste, an octagon for a new kind, a small round one for a dry
/// night. Tilt comes from the label, so the same stamp always lands the same way.
class VisaStampMark extends StatelessWidget {
  final VisaStamp stamp;
  final double scale;
  const VisaStampMark(this.stamp, {super.key, this.scale = 1});

  double get _tilt {
    final h = stamp.label.codeUnits.fold<int>(stamp.date.hashCode, (a, c) => (a * 31 + c) & 0x7fffffff);
    return ((h % 25) - 12) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final ink = PassportInk.of(stamp.kind).withValues(alpha: .88);
    final s = scale;
    final date = _shortDate(stamp.date);
    final Widget body = switch (stamp.kind) {
      StampKind.place => _Ring(
          size: 96 * s,
          ink: ink,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('ENTRY', style: _sans(6.5 * s, ink, spacing: 1.6 * s)),
            SizedBox(height: 3 * s),
            Text(stamp.label.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: _sans(10.5 * s, ink, weight: FontWeight.w800, spacing: .4 * s)),
            SizedBox(height: 3 * s),
            Text(date, style: _sans(7 * s, ink, weight: FontWeight.w600, spacing: 1 * s)),
          ]),
        ),
      StampKind.firstTaste => Container(
          width: 112 * s,
          padding: EdgeInsets.all(2.5 * s),
          decoration: BoxDecoration(border: Border.all(color: ink, width: 2 * s), borderRadius: BorderRadius.circular(5 * s)),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 7 * s, vertical: 6 * s),
            decoration: BoxDecoration(border: Border.all(color: ink, width: .8 * s), borderRadius: BorderRadius.circular(3 * s)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('FIRST TASTE', style: _sans(6.5 * s, ink, spacing: 1.6 * s)),
              SizedBox(height: 3 * s),
              Text(stamp.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: _serif(15 * s, ink, italic: true)),
              SizedBox(height: 2 * s),
              Text(date, style: _sans(7 * s, ink, weight: FontWeight.w600, spacing: 1 * s)),
            ]),
          ),
        ),
      StampKind.newKind => SizedBox(
          width: 86 * s,
          height: 86 * s,
          child: CustomPaint(
            painter: _OctagonPainter(ink, s),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(12 * s),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('NEW KIND', style: _sans(6 * s, ink, spacing: 1.4 * s)),
                  SizedBox(height: 3 * s),
                  Text((kindWords[stamp.label] ?? stamp.label).toUpperCase(), textAlign: TextAlign.center, maxLines: 2, style: _sans(9.5 * s, ink, weight: FontWeight.w800, spacing: .3 * s)),
                  SizedBox(height: 2 * s),
                  Text(date, style: _sans(6.5 * s, ink, weight: FontWeight.w600, spacing: .8 * s)),
                ]),
              ),
            ),
          ),
        ),
      StampKind.dry => _Ring(
          size: 62 * s,
          ink: ink,
          doubled: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('DRY', style: _sans(11 * s, ink, weight: FontWeight.w800, spacing: 2 * s)),
            SizedBox(height: 2 * s),
            Text(date, style: _sans(6 * s, ink, weight: FontWeight.w600, spacing: .6 * s)),
          ]),
        ),
    };
    return Semantics(
      label: switch (stamp.kind) {
        StampKind.place => 'Entry stamp: ${stamp.label}, ${formatDayLongYear(stamp.date)}',
        StampKind.firstTaste => 'First taste: ${stamp.label}, ${formatDayLongYear(stamp.date)}',
        StampKind.newKind => 'New kind: ${kindWords[stamp.label] ?? stamp.label}, ${formatDayLongYear(stamp.date)}',
        StampKind.dry => 'Dry night, ${formatDayLongYear(stamp.date)}',
      },
      excludeSemantics: true,
      child: Transform.rotate(angle: _tilt, child: body),
    );
  }
}

class _Ring extends StatelessWidget {
  final double size;
  final Color ink;
  final Widget child;
  final bool doubled;
  const _Ring({required this.size, required this.ink, required this.child, this.doubled = true});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink, width: size * .028)),
        padding: EdgeInsets.all(size * .05),
        child: Container(
          alignment: Alignment.center,
          decoration: doubled ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink, width: size * .009)) : null,
          padding: EdgeInsets.all(size * .09),
          child: child,
        ),
      );
}

class _OctagonPainter extends CustomPainter {
  final Color ink;
  final double s;
  _OctagonPainter(this.ink, this.s);
  Path _oct(Size size, double inset) {
    final w = size.width - inset * 2, h = size.height - inset * 2, c = w * .29;
    return Path()
      ..moveTo(inset + c, inset)
      ..lineTo(inset + w - c, inset)
      ..lineTo(inset + w, inset + c)
      ..lineTo(inset + w, inset + h - c)
      ..lineTo(inset + w - c, inset + h)
      ..lineTo(inset + c, inset + h)
      ..lineTo(inset, inset + h - c)
      ..lineTo(inset, inset + c)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke;
    canvas.drawPath(_oct(size, 1.2 * s), p..strokeWidth = 2.2 * s);
    canvas.drawPath(_oct(size, 5.5 * s), p..strokeWidth = .8 * s);
  }

  @override
  bool shouldRepaint(_OctagonPainter old) => old.ink != ink || old.s != s;
}

// ── paper ───────────────────────────────────────────────────────────────────
/// Passport paper: cream, with the fine wavy guilloché lines security paper has.
class PassportPaper extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const PassportPaper({super.key, required this.child, this.padding = const EdgeInsets.all(S.l), this.radius = rTile});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: const _Guilloche(),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(border: Border.all(color: PassportInk.paperEdge, width: 1), borderRadius: BorderRadius.circular(radius)),
            child: child,
          ),
        ),
      );
}

class _Guilloche extends CustomPainter {
  const _Guilloche();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PassportInk.paper);
    final p = Paint()
      ..color = PassportInk.guilloche
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (var row = 0; row < size.height / 9 + 2; row++) {
      final y0 = row * 9.0;
      final path = Path()..moveTo(0, y0);
      for (var x = 0.0; x <= size.width; x += 3) {
        path.lineTo(x, y0 + math.sin(x / 13 + row * .6) * 3.2);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_Guilloche old) => false;
}

/// A page of visa stamps, scattered the way a border officer would.
class VisaPage extends StatelessWidget {
  final String title; // "September 2026", "2026"
  final List<VisaStamp> stamps;
  final int? pageNo;
  final double scale;
  final int? max;
  final String empty;
  const VisaPage({super.key, required this.title, required this.stamps, this.pageNo, this.scale = 1, this.max, this.empty = 'No stamps yet — a new place, a first taste or a dry night earns one.'});

  @override
  Widget build(BuildContext context) {
    final shown = max == null ? stamps : stamps.take(max!).toList();
    final more = stamps.length - shown.length;
    return PassportPaper(
      padding: EdgeInsets.fromLTRB(16 * scale, 14 * scale, 16 * scale, 12 * scale),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('VISAS', style: _sans(8 * scale, PassportInk.soft, spacing: 2.4 * scale)),
          const Spacer(),
          Text(title, style: _serif(14 * scale, PassportInk.ink, italic: true)),
        ]),
        SizedBox(height: 6 * scale),
        Container(height: .8, color: PassportInk.paperEdge),
        SizedBox(height: 12 * scale),
        if (shown.isEmpty)
          Padding(padding: EdgeInsets.symmetric(vertical: 18 * scale), child: Text(empty, textAlign: TextAlign.center, style: _serif(13 * scale, PassportInk.soft, italic: true, height: 1.35)))
        else
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6 * scale,
            runSpacing: 4 * scale,
            children: [
              for (var i = 0; i < shown.length; i++)
                Transform.translate(offset: Offset(0, ((i * 7) % 11 - 5) * scale), child: VisaStampMark(shown[i], scale: scale)),
            ],
          ),
        SizedBox(height: 10 * scale),
        Row(children: [
          if (more > 0) Text('+ $more more', style: _sans(8 * scale, PassportInk.soft, weight: FontWeight.w600, spacing: .6)),
          const Spacer(),
          if (pageNo != null) Text(pageNo!.toString().padLeft(2, '0'), style: _sans(8 * scale, PassportInk.soft, weight: FontWeight.w600, spacing: 1)),
        ]),
      ]),
    );
  }
}

/// The counts a stretch of stamps adds up to, one per ink.
class StampTally extends StatelessWidget {
  final List<VisaStamp> stamps;
  final Color? textColor;
  const StampTally(this.stamps, {super.key, this.textColor});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    int n(StampKind k) => stamps.where((s) => s.kind == k).length;
    final items = [
      (StampKind.place, n(StampKind.place), n(StampKind.place) == 1 ? 'new place' : 'new places'),
      (StampKind.firstTaste, n(StampKind.firstTaste), n(StampKind.firstTaste) == 1 ? 'first taste' : 'first tastes'),
      (StampKind.newKind, n(StampKind.newKind), n(StampKind.newKind) == 1 ? 'new kind' : 'new kinds'),
      (StampKind.dry, n(StampKind.dry), n(StampKind.dry) == 1 ? 'dry night' : 'dry nights'),
    ];
    return Row(children: [
      for (final (k, count, word) in items)
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: PassportInk.of(k))),
              const SizedBox(width: 5),
              Text('$count', style: T.serif(bd, size: 22, color: textColor)),
            ]),
            Text(word, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(bd)),
          ]),
        ),
    ]);
  }
}

// ── the cover and the identity page ─────────────────────────────────────────
class PassportCover extends StatelessWidget {
  final String? name;
  const PassportCover({super.key, this.name});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(rTile),
          gradient: const RadialGradient(center: Alignment(-.3, -.5), radius: 1.3, colors: [Color(0xFF4A262C), PassportInk.leather, PassportInk.leatherDeep]),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Stack(children: [
          // the stitched edge
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: PassportInk.gold.withValues(alpha: .28), width: .8), borderRadius: BorderRadius.circular(rTile - 6)),
            ),
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('TASTE PASSPORT', style: _sans(13, PassportInk.gold, spacing: 4.5)),
              const SizedBox(height: 28),
              SizedBox(
                width: 78,
                height: 78,
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 7,
                  crossAxisSpacing: 7,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (final a in const [.35, .6, .8, 1.0])
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: PassportInk.gold.withValues(alpha: .95), width: 1.4),
                          color: PassportInk.gold.withValues(alpha: a * .35),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text('brewdiary', style: _serif(22, PassportInk.gold, italic: true)),
              const SizedBox(height: 6),
              Text('PLACES · FIRST TASTES · DRY NIGHTS', style: _sans(7.5, PassportInk.gold.withValues(alpha: .7), weight: FontWeight.w600, spacing: 2)),
            ]),
          ),
          if (name != null)
            Positioned(left: 0, right: 0, bottom: 26, child: Text(name!.toUpperCase(), textAlign: TextAlign.center, style: _sans(10, PassportInk.gold.withValues(alpha: .8), weight: FontWeight.w600, spacing: 3))),
        ]),
      );
}

/// The identity page: who, since when, what you're into, the counts, and a
/// machine-readable strip at the foot — the way a real passport ends.
class PassportIdentity extends StatelessWidget {
  final String? name;
  final Passport passport;
  final List<(String, String)> lines;
  final bool dryTonight;
  final bool showPlaces;
  const PassportIdentity({super.key, required this.name, required this.passport, required this.lines, this.dryTonight = false, this.showPlaces = true});

  String _mrz(String s) => s.toUpperCase().replaceAll(RegExp('[^A-Z0-9]+'), '<');

  @override
  Widget build(BuildContext context) {
    final who = (name ?? 'The bearer').trim();
    final parts = who.split(RegExp(r'\s+'));
    final initials = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    final since = passport.since == null ? null : parseKey(passport.since!);
    Widget field(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: _sans(7, PassportInk.soft, weight: FontWeight.w600, spacing: 1.4)),
            const SizedBox(height: 2),
            Text(value, style: _serif(16, PassportInk.ink)),
          ]),
        );
    Widget count(int n, String what) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: _serif(26, PassportInk.ink)),
            Text(what.toUpperCase(), maxLines: 2, style: _sans(6.5, PassportInk.soft, weight: FontWeight.w600, spacing: .8)),
          ]),
        );
    final line1 = 'P<BWD<${_mrz(parts.length > 1 ? parts.last : who)}<<${_mrz(parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : '')}';
    final line2 = 'BREWDIARY<${since?.year ?? ''}<P${passport.places}<K${passport.kinds}<D${passport.families}<N${passport.dryNights}';
    String pad(String s) => (s.length >= 36 ? s.substring(0, 36) : s.padRight(36, '<'));
    return PassportPaper(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('TASTE PASSPORT', style: _sans(8, PassportInk.soft, spacing: 2.4)),
          const Spacer(),
          Text('brewdiary', style: _serif(13, PassportInk.place, italic: true)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 74,
            height: 92,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: PassportInk.paperEdge.withValues(alpha: .6), border: Border.all(color: PassportInk.place.withValues(alpha: .5), width: 1), borderRadius: BorderRadius.circular(4)),
            child: Text(initials.isEmpty ? '·' : initials, style: _serif(34, PassportInk.place)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              field('Bearer', who),
              if (since != null) field('Holder since', '${monthNames[since.month - 1]} ${since.year}'),
              if (dryTonight) field('Tonight', 'Nothing with alcohol'),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        for (final (k, v) in lines) field(k, v),
        if (lines.isEmpty && !dryTonight) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Log a few more drinks and this page fills in.', style: _serif(14, PassportInk.soft, italic: true))),
        const SizedBox(height: 4),
        Row(children: [
          if (showPlaces) count(passport.places, passport.places == 1 ? 'place' : 'places'),
          count(passport.kinds, 'kinds of 8'),
          count(passport.families, 'drinks met'),
          count(passport.dryNights, 'dry nights'),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          color: PassportInk.paperEdge.withValues(alpha: .45),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${pad(line1)}\n${pad(line2)}', style: _sans(11, PassportInk.ink, weight: FontWeight.w500, spacing: 1.6).copyWith(height: 1.4, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
      ]),
    );
  }
}

/// The lines of the identity page, from the taste profile.
List<(String key, String label, String value)> tasteLines(TasteProfile p) => [
      if (p.favourites.isNotEmpty) ('into', 'Into', p.favourites.join(', ')),
      if (p.kinds.isNotEmpty) ('usually', 'Usually', p.kinds.map((k) => kindWords[k.name] ?? k.name).join(' · ')),
      if (p.moods.isNotEmpty) ('mood', 'In the mood for', p.moods.join(', ')),
      if (p.noAlcoholShare >= .4) ('free', 'Often', 'alcohol-free — happy with a good non-alcoholic pour'),
    ];

/// The month's first and last day keys.
(String, String) monthRange(int year, int month0) => (toKey(DateTime(year, month0 + 1, 1)), toKey(DateTime(year, month0 + 2, 0)));
