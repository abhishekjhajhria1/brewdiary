// The taste passport, drawn: rubber stamps in four inks, visa pages on guilloché
// paper, the leather cover and the identity page with its machine-readable strip.
// Used by the full passport (screens/taste_card.dart) and by the calendar's
// month and year cards.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../theme.dart';

// ── the look: brewdiary's own ───────────────────────────────────────────────
// Dark glass, one amber accent, the mosaic. Stamps are amber, told apart by their
// shape (a dry night's is the quieter muted ink). Every surface is opaque
// underneath, so a page shared as a picture looks the same as on the screen.

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

/// The ink a stamp is printed in: amber, or muted for a dry night.
Color stampInk(BD bd, StampKind k) => k == StampKind.dry ? bd.muted : bd.accentText;

/// The tally dot for a kind: amber at falling strengths, muted for dry.
Color stampDot(BD bd, StampKind k) => switch (k) {
      StampKind.place => bd.accent,
      StampKind.firstTaste => bd.accent.withValues(alpha: .7),
      StampKind.newKind => bd.accent.withValues(alpha: .45),
      StampKind.dry => bd.muted,
    };

String _shortDate(String key) {
  final d = parseKey(key);
  return '${d.day.toString().padLeft(2, '0')} ${monthNames[d.month - 1].substring(0, 3).toUpperCase()} ${(d.year % 100).toString().padLeft(2, '0')}';
}

TextStyle _sans(double size, Color color, {FontWeight weight = FontWeight.w700, double spacing = 1}) =>
    TextStyle(fontFamily: T.sansFamily, fontFamilyFallback: T.fallback, fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing, height: 1.15);
TextStyle _serif(double size, Color color, {bool italic = false, double height = 1.1}) =>
    TextStyle(fontFamily: T.serifFamily, fontSize: size, color: color, fontStyle: italic ? FontStyle.italic : FontStyle.normal, height: height);

// ── one stamp ───────────────────────────────────────────────────────────────
/// A stamp, shaped by what it's for: a ring for a place, a frame for a first
/// taste, an octagon for a new kind, a small ring for a dry night. The tilt comes
/// from the label, so the same stamp always lands the same way.
class VisaStampMark extends StatelessWidget {
  final VisaStamp stamp;
  final double scale;
  const VisaStampMark(this.stamp, {super.key, this.scale = 1});

