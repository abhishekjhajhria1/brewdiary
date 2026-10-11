// The picture a night is shared as: your photo, how it's treated (a look, grain, a
// vignette), the frame around it, and one sticker on top. All of it is drawn here, in
// one widget (Composition), so the studio, its thumbnails and the exported PNG are the
// same picture at different sizes.
//
// Frames are the classics — a print's border, a Polaroid, a strip of 35 mm film, a
// cinema's black bars, an inset card — each with a quiet caption where one belongs.
// Looks are colour grades, never stickers or emoji: warm, golden, mono, noir, faded,
// cool, film. Styles put a sticker, a frame and a look together in one tap.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/types.dart';
import '../theme.dart';
import 'photo_studio.dart' show NightStory;
import 'stickers.dart';

// ── frames ──────────────────────────────────────────────────────────────────
enum PhotoFrame { none, print, polaroid, film, cinema, inset }

const frameNames = {
  PhotoFrame.none: 'None',
  PhotoFrame.print: 'Print',
  PhotoFrame.polaroid: 'Polaroid',
  PhotoFrame.film: 'Film',
  PhotoFrame.cinema: 'Cinema',
  PhotoFrame.inset: 'Inset',
};

/// Frames whose border can be paper or black (film and cinema are always black).
bool frameHasTone(PhotoFrame f) => const {PhotoFrame.print, PhotoFrame.polaroid, PhotoFrame.inset}.contains(f);

const _paperFrame = Color(0xFFF3EFE7);
const _blackFrame = Color(0xFF0E0E10);
const _onPaper = Color(0xFF1B1A1F);
const _onBlack = Color(0xFFF2EEE6);

/// How far the photo sits in from each edge for a frame.
EdgeInsets frameInsets(PhotoFrame f, Size s, double u) => switch (f) {
      PhotoFrame.none => EdgeInsets.zero,
      PhotoFrame.print => EdgeInsets.fromLTRB(20 * u, 20 * u, 20 * u, 58 * u),
      PhotoFrame.polaroid => EdgeInsets.fromLTRB(18 * u, 18 * u, 18 * u, 86 * u),
      PhotoFrame.film => EdgeInsets.fromLTRB(8 * u, 38 * u, 8 * u, 38 * u),
      PhotoFrame.cinema => EdgeInsets.symmetric(vertical: s.height * .13),
      PhotoFrame.inset => EdgeInsets.fromLTRB(26 * u, 26 * u, 26 * u, 46 * u),
    };

// ── looks ───────────────────────────────────────────────────────────────────
enum PhotoLook { original, warm, golden, mono, noir, faded, cool, film }

const lookNames = {
  PhotoLook.original: 'Original',
  PhotoLook.warm: 'Warm',
  PhotoLook.golden: 'Golden',
  PhotoLook.mono: 'Mono',
  PhotoLook.noir: 'Noir',
  PhotoLook.faded: 'Faded',
  PhotoLook.cool: 'Cool',
  PhotoLook.film: 'Film',
};

/// A 4×5 colour matrix applied after [b]: a · b.
List<double> _mul(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      var s = j == 4 ? a[i * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        s += a[i * 5 + k] * b[k * 5 + j];
      }
      out[i * 5 + j] = s;
    }
  }
  return out;
}

List<double> _saturation(double s) {
  final r = .2126 * (1 - s), g = .7152 * (1 - s), b = .0722 * (1 - s);
  return [r + s, g, b, 0, 0, r, g + s, b, 0, 0, r, g, b + s, 0, 0, 0, 0, 0, 1, 0];
}

List<double> _contrast(double c, {double lift = 0}) {
  final t = 128 * (1 - c) + lift;
  return [c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0];
}

List<double> _tint(double r, double g, double b, [double ro = 0, double go = 0, double bo = 0]) => [r, 0, 0, 0, ro, 0, g, 0, 0, go, 0, 0, b, 0, bo, 0, 0, 0, 1, 0];

/// The colour grade for a look, or null for the photo as it is.
List<double>? lookMatrix(PhotoLook l) => switch (l) {
      PhotoLook.original => null,
      PhotoLook.warm => _mul(_tint(1.06, 1.0, .9, 6, 2, -4), _saturation(1.05)),
      PhotoLook.golden => _mul(_contrast(1.08), _mul(_tint(1.1, 1.02, .8, 10, 4, -6), _saturation(1.12))),
      PhotoLook.mono => _mul(_contrast(1.06), _saturation(0)),
      PhotoLook.noir => _mul(_contrast(1.32, lift: 6), _saturation(0)),
      PhotoLook.faded => _mul(_contrast(.82, lift: 14), _saturation(.72)),
      PhotoLook.cool => _mul(_tint(.94, 1.0, 1.08, -4, 0, 8), _saturation(.95)),
      PhotoLook.film => _mul(_contrast(.92, lift: 6), _mul(_tint(1.05, 1.0, .9, 10, 7, 2), _saturation(.82))),
    };

