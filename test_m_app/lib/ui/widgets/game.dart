// The passport game, drawn. The rules live in brewdiary_core/game.dart (derived
// from the diary, never stored); this is how they look: the passport card (a dark
// metal card with a security-print pattern and amber foil), rank emblems, the
// week's quests, the season stamp, collections, feats, and the little moment after
// a save that earned something.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/game.dart';
import '../theme.dart';
import 'common.dart';

// ── the card's own palette: a dark metal card in both themes ────────────────
const cardTop = Color(0xFF221A12);
const cardBottom = Color(0xFF0B0907);
const foilHi = Color(0xFFFBE3B0);
const foil = Color(0xFFE6A64B);
const foilLo = Color(0xFF9C6119);
const cardInk = Color(0xFFF5EEE3);
const cardMuted = Color(0xFFB9AC9A);

const foilGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [foilHi, foil, foilLo], stops: [0, .45, 1]);

const _roman = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

TextStyle _cs(double size, Color color, {FontWeight weight = FontWeight.w600, double spacing = 0}) =>
    T.rawSans(size, color, weight: weight, spacing: spacing);

String kindTitle(String kind) => switch (kind) {
      'coffee' => 'Coffee',
      'tea' => 'Tea',
      'soft' => 'Soft drinks',
      'beer' => 'Beer',
      'wine' => 'Wine',
      'cocktail' => 'Cocktails',
      'spirit' => 'Spirits',
      _ => kind,
    };

String mileLine(MileEvent e) => switch (e.source) {
      MileSource.firstTaste => 'First taste · ${e.label}',
      MileSource.newKind => 'New kind · ${kindTitle(e.label)}',
      MileSource.newPlace => 'New place · ${e.label}',
      MileSource.dryNight => 'Dry night',
      MileSource.collection => 'Set complete · ${e.label}',
      MileSource.quest => 'Quest · ${e.label}',
      MileSource.season => 'Season stamp · ${e.label}',
    };

IconData mileIcon(MileSource s) => switch (s) {
      MileSource.firstTaste => Ph.sparkle,
      MileSource.newKind => Ph.squaresFour,
      MileSource.newPlace => Ph.mapPin,
      MileSource.dryNight => Ph.moon,
      MileSource.collection => Ph.sealCheck,
      MileSource.quest => Ph.target,
      MileSource.season => Ph.sun,
    };

// ── rank emblem ──────────────────────────────────────────────────────────────
/// An octagon in foil with one lit point per rank climbed and the numeral inside.
class RankEmblem extends StatelessWidget {
  final int index;
  final double size;
  final bool locked;
  final Color? lockedColor;
  const RankEmblem(this.index, {super.key, this.size = 56, this.locked = false, this.lockedColor});
  @override
  Widget build(BuildContext context) {
    final lc = lockedColor ?? context.bd.faint;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EmblemPainter(index, locked, lc),
        child: Center(
          child: Text(
            _roman[index.clamp(0, 7)],
            style: T.rawSerif(size * .3, locked ? lc : foilHi, weight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

Path _octagon(Offset c, double r, [double rot = math.pi / 8]) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final a = rot + i * math.pi / 4;
    final o = c + Offset(math.cos(a) * r, math.sin(a) * r);
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

class _EmblemPainter extends CustomPainter {
  final int index;
  final bool locked;
  final Color lockedColor;
  const _EmblemPainter(this.index, this.locked, this.lockedColor);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, r * .06)
      ..strokeJoin = StrokeJoin.round;
    if (locked) {
      stroke.color = lockedColor.withValues(alpha: .7);
    } else {
      stroke.shader = foilGradient.createShader(rect);
      canvas.drawPath(_octagon(c, r * .86), Paint()..color = foil.withValues(alpha: .10));
    }
    canvas.drawPath(_octagon(c, r * .86), stroke);
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.6, r * .025)
      ..color = (locked ? lockedColor : foil).withValues(alpha: locked ? .35 : .5);
    canvas.drawPath(_octagon(c, r * .68), inner);
    // one lit point per rank climbed, at the corners
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final o = c + Offset(math.cos(a) * r * .97, math.sin(a) * r * .97);
      final lit = !locked && i < index;
      canvas.drawCircle(o, r * (lit ? .07 : .045), Paint()..color = lit ? foilHi : (locked ? lockedColor : foil).withValues(alpha: .3));
    }
  }

  @override
  bool shouldRepaint(_EmblemPainter o) => o.index != index || o.locked != locked || o.lockedColor != lockedColor;
}

// ── the passport card ───────────────────────────────────────────────────────
/// The hero: rank, name, miles and the bar to the next rank, on a dark metal card
/// with a security-print pattern. Tap to turn it over ([back]); a foil sheen
/// crosses it once when it appears and again each time it turns.
class PassportCard extends StatefulWidget {
  final PassportGame game;
  final String? name;
  final String? since;
  final Widget? back;
  const PassportCard({super.key, required this.game, this.name, this.since, this.back});
  @override
  State<PassportCard> createState() => _PassportCardState();
}

class _PassportCardState extends State<PassportCard> with TickerProviderStateMixin {
  late final _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final _sheen = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (!MediaQuery.disableAnimationsOf(context)) _sheen.forward();
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _sheen.dispose();
    super.dispose();
  }