  double get _tilt {
    final h = stamp.label.codeUnits.fold<int>(stamp.date.hashCode, (a, c) => (a * 31 + c) & 0x7fffffff);
    return ((h % 17) - 8) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final ink = stampInk(bd, stamp.kind);
    final s = scale;
    final date = _shortDate(stamp.date);
    final glow = [BoxShadow(color: ink.withValues(alpha: bd.dark ? .22 : .10), blurRadius: 14 * s)];
    final Widget body = switch (stamp.kind) {
      StampKind.place => _Ring(
          size: 96 * s,
          ink: ink,
          glow: glow,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('ENTRY', style: _sans(6.5 * s, ink.withValues(alpha: .8), spacing: 1.8 * s)),
            SizedBox(height: 3 * s),
            Text(stamp.label.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: _sans(10.5 * s, ink, weight: FontWeight.w800, spacing: .4 * s)),
            SizedBox(height: 3 * s),
            Text(date, style: _sans(7 * s, ink.withValues(alpha: .8), weight: FontWeight.w600, spacing: 1 * s)),
          ]),
        ),
      StampKind.firstTaste => Container(
          width: 112 * s,
          padding: EdgeInsets.all(2.5 * s),
          decoration: BoxDecoration(border: Border.all(color: ink, width: 1.6 * s), borderRadius: BorderRadius.circular(6 * s), boxShadow: glow),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 7 * s, vertical: 6 * s),
            decoration: BoxDecoration(border: Border.all(color: ink.withValues(alpha: .5), width: .8 * s), borderRadius: BorderRadius.circular(4 * s)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('FIRST TASTE', style: _sans(6.5 * s, ink.withValues(alpha: .8), spacing: 1.8 * s)),
              SizedBox(height: 3 * s),
              Text(stamp.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: _serif(15 * s, ink, italic: true)),
              SizedBox(height: 2 * s),
              Text(date, style: _sans(7 * s, ink.withValues(alpha: .8), weight: FontWeight.w600, spacing: 1 * s)),
            ]),
          ),
        ),
      StampKind.newKind => Container(
          width: 86 * s,
          height: 86 * s,
          decoration: BoxDecoration(boxShadow: glow, shape: BoxShape.circle),
          child: CustomPaint(
            painter: _OctagonPainter(ink, s),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(12 * s),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('NEW KIND', style: _sans(6 * s, ink.withValues(alpha: .8), spacing: 1.4 * s)),
                  SizedBox(height: 3 * s),
                  Text((kindWords[stamp.label] ?? stamp.label).toUpperCase(), textAlign: TextAlign.center, maxLines: 2, style: _sans(9.5 * s, ink, weight: FontWeight.w800, spacing: .3 * s)),
                  SizedBox(height: 2 * s),
                  Text(date, style: _sans(6.5 * s, ink.withValues(alpha: .8), weight: FontWeight.w600, spacing: .8 * s)),
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
  final List<BoxShadow>? glow;
  const _Ring({required this.size, required this.ink, required this.child, this.doubled = true, this.glow});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink, width: size * .022), boxShadow: glow),
        padding: EdgeInsets.all(size * .05),
        child: Container(
          alignment: Alignment.center,
          decoration: doubled ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink.withValues(alpha: .5), width: size * .009)) : null,
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
    final p = Paint()..style = PaintingStyle.stroke;
    canvas.drawPath(_oct(size, 1.2 * s), p..color = ink..strokeWidth = 1.8 * s);
    canvas.drawPath(_oct(size, 5.5 * s), p..color = ink.withValues(alpha: .5)..strokeWidth = .8 * s);
  }

  @override
  bool shouldRepaint(_OctagonPainter old) => old.ink != ink || old.s != s;
}

// ── the surface ─────────────────────────────────────────────────────────────
/// A passport page in the app's own material: a deep glass card with a soft amber
/// glow in one corner and a faint mosaic in the other. Opaque, so it shares well.
class PassportPaper extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool glow;
  const PassportPaper({super.key, required this.child, this.padding = const EdgeInsets.all(S.l), this.radius = rTile, this.glow = true});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: _PageGround(bd, glow),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(border: Border.all(color: bd.glassBorder, width: 1), borderRadius: BorderRadius.circular(radius)),
          child: child,
        ),
      ),
    );
  }
}

class _PageGround extends CustomPainter {
  final BD bd;
  final bool glow;
  const _PageGround(this.bd, this.glow);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = bd.sheet);
    canvas.drawRect(r, Paint()..color = bd.glass);
    if (glow) {
      canvas.drawRect(
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-1, -1),
            radius: 1.25,
            colors: [bd.accent.withValues(alpha: bd.dark ? .16 : .12), bd.accent.withValues(alpha: 0)],
          ).createShader(r),
      );
    }
    // A faint mosaic in the far corner — the diary's own pattern.
    const cell = 7.0, gap = 2.5, cols = 6, rows = 4;
    final ox = size.width - cols * (cell + gap) - 14, oy = size.height - rows * (cell + gap) - 14;
    for (var c = 0; c < cols; c++) {
      for (var row = 0; row < rows; row++) {
        final level = ((c * 7 + row * 3) % 5) / 4;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(ox + c * (cell + gap), oy + row * (cell + gap), cell, cell), const Radius.circular(1.6)),
          Paint()..color = bd.accent.withValues(alpha: .03 + level * .07),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PageGround old) => old.bd != bd || old.glow != glow;
}