// ── every choice the studio makes, in one value ─────────────────────────────
class StudioLook {
  /// null: no sticker — the frame's caption (or nothing) says it.
  final StickerKind? kind;
  final StickerInk ink;
  final StickerPlate plate;
  final StickerFace face;
  final PhotoFrame frame;

  /// Print, Polaroid and Inset frames in black instead of paper.
  final bool frameDark;
  final PhotoLook look;
  final bool grain;
  final bool vignette;

  const StudioLook({
    this.kind = StickerKind.stats,
    this.ink = StickerInk.light,
    this.plate = StickerPlate.none,
    this.face = StickerFace.serif,
    this.frame = PhotoFrame.none,
    this.frameDark = false,
    this.look = PhotoLook.original,
    this.grain = false,
    this.vignette = false,
  });

  StudioLook copyWith({
    StickerKind? Function()? kind,
    StickerInk? ink,
    StickerPlate? plate,
    StickerFace? face,
    PhotoFrame? frame,
    bool? frameDark,
    PhotoLook? look,
    bool? grain,
    bool? vignette,
  }) =>
      StudioLook(
        kind: kind != null ? kind() : this.kind,
        ink: ink ?? this.ink,
        plate: plate ?? this.plate,
        face: face ?? this.face,
        frame: frame ?? this.frame,
        frameDark: frameDark ?? this.frameDark,
        look: look ?? this.look,
        grain: grain ?? this.grain,
        vignette: vignette ?? this.vignette,
      );

  Map<String, Object?> toJson() => {
        'kind': kind?.name,
        'ink': ink.name,
        'plate': plate.name,
        'face': face.name,
        'frame': frame.name,
        'frameDark': frameDark,
        'look': look.name,
        'grain': grain,
        'vignette': vignette,
      };

  static E _pick<E extends Enum>(List<E> all, Object? name, E fallback) => all.where((e) => e.name == name).firstOrNull ?? fallback;

  factory StudioLook.fromJson(Map<String, dynamic> j) => StudioLook(
        kind: j['kind'] == null ? null : _pick(StickerKind.values, j['kind'], StickerKind.stats),
        ink: _pick(StickerInk.values, j['ink'], StickerInk.light),
        plate: _pick(StickerPlate.values, j['plate'], StickerPlate.none),
        face: _pick(StickerFace.values, j['face'], StickerFace.serif),
        frame: _pick(PhotoFrame.values, j['frame'], PhotoFrame.none),
        frameDark: j['frameDark'] == true,
        look: _pick(PhotoLook.values, j['look'], PhotoLook.original),
        grain: j['grain'] == true,
        vignette: j['vignette'] == true,
      );

  @override
  bool operator ==(Object other) => other is StudioLook && other.toJson().toString() == toJson().toString();
  @override
  int get hashCode => toJson().toString().hashCode;
}

/// Ready-made styles: a sticker, a frame and a look that belong together.
const studioStyles = <(String, StudioLook)>[
  ('Clean', StudioLook()),
  ('Print', StudioLook(kind: StickerKind.mark, frame: PhotoFrame.print, look: PhotoLook.warm)),
  ('Gallery', StudioLook(kind: StickerKind.caption, ink: StickerInk.dark, plate: StickerPlate.card, frame: PhotoFrame.inset, look: PhotoLook.mono)),
  ('Film', StudioLook(kind: StickerKind.datestamp, ink: StickerInk.amber, frame: PhotoFrame.film, look: PhotoLook.film, grain: true)),
  ('Polaroid', StudioLook(kind: null, frame: PhotoFrame.polaroid, look: PhotoLook.faded, grain: true)),
  ('Cinema', StudioLook(kind: null, frame: PhotoFrame.cinema, look: PhotoLook.cool, vignette: true)),
  ('Cover', StudioLook(kind: StickerKind.cover, look: PhotoLook.noir, vignette: true)),
  ('Ticket', StudioLook(kind: StickerKind.ticket, look: PhotoLook.golden)),
  ('Cellar', StudioLook(kind: StickerKind.label, frame: PhotoFrame.inset, frameDark: true, look: PhotoLook.warm, vignette: true)),
  ('Coaster', StudioLook(kind: StickerKind.coaster, ink: StickerInk.amber, look: PhotoLook.golden, vignette: true)),
  ('Tab', StudioLook(kind: StickerKind.receipt, look: PhotoLook.faded)),
  ('Menu', StudioLook(kind: StickerKind.menu, plate: StickerPlate.frost, look: PhotoLook.warm)),
  ('Late', StudioLook(kind: StickerKind.time, face: StickerFace.sans, look: PhotoLook.cool, grain: true, vignette: true)),
  ('Line', StudioLook(kind: StickerKind.line, plate: StickerPlate.frost, look: PhotoLook.film)),
];

