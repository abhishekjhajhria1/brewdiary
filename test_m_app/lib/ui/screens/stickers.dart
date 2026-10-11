// Stickers for sharing a night. YOUR photo is the picture; brewdiary adds one small,
// sharp piece of type on top — the way a magazine sets a caption, a run app puts the
// run on a selfie. Fifteen designs, each a few lines of type and a fine rule:
//
//   Stats · Line · Caption · Cover · Date · Datestamp · Time · Menu
//   Ticket · Label · Coaster · Stamp · Receipt · Mosaic · Mark
//
// Each can be set in white, black or amber ink, straight on the photo or on a frosted
// or solid backing, in a serif, a sans or a mono. No made-up backgrounds; the brand is
// a small mark, never a banner.
//
// Nothing rewards drinking more: no sticker headlines how many drinks. What's on them
// is when, where, what was new, who you were with — the night, not the count.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import '../theme.dart';
import 'photo_studio.dart' show NightStory, StoryLine;

enum StickerKind { stats, line, caption, cover, date, datestamp, time, menu, ticket, label, coaster, stamp, receipt, mosaic, mark }

const stickerNames = {
  StickerKind.stats: 'Stats',
  StickerKind.line: 'Line',
  StickerKind.caption: 'Caption',
  StickerKind.cover: 'Cover',
  StickerKind.date: 'Date',
  StickerKind.datestamp: 'Datestamp',
  StickerKind.time: 'Time',
  StickerKind.menu: 'Menu',
  StickerKind.ticket: 'Ticket',
  StickerKind.label: 'Label',
  StickerKind.coaster: 'Coaster',
  StickerKind.stamp: 'Stamp',
  StickerKind.receipt: 'Receipt',
  StickerKind.mosaic: 'Mosaic',
  StickerKind.mark: 'Mark',
};

/// Where each sticker sits before it's moved (as an Alignment, -1..1).
const stickerHome = {
  StickerKind.stats: Alignment(-1, .9),
  StickerKind.line: Alignment(-1, .86),
  StickerKind.caption: Alignment(-1, .92),
  StickerKind.cover: Alignment(0, -1),
  StickerKind.date: Alignment(-1, -.9),
  StickerKind.datestamp: Alignment(.95, .95),
  StickerKind.time: Alignment(-1, -.88),
  StickerKind.menu: Alignment(.9, .85),
  StickerKind.ticket: Alignment(0, .9),
  StickerKind.label: Alignment(.9, .82),
  StickerKind.coaster: Alignment(.9, .86),
  StickerKind.stamp: Alignment(.85, -.8),
  StickerKind.receipt: Alignment(.9, .82),
  StickerKind.mosaic: Alignment(1, .9),
  StickerKind.mark: Alignment(1, .96),
};

/// The ink a sticker is printed in: white for most photos, black for bright ones,
/// or the one amber.
enum StickerInk { light, dark, amber }

/// What the type sits on: straight on the photo, a frosted pane, or a solid card.
enum StickerPlate { none, frost, card }

const plateNames = {StickerPlate.none: 'None', StickerPlate.frost: 'Frost', StickerPlate.card: 'Card'};

/// The face the big type is set in.
enum StickerFace { serif, sans, mono }

const faceNames = {StickerFace.serif: 'Serif', StickerFace.sans: 'Sans', StickerFace.mono: 'Mono'};

/// Stickers that are type on the photo, so a backing and a face can change them.
/// (A ticket, a label, a receipt or a stamp is its own object.)
bool takesPlate(StickerKind k) => const {StickerKind.stats, StickerKind.line, StickerKind.caption, StickerKind.date, StickerKind.time, StickerKind.menu, StickerKind.mark}.contains(k);
bool takesFace(StickerKind k) => takesPlate(k) || k == StickerKind.cover;

const paperTone = Color(0xFFF6F2EA);
const nightTone = Color(0xFF131216);
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

