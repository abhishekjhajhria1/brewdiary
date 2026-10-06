// The twelve photo overlays. Each one is drawn in units of a 360-wide frame (u),
// so the on-screen preview, the little thumbnails and the 1080px export are the
// same picture at different sizes.
//
// The rules they keep:
//   • The photo is the hero. Type sits at the edges, in blocks, on a scrim only
//     where it needs one — never across a face.
//   • Big, confident type: one headline, a few small labels, nothing in between.
//   • Never the number of drinks as a headline stat. What's big is the place, the
//     night, the time, a first taste, the miles (which only variety earns).
//   • The brand is a hint: the small mosaic mark and the wordmark, once.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/game.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import '../theme.dart';
import '../widgets/game.dart' show RankEmblem, foilGradient, foil, foilHi, foilLo, cardInk, cardMuted, cardTop, cardBottom;
import 'photo_studio.dart' show NightStory, StoryLine;

/// The overlays, in the order they're offered.
const overlayNames = ['Route', 'Caption', 'Lineup', 'Cover', 'Receipt', 'Ticket', 'Stamp', 'Passport', 'Polaroid', 'Film', 'Postcard', 'Mosaic'];

/// When there's no photo yet: a warm night, out of focus.
class NightBackdrop extends StatelessWidget {
  final String seed;
  const NightBackdrop({super.key, required this.seed});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BackdropPainter(fnv1a(seed)), child: const SizedBox.expand());
}

class _BackdropPainter extends CustomPainter {
  final int seed;
  const _BackdropPainter(this.seed);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1C1310), Color(0xFF0E0B10), Color(0xFF07060A)]).createShader(r));
    final rnd = math.Random(seed);
    const tints = [Color(0xFFE6A64B), Color(0xFFF0C27A), Color(0xFFD9733A), Color(0xFFC94A6E), Color(0xFFFFE2B0)];
    for (var i = 0; i < 26; i++) {
      final c = Offset(rnd.nextDouble() * size.width, size.height * (.05 + rnd.nextDouble() * .62));
      final rad = size.width * (.03 + rnd.nextDouble() * .09);
      final tint = tints[rnd.nextInt(tints.length)];
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..shader = RadialGradient(colors: [tint.withValues(alpha: .38 + rnd.nextDouble() * .3), tint.withValues(alpha: .06)], stops: const [.55, 1]).createShader(Rect.fromCircle(center: c, radius: rad))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * .18),
      );
    }
    // a glow where a bar top would be
    canvas.drawRect(
      r,
      Paint()..shader = RadialGradient(center: const Alignment(0, .35), radius: .9, colors: [const Color(0xFFE6A64B).withValues(alpha: .22), Colors.transparent]).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter o) => o.seed != seed;
}

class Overlays {
  final double u;
  final NightStory s;
  final List<Entry> entries;
  late final PassportGame game = passportGame(entries);
  Overlays(this.u, this.s, this.entries);

  // ── palette ───────────────────────────────────────────────────────────────
  static const white = Color(0xFFFFFBF4);
  static const paper = Color(0xFFF7F2E8);
  static const ink = Color(0xFF17130F);
  static const inkSoft = Color(0xFF6B6158);
  static const amber = Color(0xFFE6A64B);
  static const amberDeep = Color(0xFFB06A1E);
  static const soft = [Shadow(color: Color(0x66000000), blurRadius: 16)];

  // ── type ──────────────────────────────────────────────────────────────────
  TextStyle sans(double size, {Color color = white, double weight = 600, double spacing = 0, double? height, bool shade = true}) => TextStyle(
        fontFamily: T.sansFamily, fontFamilyFallback: T.fallback,
        fontSize: size * u,
        color: color,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        fontVariations: [FontVariation('wght', weight)],
        letterSpacing: spacing * u,
        height: height,
        shadows: shade ? soft : null,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      );
  TextStyle serif(double size, {Color color = white, bool italic = false, double weight = 400, double height = 1.0, bool shade = true, double spacing = 0}) => TextStyle(
        fontFamily: T.serifFamily,
        fontSize: size * u,
        color: color,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        fontVariations: [FontVariation('wght', weight), FontVariation('opsz', math.min(72, size))],
        height: height,
        letterSpacing: spacing * u,
        shadows: shade ? soft : null,
      );
  TextStyle label({Color color = const Color(0xCCFFFFFF), double size = 8, bool shade = true}) => sans(size, color: color, weight: 650, spacing: size * .18, shade: shade);