// ── the picture ─────────────────────────────────────────────────────────────
/// The whole picture at [width]: background, the graded photo, the frame and its
/// caption, and the sticker at [at] (its home when null), sized by [scale] and turned
/// by [angle]. [stickerKey] marks the sticker alone, for a see-through export.
class Composition extends StatelessWidget {
  final NightStory story;
  final ImageProvider? photo;
  final StudioLook look;
  final double width;

  /// Width / height: 9/16 a Story, 4/5 a Post, 1 a Square.
  final double ratio;
  final List<Entry> diary;
  final Alignment? at;
  final double scale;
  final double angle;
  final GlobalKey? stickerKey;

  const Composition({
    super.key,
    required this.story,
    required this.photo,
    required this.look,
    required this.width,
    required this.ratio,
    this.diary = const [],
    this.at,
    this.scale = 1,
    this.angle = 0,
    this.stickerKey,
  });

  /// The photo's rectangle inside a picture of [size].
  static Rect photoRect(PhotoFrame f, Size size) => frameInsets(f, size, size.width / 360).deflateRect(Offset.zero & size);

  @override
  Widget build(BuildContext context) {
    final u = width / 360;
    final size = Size(width, width / ratio);
    final rect = photoRect(look.frame, size);
    final black = look.frame == PhotoFrame.film || look.frame == PhotoFrame.cinema || (frameHasTone(look.frame) && look.frameDark);
    final tone = black ? _blackFrame : _paperFrame;
    final onTone = black ? _onBlack : _onPaper;
    final plain = look.ink == StickerInk.dark ? paperTone : nightTone;

    Widget picture = photo == null ? ColoredBox(color: plain) : Image(image: photo!, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    final m = lookMatrix(look.look);
    if (photo != null && m != null) picture = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: picture);
    final radius = look.frame == PhotoFrame.inset ? 14 * u : (look.frame == PhotoFrame.polaroid || look.frame == PhotoFrame.print ? 1.5 * u : 0.0);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: ClipRect(
        child: Stack(children: [
          if (look.frame != PhotoFrame.none) Positioned.fill(child: ColoredBox(color: tone)),
          Positioned.fromRect(
            rect: rect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(fit: StackFit.expand, children: [
                picture,
                if (look.grain) CustomPaint(painter: GrainPainter(u)),
                if (look.vignette)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(radius: .95, colors: [Color(0x00000000), Color(0x8C000000)], stops: [.5, 1]),
                    ),
                  ),
              ]),
            ),
          ),
          ..._frameMarks(size, rect, u, onTone),
          if (look.kind != null)
            Positioned.fromRect(
              rect: rect.deflate(12 * u),
              child: Align(
                alignment: at ?? stickerHome[look.kind]!,
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(
                    scale: scale,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: RepaintBoundary(
                        key: stickerKey,
                        child: Padding(
                          padding: EdgeInsets.all(8 * u), // room for a tilted stamp or a shadow
                          child: Sticker(kind: look.kind!, story: story, ink: look.ink, plate: look.plate, face: look.face, u: u, diary: diary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  /// A frame's own marks: a print's caption, a Polaroid's line, film's sprockets and
  /// edge print, a cinema's subtitle, an inset card's small label.
  List<Widget> _frameMarks(Size size, Rect photo, double u, Color on) {
    final d = parseKey(story.dateKey);
    final dots = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final place = story.venue?.trim().isEmpty ?? true ? null : story.venue!.trim();
    final lead = leadLine(story);
    switch (look.frame) {
      case PhotoFrame.none:
        return const [];
      case PhotoFrame.print:
        return [
          Positioned(
            left: photo.left,
            right: size.width - photo.right,
            top: photo.bottom,
            bottom: 0,
            child: Row(children: [
              Expanded(child: Text(place ?? lead ?? 'A night out', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rawSerif(12.5 * u, on, italic: true))),
              SizedBox(width: 10 * u),
              Text(dots, style: T.rawMono(8.5 * u, on.withValues(alpha: .75))),
            ]),
          ),
        ];
      case PhotoFrame.polaroid:
        return [
          Positioned(
            left: photo.left + 4 * u,
            right: size.width - photo.right,
            top: photo.bottom + 16 * u,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lead ?? place ?? 'A night out', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rawSerif(23 * u, on, italic: true, height: 1.1)),
              SizedBox(height: 6 * u),
              Text([?place, dots].join('  ·  ').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rawSans(7.5 * u, on.withValues(alpha: .65), weight: FontWeight.w600, spacing: 1.4 * u)),
            ]),
          ),
        ];
      case PhotoFrame.film:
        final edge = BD.darkTokens.accent;
        return [
          Positioned.fill(child: CustomPaint(painter: _Sprockets(photo, u))),
          Positioned(
            left: 14 * u,
            top: photo.top - 13 * u,
            child: Text('BWDY 400', style: T.rawMono(7 * u, edge, weight: FontWeight.w500, spacing: 1 * u)),
          ),
          Positioned(
            right: 14 * u,
            top: photo.top - 13 * u,
            child: Text(dots, style: T.rawMono(7 * u, edge, weight: FontWeight.w500)),
          ),
          Positioned(
            left: 14 * u,
            top: photo.bottom + 4 * u,
            child: Row(children: [
              CustomPaint(size: Size(5 * u, 6 * u), painter: _Arrow(edge)),
              SizedBox(width: 3 * u),
              Text('${d.day}     ${d.day}A', style: T.rawMono(7 * u, edge, weight: FontWeight.w500, spacing: 1 * u)),
            ]),
          ),
        ];
      case PhotoFrame.cinema:
        return [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: photo.top,
            child: Center(child: Text('BREWDIARY  ·  $dots', style: T.rawSans(7 * u, on.withValues(alpha: .55), weight: FontWeight.w600, spacing: 2 * u))),
          ),
          Positioned(
            left: 24 * u,
            right: 24 * u,
            top: photo.bottom,
            bottom: 0,
            child: Center(
              child: Text(
                [?lead, ?place].join(' — '),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: T.rawSerif(14 * u, on, italic: true, height: 1.25),
              ),
            ),
          ),
        ];
      case PhotoFrame.inset:
        return [
          Positioned(
            left: 0,
            right: 0,
            top: photo.bottom,
            bottom: 0,
            child: Center(
              child: Text(
                [?(place == null ? null : shortPlace(place)), dots].join('  ·  ').toUpperCase(),
                style: T.rawSans(7.5 * u, on.withValues(alpha: .7), weight: FontWeight.w600, spacing: 2 * u),
              ),
            ),
          ),
        ];
    }
  }
}

/// Film grain: a fixed scatter of light and dark specks, so the same photo always
/// gets the same grain (and the export matches the preview).
class GrainPainter extends CustomPainter {
  final double u;
  GrainPainter(this.u);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(26);
    // x, y pairs: an even count.
    final n = (size.width * size.height / (7 * u * u)).clamp(200, 30000).toInt() ~/ 2 * 2;
    final light = Float32List(n), dark = Float32List(n);
    for (var i = 0; i < n; i += 2) {
      light[i] = r.nextDouble() * size.width;
      light[i + 1] = r.nextDouble() * size.height;
      dark[i] = r.nextDouble() * size.width;
      dark[i + 1] = r.nextDouble() * size.height;
    }
    final p = Paint()
      ..strokeWidth = .9 * u
      ..strokeCap = StrokeCap.round;
    canvas.drawRawPoints(ui.PointMode.points, light, p..color = Colors.white.withValues(alpha: .09));
    canvas.drawRawPoints(ui.PointMode.points, dark, p..color = Colors.black.withValues(alpha: .12));
  }

  @override
  bool shouldRepaint(GrainPainter o) => o.u != u;
}

/// The small arrow film prints beside a frame number.
class _Arrow extends CustomPainter {
  final Color color;
  _Arrow(this.color);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height)
          ..close(),
        Paint()..color = color,
      );

  @override
  bool shouldRepaint(_Arrow o) => o.color != color;
}

/// A strip of 35 mm film: the bright sprocket holes in the black edges.
class _Sprockets extends CustomPainter {
  final Rect photo;
  final double u;
  _Sprockets(this.photo, this.u);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = Paint()..color = const Color(0xFFE9E4DA).withValues(alpha: .92);
    final w = 8 * u, h = 11 * u, step = 17 * u;
    for (final y in [photo.top - 31 * u, photo.bottom + 18 * u]) {
      for (var x = 6 * u; x + w < size.width; x += step) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(1.6 * u)), hole);
      }
    }
  }

  @override
  bool shouldRepaint(_Sprockets o) => o.photo != photo || o.u != u;
}
