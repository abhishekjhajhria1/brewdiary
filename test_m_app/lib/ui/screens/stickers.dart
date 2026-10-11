// Stickers for sharing a night. YOUR photo is the picture; brewdiary adds one small,
// sharp sticker on top — the way a run app puts the run on a selfie. Six designs,
// each a few lines of type: Stats, Line, Mosaic, Stamp, Receipt, Date. No made-up
// backgrounds; the brand is a small mark, never a banner.
//
// Nothing rewards drinking more: no sticker headlines how many drinks. What's on
// them is when, where, what was new, who you were with — the night, not the count.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import '../theme.dart';
import 'photo_studio.dart' show NightStory, StoryLine;

enum StickerKind { stats, line, mosaic, stamp, receipt, date }

const stickerNames = {
  StickerKind.stats: 'Stats',
  StickerKind.line: 'Line',
  StickerKind.mosaic: 'Mosaic',
  StickerKind.stamp: 'Stamp',
  StickerKind.receipt: 'Receipt',
  StickerKind.date: 'Date',
};

/// Where each sticker sits before it's moved (as an Alignment, -1..1).
const stickerHome = {
  StickerKind.stats: Alignment(-1, .86),
  StickerKind.line: Alignment(-1, .82),
  StickerKind.mosaic: Alignment(1, .86),
  StickerKind.stamp: Alignment(.85, -.78),
  StickerKind.receipt: Alignment(.9, .8),
  StickerKind.date: Alignment(-1, -.84),
};

/// The ink a sticker is printed in: white for most photos, black for bright ones,
/// or the one amber.
enum StickerInk { light, dark, amber }

const _paper = Color(0xFFF7F3EC);
const _paperInk = Color(0xFF1B1A1F);
Color get _amber => BD.darkTokens.accent;

Color inkColor(StickerInk ink) => switch (ink) {
      StickerInk.light => const Color(0xFFFAF7F2),
      StickerInk.dark => const Color(0xFF16151A),
      StickerInk.amber => _amber,
    };

/// "21:40" → "9:40 pm".
String twelveHour(String hhmm) {
  final p = hhmm.split(':');
  final h = int.tryParse(p.first) ?? 0;
  final m = p.length > 1 ? p[1] : '00';
  return '${h % 12 == 0 ? 12 : h % 12}:$m ${h < 12 ? 'am' : 'pm'}';
}

/// The first part of a place ("Soka, Bandra" → "Soka").
String shortPlace(String v) => v.split(',').first.trim();

/// Up to three facts about the night for the Stats sticker — never a drink count.
List<({String label, String value})> statCells(NightStory s) {
  final out = <({String label, String value})>[];
  final day = parseKey(s.dateKey);
  out.add(s.time != null ? (label: 'Since', value: twelveHour(s.time!)) : (label: 'Night', value: weekdays[mondayIndex(day)]));
  if (s.venue != null && s.venue!.trim().isNotEmpty) out.add((label: 'At', value: shortPlace(s.venue!)));
  if (s.dry) {
    out.add((label: 'Tonight', value: 'Dry'));
  } else if (s.newToYou > 0) {
    out.add((label: 'New to me', value: '${s.newToYou}'));
  }
  if (out.length < 3 && (s.withPeople ?? 0) > 0) out.add((label: 'With', value: s.withPeople == 1 ? '1 friend' : '${s.withPeople} friends'));
  if (out.length < 3 && s.mood != null) out.add((label: 'Mood', value: s.mood!));
  return out.take(3).toList();
}

class Sticker extends StatelessWidget {
  final StickerKind kind;
  final NightStory story;
  final StickerInk ink;

  /// One unit: the canvas width / 360, so a 1080-wide export is the same sticker, bigger.
  final double u;

  /// The diary, for the Mosaic sticker's month.
  final List<Entry> diary;

  const Sticker({super.key, required this.kind, required this.story, required this.ink, required this.u, this.diary = const []});