  // ── the night, in words ───────────────────────────────────────────────────
  DateTime get date => parseKey(s.dateKey);
  String get day3 => const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][date.weekday - 1];
  String get mon3 => monthNames[date.month - 1].substring(0, 3).toUpperCase();
  String get dayMonth => '${date.day} $mon3';
  String get fullDate => '${date.day} $mon3 ${date.year}';
  String get heading => s.title ?? s.venue ?? (s.dry ? 'A dry night' : 'The night');
  String? get place => s.venue;
  List<StoryLine> get lines => s.lines.isEmpty ? [StoryLine(s.dry ? 'Nothing with alcohol' : heading)] : s.lines;
  List<String> get names => [for (final l in lines) l.name];
  String? get total => s.billTotal == null ? null : formatMoney(s.billTotal!, s.currency);
  String get people {
    final w = s.who;
    if (w.isEmpty) return (s.withPeople ?? 0) > 0 ? '${s.withPeople} friends' : 'Solo';
    if (w.length <= 2) return w.join(' & ');
    return '${w.take(2).join(', ')} +${w.length - 2}';
  }

  List<MileEvent> get tonight => [for (final e in game.ledger) if (e.date == s.dateKey) e];
  int get milesTonight => tonight.fold(0, (a, e) => a + e.miles);
  int get firstTastes => math.max(tonight.where((e) => e.source == MileSource.firstTaste).length, s.newToYou);
  int get nightsKept => stats(entries).current;
  int get daysLogged => loggedDates(entries).length;

  /// The best small number for tonight: miles if any, else first tastes, else company.
  (String, String) get bestStat => milesTonight > 0
      ? ('MILES', '+$milesTonight')
      : firstTastes > 0
          ? ('FIRST TASTES', '$firstTastes')
          : ('WITH', s.who.isEmpty && (s.withPeople ?? 0) == 0 ? 'Solo' : '${s.withPeople ?? s.who.length}');

  // ── shared pieces ─────────────────────────────────────────────────────────
  Widget mark({Color color = white, double scale = 1, bool shade = true}) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 10 * u * scale,
          height: 10 * u * scale,
          child: CustomPaint(painter: _MarkPainter()),
        ),
        SizedBox(width: 5 * u * scale),
        Text('brewdiary', style: serif(12.5 * scale, color: color, italic: true, shade: shade)),
      ]);

  Widget scrim({bool top = false, double strength = .75, double reach = .6}) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: strength), Colors.black.withValues(alpha: strength * .45), Colors.black.withValues(alpha: 0)],
            stops: [0, reach * .55, reach],
          ),
        ),
      );

  Widget stat(String label, String value, {Color color = white, double size = 30, CrossAxisAlignment align = CrossAxisAlignment.start}) => Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: this.label(size: 7.5)),
        SizedBox(height: 3 * u),
        Text(value, maxLines: 1, style: sans(size, color: color, weight: 700, height: 1)),
      ]);

  EdgeInsets get m => EdgeInsets.all(22 * u);

  // ── 0 · Route — the run-app overlay, for a night ─────────────────────────
  Widget route() {
    final (bl, bv) = bestStat;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .82, reach: .62),
      Positioned(left: 22 * u, top: 20 * u, child: mark()),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        bottom: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 74 * u,
            child: CustomPaint(painter: _RoutePainter(fnv1a(s.dateKey), math.max(2, lines.length), u)),
          ),
          SizedBox(height: 12 * u),
          Text([day3, dayMonth, ?place].join('  ·  ').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: label(color: amber, size: 8.5)),
          SizedBox(height: 6 * u),
          Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(32, weight: 450, height: 1.05)),
          SizedBox(height: 14 * u),
          Container(height: .8 * u, color: Colors.white.withValues(alpha: .25)),
          SizedBox(height: 12 * u),
          Row(children: [
            Expanded(child: stat('STARTED', s.time ?? '—')),
            Expanded(child: stat('TRIED', names.length == 1 ? names.first.split(' ').first : '${names.length} kinds', size: names.length == 1 ? 22 : 30)),
            Expanded(child: stat(bl, bv, color: bl == 'MILES' ? amber : white)),
          ]),
        ]),
      ),
    ]);
  }

  // ── 1 · Caption — small, clean, bottom-left ──────────────────────────────
  Widget caption() {
    final shown = names.take(4).toList();
    final more = names.length - shown.length;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .55, reach: .5),
      Positioned(
        left: 24 * u,
        right: 24 * u,
        bottom: 24 * u,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final n in shown) Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(19, weight: 600, height: 1.22)),
              if (more > 0) Text('and $more more', style: sans(13, color: const Color(0xB3FFFFFF), weight: 500, height: 1.4)),
              SizedBox(height: 10 * u),
              Container(width: 26 * u, height: 2 * u, color: amber),
              SizedBox(height: 10 * u),
              Text([?place, ?s.time, dayMonth].join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(10.5, color: const Color(0xD9FFFFFF), weight: 500)),
            ]),
          ),
          SizedBox(width: 12 * u),
          mark(scale: .9),
        ]),
      ),
    ]);
  }

  // ── 2 · Lineup — a festival bill ─────────────────────────────────────────
  Widget lineup() {
    final head = names.first;
    final rest = names.skip(1).take(6).toList();
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .9, reach: .72),
      Positioned(
        left: 20 * u,
        right: 20 * u,
        bottom: 24 * u,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('BREWDIARY PRESENTS', style: label(color: amber, size: 8)),
          SizedBox(height: 10 * u),
          SizedBox(
            width: double.infinity,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(head.toUpperCase(), maxLines: 1, style: sans(52, weight: 850, spacing: -1.2, height: .95))),
          ),
          if (rest.isNotEmpty) ...[
            SizedBox(height: 10 * u),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8 * u,
              runSpacing: 4 * u,
              children: [
                for (var i = 0; i < rest.length; i++) ...[
                  Text(rest[i].toUpperCase(), style: sans(i < 2 ? 18 : 14, weight: 750, spacing: .2)),
                  if (i < rest.length - 1) Text('•', style: sans(i < 2 ? 18 : 14, color: amber, weight: 700)),
                ],
              ],
            ),
          ],
          SizedBox(height: 16 * u),
          Container(height: .8 * u, color: Colors.white.withValues(alpha: .3)),
          SizedBox(height: 10 * u),
          Text(['$day3 $dayMonth', ?place, if (s.time != null) 'DOORS ${s.time}'].join('   ·   ').toUpperCase(), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: label(size: 8)),
        ]),
      ),
    ]);
  }

  // ── 3 · Cover — a magazine cover ─────────────────────────────────────────
  Widget cover() {
    final t = total;
    return Stack(fit: StackFit.expand, children: [
      scrim(top: true, strength: .6, reach: .4),
      scrim(strength: .78, reach: .55),
      Positioned(
        left: 18 * u,
        right: 18 * u,
        top: 14 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FittedBox(fit: BoxFit.fitWidth, child: Text('brewdiary', style: serif(80, italic: true, weight: 500, height: .95, spacing: -1.5))),
          SizedBox(height: 2 * u),
          Row(children: [
            Text('ISSUE NO. $daysLogged', style: label(size: 7.5)),
            const Spacer(),
            Text('${monthNames[date.month - 1].toUpperCase()} ${date.year}', style: label(size: 7.5)),
          ]),
          SizedBox(height: 5 * u),
          Container(height: .8 * u, color: Colors.white.withValues(alpha: .5)),
        ]),
      ),
      if (t != null)
        Positioned(
          right: 22 * u,
          top: 132 * u,
          child: Transform.rotate(
            angle: .18,
            child: Container(
              width: 74 * u,
              height: 74 * u,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: amber, shape: BoxShape.circle),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('THE BILL', style: sans(7, color: ink, weight: 750, spacing: 1, shade: false)),
                SizedBox(height: 2 * u),
                Text(t, style: serif(16, color: ink, weight: 600, shade: false)),
              ]),
            ),
          ),
        ),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        bottom: 24 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('TONIGHT\'S STORY', style: label(color: amber, size: 8)),
          SizedBox(height: 6 * u),
          Text(heading, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(44, italic: true, weight: 420, height: .98)),
          SizedBox(height: 10 * u),
          Text(
            names.length > 1 ? 'Inside: ${names.take(2).join(', ')}${names.length > 2 ? ' & more' : ''}' : (s.note ?? 'Inside: ${names.first}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: sans(12.5, weight: 500, height: 1.35),
          ),
          if (place != null) ...[
            SizedBox(height: 4 * u),
            Text('At $place', maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(12.5, color: const Color(0xBFFFFFFF), weight: 500)),
          ],
        ]),
      ),
    ]);
  }

  // ── 4 · Receipt ───────────────────────────────────────────────────────────
  Widget receipt() {
    final shown = lines.take(6).toList();
    final more = lines.length - shown.length;
    final t = total;
    TextStyle r(double size, {double weight = 500, Color color = ink, double spacing = .4}) => sans(size, color: color, weight: weight, spacing: spacing, shade: false, height: 1.25);
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .4, reach: .5),
      Positioned(
        right: 22 * u,
        bottom: 26 * u,
        width: 196 * u,
        child: Transform.rotate(
          angle: -2 * math.pi / 180,
          child: DecoratedBox(
            decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 24 * u, offset: Offset(0, 10 * u))]),
            child: ClipPath(
              clipper: _Zigzag(4 * u),
              child: Container(
                color: paper,
                padding: EdgeInsets.fromLTRB(16 * u, 18 * u, 16 * u, 16 * u),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Text((place ?? 'The night').toUpperCase(), textAlign: TextAlign.center, maxLines: 2, style: r(11, weight: 800, spacing: 1.2)),
                  SizedBox(height: 3 * u),
                  Text([fullDate, ?s.time].join('   '), textAlign: TextAlign.center, style: r(8, color: inkSoft)),
                  SizedBox(height: 9 * u),
                  _dashes(),
                  SizedBox(height: 8 * u),
                  for (final l in shown)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 1.6 * u),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 18 * u, child: Text('${l.qty}×', style: r(9, color: inkSoft))),
                        Expanded(child: Text(l.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: r(9, weight: 600))),
                        if (l.price != null) Text(formatMoney(l.price! * l.qty, s.currency), style: serif(10, color: ink, shade: false, weight: 500)),
                      ]),
                    ),
                  if (more > 0) Text('+ $more MORE', style: r(8, color: inkSoft)),
                  SizedBox(height: 8 * u),
                  _dashes(),
                  SizedBox(height: 8 * u),
                  if (t != null)
                    Row(children: [
                      Text('TOTAL', style: r(11, weight: 800, spacing: 1.4)),
                      const Spacer(),
                      Text(t, style: serif(17, color: ink, shade: false, weight: 600)),
                    ]),
                  if (t != null) SizedBox(height: 6 * u),
                  Row(children: [
                    Text(firstTastes > 0 ? 'FIRST TASTES  $firstTastes' : 'WITH  ${people.toUpperCase()}', style: r(7.5, color: inkSoft, weight: 600, spacing: .8)),
                    const Spacer(),
                    if (milesTonight > 0) Text('+$milesTonight MI', style: r(7.5, color: amberDeep, weight: 800, spacing: .8)),
                  ]),
                  SizedBox(height: 10 * u),
                  SizedBox(height: 24 * u, child: CustomPaint(painter: _Barcode(fnv1a(s.dateKey), ink))),
                  SizedBox(height: 8 * u),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [mark(color: ink, scale: .8, shade: false)]),
                  SizedBox(height: 2 * u),
                  Text('DRINK WIDELY', textAlign: TextAlign.center, style: r(6.5, color: inkSoft, weight: 600, spacing: 2)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _dashes({Color color = inkSoft}) => LayoutBuilder(builder: (_, c) {
        final n = (c.maxWidth / (6 * u)).floor();
        return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (var i = 0; i < n; i++) Container(width: 3 * u, height: .9 * u, color: color)]);
      });

  // ── 5 · Ticket ────────────────────────────────────────────────────────────
  Widget ticket() {
    final stubW = 64 * u;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .45, reach: .45),
      Positioned(
        left: 18 * u,
        right: 18 * u,
        bottom: 24 * u,
        height: 132 * u,
        child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 22 * u, offset: Offset(0, 8 * u))]),
          child: LayoutBuilder(builder: (context, c) {
            final cut = c.maxWidth - stubW;
            return ClipPath(
              clipper: _TicketClip(stubAt: cut, notch: 9 * u, radius: 12 * u),
              child: Container(
                color: paper,
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(18 * u, 14 * u, 14 * u, 14 * u),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('ADMIT ONE', style: sans(8, color: amberDeep, weight: 800, spacing: 1.8, shade: false)),
                          const Spacer(),
                          mark(color: ink, scale: .75, shade: false),
                        ]),
                        SizedBox(height: 8 * u),
                        Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(27, color: ink, shade: false, weight: 450)),
                        const Spacer(),
                        Row(children: [
                          _tField('DATE', '$day3 $dayMonth'),
                          SizedBox(width: 14 * u),
                          _tField('DOORS', s.time ?? '—'),
                          SizedBox(width: 14 * u),
                          Expanded(child: _tField('AT', place ?? 'Somewhere good')),
                        ]),
                      ]),
                    ),
                  ),
                  CustomPaint(size: Size(1, 132 * u), painter: _Perforation(u, inkSoft.withValues(alpha: .6))),
                  SizedBox(
                    width: stubW,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14 * u, horizontal: 10 * u),
                      child: Column(children: [
                        Text('No.', style: sans(7, color: inkSoft, weight: 600, shade: false)),
                        Text(daysLogged.toString().padLeft(3, '0'), style: sans(15, color: ink, weight: 800, shade: false)),
                        SizedBox(height: 6 * u),
                        Expanded(child: CustomPaint(size: Size(28 * u, double.infinity), painter: _Barcode(fnv1a('t${s.dateKey}'), ink, vertical: true))),
                      ]),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
      ),
    ]);
  }

  Widget _tField(String l, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(l, style: sans(6.5, color: inkSoft, weight: 700, spacing: 1.2, shade: false)),
        SizedBox(height: 2 * u),
        Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11, color: ink, weight: 700, shade: false)),
      ]);

  // ── 6 · Stamp — a passport entry stamp, in amber ink ─────────────────────
  Widget stamp() {
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .62, reach: .5),
      Positioned(
        right: 14 * u,
        bottom: 18 * u,
        child: Transform.rotate(
          angle: -14 * math.pi / 180,
          child: SizedBox(
            width: 168 * u,
            height: 168 * u,
            child: CustomPaint(
              painter: _RubberStamp(
                u: u,
                top: (place ?? 'THE NIGHT').toUpperCase(),
                bottom: 'ENTRY  ·  TASTE PASSPORT',
                seed: fnv1a(s.dateKey),
                center: fullDate,
                sub: [?s.time, if (firstTastes > 0) '$firstTastes NEW'].join('  ·  '),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 22 * u,
        bottom: 26 * u,
        width: 150 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final n in names.take(3)) Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(15, weight: 600, height: 1.3)),
          SizedBox(height: 10 * u),
          mark(scale: .85),
        ]),
      ),
    ]);
  }

  // ── 7 · Passport — the card, as a sticker ────────────────────────────────
  Widget passportCard() {
    final g = game;
    final firsts = tonight.where((e) => e.source == MileSource.firstTaste || e.source == MileSource.newPlace || e.source == MileSource.season).take(3).toList();
    final mi = milesTonight;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .55, reach: .55),
      Positioned(
        left: 20 * u,
        right: 20 * u,
        bottom: 22 * u,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18 * u),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 24 * u, offset: Offset(0, 8 * u))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18 * u),
            child: CustomPaint(
              painter: _MiniCardGround(),
              child: Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18 * u), border: Border.all(color: foil.withValues(alpha: .45), width: .8 * u)),
                padding: EdgeInsets.fromLTRB(16 * u, 14 * u, 16 * u, 14 * u),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Text('TASTE PASSPORT', style: sans(7.5, color: foil, weight: 750, spacing: 1.8, shade: false)),
                    const Spacer(),
                    Text('brewdiary', style: serif(11, color: cardMuted, italic: true, shade: false)),
                  ]),
                  SizedBox(height: 10 * u),
                  Row(children: [
                    SizedBox(width: 50 * u, height: 50 * u, child: FittedBox(child: RankEmblem(g.rank.index, size: 50))),
                    SizedBox(width: 12 * u),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.rank.title, style: serif(26, color: cardInk, shade: false)),
                        SizedBox(height: 2 * u),
                        Text([fullDate, ?place].join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(9, color: cardMuted, weight: 500, shade: false)),
                      ]),
                    ),
                    if (mi > 0)
                      ShaderMask(
                        shaderCallback: (r) => foilGradient.createShader(r),
                        child: Text('+$mi', style: serif(30, color: Colors.white, shade: false, weight: 500)),
                      ),
                  ]),
                  SizedBox(height: 10 * u),
                  Container(height: .8 * u, color: foil.withValues(alpha: .25)),
                  SizedBox(height: 8 * u),
                  if (firsts.isEmpty)
                    Text(names.take(3).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(10.5, color: cardInk, weight: 550, shade: false))
                  else
                    Wrap(spacing: 6 * u, runSpacing: 5 * u, children: [
                      for (final e in firsts)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 7 * u, vertical: 3 * u),
                          decoration: BoxDecoration(
                            gradient: e.gilded ? foilGradient : null,
                            color: e.gilded ? null : foil.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(6 * u),
                            border: Border.all(color: foil.withValues(alpha: .55), width: .7 * u),
                          ),
                          child: Text(
                            switch (e.source) { MileSource.newPlace => 'New place · ${e.label}', MileSource.season => e.label, _ => 'First · ${e.label}' },
                            style: sans(9, color: e.gilded ? ink : foilHi, weight: 700, shade: false),
                          ),
                        ),
                    ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  // ── 8 · Polaroid ──────────────────────────────────────────────────────────
  Widget polaroid(Widget bg) {
    return Stack(fit: StackFit.expand, children: [
      const NightBackdrop(seed: 'polaroid'),
      Container(color: const Color(0x66000000)),
      Center(
        child: Transform.rotate(
          angle: -2.2 * math.pi / 180,
          child: Container(
            width: 300 * u,
            padding: EdgeInsets.fromLTRB(14 * u, 14 * u, 14 * u, 0),
            decoration: BoxDecoration(color: paper, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 26 * u, offset: Offset(0, 10 * u))]),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(aspectRatio: 1, child: ClipRect(child: bg)),
              SizedBox(
                height: 78 * u,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(4 * u, 12 * u, 4 * u, 10 * u),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(24, color: ink, italic: true, shade: false, weight: 420)),
                    const Spacer(),
                    Row(children: [
                      Expanded(child: Text([?place, dayMonth].join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(9, color: inkSoft, weight: 600, spacing: .6, shade: false))),
                      mark(color: ink, scale: .75, shade: false),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── 9 · Film ──────────────────────────────────────────────────────────────
  Widget film(Widget bg) {
    const orange = Color(0xFFFF8A3D);
    Widget sprockets() => SizedBox(
          height: 22 * u,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < 12; i++) Container(width: 12 * u, height: 8 * u, decoration: BoxDecoration(color: const Color(0xFFEDE6DA), borderRadius: BorderRadius.circular(2 * u))),
          ]),
        );
    final yy = (date.year % 100).toString().padLeft(2, '0');
    return Container(
      color: const Color(0xFF0D0B0A),
      child: Column(children: [
        sprockets(),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * u),
          child: Row(children: [
            Text('BREWDIARY 400', style: sans(7, color: orange.withValues(alpha: .8), weight: 700, spacing: 1.4, shade: false)),
            const Spacer(),
            Text('▸ ${daysLogged.toString().padLeft(2, '0')}A', style: sans(7, color: orange.withValues(alpha: .8), weight: 700, spacing: 1.4, shade: false)),
          ]),
        ),
        SizedBox(height: 4 * u),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * u),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3 * u),
              child: Stack(fit: StackFit.expand, children: [
                bg,
                Positioned(
                  right: 12 * u,
                  bottom: 10 * u,
                  child: Text(
                    "'$yy ${date.month} ${date.day}",
                    style: sans(17, color: orange, weight: 700, spacing: 1.5, shade: false).copyWith(shadows: [Shadow(color: orange.withValues(alpha: .8), blurRadius: 8 * u)]),
                  ),
                ),
              ]),
            ),
          ),
        ),
        SizedBox(height: 8 * u),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * u),
          child: Row(children: [
            Expanded(child: Text(names.take(3).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(13, color: const Color(0xFFEDE6DA), italic: true, shade: false))),
            SizedBox(width: 10 * u),
            Text(place ?? '', maxLines: 1, style: sans(8.5, color: const Color(0xFF9C948A), weight: 600, spacing: .8, shade: false)),
          ]),
        ),
        SizedBox(height: 4 * u),
        sprockets(),
      ]),
    );
  }

  // ── 10 · Postcard ─────────────────────────────────────────────────────────
  Widget postcard(Widget bg) {
    return Container(
      color: paper,
      child: Stack(children: [
        Column(children: [
          Expanded(flex: 62, child: SizedBox.expand(child: bg)),
          Expanded(
            flex: 38,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20 * u, 30 * u, 20 * u, 16 * u),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(
                        s.note ?? (names.length > 1 ? 'Had ${names.take(2).join(' and ')}. Wish you were here.' : 'Wish you were here.'),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: serif(13.5, color: ink, italic: true, shade: false, height: 1.3),
                      ),
                    ),
                    mark(color: ink, scale: .8, shade: false),
                  ]),
                ),
                Container(width: .8 * u, margin: EdgeInsets.symmetric(horizontal: 14 * u), color: inkSoft.withValues(alpha: .4)),
                Expanded(
                  flex: 2,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Container(
                      width: 42 * u,
                      height: 50 * u,
                      padding: EdgeInsets.all(3 * u),
                      decoration: BoxDecoration(border: Border.all(color: amberDeep, width: 1 * u)),
                      child: CustomPaint(painter: _MarkPainter(), child: const SizedBox.expand()),
                    ),
                    const Spacer(),
                    Container(height: .8 * u, color: inkSoft.withValues(alpha: .4)),
                    SizedBox(height: 5 * u),
                    Align(alignment: Alignment.centerLeft, child: Text(fullDate, style: sans(8.5, color: inkSoft, weight: 600, shade: false))),
                    SizedBox(height: 5 * u),
                    Container(height: .8 * u, color: inkSoft.withValues(alpha: .4)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
        Positioned(
          left: 20 * u,
          right: 20 * u,
          top: 450 * .62 * u - 46 * u,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Greetings from', style: serif(16, italic: true)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(place ?? heading, maxLines: 1, style: serif(46, weight: 600, height: 1, color: amber).copyWith(shadows: [Shadow(color: Colors.black.withValues(alpha: .55), blurRadius: 14 * u, offset: Offset(0, 2 * u))])),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── 11 · Mosaic — the month, as the app draws it ─────────────────────────
  Widget mosaic() {
    final counts = countsByDate(entries);
    final grid = monthGrid(date.year, date.month - 1);
    final weeks = (grid.length / 7).ceil();
    final lastRow = [for (var w = weeks - 1; w >= 0; w--) if (grid.skip(w * 7).take(7).any((d) => d.inMonth)) w].first;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .6, reach: .62),
      Positioned(
        left: 18 * u,
        right: 18 * u,
        bottom: 20 * u,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18 * u),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: EdgeInsets.all(16 * u),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .42),
                borderRadius: BorderRadius.circular(18 * u),
                border: Border.all(color: Colors.white.withValues(alpha: .16), width: .8 * u),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(monthNames[date.month - 1].toUpperCase(), style: label(color: amber, size: 8)),
                    SizedBox(height: 6 * u),
                    Text(heading, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(24, height: 1.05)),
                    SizedBox(height: 10 * u),
                    Text(nightsKept > 1 ? '$nightsKept nights kept' : 'Every night counts', style: sans(10.5, color: const Color(0xD9FFFFFF), weight: 600)),
                    Text('dry ones too', style: sans(9.5, color: const Color(0x99FFFFFF), weight: 500)),
                    SizedBox(height: 12 * u),
                    mark(scale: .8),
                  ]),
                ),
                SizedBox(width: 12 * u),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var w = 0; w <= lastRow; w++)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final d in grid.skip(w * 7).take(7))
                        Container(
                          width: 15 * u,
                          height: 15 * u,
                          margin: EdgeInsets.all(1.5 * u),
                          decoration: BoxDecoration(
                            color: !d.inMonth
                                ? Colors.transparent
                                : (counts[d.key] ?? 0) == 0
                                    ? Colors.white.withValues(alpha: .08)
                                    : amber.withValues(alpha: const [0.0, .35, .55, .78, 1.0][intensityLevel(counts[d.key]!)]),
                            borderRadius: BorderRadius.circular(3.5 * u),
                            border: d.key == s.dateKey ? Border.all(color: white, width: 1.2 * u) : null,
                            boxShadow: d.inMonth && (counts[d.key] ?? 0) >= 3 ? [BoxShadow(color: amber.withValues(alpha: .5), blurRadius: 5 * u)] : null,
                          ),
                        ),
                    ]),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ── painters ────────────────────────────────────────────────────────────────

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final g = size.shortestSide * .12;
    final cell = (size.shortestSide - g) / 2;
    const a = [.4, .65, .85, 1.0];
    for (var i = 0; i < 4; i++) {
      final r = Rect.fromLTWH((i % 2) * (cell + g), (i ~/ 2) * (cell + g), cell, cell);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * .22)), Paint()..color = Overlays.amber.withValues(alpha: a[i]));
    }
  }

  @override
  bool shouldRepaint(_MarkPainter o) => false;
}