/// The line a sticker leads with: what the person typed, else the night's title.
String? leadLine(NightStory s) {
  final c = s.caption?.trim();
  if (c != null && c.isNotEmpty) return c;
  return s.title;
}

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
  final StickerPlate plate;
  final StickerFace face;

  /// One unit: the canvas width / 360, so a 1080-wide export is the same sticker, bigger.
  final double u;

  /// The diary, for the Mosaic sticker's month.
  final List<Entry> diary;

  const Sticker({super.key, required this.kind, required this.story, required this.ink, required this.u, this.plate = StickerPlate.none, this.face = StickerFace.serif, this.diary = const []});

  bool get _plated => plate != StickerPlate.none && takesPlate(kind);

  /// A card behind light or amber type is near-black; behind black type, paper.
  Color get _card => ink == StickerInk.dark ? paperTone : nightTone;
  Color get _ink => inkColor(ink);

  /// Type straight on a photo carries a soft shadow so it reads on anything.
  List<Shadow>? get _shade => _plated
      ? null
      : ink == StickerInk.dark
          ? [Shadow(color: Colors.white.withValues(alpha: .35), blurRadius: 8 * u)]
          : [Shadow(color: Colors.black.withValues(alpha: .5), blurRadius: 10 * u), Shadow(color: Colors.black.withValues(alpha: .22), blurRadius: 2 * u)];

  TextStyle _label(double size, {Color? color}) => (face == StickerFace.mono && takesFace(kind)
          ? T.rawMono(size * u, color ?? _ink, weight: FontWeight.w500, spacing: size * u * .12)
          : T.rawSans(size * u, color ?? _ink, weight: FontWeight.w600, spacing: size * u * .18))
      .copyWith(shadows: color == null ? _shade : null);

  TextStyle _sans(double size, {FontWeight weight = FontWeight.w500, Color? color}) =>
      (face == StickerFace.mono && takesFace(kind) ? T.rawMono(size * u, color ?? _ink, weight: FontWeight.w400) : T.rawSans(size * u, color ?? _ink, weight: weight))
          .copyWith(shadows: color == null ? _shade : null);

  /// The big type, in the chosen face. A serif is the house default; a sans is set
  /// light and tight; a mono is set like a typewriter.
  TextStyle _display(double size, {bool italic = false, double? height, Color? color}) {
    final c = color ?? _ink;
    final f = takesFace(kind) ? face : StickerFace.serif;
    final base = switch (f) {
      StickerFace.serif => T.rawSerif(size * u, c, italic: italic, height: height).copyWith(letterSpacing: -.015 * size * u),
      StickerFace.sans => T.rawSans(size * u * .92, c, weight: FontWeight.w300, spacing: -.03 * size * u).copyWith(height: height),
      StickerFace.mono => T.rawMono(size * u * .78, c, height: height, spacing: -.02 * size * u),
    };
    return base.copyWith(shadows: color == null ? _shade : null, fontFeatures: T.tnum);
  }

  List<String> get _names => [for (final l in story.lines) l.name];
  DateTime get _day => parseKey(story.dateKey);
  String get _mon3 => monthNames[_day.month - 1].substring(0, 3);
  String get _dayLabel => '${weekdays[mondayIndex(_day)]} ${_day.day} $_mon3';
  String get _dots => '${_day.day.toString().padLeft(2, '0')}.${_day.month.toString().padLeft(2, '0')}.${(_day.year % 100).toString().padLeft(2, '0')}';
  String? get _place => story.venue == null || story.venue!.trim().isEmpty ? null : shortPlace(story.venue!);

  /// The mark: four amber squares (the mosaic) and the wordmark.
  Widget _mark({double scale = 1, Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(size: Size.square(11 * u * scale), painter: _MarkPainter(_amber)),
        SizedBox(width: 6 * u * scale),
        Text('brewdiary', style: T.rawSerif(13 * scale * u, color ?? _ink, italic: true, height: 1).copyWith(shadows: color == null ? _shade : null)),
      ]);

  Widget _hairline(double width, {double alpha = .7}) => Container(width: width, height: .8 * u, color: _ink.withValues(alpha: alpha));

  /// Type on the photo, on a frosted pane, or on a card.
  Widget _backed(Widget child) {
    if (!_plated) return child;
    final r = BorderRadius.circular(14 * u);
    final pad = EdgeInsets.fromLTRB(16 * u, 14 * u, 16 * u, 14 * u);
    if (plate == StickerPlate.card) {
      return Container(padding: pad, decoration: BoxDecoration(color: _card, borderRadius: r), child: child);
    }
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14 * u, sigmaY: 14 * u),
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            color: ink == StickerInk.dark ? Colors.white.withValues(alpha: .42) : Colors.black.withValues(alpha: .28),
            borderRadius: r,
            border: Border.all(color: _ink.withValues(alpha: .16), width: .8 * u),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _backed(switch (kind) {
        StickerKind.stats => _stats(),
        StickerKind.line => _line(),
        StickerKind.caption => _caption(),
        StickerKind.cover => _cover(),
        StickerKind.date => _date(),
        StickerKind.datestamp => _datestamp(),
        StickerKind.time => _time(),
        StickerKind.menu => _menu(),
        StickerKind.ticket => _ticket(),
        StickerKind.label => _labelSticker(),
        StickerKind.coaster => _coaster(),
        StickerKind.stamp => _stamp(),
        StickerKind.receipt => _receipt(),
        StickerKind.mosaic => _mosaic(),
        StickerKind.mark => _markSticker(),
      });

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
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(c.value, maxLines: 1, style: _display(26, height: 1.05))),
                ]),
              ),
            ),
        ]),
        if (_names.isNotEmpty) ...[
          SizedBox(height: 12 * u),
          _hairline(double.infinity),
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
    final style = _display(31, italic: true, height: 1.12);
    final lead = story.caption?.trim();
    return SizedBox(
      width: 270 * u,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text([_dayLabel, ?_place].join('  ·  ').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(8.5)),
        SizedBox(height: 8 * u),
        if (lead != null && lead.isNotEmpty)
          Text(lead, maxLines: 4, overflow: TextOverflow.ellipsis, style: style)
        else if (story.dry || shown.isEmpty)
          Text(story.dry ? 'A dry night.' : (story.title ?? 'A night.'), style: style)
        else ...[
          for (var i = 0; i < shown.length; i++)
            Text(i == shown.length - 1 && more == 0 ? (shown.length > 1 ? 'then ${shown[i]}.' : '${shown[i]}.') : '${shown[i]},', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          if (more > 0) Text('and $more more.', style: style),
        ],
        SizedBox(height: 12 * u),
        _mark(scale: .85),
      ]),
    );
  }

  // ── Caption: a gallery label — the title, then where and when, small ───────────
  Widget _caption() {
    final when = '${_day.day} ${monthNames[_day.month - 1]} ${_day.year}';
    return SizedBox(
      width: 236 * u,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(leadLine(story) ?? (story.dry ? 'A dry night' : 'A night out'), maxLines: 3, overflow: TextOverflow.ellipsis, style: _display(21, italic: true, height: 1.15)),
        SizedBox(height: 6 * u),
        Text([?story.venue?.trim(), when].join(' — '), maxLines: 2, style: _sans(10.5, weight: FontWeight.w400)),
        if (story.mood != null) Text(story.mood!, style: _sans(10.5, weight: FontWeight.w400).copyWith(fontStyle: FontStyle.italic)),
        SizedBox(height: 9 * u),
        _hairline(26 * u),
        SizedBox(height: 7 * u),
        Text('BREWDIARY', style: _label(7)),
      ]),
    );
  }

  // ── Cover: a masthead across the top, the night as its cover line ──────────────
  Widget _cover() {
    final lead = leadLine(story);
    final big = switch (takesFace(kind) ? face : StickerFace.serif) { StickerFace.serif => 64.0, StickerFace.sans => 60.0, StickerFace.mono => 58.0 };
    return SizedBox(
      width: 324 * u,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text('brewdiary', maxLines: 1, style: _display(big, height: .95).copyWith(letterSpacing: -.035 * big * u))),
        SizedBox(height: 4 * u),
        _hairline(double.infinity, alpha: .9),
        SizedBox(height: 6 * u),
        Row(children: [
          Text('${weekdays[mondayIndex(_day)]} $_dots'.toUpperCase(), style: _label(8)),
          const Spacer(),
          if (_place != null) Flexible(child: Text(_place!.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(8))),
        ]),
        if (lead != null) ...[
          SizedBox(height: 10 * u),
          Text(lead, maxLines: 2, overflow: TextOverflow.ellipsis, style: _display(20, italic: true, height: 1.1)),
        ],
      ]),
    );
  }

  // ── Date: the quietest — the date, the day, the place ──────────────────────────
  Widget _date() => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${_day.day.toString().padLeft(2, '0')}.${_day.month.toString().padLeft(2, '0')}', style: _display(76, height: .95)),
        SizedBox(height: 4 * u),
        Text([weekdaysLong[mondayIndex(_day)], ?_place].join('  ·  ').toUpperCase(), style: _label(9)),
        SizedBox(height: 10 * u),
        _mark(scale: .85),
      ]);

  // ── Datestamp: the orange date a film camera burns into the corner ─────────────
  Widget _datestamp() {
    final text = "'${(_day.year % 100).toString().padLeft(2, '0')} ${_day.month} ${_day.day.toString().padLeft(2, '0')}";
    final color = ink == StickerInk.amber ? const Color(0xFFFF9E3D) : _ink;
    return CustomPaint(size: _SevenSeg.measure(text, u), painter: _SevenSeg(text, color, u));
  }

  // ── Time: when the night started, big ─────────────────────────────────────────
  Widget _time() {
    final t = story.time == null ? null : twelveHour(story.time!);
    final hm = t?.split(' ').first;
    final ap = t?.split(' ').last;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(t == null ? 'TONIGHT' : 'FROM', style: _label(8.5)),
      SizedBox(height: 2 * u),
      Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(hm ?? weekdays[mondayIndex(_day)], style: _display(68, height: 1)),
        if (ap != null) Padding(padding: EdgeInsets.only(top: 10 * u, left: 4 * u), child: Text(ap, style: _display(18, italic: true))),
      ]),
      SizedBox(height: 4 * u),
      Text([?_place, weekdaysLong[mondayIndex(_day)]].join('  ·  ').toUpperCase(), style: _label(8.5)),
    ]);
  }

  // ── Menu: tonight, set like a tasting menu (names, never how many) ────────────
  Widget _menu() {
    final names = _names.take(6).toList();
    final more = _names.length - names.length;
    return SizedBox(
      width: 206 * u,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('— TONIGHT —', style: _label(8)),
        SizedBox(height: 10 * u),
        if (names.isEmpty) Text(story.dry ? 'A dry night' : (leadLine(story) ?? 'A night out'), textAlign: TextAlign.center, style: _display(17, italic: true, height: 1.3)),
        for (final n in names) Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: _display(17, italic: true, height: 1.38)),
        if (more > 0) Text('& more', style: _display(13, italic: true, height: 1.4)),
        SizedBox(height: 9 * u),
        Transform.rotate(angle: math.pi / 4, child: Container(width: 4 * u, height: 4 * u, color: _ink.withValues(alpha: .85))),
        SizedBox(height: 9 * u),
        Text([?_place, _dots].join('  ·  ').toUpperCase(), textAlign: TextAlign.center, style: _label(7.5)),
      ]),
    );
  }

  // ── Ticket: an admission stub, perforated ─────────────────────────────────────
  Widget _ticket() {
    final paper = ink == StickerInk.dark ? nightTone : paperTone;
    final on = ink == StickerInk.dark ? const Color(0xFFF2EEE6) : _paperInk;
    final accent = ink == StickerInk.amber ? _amber : on;
    TextStyle mono(double s, {FontWeight w = FontWeight.w400, Color? c}) => T.rawMono(s * u, c ?? on, weight: w, height: 1.2);
    final w = 300 * u, h = 112 * u, stub = 78 * u;
    final title = leadLine(story) ?? _place ?? 'A night out';
    Widget cell(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: mono(6.5, c: on.withValues(alpha: .6))),
          SizedBox(height: 2 * u),
          Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(9, w: FontWeight.w500)),
        ]);
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 16 * u, offset: Offset(0, 5 * u))]),
      child: ClipPath(
        clipper: _TicketClip(notchX: w - stub, r: 7 * u),
        child: Container(
          width: w,
          height: h,
          color: paper,
          child: Row(children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16 * u, 13 * u, 12 * u, 12 * u),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('ADMIT ONE', style: mono(7.5, w: FontWeight.w500, c: accent).copyWith(letterSpacing: 1.6 * u)),
                    const Spacer(),
                    _mark(scale: .7, color: on),
                  ]),
                  const Spacer(),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rawSerif(21 * u, on, height: 1.05)),
                  const Spacer(),
                  Row(children: [
                    Expanded(child: cell('DATE', _dots)),
                    if (story.time != null) Expanded(child: cell('DOORS', twelveHour(story.time!).toUpperCase())),
                    Expanded(flex: 2, child: cell('AT', (_place ?? 'ANYWHERE').toUpperCase())),
                  ]),
                ]),
              ),
            ),
            CustomPaint(size: Size(1 * u, h), painter: _Perforation(on.withValues(alpha: .4), u)),
            SizedBox(
              width: stub - 1 * u,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12 * u, horizontal: 10 * u),
                child: Column(children: [
                  Text('No.', style: mono(6.5, c: on.withValues(alpha: .6))),
                  Text('${_day.month.toString().padLeft(2, '0')}${_day.day.toString().padLeft(2, '0')}', style: mono(13, w: FontWeight.w500)),
                  SizedBox(height: 6 * u),
                  Expanded(child: CustomPaint(size: Size.infinite, painter: _Barcode(story.dateKey, on, u))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Label: a bottle label — a double rule, the place, the edition ─────────────
  Widget _labelSticker() {
    final paper = ink == StickerInk.dark ? nightTone : paperTone;
    final on = ink == StickerInk.dark ? const Color(0xFFF2EEE6) : _paperInk;
    final accent = ink == StickerInk.amber ? _amber : on;
    final head = (_place ?? leadLine(story) ?? 'A night').toUpperCase();
    final sub = story.dry ? 'a dry night' : (story.mood ?? (story.caption?.trim().isNotEmpty == true ? story.caption!.trim() : 'a night out'));
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 16 * u, offset: Offset(0, 5 * u))]),
      child: Container(
        width: 182 * u,
        padding: EdgeInsets.all(7 * u),
        color: paper,
        child: Container(
          padding: EdgeInsets.fromLTRB(12 * u, 16 * u, 12 * u, 14 * u),
          decoration: BoxDecoration(border: Border.all(color: accent, width: .8 * u)),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 2 * u),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('BREWDIARY', style: T.rawSans(6.5 * u, accent, weight: FontWeight.w600, spacing: 2.2 * u)),
              SizedBox(height: 12 * u),
              FittedBox(fit: BoxFit.scaleDown, child: Text(head, maxLines: 1, style: T.rawSerif(24 * u, on, height: 1).copyWith(letterSpacing: 2.2 * u))),
              SizedBox(height: 5 * u),
              Text(sub, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: T.rawSerif(13 * u, on, italic: true, height: 1.15)),
              SizedBox(height: 12 * u),
              Row(children: [
                Expanded(child: Container(height: .8 * u, color: accent)),
                Padding(padding: EdgeInsets.symmetric(horizontal: 6 * u), child: Transform.rotate(angle: math.pi / 4, child: Container(width: 4 * u, height: 4 * u, color: accent))),
                Expanded(child: Container(height: .8 * u, color: accent)),
              ]),
              SizedBox(height: 10 * u),
              Text('EDITION', style: T.rawSans(6 * u, on.withValues(alpha: .7), weight: FontWeight.w600, spacing: 2 * u)),
              SizedBox(height: 2 * u),
              Text('${_day.day.toString().padLeft(2, '0')} · ${_day.month.toString().padLeft(2, '0')} · ${_day.year}', style: T.rawSerif(12 * u, on).copyWith(fontFeatures: T.tnum)),
              SizedBox(height: 8 * u),
              Text(weekdaysLong[mondayIndex(_day)].toUpperCase(), style: T.rawSans(6 * u, on.withValues(alpha: .7), weight: FontWeight.w600, spacing: 2 * u)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Coaster: a round card with the night around its rim ───────────────────────
  Widget _coaster() {
    final dark = ink != StickerInk.dark;
    final disc = dark ? nightTone : paperTone;
    final on = dark ? const Color(0xFFF2EEE6) : _paperInk;
    final accent = ink == StickerInk.amber ? _amber : on;
    final rim = ['BREWDIARY', ?_place?.toUpperCase(), weekdaysLong[mondayIndex(_day)].toUpperCase()].join('  ·  ');
    final size = 172 * u;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: disc, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 16 * u, offset: Offset(0, 5 * u))]),
        child: CustomPaint(
          painter: _CircleText('$rim  ·  ', T.rawSans(8 * u, accent, weight: FontWeight.w600), radius: size / 2 - 17 * u, ring: on.withValues(alpha: .5), u: u),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${_day.day}', style: T.rawSerif(52 * u, on, height: .95).copyWith(fontFeatures: T.tnum)),
              Text('${monthNames[_day.month - 1].toUpperCase()} ${_day.year}', style: T.rawSans(7 * u, on.withValues(alpha: .8), weight: FontWeight.w600, spacing: 1.6 * u)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Stamp: a round passport stamp, a little crooked ────────────────────────────
  Widget _stamp() {
    final place = _place?.toUpperCase() ?? 'BREWDIARY';
    final size = 158 * u;
    final shade = ink != StickerInk.dark;
    TextStyle lab(double s) => T.rawSans(s * u, _ink, weight: FontWeight.w600, spacing: s * u * .18);
    return Transform.rotate(
      angle: -.13,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _StampRing(_ink, u, shade: shade),
          child: Padding(
            padding: EdgeInsets.all(26 * u),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(story.dry ? 'DRY NIGHT' : 'BREWDIARY', style: lab(7.5)),
              SizedBox(height: 5 * u),
              Text('${_day.day} ${_mon3.toUpperCase()}', style: T.rawSerif(30 * u, _ink, height: 1).copyWith(fontFeatures: T.tnum)),
              Text('${_day.year}', style: lab(8)),
              SizedBox(height: 6 * u),
              Container(width: 54 * u, height: .8 * u, color: _ink.withValues(alpha: .8)),
              SizedBox(height: 6 * u),
              Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: lab(9.5)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Receipt: a small paper slip (prices only if you typed them) ────────────────
  Widget _receipt() {
    final lines = story.lines.take(7).toList();
    final more = story.lines.length - lines.length;
    final total = story.billTotal;
    TextStyle mono(double size, {FontWeight weight = FontWeight.w400}) => T.rawMono(size * u, _paperInk, weight: weight, height: 1.4).copyWith(fontFeatures: T.tnum);
    Widget dashes() => Padding(padding: EdgeInsets.symmetric(vertical: 6 * u), child: CustomPaint(size: Size(double.infinity, 1 * u), painter: _Dashes(_paperInk.withValues(alpha: .45), u)));
    Widget row(String left, String? right, {FontWeight weight = FontWeight.w400}) => Row(children: [
          Expanded(child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(8.5, weight: weight))),
          if (right != null) Text(right, style: mono(8.5, weight: weight)),
        ]);
    return Transform.rotate(
      angle: .035,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .28), blurRadius: 18 * u, offset: Offset(0, 6 * u))]),
        child: ClipPath(
          clipper: _ZigzagBottom(5 * u),
          child: Container(
            width: 180 * u,
            color: paperTone,
            padding: EdgeInsets.fromLTRB(14 * u, 14 * u, 14 * u, 18 * u),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: _mark(scale: .9, color: _paperInk)),
              SizedBox(height: 6 * u),
              if (story.venue != null) Text(story.venue!.toUpperCase(), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(7.5, weight: FontWeight.w500)),
              Text(
                '${_day.day.toString().padLeft(2, '0')}.${_day.month.toString().padLeft(2, '0')}.${_day.year}${story.time == null ? '' : '  ${story.time}'}',
                textAlign: TextAlign.center,
                style: mono(7.5),
              ),
              dashes(),
              if (lines.isEmpty) row(story.dry ? 'A dry night' : 'Nothing on it yet', null),
              for (final l in lines) row('${l.qty} × ${l.name}', l.price == null ? null : formatMoney(l.price! * l.qty, story.currency)),
              if (more > 0) row('+ $more more', null),
              if (total != null) ...[dashes(), row('TOTAL', formatMoney(total, story.currency), weight: FontWeight.w500)],
              dashes(),
              Text('THANK YOU  ·  BWDY.SITE', textAlign: TextAlign.center, style: mono(6.5, weight: FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Mosaic: the month, tonight's square ringed ─────────────────────────────────
  Widget _mosaic() {
    final grid = monthGrid(_day.year, _day.month - 1);
    final counts = countsByDate(diary);
    final kept = {for (final e in diary) if (e.date.startsWith(story.dateKey.substring(0, 7))) e.date}.length;
    final glass = ink == StickerInk.dark ? Colors.white.withValues(alpha: .72) : Colors.black.withValues(alpha: .42);
    final cell = 21.0 * u, gap = 4.0 * u;
    TextStyle lab(double s, Color c) => T.rawSans(s * u, c, weight: FontWeight.w600, spacing: s * u * .18);
    return Container(
      padding: EdgeInsets.fromLTRB(14 * u, 13 * u, 14 * u, 12 * u),
      decoration: BoxDecoration(color: glass, borderRadius: BorderRadius.circular(18 * u), border: Border.all(color: _ink.withValues(alpha: .18), width: .8 * u)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 7 * cell + 6 * gap,
          child: Row(children: [
            Text(monthNames[_day.month - 1].toUpperCase(), style: lab(8.5, _ink)),
            const Spacer(),
            Text(kept == 1 ? '1 night kept' : '$kept nights kept', style: lab(8.5, _ink.withValues(alpha: .75))),
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

  // ── Mark: almost nothing — the mark and the date, like a signature ─────────────
  Widget _markSticker() => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        _mark(scale: 1.1),
        SizedBox(width: 10 * u),
        Container(width: .8 * u, height: 14 * u, color: _ink.withValues(alpha: .6)),
        SizedBox(width: 10 * u),
        Text(_dots, style: _label(9.5)),
      ]);
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

/// A film camera's date-back: seven-segment digits, slanted, with a little glow.
class _SevenSeg extends CustomPainter {
  final String text;
  final Color color;
  final double u;
  _SevenSeg(this.text, this.color, this.u);

  static const _digits = {
    '0': 'abcdef',
    '1': 'bc',
    '2': 'abged',
    '3': 'abgcd',
    '4': 'fgbc',
    '5': 'afgcd',
    '6': 'afgedc',
    '7': 'abc',
    '8': 'abcdefg',
    '9': 'abcdfg',
  };

  static double _w(String ch, double u) => ch == ' ' ? 9 * u : (ch == "'" ? 6 * u : 15 * u);
  static Size measure(String text, double u) => Size(text.split('').fold<double>(0, (s, c) => s + _w(c, u)) + 8 * u, 32 * u);

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = color.withValues(alpha: .55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * u);
    final core = Paint()..color = color;
    canvas.save();
    canvas.translate(4 * u, 4 * u);
    canvas.skew(-.12, 0);
    canvas.translate(3 * u, 0);
    var x = 0.0;
    const h = 24.0, t = 3.0, w = 11.0;
    for (final ch in text.split('')) {
      if (ch == "'") {
        final r = Rect.fromLTWH(x + 1 * u, 0, 2.6 * u, 6 * u);
        for (final p in [glow, core]) {
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(1 * u)), p);
        }
      }
      final segs = _digits[ch];
      if (segs != null) {
        Rect seg(String s) => switch (s) {
              'a' => Rect.fromLTWH(x + t * u, 0, (w - 2 * t) * u, t * u),
              'b' => Rect.fromLTWH(x + (w - t) * u, t * u * .7, t * u, (h / 2 - t) * u),
              'c' => Rect.fromLTWH(x + (w - t) * u, (h / 2 + t * .3) * u, t * u, (h / 2 - t) * u),
              'd' => Rect.fromLTWH(x + t * u, (h - t) * u, (w - 2 * t) * u, t * u),
              'e' => Rect.fromLTWH(x, (h / 2 + t * .3) * u, t * u, (h / 2 - t) * u),
              'f' => Rect.fromLTWH(x, t * u * .7, t * u, (h / 2 - t) * u),
              _ => Rect.fromLTWH(x + t * u, (h / 2 - t / 2) * u, (w - 2 * t) * u, t * u),
            };
        for (final p in [glow, core]) {
          for (final s in segs.split('')) {
            canvas.drawRRect(RRect.fromRectAndRadius(seg(s), Radius.circular(1.1 * u)), p);
          }
        }
      }
      x += _w(ch, u);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SevenSeg o) => o.text != text || o.color != color || o.u != u;
}

/// Text set around a circle (a coaster's rim), spaced to close the ring exactly.
class _CircleText extends CustomPainter {
  final String text;
  final TextStyle style;
  final double radius;
  final Color ring;
  final double u;
  _CircleText(this.text, this.style, {required this.radius, required this.ring, required this.u});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8 * u
      ..color = ring;
    canvas.drawCircle(c, radius + 11 * u, ringPaint);
    canvas.drawCircle(c, radius - 9 * u, ringPaint);
    final glyphs = [
      for (final ch in text.split(''))
        TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout(),
    ];
    final total = glyphs.fold<double>(0, (s, g) => s + g.width);
    final circumference = 2 * math.pi * radius;
    // Repeat the text if it's short, then share the leftover space between letters.
    final reps = math.max(1, (circumference / (total * 1.15)).floor());
    final all = [for (var r = 0; r < reps; r++) ...glyphs];
    final used = total * reps;
    final gap = (circumference - used) / all.length;
    var a = -math.pi / 2;
    for (final g in all) {
      final arc = (g.width + gap) / radius;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a + arc / 2 + math.pi / 2);
      g.paint(canvas, Offset(-g.width / 2, -radius - g.height / 2));
      canvas.restore();
      a += arc;
    }
  }

  @override
  bool shouldRepaint(_CircleText o) => o.text != text || o.radius != radius || o.style != style;
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
      if (shade) {
        canvas.drawCircle(
          c,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width + 2 * u
            ..color = Colors.black.withValues(alpha: .18)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * u),
        );
      }
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = ink,
      );
    }

    ring(r - 2 * u, 2.4 * u);
    ring(r - 13 * u, 1 * u);
    final tick = Paint()
      ..color = ink
      ..strokeWidth = 1 * u;
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
    final p = Paint()
      ..color = color
      ..strokeWidth = size.height;
    for (var x = 0.0; x < size.width; x += 5 * u) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 2.5 * u, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_Dashes o) => false;
}

/// A ticket's tear line: a column of small dashes.
class _Perforation extends CustomPainter {
  final Color color;
  final double u;
  _Perforation(this.color, this.u);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.width;
    for (var y = 9 * u; y < size.height - 9 * u; y += 6 * u) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 3 * u), p);
    }
  }

  @override
  bool shouldRepaint(_Perforation o) => false;
}

