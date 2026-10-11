// The passport game, drawn. The rules live in brewdiary_core/game.dart (derived
// from the diary, never stored); this is how they look — calm, in type and the
// mosaic: a flat amber rank emblem, the taste map (every drink family as a square,
// one row per collection), the week's quests, the season, feats, the share poster,
// the passport on the calendar, and the little moment after a save that earned
// something. (The foil palette below is kept for the photo overlay's sticker.)
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
/// An octagon in amber with one lit point per rank climbed and the numeral inside.
class RankEmblem extends StatelessWidget {
  final int index;
  final double size;
  final bool locked;
  final Color? lockedColor;
  const RankEmblem(this.index, {super.key, this.size = 56, this.locked = false, this.lockedColor});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final lc = lockedColor ?? bd.faint;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EmblemPainter(index, locked, lc, bd.accent),
        child: Center(child: Text(_roman[index.clamp(0, 7)], style: T.rawSerif(size * .3, locked ? lc : bd.accentText, weight: FontWeight.w500))),
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
  final Color accent;
  const _EmblemPainter(this.index, this.locked, this.lockedColor, this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final color = locked ? lockedColor.withValues(alpha: .7) : accent;
    if (!locked) canvas.drawPath(_octagon(c, r * .86), Paint()..color = accent.withValues(alpha: .1));
    canvas.drawPath(
      _octagon(c, r * .86),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * .055)
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final o = c + Offset(math.cos(a) * r * .97, math.sin(a) * r * .97);
      final lit = !locked && i < index;
      canvas.drawCircle(o, r * (lit ? .065 : .04), Paint()..color = lit ? accent : color.withValues(alpha: .3));
    }
  }

  @override
  bool shouldRepaint(_EmblemPainter o) => o.index != index || o.locked != locked || o.lockedColor != lockedColor || o.accent != accent;
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
class QuestList extends StatelessWidget {
  final List<QuestState> quests;
  const QuestList({super.key, required this.quests});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.xs),
      child: Column(children: [
        for (var i = 0; i < quests.length; i++) ...[
          if (i > 0) Container(height: .8, color: bd.line),
          Semantics(
            label: '${quests[i].def.title}. ${quests[i].def.line} ${quests[i].done ? 'Done.' : '${quests[i].progress} of ${quests[i].def.target}.'}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.m),
              child: Row(children: [
                ProgressRing(value: quests[i].progress / quests[i].def.target, done: quests[i].done, size: 30, icon: _questIcon(quests[i].def.id)),
                const SizedBox(width: S.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(quests[i].def.title, style: T.sans(bd, size: 15, weight: FontWeight.w500, color: quests[i].done ? bd.muted : bd.ink)),
                    Text(quests[i].def.line, style: T.caption(bd)),
                  ]),
                ),
                const SizedBox(width: S.s),
                Text(quests[i].done ? 'done' : '+$milesQuest', style: T.sans(bd, size: 13, weight: FontWeight.w600, color: quests[i].done ? bd.accentText : bd.faint).copyWith(fontFeatures: T.tnum)),
              ]),
            ),
          ),
        ],
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

/// The season in one line: its motif, its name, stamped or how long it's open.
class SeasonLine extends StatelessWidget {
  final SeasonNow season;
  final VoidCallback onTap;
  const SeasonLine({super.key, required this.season, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = season;
    final earned = s.earnedOn != null;
    final line = earned
        ? 'Stamped with ${s.earnedWith} · ${shortDay(s.earnedOn!)}'
        : '${s.daysLeft <= 0 ? 'Closes today' : 'Closes in ${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'}'} · try ${s.picks.take(2).join(' or ')}';
    return Glass(
      onTap: onTap,
      semanticLabel: '${s.window.label}. $line',
      padding: const EdgeInsets.fromLTRB(S.l, S.m, S.m, S.m),
      child: Row(children: [
        SeasonMotif(s.window.def.id, size: 40, earned: earned),
        const SizedBox(width: S.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.window.label, style: T.serif(bd, size: 19, height: 1.15)),
            const SizedBox(height: 2),
            Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption(bd, color: !earned && s.daysLeft <= 14 ? bd.accentText : null)),
          ]),
        ),
        const SizedBox(width: S.s),
        Text(earned ? 'stamped' : '+$milesSeason', style: T.sans(bd, size: 13, weight: FontWeight.w600, color: earned ? bd.accentText : bd.faint)),
        const SizedBox(width: S.xs),
        Icon(Ph.caretRight, size: 15, color: bd.faint),
      ]),
    );
  }
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