  void _turn() {
    if (widget.back == null) return;
    _flip.isDismissed || _flip.status == AnimationStatus.reverse ? _flip.forward() : _flip.reverse();
    if (!MediaQuery.disableAnimationsOf(context)) _sheen.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    return Semantics(
      button: widget.back != null,
      label: 'Passport. ${g.rank.title}, ${g.miles} miles${g.next == null ? '' : ', ${g.toNext} to ${g.next!.title}'}. ${widget.back == null ? '' : 'Double tap to turn over.'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _turn,
        child: AspectRatio(
          aspectRatio: 1.586,
          child: AnimatedBuilder(
            animation: Listenable.merge([_flip, _sheen]),
            builder: (context, _) {
              final t = Curves.easeInOutCubic.transform(_flip.value);
              final showBack = t > .5;
              final face = showBack ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: _CardBack(child: widget.back!)) : _CardFront(game: g, name: widget.name, since: widget.since);
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .0012)
                  ..rotateY(math.pi * t),
                child: _CardShell(sheen: _sheen.value, child: face),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final double sheen;
  final Widget child;
  const _CardShell({required this.sheen, required this.child});
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: foil.withValues(alpha: .16), blurRadius: 28, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CustomPaint(
          painter: _CardGround(sheen),
          foregroundPainter: _CardEdge(),
          child: Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), child: child),
        ),
      ),
    );
  }
}

/// The ground: a warm dark gradient, a guilloché rosette (the fine engraved
/// lines on banknotes and passports), a glow behind the emblem, and the sheen.
class _CardGround extends CustomPainter {
  final double sheen;
  const _CardGround(this.sheen);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cardTop, cardBottom]).createShader(r));
    canvas.drawRect(
      r,
      Paint()
        ..shader = RadialGradient(center: const Alignment(-.75, -.1), radius: .9, colors: [foil.withValues(alpha: .20), foil.withValues(alpha: 0)]).createShader(r),
    );
    // guilloché: a rose of wavy rings around a point off the right edge
    final c = Offset(size.width * .92, size.height * .62);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = foil.withValues(alpha: .085);
    for (var k = 0; k < 16; k++) {
      final base = size.height * (.22 + k * .055);
      final path = Path();
      for (var i = 0; i <= 180; i++) {
        final th = i / 180 * math.pi * 2;
        final rr = base + size.height * .035 * math.sin(th * 9 + k * .55);
        final p = c + Offset(math.cos(th) * rr, math.sin(th) * rr);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, line);
    }
    // the sheen: a soft diagonal band of light, crossing once
    if (sheen > 0 && sheen < 1) {
      final x = -0.6 + sheen * 2.2;
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment(x - .5, -1),
            end: Alignment(x + .5, 1),
            colors: [Colors.white.withValues(alpha: 0), foilHi.withValues(alpha: .16), Colors.white.withValues(alpha: 0)],
          ).createShader(r),
      );
    }
  }

  @override
  bool shouldRepaint(_CardGround o) => o.sheen != sheen;
}

class _CardEdge extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius((Offset.zero & size).deflate(.5), const Radius.circular(21.5));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [foilHi.withValues(alpha: .55), foil.withValues(alpha: .12), foilLo.withValues(alpha: .4)]).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_CardEdge o) => false;
}