/// A night's "route": one point per thing you had, a smooth amber line between
/// them, start hollow and finish filled — the run-app trace, for an evening.
class _RoutePainter extends CustomPainter {
  final int seed;
  final int points;
  final double u;
  const _RoutePainter(this.seed, this.points, this.u);
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final n = points.clamp(2, 8);
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = size.width * (.04 + .92 * i / (n - 1));
      final y = size.height * (.2 + rnd.nextDouble() * .6);
      pts.add(Offset(x, y));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx + (mid.dx - a.dx) * 1.2, a.dy, mid.dx, mid.dy);
      path.quadraticBezierTo(b.dx - (b.dx - mid.dx) * 1.2, b.dy, b.dx, b.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7 * u
        ..strokeCap = StrokeCap.round
        ..color = Overlays.amber.withValues(alpha: .25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * u),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * u
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Overlays.amber,
    );
    for (var i = 1; i < pts.length - 1; i++) {
      canvas.drawCircle(pts[i], 3.2 * u, Paint()..color = Overlays.white);
    }
    canvas.drawCircle(pts.first, 5.5 * u, Paint()..color = Colors.black);
    canvas.drawCircle(
      pts.first,
      5.5 * u,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * u
        ..color = Overlays.white,
    );
    canvas.drawCircle(pts.last, 6.5 * u, Paint()..color = Overlays.white);
    canvas.drawCircle(pts.last, 3 * u, Paint()..color = Overlays.amber);
  }

  @override
  bool shouldRepaint(_RoutePainter o) => o.seed != seed || o.points != points || o.u != u;
}