  Color get _ink => inkColor(ink);
  List<Shadow> get _shade => ink == StickerInk.dark
      ? [Shadow(color: Colors.white.withValues(alpha: .35), blurRadius: 8 * u)]
      : [Shadow(color: Colors.black.withValues(alpha: .5), blurRadius: 10 * u), Shadow(color: Colors.black.withValues(alpha: .25), blurRadius: 2 * u)];

  TextStyle _label(double size, {Color? color}) => T.rawSans(size * u, color ?? _ink, weight: FontWeight.w600, spacing: size * u * .18).copyWith(shadows: color == null ? _shade : null);
  TextStyle _sans(double size, {FontWeight weight = FontWeight.w500, Color? color}) => T.rawSans(size * u, color ?? _ink, weight: weight).copyWith(shadows: color == null ? _shade : null);
  TextStyle _serif(double size, {bool italic = false, double? height, Color? color}) =>
      T.rawSerif(size * u, color ?? _ink, italic: italic, height: height).copyWith(shadows: color == null ? _shade : null, fontFeatures: T.tnum);

  List<String> get _names => [for (final l in story.lines) l.name];

  String get _dayLabel {
    final d = parseKey(story.dateKey);
    return '${weekdays[mondayIndex(d)]} ${d.day} ${monthNames[d.month - 1].substring(0, 3)}';
  }

  /// The mark: four amber squares (the mosaic) and the wordmark.
  Widget _mark({double scale = 1, Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(size: Size.square(11 * u * scale), painter: _MarkPainter(_amber)),
        SizedBox(width: 6 * u * scale),
        Text('brewdiary', style: _serif(13 * scale, italic: true, color: color).copyWith(height: 1)),
      ]);

  @override
  Widget build(BuildContext context) => switch (kind) {
        StickerKind.stats => _stats(),
        StickerKind.line => _line(),
        StickerKind.mosaic => _mosaic(),
        StickerKind.stamp => _stamp(),
        StickerKind.receipt => _receipt(),
        StickerKind.date => _date(),
      };