class _CardFront extends StatelessWidget {
  final PassportGame game;
  final String? name;
  final String? since;
  const _CardFront({required this.game, this.name, this.since});
  @override
  Widget build(BuildContext context) {
    final g = game;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('TASTE PASSPORT', style: _cs(9.5, foil, weight: FontWeight.w700, spacing: 2.2)),
        const Spacer(),
        Text('brewdiary', style: T.rawSerif(14, cardMuted, italic: true)),
      ]),
      const Spacer(),
      Row(children: [
        RankEmblem(g.rank.index, size: 62),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(g.rank.title, style: T.rawSerif(34, cardInk, height: 1))),
            const SizedBox(height: 4),
            Text(
              [if ((name ?? '').trim().isNotEmpty) name!.trim(), if (since != null) 'since $since'].join(' · ').ifEmpty('Rank ${_roman[g.rank.index]} of VIII'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _cs(12, cardMuted, weight: FontWeight.w500),
            ),
          ]),
        ),
      ]),
      const Spacer(),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        ShaderMask(
          shaderCallback: (r) => foilGradient.createShader(r),
          child: Text('${g.miles}', style: T.rawSerif(30, Colors.white, height: 1).copyWith(fontFeatures: T.tnum)),
        ),
        const SizedBox(width: 6),
        Text('miles', style: _cs(11.5, cardMuted, weight: FontWeight.w500)),
        const Spacer(),
        Text(g.next == null ? 'The top of the map' : '${g.toNext} to ${g.next!.title}', style: _cs(11.5, cardMuted, weight: FontWeight.w500)),
      ]),
      const SizedBox(height: 8),
      _FoilBar(value: g.progress),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _FoilBar extends StatelessWidget {
  final double value;
  const _FoilBar({required this.value});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, c) => Stack(children: [
          Container(decoration: BoxDecoration(color: Colors.white.withValues(alpha: .09), borderRadius: BorderRadius.circular(3))),
          Container(
            width: math.max(6, c.maxWidth * value.clamp(0, 1)),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [foilLo, foil, foilHi]),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [BoxShadow(color: foil.withValues(alpha: .55), blurRadius: 8)],
            ),
          ),
        ]),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final Widget child;
  const _CardBack({required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('WHAT THE BAR SEES', style: _cs(9.5, foil, weight: FontWeight.w700, spacing: 2.2)),
        const Spacer(),
        Icon(Ph.arrowsClockwise, size: 14, color: cardMuted),
      ]),
      const SizedBox(height: 12),
      Expanded(child: child),
    ]);
  }
}

/// Small chips for the back of the card.
class CardChips extends StatelessWidget {
  final List<(String, bool)> chips;
  const CardChips(this.chips, {super.key});
  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) {
      return Text('Nothing yet — log a few drinks, or add what you love under Taste.', style: _cs(13, cardMuted, weight: FontWeight.w500));
    }
    return ClipRect(
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (t, strong) in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: strong ? foil.withValues(alpha: .2) : Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: strong ? foil.withValues(alpha: .6) : Colors.white.withValues(alpha: .12), width: .8),
            ),
            child: Text(t, style: _cs(12, strong ? foilHi : cardInk, weight: strong ? FontWeight.w700 : FontWeight.w500)),
          ),
      ]),
    );
  }
}

// ── a progress ring ─────────────────────────────────────────────────────────
class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final bool done;
  final IconData? icon;
  const ProgressRing({super.key, required this.value, this.size = 40, this.done = false, this.icon});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0, 1), bd.line, bd.accent, done),
        child: Center(
          child: done
              ? Icon(PhBold.check, size: size * .42, color: bd.accentContrast)
              : Icon(icon ?? Ph.target, size: size * .42, color: value > 0 ? bd.accentText : bd.faint),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color track;
  final Color fill;
  final bool done;
  const _RingPainter(this.value, this.track, this.fill, this.done);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    if (done) {
      canvas.drawCircle(c, r + 1, Paint()..color = fill);
      return;
    }
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = track);
    if (value > 0) canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 2 * value, false, p..color = fill);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.value != value || o.done != done || o.fill != fill || o.track != track;
}