/// A rubber stamp: two rings, text around the rim, the date in the middle, and
/// a little ink texture so it reads as pressed, not printed.
class _RubberStamp extends CustomPainter {
  final double u;
  final String top;
  final String bottom;
  final String center;
  final String sub;
  final int seed;
  const _RubberStamp({required this.u, required this.top, required this.bottom, required this.center, required this.sub, required this.seed});

  static const ink = Color(0xFFF0A947);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.saveLayer(Offset.zero & size, Paint());
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = ink;
    canvas.drawCircle(c, r - 2 * u, ring..strokeWidth = 3 * u);
    canvas.drawCircle(c, r - 8 * u, ring..strokeWidth = 1 * u);
    canvas.drawCircle(c, r * .6, ring..strokeWidth = 1.2 * u);
    _arc(canvas, c, r - 19 * u, top.length > 22 ? '${top.substring(0, 21)}…' : top, 11.5 * u, true);
    _arc(canvas, c, r - 19 * u, bottom, 7.5 * u, false);
    // stars between the two arcs
    for (final a in [math.pi, 0.0]) {
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 17 * u);
      canvas.drawCircle(p, 2 * u, Paint()..color = ink);
    }
    _text(canvas, center, c.translate(0, -4 * u), 11.5 * u, FontWeight.w800, .8);
    if (sub.isNotEmpty) _text(canvas, sub, c.translate(0, 11 * u), 7 * u, FontWeight.w700, 1.2);
    // ink texture: knock out tiny specks
    final rnd = math.Random(seed);
    final knock = Paint()..blendMode = BlendMode.dstOut;
    for (var i = 0; i < 420; i++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawCircle(p, (.4 + rnd.nextDouble() * 1.1) * u, knock..color = Colors.black.withValues(alpha: .35 + rnd.nextDouble() * .5));
    }
    canvas.restore();
  }

  void _text(Canvas canvas, String s, Offset at, double size, FontWeight w, double spacing) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: T.sansFamily, fontFamilyFallback: T.fallback, fontSize: size, color: ink, fontWeight: w, fontVariations: [FontVariation('wght', w.value.toDouble())], letterSpacing: spacing * u)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  void _arc(Canvas canvas, Offset c, double radius, String s, double size, bool top) {
    final style = TextStyle(fontFamily: T.sansFamily, fontFamilyFallback: T.fallback, fontSize: size, color: ink, fontWeight: FontWeight.w800, fontVariations: const [FontVariation('wght', 800)], letterSpacing: 1.6 * u);
    final glyphs = [
      for (final ch in s.characters) TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout(),
    ];
    final total = glyphs.fold<double>(0, (a, g) => a + g.width + 1.6 * u);
    final sweep = total / radius;
    var a = top ? -math.pi / 2 - sweep / 2 : math.pi / 2 + sweep / 2;
    for (final g in glyphs) {
      final step = (g.width + 1.6 * u) / radius;
      final mid = top ? a + step / 2 : a - step / 2;
      final p = c + Offset(math.cos(mid), math.sin(mid)) * radius;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(top ? mid + math.pi / 2 : mid - math.pi / 2);
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
      canvas.restore();
      a = top ? a + step : a - step;
    }
  }

  @override
  bool shouldRepaint(_RubberStamp o) => o.top != top || o.center != center || o.sub != sub || o.u != u;
}