/// A page of stamps for a month or a year.
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
    final bd = context.bd;
    final shown = max == null ? stamps : stamps.take(max!).toList();
    final more = stamps.length - shown.length;
    return PassportPaper(
      padding: EdgeInsets.fromLTRB(18 * scale, 16 * scale, 18 * scale, 14 * scale),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('STAMPS', style: _sans(8.5 * scale, bd.faint, spacing: 2.2 * scale, weight: FontWeight.w600)),
          const Spacer(),
          Text(title, style: _serif(17 * scale, bd.ink, italic: true)),
        ]),
        SizedBox(height: 8 * scale),
        Container(height: .8, color: bd.line),
        SizedBox(height: 14 * scale),
        if (shown.isEmpty)
          Padding(padding: EdgeInsets.symmetric(vertical: 22 * scale), child: Text(empty, textAlign: TextAlign.center, style: _serif(14 * scale, bd.muted, italic: true, height: 1.4)))
        else
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8 * scale,
            runSpacing: 6 * scale,
            children: [
              for (var i = 0; i < shown.length; i++)
                Transform.translate(offset: Offset(0, ((i * 7) % 11 - 5) * scale), child: VisaStampMark(shown[i], scale: scale)),
            ],
          ),
        SizedBox(height: 12 * scale),
        Row(children: [
          if (more > 0) Text('+ $more more', style: _sans(8.5 * scale, bd.faint, weight: FontWeight.w600, spacing: .6)),
          const Spacer(),
          if (pageNo != null) Text(pageNo!.toString().padLeft(2, '0'), style: _sans(8.5 * scale, bd.faint, weight: FontWeight.w600, spacing: 1)),
        ]),
      ]),
    );
  }
}