// ── the taste map ───────────────────────────────────────────────────────────
/// Every drink family as a square, one row per collection — the mosaic, for
/// taste. A first taste fills a square; a gilded one glows. Tap a row to open it.
class TasteMap extends StatefulWidget {
  final List<CollectionState> collections;
  final Set<String> gilded;
  final void Function(CollectionState)? onOpen;
  final bool compact;

  /// Fill the squares in, row by row, when it first appears (the passport page).
  /// Off for anything captured as an image — the share poster must be whole.
  final bool animate;
  const TasteMap({super.key, required this.collections, required this.gilded, this.onOpen, this.compact = false, this.animate = false});
  @override
  State<TasteMap> createState() => _TasteMapState();
}

class _TasteMapState extends State<TasteMap> with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100), value: widget.animate ? 0 : 1);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.animate) return;
    _started = true;
    if (context.reduceMotion) {
      _fill.value = 1;
    } else {
      _fill.forward();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  /// How far square [i] of row [row] has filled in: each row starts a beat after
  /// the one above, each square a moment after the one before it.
  double _appear(int row, int i) {
    final t = _fill.value;
    if (t >= 1) return 1;
    final start = row * .07 + i * .03;
    return Curves.easeOutBack.transform(((t - start) / .32).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final collections = widget.collections;
    final compact = widget.compact;
    return LayoutBuilder(builder: (context, c) {
      final label = compact ? 0.0 : 74.0;
      final count = compact ? 0.0 : 38.0;
      const gap = 4.0;
      final most = collections.fold<int>(0, (m, x) => math.max(m, x.total));
      final cell = ((c.maxWidth - label - count - (most - 1) * gap) / most).clamp(8.0, 22.0);
      return AnimatedBuilder(
        animation: _fill,
        builder: (context, _) => Column(children: [
          for (final (row, col) in collections.indexed)
            Semantics(
              button: widget.onOpen != null,
              label: '${col.collection.title}, ${col.have} of ${col.total}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpen == null
                    ? null
                    : () {
                        Haptics.tick();
                        widget.onOpen!(col);
                      },
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: compact ? 2 : 6),
                  child: Row(children: [
                    if (!compact)
                      SizedBox(
                        width: label,
                        child: Text(shortCollection(col.collection.id), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 13, color: col.complete ? bd.accentText : bd.muted, weight: col.complete ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    for (var i = 0; i < col.collection.families.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      _Square(size: cell, filled: col.tried.containsKey(col.collection.families[i]), gilded: widget.gilded.contains(col.collection.families[i]), appear: _appear(row, i)),
                    ],
                    const Spacer(),
                    if (!compact) Text('${col.have}/${col.total}', style: T.sans(bd, size: 12.5, color: col.have == 0 ? bd.faint : bd.muted).copyWith(fontFeatures: T.tnum)),
                  ]),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

/// A collection's name, short enough for a row label.
String shortCollection(String id) => switch (id) {
      'coffee' => 'Coffee',
      'tea' => 'Tea',
      'zero' => 'Zero proof',
      'brewery' => 'Beer',
      'cellar' => 'Wine',
      'classics' => 'Classics',
      'long' => 'Long drinks',
      'backbar' => 'Spirits',
      _ => id,
    };

class _Square extends StatelessWidget {
  final double size;
  final bool filled;
  final bool gilded;

  /// 0 → 1 as a filled square fills in (its outline shows until it lands).
  final double appear;
  const _Square({required this.size, required this.filled, required this.gilded, this.appear = 1});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final radius = BorderRadius.circular(size * .22);
    final outline = Container(width: size, height: size, decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: bd.lineStrong, width: .9)));
    if (!filled) return outline;
    final a = appear.clamp(0.0, 1.0);
    final fill = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bd.accent.withValues(alpha: gilded ? 1 : .62),
        borderRadius: radius,
        boxShadow: gilded ? [BoxShadow(color: bd.accent.withValues(alpha: .7 * a), blurRadius: size * .5)] : null,
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Opacity(opacity: 1 - a, child: outline),
        Opacity(opacity: a, child: Transform.scale(scale: .35 + .65 * appear, child: fill)),
      ]),
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
  const FeatMedal(this.feat, {super.key, this.size = 52});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final f = feat;
    return Semantics(
      label: '${f.def.title}. ${f.def.line} ${f.earned ? 'Earned ${formatDayLong(f.earnedOn!)}.' : '${f.progress} of ${f.def.target}.'}',
      excludeSemantics: true,
      child: SizedBox(
        width: size + 30,
        child: Column(children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _MedalPainter(f.earned, f.progress / f.def.target, bd.line, bd.accent),
              child: Center(child: Icon(featIcon(f.def.id), size: size * .4, color: f.earned ? bd.accentContrast : bd.faint)),
            ),
          ),
          const SizedBox(height: 6),
          Text(f.def.title, textAlign: TextAlign.center, maxLines: 2, style: T.sans(bd, size: 11.5, weight: FontWeight.w500, color: f.earned ? bd.ink : bd.muted, height: 1.2)),
        ]),
      ),
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
    if (earned) {
      canvas.drawCircle(c, r - 1, Paint()..color = accent);
      return;
    }
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r - 1.5, p..color = track);
    if (progress > 0) canvas.drawArc(Rect.fromCircle(center: c, radius: r - 1.5), -math.pi / 2, math.pi * 2 * progress.clamp(0, 1), false, p..color = accent.withValues(alpha: .8));
  }

  @override
  bool shouldRepaint(_MedalPainter o) => o.earned != earned || o.progress != progress || o.track != track || o.accent != accent;
}

/// Feats in a row you can slide — earned first.
class FeatRow extends StatelessWidget {
  final List<FeatState> feats;
  const FeatRow({super.key, required this.feats});
  @override
  Widget build(BuildContext context) {
    final sorted = [...feats.where((f) => f.earned), ...feats.where((f) => !f.earned)];
    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: S.xs),
        itemBuilder: (_, i) => FeatMedal(sorted[i]),
      ),
    );
  }
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
                  color: e.gilded ? bd.accent : bd.accent.withValues(alpha: .12),
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
          // The badge pops in as the strip opens.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: context.reduceMotion ? 1 : .4, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(10), boxShadow: gild ? [BoxShadow(color: bd.accent.withValues(alpha: .7), blurRadius: 10)] : null),
              child: Icon(u.rankUp != null ? PhFill.crown : (gild ? PhFill.sparkle : (u.events.isNotEmpty ? mileIcon(u.events.first.source) : PhFill.star)), size: 17, color: bd.accentContrast),
            ),
          ),
          const SizedBox(width: S.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              u.miles > 0
                  ? CountUp(u.miles, duration: const Duration(milliseconds: 600), format: (v) => '+${v.round()} miles${gild ? ' · gilded!' : ''}', style: T.sans(bd, size: 14, weight: FontWeight.w700, color: bd.accentText))
                  : Text('On your passport', style: T.sans(bd, size: 14, weight: FontWeight.w700, color: bd.accentText)),
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
          _Landing(child: RankEmblem(rank.index, size: 112)),
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

/// The new rank's emblem arriving: it springs up from small and one ring goes out
/// from it, like the ripple when a day is logged — once, then still.
class _Landing extends StatefulWidget {
  final Widget child;
  const _Landing({required this.child});
  @override
  State<_Landing> createState() => _LandingState();
}

class _LandingState extends State<_Landing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _c.value = 1;
    } else {
      // Let the sheet rise first.
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.bd.accent;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final pop = Curves.elasticOut.transform(((t - .18) / .82).clamp(0.0, 1.0));
        final ring = Curves.easeOutCubic.transform(((t - .3) / .7).clamp(0.0, 1.0));
        return CustomPaint(
          painter: _RingOut(ring, accent),
          child: Opacity(opacity: (t / .2).clamp(0.0, 1.0), child: Transform.scale(scale: .55 + .45 * pop, child: child)),
        );
      },
    );
  }
}