// ── this week's quests ──────────────────────────────────────────────────────
class QuestCard extends StatelessWidget {
  final List<QuestState> quests;
  final int daysLeft;
  const QuestCard({super.key, required this.quests, required this.daysLeft});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final done = quests.where((q) => q.done).length;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(done == quests.length ? 'All three done.' : '$done of ${quests.length} this week', style: T.serif(bd, size: 22, height: 1.1))),
          _Pill(daysLeft == 0 ? 'New ones tomorrow' : 'New in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}'),
        ]),
        const SizedBox(height: S.s),
        for (final q in quests)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.s),
            child: Row(children: [
              ProgressRing(value: q.progress / q.def.target, done: q.done, size: 40, icon: _questIcon(q.def.id)),
              const SizedBox(width: S.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(q.def.title, style: T.sans(bd, size: 15.5, weight: FontWeight.w600, color: q.done ? bd.muted : bd.ink)),
                  const SizedBox(height: 2),
                  Text(q.def.target > 1 && !q.done ? '${q.def.line}  ${q.progress}/${q.def.target}' : q.def.line, style: T.caption(bd)),
                ]),
              ),
              const SizedBox(width: S.s),
              Text(q.done ? 'Done' : '+$milesQuest', style: T.sans(bd, size: 13, weight: FontWeight.w700, color: q.done ? bd.faint : bd.accentText)),
            ]),
          ),
      ]),
    );
  }

  static IconData _questIcon(String id) => switch (id) {
        'dry_two' => Ph.moon,
        'free_new' => Ph.leaf,
        'new_family' => Ph.sparkle,
        'new_place' => Ph.mapPin,
        'new_note' => Ph.dropHalf,
        'with_friend' => Ph.users,
        'write_it' => Ph.notePencil,
        'new_kind' => Ph.squaresFour,
        _ => Ph.target,
      };
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
        color: strong ? bd.accent.withValues(alpha: .16) : bd.glass,
        borderRadius: BorderRadius.circular(rCtl),
        border: Border.all(color: strong ? bd.accent.withValues(alpha: .45) : bd.line, width: .8),
      ),
      child: Text(text, style: T.sans(bd, size: 12, weight: FontWeight.w600, color: strong ? bd.accentText : bd.muted)),
    );
  }
}

// ── the season stamp ────────────────────────────────────────────────────────
/// A small painted motif per season, in amber.
class SeasonMotif extends StatelessWidget {
  final String season;
  final double size;
  final bool earned;
  const SeasonMotif(this.season, {super.key, this.size = 64, this.earned = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _MotifPainter(season, earned ? bd.accent : bd.accentText.withValues(alpha: .7), earned)));
  }
}

class _MotifPainter extends CustomPainter {
  final String season;
  final Color color;
  final bool earned;
  const _MotifPainter(this.season, this.color, this.earned);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color;
    if (earned) canvas.drawCircle(c, r - 1, Paint()..color = color.withValues(alpha: .14));
    canvas.drawCircle(c, r - 1, ring);
    canvas.drawCircle(c, r - 5, ring..strokeWidth = .7);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    switch (season) {
      case 'monsoon': // a cloud and rain
        final cloud = Path()
          ..moveTo(c.dx - r * .42, c.dy - r * .02)
          ..arcToPoint(Offset(c.dx - r * .1, c.dy - r * .3), radius: Radius.circular(r * .2))
          ..arcToPoint(Offset(c.dx + r * .3, c.dy - r * .18), radius: Radius.circular(r * .25))
          ..arcToPoint(Offset(c.dx + r * .4, c.dy - r * .02), radius: Radius.circular(r * .12))
          ..close();
        canvas.drawPath(cloud, p);
        for (var i = 0; i < 4; i++) {
          final x = c.dx - r * .3 + i * r * .2;
          canvas.drawLine(Offset(x, c.dy + r * .14), Offset(x - r * .07, c.dy + r * .36), p);
        }
      case 'winter': // a six-armed flake
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final end = c + Offset(math.cos(a), math.sin(a)) * r * .45;
          canvas.drawLine(c, end, p);
          final mid = c + Offset(math.cos(a), math.sin(a)) * r * .28;
          canvas.drawLine(mid, mid + Offset(math.cos(a + .7), math.sin(a + .7)) * r * .12, p);
          canvas.drawLine(mid, mid + Offset(math.cos(a - .7), math.sin(a - .7)) * r * .12, p);
        }
      case 'spring': // five petals
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + i * math.pi * 2 / 5;
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(a);
          canvas.drawOval(Rect.fromCenter(center: Offset(r * .24, 0), width: r * .4, height: r * .2), p);
          canvas.restore();
        }
        canvas.drawCircle(c, r * .06, Paint()..color = color);
      default: // harvest: a stalk of grain
        canvas.drawLine(Offset(c.dx, c.dy + r * .45), Offset(c.dx, c.dy - r * .42), p);
        for (var i = 0; i < 4; i++) {
          final y = c.dy - r * .3 + i * r * .17;
          canvas.drawOval(Rect.fromCenter(center: Offset(c.dx - r * .12, y), width: r * .2, height: r * .1), p);
          canvas.drawOval(Rect.fromCenter(center: Offset(c.dx + r * .12, y), width: r * .2, height: r * .1), p);
        }
    }
  }

  @override
  bool shouldRepaint(_MotifPainter o) => o.season != season || o.color != color || o.earned != earned;
}