  // ── Stats: three facts in a row, the night's line under a hairline ─────────────
  Widget _stats() {
    final cells = statCells(story);
    return SizedBox(
      width: 312 * u,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _mark(),
        SizedBox(height: 14 * u),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, c) in cells.indexed)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == cells.length - 1 ? 0 : 14 * u),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.label.toUpperCase(), maxLines: 1, style: _label(8.5)),
                  SizedBox(height: 4 * u),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(c.value, maxLines: 1, style: _serif(26, height: 1.05))),
                ]),
              ),
            ),
        ]),
        if (_names.isNotEmpty) ...[
          SizedBox(height: 12 * u),
          Container(height: .8 * u, color: _ink.withValues(alpha: .7)),
          SizedBox(height: 9 * u),
          Text(_names.join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: _sans(12)),
        ],
      ]),
    );
  }

  // ── Line: the night as a few lines of verse ────────────────────────────────────
  Widget _line() {
    final names = _names;
    final shown = names.take(4).toList();
    final more = names.length - shown.length;
    final place = story.venue == null ? null : shortPlace(story.venue!);
    return SizedBox(
      width: 270 * u,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text([_dayLabel, ?place].join('  ·  ').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(8.5)),
        SizedBox(height: 8 * u),
        if (story.dry || shown.isEmpty)
          Text(story.dry ? 'A dry night.' : (story.title ?? 'A night.'), style: _serif(31, italic: true, height: 1.12))
        else
          for (var i = 0; i < shown.length; i++)
            Text(
              i == shown.length - 1 && more == 0 ? (shown.length > 1 ? 'then ${shown[i]}.' : '${shown[i]}.') : '${shown[i]},',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _serif(31, italic: true, height: 1.12),
            ),
        if (more > 0) Text('and $more more.', style: _serif(31, italic: true, height: 1.12)),
        SizedBox(height: 12 * u),
        _mark(scale: .85),
      ]),
    );
  }

  // ── Mosaic: the month, tonight's square ringed ─────────────────────────────────
  Widget _mosaic() {
    final d = parseKey(story.dateKey);
    final grid = monthGrid(d.year, d.month - 1);
    final counts = countsByDate(diary);
    final kept = {for (final e in diary) if (e.date.startsWith(story.dateKey.substring(0, 7))) e.date}.length;
    final glass = ink == StickerInk.dark ? Colors.white.withValues(alpha: .72) : Colors.black.withValues(alpha: .42);
    final cell = 21.0 * u, gap = 4.0 * u;
    return Container(
      padding: EdgeInsets.fromLTRB(14 * u, 13 * u, 14 * u, 12 * u),
      decoration: BoxDecoration(color: glass, borderRadius: BorderRadius.circular(18 * u), border: Border.all(color: _ink.withValues(alpha: .18), width: .8 * u)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 7 * cell + 6 * gap,
          child: Row(children: [
            Text(monthNames[d.month - 1].toUpperCase(), style: _label(8.5, color: _ink)),
            const Spacer(),
            Text(kept == 1 ? '1 night kept' : '$kept nights kept', style: _label(8.5, color: _ink.withValues(alpha: .75))),
          ]),
        ),
        SizedBox(height: 10 * u),
        SizedBox(
          width: 7 * cell + 6 * gap,
          child: Wrap(spacing: gap, runSpacing: gap, children: [
            for (final g in grid)
              Container(
                width: cell,
                height: cell,
                decoration: BoxDecoration(
                  color: !g.inMonth
                      ? Colors.transparent
                      : (counts[g.key] ?? 0) > 0
                          ? _amber.withValues(alpha: const [0.0, .38, .58, .8, 1.0][intensityLevel(counts[g.key]!).clamp(0, 4)])
                          : _ink.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(5 * u),
                  border: g.key == story.dateKey ? Border.all(color: _ink, width: 1.6 * u) : null,
                ),
              ),
          ]),
        ),
        SizedBox(height: 11 * u),
        _mark(scale: .8, color: _ink),
      ]),
    );
  }

  // ── Stamp: a round passport stamp, a little crooked ────────────────────────────
  Widget _stamp() {
    final d = parseKey(story.dateKey);
    final place = story.venue == null ? 'BREWDIARY' : shortPlace(story.venue!).toUpperCase();
    final size = 158 * u;
    return Transform.rotate(
      angle: -.13,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _StampRing(_ink, u, shade: ink != StickerInk.dark),
          child: Padding(
            padding: EdgeInsets.all(26 * u),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(story.dry ? 'DRY NIGHT' : 'BREWDIARY', style: _label(7.5)),
              SizedBox(height: 5 * u),
              Text('${d.day} ${monthNames[d.month - 1].substring(0, 3).toUpperCase()}', style: _serif(30, height: 1)),
              Text('${d.year}', style: _label(8)),
              SizedBox(height: 6 * u),
              Container(width: 54 * u, height: .8 * u, color: _ink.withValues(alpha: .8)),
              SizedBox(height: 6 * u),
              Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: _label(9.5)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Receipt: a small paper slip (prices only if you typed them) ────────────────
  Widget _receipt() {
    final d = parseKey(story.dateKey);
    final lines = story.lines.take(7).toList();
    final more = story.lines.length - lines.length;
    final total = story.billTotal;
    TextStyle mono(double size, {FontWeight weight = FontWeight.w500}) => T.rawSans(size * u, _paperInk, weight: weight).copyWith(fontFeatures: T.tnum, height: 1.35);
    Widget dashes() => Padding(padding: EdgeInsets.symmetric(vertical: 6 * u), child: CustomPaint(size: Size(double.infinity, 1 * u), painter: _Dashes(_paperInk.withValues(alpha: .45), u)));
    Widget row(String left, String? right, {FontWeight weight = FontWeight.w500}) => Row(children: [
          Expanded(child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(9.5, weight: weight))),
          if (right != null) Text(right, style: mono(9.5, weight: weight)),
        ]);
    return Transform.rotate(
      angle: .035,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .28), blurRadius: 18 * u, offset: Offset(0, 6 * u))]),
        child: ClipPath(
          clipper: _ZigzagBottom(5 * u),
          child: Container(
            width: 176 * u,
            color: _paper,
            padding: EdgeInsets.fromLTRB(14 * u, 14 * u, 14 * u, 18 * u),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: _mark(scale: .9, color: _paperInk)),
              SizedBox(height: 6 * u),
              if (story.venue != null) Text(story.venue!.toUpperCase(), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(8.5, weight: FontWeight.w600)),
              Text(
                '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}${story.time == null ? '' : '  ${story.time}'}',
                textAlign: TextAlign.center,
                style: mono(8.5),
              ),
              dashes(),
              if (lines.isEmpty) row(story.dry ? 'A dry night' : 'Nothing on it yet', null),
              for (final l in lines) row('${l.qty} × ${l.name}', l.price == null ? null : formatMoney(l.price! * l.qty, story.currency)),
              if (more > 0) row('+ $more more', null),
              if (total != null) ...[dashes(), row('TOTAL', formatMoney(total, story.currency), weight: FontWeight.w700)],
              dashes(),
              Text('THANK YOU  ·  BWDY.SITE', textAlign: TextAlign.center, style: mono(7.5, weight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Date: the quietest — the date, the day, the place ──────────────────────────
  Widget _date() {
    final d = parseKey(story.dateKey);
    final place = story.venue == null ? null : shortPlace(story.venue!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}', style: _serif(76, height: .95)),
      SizedBox(height: 4 * u),
      Text([weekdaysLong[mondayIndex(d)], ?place].join('  ·  ').toUpperCase(), style: _label(9)),
      SizedBox(height: 10 * u),
      _mark(scale: .85),
    ]);
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  _MarkPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final g = size.shortestSide * .14;
    final cell = (size.shortestSide - g) / 2;
    const a = [.45, .7, .85, 1.0];
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH((i % 2) * (cell + g), (i ~/ 2) * (cell + g), cell, cell);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * .24)), Paint()..color = color.withValues(alpha: a[i]));
    }
  }

  @override
  bool shouldRepaint(_MarkPainter o) => o.color != color;
}