/// The counts a stretch of stamps adds up to.
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
              Container(width: 7, height: 7, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: stampDot(bd, k))),
              const SizedBox(width: 6),
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
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ClipRRect(
      borderRadius: BorderRadius.circular(rTile),
      child: Container(
        decoration: BoxDecoration(
          color: bd.sheet,
          borderRadius: BorderRadius.circular(rTile),
          border: Border.all(color: bd.glassBorder),
          gradient: RadialGradient(center: const Alignment(0, -.15), radius: .95, colors: [bd.accent.withValues(alpha: bd.dark ? .22 : .16), bd.sheet.withValues(alpha: 0)]),
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _PageGround(bd, false))),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: const Alignment(0, -.15), radius: .9, colors: [bd.accent.withValues(alpha: bd.dark ? .2 : .14), bd.accent.withValues(alpha: 0)]),
              ),
            ),
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('TASTE PASSPORT', style: _sans(12, bd.ink, spacing: 5, weight: FontWeight.w600)),
              const SizedBox(height: 34),
              // The mosaic, lit: the diary's emblem.
              SizedBox(
                width: 92,
                height: 92,
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    for (final a in const [.18, .45, .3, .6, 1.0, .5, .3, .7, .22])
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: bd.accent.withValues(alpha: a),
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: a >= .99 ? [BoxShadow(color: bd.accent.withValues(alpha: .6), blurRadius: 16)] : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              Text('brewdiary', style: _serif(24, bd.ink, italic: true)),
              const SizedBox(height: 8),
              Text('places · first tastes · dry nights', style: _sans(10, bd.muted, weight: FontWeight.w500, spacing: .6)),
            ]),
          ),
          if (name != null)
            Positioned(left: 0, right: 0, bottom: 28, child: Text(name!, textAlign: TextAlign.center, style: _serif(18, bd.accentText, italic: true))),
        ]),
      ),
    );
  }
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
    final bd = context.bd;
    final who = (name ?? 'The bearer').trim();
    final parts = who.split(RegExp(r'\s+'));
    final initials = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    final since = passport.since == null ? null : parseKey(passport.since!);
    Widget field(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: _sans(7.5, bd.faint, weight: FontWeight.w600, spacing: 1.6)),
            const SizedBox(height: 3),
            Text(value, style: _serif(17, bd.ink)),
          ]),
        );
    Widget count(int n, String what) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: _serif(28, bd.accentText)),
            const SizedBox(height: 2),
            Text(what.toUpperCase(), maxLines: 2, style: _sans(6.5, bd.faint, weight: FontWeight.w600, spacing: .9)),
          ]),
        );
    final line1 = 'P<BWD<${_mrz(parts.length > 1 ? parts.last : who)}<<${_mrz(parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : '')}';
    final line2 = 'BREWDIARY<${since?.year ?? ''}<P${passport.places}<K${passport.kinds}<D${passport.families}<N${passport.dryNights}';
    String pad(String s) => (s.length >= 36 ? s.substring(0, 36) : s.padRight(36, '<'));
    return PassportPaper(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('TASTE PASSPORT', style: _sans(8.5, bd.faint, spacing: 2.2, weight: FontWeight.w600)),
          const Spacer(),
          Text('brewdiary', style: _serif(14, bd.accentText, italic: true)),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bd.accent.withValues(alpha: .14),
              border: Border.all(color: bd.accent.withValues(alpha: .55), width: 1.2),
              boxShadow: [BoxShadow(color: bd.accent.withValues(alpha: bd.dark ? .25 : .12), blurRadius: 18)],
            ),
            child: Text(initials.isEmpty ? '·' : initials, style: _serif(26, bd.accentText)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: _serif(26, bd.ink)),
              if (since != null) Text('Keeping the diary since ${monthNames[since.month - 1]} ${since.year}', style: _sans(11, bd.muted, weight: FontWeight.w500, spacing: .2)),
            ]),
          ),
        ]),
        if (dryTonight) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: bd.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.accent.withValues(alpha: .45))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('TONIGHT', style: _sans(9, bd.accentText.withValues(alpha: .75), weight: FontWeight.w700, spacing: 2)),
              const SizedBox(width: 10),
              Text('Nothing with alcohol', style: _sans(13, bd.accentText, weight: FontWeight.w600, spacing: .2)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Container(height: .8, color: bd.line),
        const SizedBox(height: 14),
        for (final (k, v) in lines) field(k, v),
        if (lines.isEmpty && !dryTonight) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Log a few more drinks and this page fills in.', style: _serif(15, bd.muted, italic: true))),
        const SizedBox(height: 4),
        Row(children: [
          if (showPlaces) count(passport.places, passport.places == 1 ? 'place' : 'places'),
          count(passport.kinds, 'kinds of 8'),
          count(passport.families, 'drinks met'),
          count(passport.dryNights, 'dry nights'),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(color: bd.line, borderRadius: BorderRadius.circular(6)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${pad(line1)}\n${pad(line2)}', style: _sans(11, bd.muted, weight: FontWeight.w500, spacing: 1.6).copyWith(height: 1.45, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
      ]),
    );
  }
}

/// The lines of the identity page: the taste profile, the palate, and what the
/// person has told us (loves, avoid, sweetness, diet, allergies).
List<(String key, String label, String value)> tasteLines(TasteProfile p, {List<PalateNote> notes = const [], List<String> loves = const [], List<String> avoid = const [], String? sweetness, List<String> diet = const [], List<String> allergies = const []}) {
  final into = <String>[];
  for (final x in [...loves, ...p.favourites]) {
    if (!into.any((y) => y.toLowerCase() == x.toLowerCase())) into.add(x);
  }
  return [
    if (into.isNotEmpty) ('into', 'Into', into.take(6).join(', ')),
    if (notes.isNotEmpty) ('palate', 'Palate', notes.take(3).map((n) => n.note).join(' · ')),
    if (p.kinds.isNotEmpty) ('usually', 'Usually', p.kinds.map((k) => kindWords[k.name] ?? k.name).join(' · ')),
    if (sweetness != null) ('sweet', 'Sweetness', switch (sweetness) { 'dry' => 'dry — not sweet', 'sweet' => 'on the sweet side', _ => 'balanced' }),
    if (avoid.isNotEmpty) ('avoid', 'Rather not', avoid.join(', ')),
    if (diet.isNotEmpty) ('diet', 'Diet', diet.join(', ')),
    if (allergies.isNotEmpty) ('allergies', 'Allergic to', allergies.join(', ')),
    if (p.moods.isNotEmpty) ('mood', 'In the mood for', p.moods.join(', ')),
    if (p.noAlcoholShare >= .4) ('free', 'Often', 'alcohol-free — happy with a good non-alcoholic pour'),
  ];
}