class SeasonCard extends StatelessWidget {
  final SeasonNow season;
  final void Function(String family) onPick;
  final Set<String> onList;
  const SeasonCard({super.key, required this.season, required this.onPick, this.onList = const {}});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = season;
    final earned = s.earnedOn != null;
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SeasonMotif(s.window.def.id, earned: earned),
          const SizedBox(width: S.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SEASON STAMP', style: T.label(bd, color: bd.accentText)),
              const SizedBox(height: 4),
              Text(s.window.label, style: T.serif(bd, size: 24, height: 1.05)),
              const SizedBox(height: 4),
              Text(
                earned ? 'Stamped with ${s.earnedWith} on ${shortDay(s.earnedOn!)}. Next season brings a new one.' : '${s.window.def.line} One of these, once, before it closes.',
                style: T.caption(bd),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: S.m),
        Row(children: [
          _Pill(earned ? 'Stamped · +$milesSeason' : (s.daysLeft <= 0 ? 'Closes today' : 'Closes in ${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'}'), strong: !earned && s.daysLeft <= 14 || earned),
          const Spacer(),
          if (!earned) Text('+$milesSeason miles', style: T.sans(bd, size: 13, weight: FontWeight.w700, color: bd.accentText)),
        ]),
        if (!earned) ...[
          const SizedBox(height: S.m),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final f in s.picks.take(6)) BdChip(onList.contains(f.toLowerCase()) ? '$f · listed' : f, active: onList.contains(f.toLowerCase()), onTap: () => onPick(f)),
          ]),
          const SizedBox(height: S.s),
          Text('Tap one to put it on your to-try list.', style: T.caption(bd)),
        ],
      ]),
    );
  }
}

// ── the road of ranks ───────────────────────────────────────────────────────
class RankRoad extends StatelessWidget {
  final PassportGame game;
  const RankRoad({super.key, required this.game});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: ranks.length,
        separatorBuilder: (_, i) => Padding(padding: const EdgeInsets.only(top: S.s + 23), child: Align(alignment: Alignment.topCenter, child: Container(width: 14, height: 1.2, color: i < game.rank.index ? bd.accent : bd.line))),
        itemBuilder: (_, i) {
          final r = ranks[i];
          final here = i == game.rank.index;
          final locked = i > game.rank.index;
          return Container(
            width: 92,
            padding: const EdgeInsets.symmetric(vertical: S.s),
            decoration: BoxDecoration(
              color: here ? bd.accent.withValues(alpha: .12) : null,
              borderRadius: BorderRadius.circular(rCtl),
              border: Border.all(color: here ? bd.accent.withValues(alpha: .5) : Colors.transparent),
            ),
            child: Column(children: [
              RankEmblem(i, size: 46, locked: locked),
              const SizedBox(height: 6),
              Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 12.5, weight: FontWeight.w600, color: locked ? bd.faint : bd.ink)),
              Text(here ? 'You' : '${r.from} mi', style: T.sans(bd, size: 11, color: here ? bd.accentText : bd.faint, weight: here ? FontWeight.w700 : FontWeight.w400)),
            ]),
          );
        },
      ),
    );
  }
}