class _MiniCardGround extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cardTop, cardBottom]).createShader(r));
    canvas.drawRect(r, Paint()..shader = RadialGradient(center: const Alignment(-.8, -.3), radius: .9, colors: [foil.withValues(alpha: .2), Colors.transparent]).createShader(r));
    final c = Offset(size.width * .95, size.height * .7);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = foil.withValues(alpha: .08);
    for (var k = 0; k < 12; k++) {
      final base = size.height * (.25 + k * .07);
      final path = Path();
      for (var i = 0; i <= 140; i++) {
        final th = i / 140 * math.pi * 2;
        final rr = base + size.height * .04 * math.sin(th * 9 + k * .55);
        final p = c + Offset(math.cos(th) * rr, math.sin(th) * rr);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, line);
    }
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [foilHi.withValues(alpha: 0), foilLo.withValues(alpha: 0)]).createShader(r));
  }

  @override
  bool shouldRepaint(_MiniCardGround o) => false;
}

class _Zigzag extends CustomClipper<Path> {
  final double tooth;
  _Zigzag(this.tooth);
  @override
  Path getClip(Size s) {
    final n = (s.width / (tooth * 2)).ceil();
    final w = s.width / n;
    final p = Path()..moveTo(0, tooth);
    for (var i = 0; i < n; i++) {
      p
        ..lineTo(i * w + w / 2, 0)
        ..lineTo((i + 1) * w, tooth);
    }
    p.lineTo(s.width, s.height - tooth);
    for (var i = n; i > 0; i--) {
      p
        ..lineTo(i * w - w / 2, s.height)
        ..lineTo((i - 1) * w, s.height - tooth);
    }
    return p..close();
  }