/// The palate page: what you lean towards, as amber bars that brighten with
/// strength — the mosaic's own scale.
class PassportPalate extends StatelessWidget {
  final List<PalateNote> notes;
  final String? sweetness;
  final List<String> avoid;
  const PassportPalate({super.key, required this.notes, this.sweetness, this.avoid = const []});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final lean = notes.where((n) => n.share >= .99).map((n) => n.note).toList();
    final top = (lean.isEmpty && notes.isNotEmpty ? [notes.first.note] : lean).take(3).toList();
    return PassportPaper(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('PALATE', style: _sans(8.5, bd.faint, spacing: 2.2, weight: FontWeight.w600)),
          const Spacer(),
          Text('brewdiary', style: _serif(14, bd.accentText, italic: true)),
        ]),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('Log a few drinks and your palate draws itself here — smoky, citrus, creamy, whatever you lean towards.', textAlign: TextAlign.center, style: _serif(15, bd.muted, italic: true, height: 1.4)),
          )
        else ...[
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Leans '),
              for (var i = 0; i < top.length; i++) ...[
                if (i > 0) TextSpan(text: i == top.length - 1 ? ' and ' : ', '),
                TextSpan(text: top[i], style: TextStyle(color: bd.accentText, fontStyle: FontStyle.italic)),
              ],
              const TextSpan(text: '.'),
            ]),
            style: _serif(28, bd.ink, height: 1.15),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < notes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                SizedBox(width: 74, child: Text(notes[i].note, style: _sans(13, bd.ink, weight: FontWeight.w500, spacing: .2))),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => Stack(children: [
                      Container(height: 8, decoration: BoxDecoration(color: bd.line, borderRadius: BorderRadius.circular(4))),
                      Container(
                        height: 8,
                        width: c.maxWidth * notes[i].share.clamp(.06, 1.0),
                        decoration: BoxDecoration(
                          color: bd.accent.withValues(alpha: .35 + .65 * notes[i].share),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: notes[i].share >= .99 ? [BoxShadow(color: bd.accent.withValues(alpha: .45), blurRadius: 10)] : null,
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
        ],
        if (sweetness != null || avoid.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(height: .8, color: bd.line),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (sweetness != null) _Pill(switch (sweetness) { 'dry' => 'Dry — not sweet', 'sweet' => 'On the sweet side', _ => 'Balanced sweetness' }),
            if (avoid.isNotEmpty) _Pill('Rather not: ${avoid.join(', ')}', strong: true),
          ]),
        ],
        const SizedBox(height: 12),
        Text('From what you log — each drink counts once a night.', style: _sans(10, bd.faint, weight: FontWeight.w500, spacing: .2)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool strong;
  const _Pill(this.text, {this.strong = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: strong ? bd.accent.withValues(alpha: .14) : bd.glass,
        borderRadius: BorderRadius.circular(rCtl),
        border: Border.all(color: strong ? bd.accent.withValues(alpha: .45) : bd.line),
      ),
      child: Text(text, style: _sans(12, strong ? bd.accentText : bd.ink, weight: FontWeight.w500, spacing: .1)),
    );
  }
}

/// The month's first and last day keys.
(String, String) monthRange(int year, int month0) => (toKey(DateTime(year, month0 + 1, 1)), toKey(DateTime(year, month0 + 2, 0)));