/// Two rings and a row of small ticks between them — a rubber stamp, crisp.
class _StampRing extends CustomPainter {
  final Color ink;
  final double u;
  final bool shade;
  _StampRing(this.ink, this.u, {required this.shade});
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    void ring(double radius, double width) {
      if (shade) canvas.drawCircle(c, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = width + 2 * u..color = Colors.black.withValues(alpha: .18)..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * u));
      canvas.drawCircle(c, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = width..color = ink);
    }

    ring(r - 2 * u, 2.4 * u);
    ring(r - 13 * u, 1 * u);
    final tick = Paint()..color = ink..strokeWidth = 1 * u;
    for (var i = 0; i < 48; i++) {
      final a = i * math.pi * 2 / 48;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - 9.5 * u), c + dir * (r - 6 * u), tick);
    }
  }

  @override
  bool shouldRepaint(_StampRing o) => o.ink != ink || o.u != u;
}

class _Dashes extends CustomPainter {
  final Color color;
  final double u;
  _Dashes(this.color, this.u);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = size.height;
    for (var x = 0.0; x < size.width; x += 5 * u) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 2.5 * u, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_Dashes o) => false;
}

class _ZigzagBottom extends CustomClipper<Path> {
  final double tooth;
  _ZigzagBottom(this.tooth);
  @override
  Path getClip(Size size) {
    final p = Path()..lineTo(size.width, 0)..lineTo(size.width, size.height - tooth);
    var x = size.width;
    var down = true;
    while (x > 0) {
      x -= tooth;
      p.lineTo(math.max(x, 0), down ? size.height : size.height - tooth);
      down = !down;
    }
    return p..close();
  }

  @override
  bool shouldReclip(_ZigzagBottom o) => o.tooth != tooth;
}

/// For tests: a story with every field, so a sticker shows all it can.
@visibleForTesting
NightStory sampleNight() => const NightStory(
      dateKey: '2026-09-26',
      title: "Mira's birthday",
      venue: 'Soka, Bandra',
      mood: 'smoky',
      withPeople: 3,
      time: '21:40',
      newToYou: 2,
      lines: [StoryLine('Mezcal Negroni', price: 650), StoryLine('Paloma', price: 520), StoryLine('Truffle fries', price: 380), StoryLine('Lime soda', price: 150)],
    );