  @override
  bool shouldReclip(_Zigzag old) => old.tooth != tooth;
}

class _TicketClip extends CustomClipper<Path> {
  final double stubAt, notch, radius;
  _TicketClip({required this.stubAt, required this.notch, required this.radius});
  @override
  Path getClip(Size s) {
    final body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(radius)));
    final cuts = Path()
      ..addOval(Rect.fromCircle(center: Offset(stubAt, 0), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(stubAt, s.height), radius: notch));
    return Path.combine(PathOperation.difference, body, cuts);
  }

  @override
  bool shouldReclip(_TicketClip old) => old.stubAt != stubAt || old.notch != notch;
}

class _Perforation extends CustomPainter {
  final double u;
  final Color color;
  _Perforation(this.u, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var y = 14 * u; y < size.height - 12 * u; y += 7 * u) {
      canvas.drawCircle(Offset(0, y), 1.3 * u, p);
    }
  }

  @override
  bool shouldRepaint(_Perforation old) => false;
}

/// Bars from a seed: the same night always gets the same barcode.
class _Barcode extends CustomPainter {
  final int seed;
  final Color color;
  final bool vertical;
  _Barcode(this.seed, this.color, {this.vertical = false});
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final p = Paint()..color = color;
    final length = vertical ? size.height : size.width;
    final unit = length / 96;
    var x = 0.0;
    var bar = true;
    while (x < length) {
      final w = math.min(unit * (1 + r.nextInt(bar ? 3 : 2)), length - x);
      if (bar) canvas.drawRect(vertical ? Rect.fromLTWH(0, x, size.width, w) : Rect.fromLTWH(x, 0, w, size.height), p);
      x += w;
      bar = !bar;
    }
  }

  @override
  bool shouldRepaint(_Barcode old) => old.seed != seed;
}