class _RingOut extends CustomPainter {
  final double t;
  final Color color;
  _RingOut(this.t, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      size.center(Offset.zero),
      r * (.9 + .7 * t),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * (1 - t) + .5
        ..color = color.withValues(alpha: .55 * (1 - t)),
    );
  }

  @override
  bool shouldRepaint(_RingOut old) => old.t != t || old.color != color;
}

// ── a thin line to the next rank ────────────────────────────────────────────
class RankLine extends StatelessWidget {
  final double value;
  const RankLine(this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final target = value.clamp(0.0, 1.0);
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, c) => Stack(children: [
          Container(decoration: BoxDecoration(color: bd.line, borderRadius: BorderRadius.circular(2))),
          // It draws out to where you are when it appears, and on from there after a save.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: target),
            duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
            curve: Easing.emphasizedDecelerate,
            builder: (context, v, _) => Container(width: (c.maxWidth * v).clamp(3.0, c.maxWidth), decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(2))),
          ),
        ]),
      ),
    );
  }
}

// ── the passport on the calendar ────────────────────────────────────────────
/// The calendar's glance at the passport: rank and miles, the line to the next
/// rank, and one line of what this month added and what's open this week.
class PassportMini extends StatelessWidget {
  final PassportGame game;
  final String period;
  final int stampCount;
  final VoidCallback onTap;
  const PassportMini({super.key, required this.game, required this.period, required this.stampCount, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final g = game;
    final questsDone = g.quests.where((q) => q.done).length;
    final s = g.season;
    return Glass(
      onTap: onTap,
      semanticLabel: 'Taste passport. ${g.rank.title}, ${g.miles} miles. $stampCount stamps in $period. $questsDone of ${g.quests.length} quests this week.',
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          RankEmblem(g.rank.index, size: 40),
          const SizedBox(width: S.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.rank.title, style: T.serif(bd, size: 22, height: 1.05)),
              const SizedBox(height: 2),
              Text(g.next == null ? '${g.miles} miles' : '${g.miles} miles · ${g.toNext} to ${g.next!.title}', style: T.caption(bd)),
            ]),
          ),
          Icon(Ph.caretRight, size: 16, color: bd.faint),
        ]),
        const SizedBox(height: S.m),
        RankLine(g.progress),
        const SizedBox(height: S.m),
        Text(
          [
            '${g.families} of ${g.collections.fold<int>(0, (a, c) => a + c.total)} tastes',
            stampCount == 0 ? 'no stamps in $period yet' : '$stampCount ${stampCount == 1 ? 'stamp' : 'stamps'} in $period',
            'quests $questsDone/${g.quests.length}',
            if (s.earnedOn == null && s.daysLeft <= 14) '${s.window.def.title} closes in ${s.daysLeft}d',
          ].join(' · '),
          style: T.caption(bd),
        ),
      ]),
    );
  }
}