// ── collections ─────────────────────────────────────────────────────────────
class CollectionTile extends StatelessWidget {
  final CollectionState state;
  final Set<String> gilded;
  final VoidCallback onTap;
  const CollectionTile({super.key, required this.state, required this.gilded, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = state;
    return Glass(
      onTap: onTap,
      semanticLabel: '${s.collection.title}, ${s.have} of ${s.total}',
      padding: const EdgeInsets.all(S.m + 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.collection.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 14, weight: FontWeight.w600))),
          if (s.complete) Icon(PhFill.sealCheck, size: 16, color: bd.accent) else Text('${s.have}/${s.total}', style: T.sans(bd, size: 12.5, weight: FontWeight.w700, color: s.have > 0 ? bd.accentText : bd.faint)),
        ]),
        const SizedBox(height: S.m),
        Wrap(spacing: 5, runSpacing: 5, children: [
          for (final f in s.collection.families) _Slot(filled: s.tried.containsKey(f), gilded: gilded.contains(f), label: f),
        ]),
      ]),
    );
  }
}

class _Slot extends StatelessWidget {
  final bool filled;
  final bool gilded;
  final String label;
  const _Slot({required this.filled, required this.gilded, required this.label});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled && !gilded ? bd.accent.withValues(alpha: .85) : null,
        gradient: filled && gilded ? foilGradient : null,
        borderRadius: BorderRadius.circular(6),
        border: filled ? null : Border.all(color: bd.lineStrong, width: .9),
        boxShadow: gilded ? [BoxShadow(color: foil.withValues(alpha: .6), blurRadius: 6)] : null,
      ),
      child: gilded && filled
          ? const Icon(PhFill.sparkle, size: 12, color: Color(0xFF2A1A08))
          : Text(label.characters.first, style: T.sans(bd, size: 10.5, weight: FontWeight.w700, color: filled ? bd.accentContrast : bd.faint)),
    );
  }
}

// ── feats ────────────────────────────────────────────────────────────────────
IconData featIcon(String id) => switch (id) {
      'first_page' => Ph.notebook,
      'kinds_5' || 'kinds_7' => Ph.squaresFour,
      'zero_3' => Ph.leaf,
      'places_3' || 'places_10' => Ph.mapTrifold,
      'quiet_month' => Ph.moonStars,
      'balanced_week' => Ph.scales,
      'notes_8' => Ph.dropHalf,
      'company_3' => Ph.usersThree,
      'full_set' => Ph.sealCheck,
      'families_25' => Ph.compass,
      'seasons_4' => Ph.sun,
      _ => Ph.star,
    };

class FeatMedal extends StatelessWidget {
  final FeatState feat;
  final double size;
  const FeatMedal(this.feat, {super.key, this.size = 60});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final f = feat;
    return Semantics(
      label: '${f.def.title}. ${f.def.line} ${f.earned ? 'Earned ${formatDayLong(f.earnedOn!)}.' : '${f.progress} of ${f.def.target}.'}',
      excludeSemantics: true,
      child: Column(children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _MedalPainter(f.earned, f.progress / f.def.target, bd.line, bd.accent),
            child: Center(child: Icon(featIcon(f.def.id), size: size * .38, color: f.earned ? foilHi : bd.faint)),
          ),
        ),
        const SizedBox(height: 6),
        Text(f.def.title, textAlign: TextAlign.center, maxLines: 2, style: T.sans(bd, size: 12, weight: FontWeight.w600, color: f.earned ? bd.ink : bd.muted, height: 1.2)),
        Text(f.earned ? shortDay(f.earnedOn!) : '${f.progress}/${f.def.target}', style: T.sans(bd, size: 11, color: f.earned ? bd.accentText : bd.faint)),
      ]),
    );
  }
}