/// A barcode from the date: decorative, the same bars for the same night.
class _Barcode extends CustomPainter {
  final String seed;
  final Color color;
  final double u;
  _Barcode(this.seed, this.color, this.u);
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed.hashCode);
    final p = Paint()..color = color;
    var x = 0.0;
    while (x < size.width) {
      final w = (1 + r.nextInt(3)) * .8 * u;
      if (x + w > size.width) break;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      x += w + (1 + r.nextInt(2)) * .9 * u;
    }
  }

  @override
  bool shouldRepaint(_Barcode o) => o.seed != seed || o.color != color;
}

/// A ticket: a rectangle with a round notch top and bottom at the tear line.
class _TicketClip extends CustomClipper<Path> {
  final double notchX;
  final double r;
  _TicketClip({required this.notchX, required this.r});
  @override
  Path getClip(Size size) {
    final body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r * .6)));
    final notches = Path()
      ..addOval(Rect.fromCircle(center: Offset(notchX, 0), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(notchX, size.height), radius: r));
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  bool shouldReclip(_TicketClip o) => o.notchX != notchX || o.r != r;
}

class _ZigzagBottom extends CustomClipper<Path> {
  final double tooth;
  _ZigzagBottom(this.tooth);
  @override
  Path getClip(Size size) {
    final p = Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - tooth);
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