// ── the share poster ────────────────────────────────────────────────────────
/// What you share: your name, your rank, your taste map. Drawn in the dark theme's
/// colours whatever the phone is set to, so it looks the same everywhere.
class PassportPoster extends StatelessWidget {
  final PassportGame game;
  final String? name;
  const PassportPoster({super.key, required this.game, this.name});
  @override
  Widget build(BuildContext context) {
    final g = game;
    final dark = Theme.of(context).copyWith(extensions: const [BD.darkTokens]);
    return Theme(
      data: dark,
      child: Builder(builder: (context) {
        final bd = context.bd;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(-.8, -1), radius: 1.4, colors: [bd.accent.withValues(alpha: .18), bd.base], stops: const [0, .7]),
            color: bd.base,
          ),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('TASTE PASSPORT', style: T.label(bd, color: bd.accentText)),
              const Spacer(),
              Text('brewdiary', style: T.serif(bd, size: 16, italic: true, color: bd.muted)),
            ]),
            const SizedBox(height: 26),
            Row(children: [
              Expanded(child: Text((name ?? '').trim().isEmpty ? 'My passport' : name!.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.serif(bd, size: 40, height: 1))),
              RankEmblem(g.rank.index, size: 46),
            ]),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              TextSpan(text: g.rank.title, style: T.serif(bd, size: 20, italic: true, color: bd.accentText)),
              TextSpan(text: '  ·  ${g.miles} miles  ·  ${g.families} tastes', style: T.sans(bd, size: 14, color: bd.muted)),
            ])),
            const SizedBox(height: 24),
            TasteMap(collections: g.collections, gilded: g.gilded),
            const SizedBox(height: 18),
            Text('Miles for range, never rounds.', style: T.caption(bd)),
          ]),
        );
      }),
    );
  }
}