class _MedalPainter extends CustomPainter {
  final bool earned;
  final double progress;
  final Color track;
  final Color accent;
  const _MedalPainter(this.earned, this.progress, this.track, this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Offset.zero & size;
    if (earned) {
      canvas.drawCircle(c, r - 1, Paint()..shader = const RadialGradient(colors: [Color(0xFF3A2A16), Color(0xFF16100A)]).createShader(rect));
      canvas.drawCircle(
        c,
        r - 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..shader = foilGradient.createShader(rect),
      );
      // a ring of tiny ticks, like a coin's edge
      final tick = Paint()
        ..strokeWidth = 1
        ..color = foil.withValues(alpha: .5);
      for (var i = 0; i < 36; i++) {
        final a = i * math.pi * 2 / 36;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r - 6), c + Offset(math.cos(a), math.sin(a)) * (r - 8.5), tick);
      }
    } else {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawCircle(c, r - 1.5, p..color = track);
      if (progress > 0) canvas.drawArc(Rect.fromCircle(center: c, radius: r - 1.5), -math.pi / 2, math.pi * 2 * progress.clamp(0, 1), false, p..color = accent.withValues(alpha: .8));
    }
  }

  @override
  bool shouldRepaint(_MedalPainter o) => o.earned != earned || o.progress != progress || o.track != track || o.accent != accent;
}

// ── the miles ledger and the rules ──────────────────────────────────────────
class MilesLedger extends StatelessWidget {
  final List<MileEvent> events;
  const MilesLedger(this.events, {super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (events.isEmpty) return Text('Your first miles come with your first log — a drink or a dry night.', style: T.bodyMuted(bd));
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.s),
      child: Column(children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: e.gilded ? foilGradient : null,
                  color: e.gilded ? null : bd.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(mileIcon(e.source), size: 16, color: e.gilded ? bd.accentContrast : bd.accentText),
              ),
              const SizedBox(width: S.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mileLine(e) + (e.gilded ? ' · gilded' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 14.5, weight: FontWeight.w500)),
                  Text(formatDayLongYear(e.date), style: T.caption(bd)),
                ]),
              ),
              Text('+${e.miles}', style: T.sans(bd, size: 14, weight: FontWeight.w700, color: bd.accentText).copyWith(fontFeatures: T.tnum)),
            ]),
          ),
      ]),
    );
  }
}

class MilesGuide extends StatelessWidget {
  const MilesGuide({super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget row(IconData i, String what, int miles) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Icon(i, size: 16, color: bd.accentText),
            const SizedBox(width: S.m),
            Expanded(child: Text(what, style: T.sans(bd, size: 14.5))),
            Text('+$miles', style: T.sans(bd, size: 14, weight: FontWeight.w700, color: bd.muted)),
          ]),
        );
    return Group(
      footer: 'Range, never rounds: two first tastes a night count, one new place a night, and the tenth of anything earns nothing. Every dry night earns.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.s),
          child: Column(children: [
            row(Ph.sparkle, 'A first taste', milesFirstTaste),
            row(Ph.squaresFour, 'A new kind of drink', milesNewKind),
            row(Ph.mapPin, 'A new place', milesNewPlace),
            row(Ph.moon, 'A dry night', milesDryNight),
            row(Ph.target, 'A weekly quest', milesQuest),
            row(Ph.sun, 'The season stamp', milesSeason),
            row(Ph.sealCheck, 'A full collection', milesCollection),
          ]),
        ),
      ],
    );
  }
}

// ── the moment after a save ─────────────────────────────────────────────────
/// A compact strip for the log sheet: "+35 miles · First taste · Paloma".
class UnlockStrip extends StatelessWidget {
  final Unlocks unlocks;
  const UnlockStrip(this.unlocks, {super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final u = unlocks;
    final lines = [
      if (u.rankUp != null) 'You are a ${u.rankUp!.title} now',
      for (final e in u.events.take(2)) mileLine(e),
      for (final f in u.feats.take(1)) 'Feat · ${f.title}',
    ];
    final gild = u.events.any((e) => e.gilded);
    return Semantics(
      liveRegion: true,
      label: '${u.miles > 0 ? 'Plus ${u.miles} miles. ' : ''}${lines.join('. ')}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.m, vertical: S.m - 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [bd.accent.withValues(alpha: .22), bd.accent.withValues(alpha: .08)]),
          borderRadius: BorderRadius.circular(rCtl),
          border: Border.all(color: bd.accent.withValues(alpha: .5), width: .8),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(gradient: foilGradient, borderRadius: BorderRadius.circular(10), boxShadow: gild ? [BoxShadow(color: foil.withValues(alpha: .7), blurRadius: 10)] : null),
            child: Icon(u.rankUp != null ? PhFill.crown : (gild ? PhFill.sparkle : (u.events.isNotEmpty ? mileIcon(u.events.first.source) : PhFill.star)), size: 17, color: const Color(0xFF1A130B)),
          ),
          const SizedBox(width: S.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.miles > 0 ? '+${u.miles} miles${gild ? ' · gilded!' : ''}' : 'On your passport', style: T.sans(bd, size: 14, weight: FontWeight.w700, color: bd.accentText)),
              Text(lines.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 12.5, color: bd.ink, height: 1.3)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The bigger moment: a new rank.
Future<void> showRankUp(BuildContext context, Rank rank) => showBdSheet<void>(
      context,
      builder: (context) {
        final bd = context.bd;
        return Column(children: [
          const SizedBox(height: S.s),
          RankEmblem(rank.index, size: 112),
          const SizedBox(height: S.l),
          Text('RANK ${_roman[rank.index]}', style: T.label(bd, color: bd.accentText)),
          const SizedBox(height: S.s),
          Text(rank.title, style: T.serif(bd, size: 40)),
          const SizedBox(height: S.s),
          Text(rank.line, textAlign: TextAlign.center, style: T.serif(bd, size: 18, italic: true, color: bd.muted, height: 1.3)),
          const SizedBox(height: S.xl),
          BdButton('Lovely', onTap: () => Navigator.pop(context)),
        ]);
      },
    );

// ── the passport on the calendar ────────────────────────────────────────────
/// A slim version of the card for the calendar: rank, miles, the bar, then what
/// this month (or year) added and what's open this week.
class PassportMini extends StatelessWidget {
  final PassportGame game;
  final String period;
  final Widget stamps;
  final int stampCount;
  final VoidCallback onTap;
  const PassportMini({super.key, required this.game, required this.period, required this.stamps, required this.stampCount, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final g = game;
    final questsDone = g.quests.where((q) => q.done).length;
    final s = g.season;
    return Semantics(
      button: true,
      label: 'Taste passport. ${g.rank.title}, ${g.miles} miles. $stampCount stamps in $period. $questsDone of ${g.quests.length} quests this week.',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: _CardShell(
          sheen: 0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              RankEmblem(g.rank.index, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.rank.title, style: T.rawSerif(24, cardInk, height: 1)),
                  const SizedBox(height: 3),
                  Text(g.next == null ? '${g.miles} miles · the top of the map' : '${g.miles} miles · ${g.toNext} to ${g.next!.title}', style: _cs(11.5, cardMuted, weight: FontWeight.w500)),
                ]),
              ),
              const Icon(Ph.caretRight, size: 16, color: cardMuted),
            ]),
            const SizedBox(height: 12),
            _FoilBar(value: g.progress),
            const SizedBox(height: 14),
            Row(children: [
              Text(period.toUpperCase(), style: _cs(9.5, foil, weight: FontWeight.w700, spacing: 1.8)),
              const Spacer(),
              Text(stampCount == 0 ? 'no stamps yet' : '$stampCount ${stampCount == 1 ? 'stamp' : 'stamps'}', style: _cs(11, cardMuted, weight: FontWeight.w500)),
            ]),
            const SizedBox(height: 8),
            stamps,
            const SizedBox(height: 12),
            Row(children: [
              _MiniTag(icon: Ph.target, text: 'Quests $questsDone/${g.quests.length}'),
              const SizedBox(width: 6),
              Flexible(
                child: _MiniTag(
                  icon: Ph.sun,
                  text: s.earnedOn != null ? '${s.window.def.title} stamped' : '${s.window.def.title} · ${s.daysLeft <= 0 ? 'closes today' : '${s.daysLeft}d left'}',
                  strong: s.earnedOn == null && s.daysLeft <= 14,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool strong;
  const _MiniTag({required this.icon, required this.text, this.strong = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: strong ? foil.withValues(alpha: .16) : Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: strong ? foil.withValues(alpha: .5) : Colors.white.withValues(alpha: .1), width: .8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: strong ? foilHi : cardMuted),
        const SizedBox(width: 5),
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: _cs(11.5, strong ? foilHi : cardInk, weight: FontWeight.w600))),
      ]),
    );
  }
}
