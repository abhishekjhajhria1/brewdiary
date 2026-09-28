// The photo studio — put a brewdiary overlay on a photo from the night and share
// it, the way a run app puts your route on a selfie.
//
// What an overlay may say: the date, the place, the party, who you were with, the
// mood, your streak of nights kept (dry nights count), your mosaic. What it never
// says: how many drinks. A share card that counts rounds is a leaderboard you win
// by drinking more (CLAUDE.md: nothing rewards drinking more).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/date.dart';
import '../../core/derive.dart';
import '../../core/types.dart';
import '../../data/entries.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

/// Everything an overlay can draw from — counts of NIGHTS, never of drinks.
class NightStory {
  final String dateKey;
  final String? title; // a party's name, or the drink
  final String? venue;
  final String? mood;
  final int? withPeople; // friends at the party, you not included
  final bool dry;
  const NightStory({required this.dateKey, this.title, this.venue, this.mood, this.withPeople, this.dry = false});

  factory NightStory.fromEntry(Entry e) => NightStory(dateKey: e.date, title: e.type == DrinkType.none ? 'A dry night' : e.drink, venue: e.venue, mood: e.mood, dry: e.type == DrinkType.none, withPeople: e.whoWith?.length);
}

Future<void> showPhotoStudio(BuildContext context, NightStory story, {String? photo}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PhotoStudio(story: story, photo: photo)));

/// The overlays, in the order they're offered.
const overlayNames = ['Classic', 'Mosaic', 'Big date', 'Nights kept', 'Mood', 'The party', 'Place', 'Ticket', 'Polaroid', 'Stamp', 'Film'];

class PhotoStudio extends StatefulWidget {
  final NightStory story;
  final String? photo;
  const PhotoStudio({super.key, required this.story, this.photo});
  @override
  State<PhotoStudio> createState() => _PhotoStudioState();
}

class _PhotoStudioState extends State<PhotoStudio> {
  final _frame = GlobalKey();
  late String? _photo = widget.photo;
  int _overlay = 0;
  bool _showPlace = true;
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 88);
      if (x != null) setState(() => _photo = x.path);
    } catch (_) {
      if (mounted) toast(context, "Couldn't open photos — check brewdiary's permission in Settings.");
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _frame.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brewdiary-${widget.story.dateKey}-${overlayNames[_overlay].toLowerCase().replaceAll(' ', '-')}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
    } catch (_) {
      if (mounted) toast(context, "Couldn't make the image — try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final story = _showPlace ? widget.story : NightStory(dateKey: widget.story.dateKey, title: widget.story.title, mood: widget.story.mood, withPeople: widget.story.withPeople, dry: widget.story.dry);
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SubPage(
          title: 'Share the night',
          large: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(rTile),
              child: RepaintBoundary(
                key: _frame,
                child: AspectRatio(aspectRatio: 4 / 5, child: OverlayFrame(photo: _photo, story: story, overlay: _overlay)),
              ),
            ),
            const SizedBox(height: S.m),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: overlayNames.length,
                separatorBuilder: (_, _) => const SizedBox(width: S.s),
                itemBuilder: (_, i) => BdChip(overlayNames[i], active: i == _overlay, onTap: () => setState(() => _overlay = i)),
              ),
            ),
            const SizedBox(height: S.l),
            Row(children: [
              Expanded(child: BdButton('Photos', kind: BtnKind.secondary, icon: Ph.images, onTap: () => _pick(ImageSource.gallery))),
              const SizedBox(width: S.s),
              Expanded(child: BdButton('Camera', kind: BtnKind.secondary, icon: Ph.camera, onTap: () => _pick(ImageSource.camera))),
            ]),
            if (widget.story.venue != null) ...[
              const SizedBox(height: S.m),
              Group(children: [
                SettingRow(title: 'Show the place', trailing: BdToggle(on: _showPlace, label: 'Show the place', onChanged: (v) => setState(() => _showPlace = v))),
              ]),
            ],
            const SizedBox(height: S.l),
            BdButton(_busy ? 'Making it…' : 'Share', icon: Ph.shareNetwork, onTap: _share),
            const SizedBox(height: S.m),
            Text('Your photo stays on your phone until you share it. Overlays show the night, never how many drinks.', textAlign: TextAlign.center, style: T.caption(bd)),
          ]),
        ),
      ),
    );
  }
}

/// A photo (or a warm placeholder) with one overlay on top. Sized by its parent.
class OverlayFrame extends StatelessWidget {
  final String? photo;
  final NightStory story;
  final int overlay;
  const OverlayFrame({super.key, required this.photo, required this.story, required this.overlay});

  @override
  Widget build(BuildContext context) {
    final entries = entryStore.entries;
    return LayoutBuilder(builder: (context, box) {
      final u = box.maxWidth / 360; // design unit: a 360-wide frame
      final bg = photo == null
          ? const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A1E14), Color(0xFF12131A), Color(0xFF3A1F2A)])))
          : Image(image: photo!.startsWith('http') ? NetworkImage(photo!) as ImageProvider : FileImage(File(photo!)), fit: BoxFit.cover);
      final layer = switch (overlay) {
        0 => _classic(u),
        1 => _mosaic(u, entries),
        2 => _bigDate(u),
        3 => _nightsKept(u, entries),
        4 => _mood(u),
        5 => _party(u),
        6 => _place(u),
        7 => _ticket(u),
        8 => null, // polaroid wraps the photo instead
        9 => _stamp(u),
        _ => null, // film wraps the photo too
      };
      if (overlay == 8) return _polaroid(u, bg);
      if (overlay == 10) return _film(u, bg);
      return Stack(fit: StackFit.expand, children: [bg, ?layer]);
    });
  }

  // ── pieces ────────────────────────────────────────────────────────────────
  static const _white = Color(0xFFFAF6EE);
  static const _amber = Color(0xFFE6A64B);
  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 12)];

  TextStyle _serif(double size, {Color color = _white, bool italic = false}) =>
      TextStyle(fontFamily: T.serifFamily, fontSize: size, color: color, height: 1.05, fontStyle: italic ? FontStyle.italic : FontStyle.normal, shadows: _shadow);
  TextStyle _sans(double size, {Color color = _white, FontWeight weight = FontWeight.w600, double spacing = 0}) =>
      TextStyle(fontFamily: T.sansFamily, fontSize: size, color: color, fontWeight: weight, letterSpacing: spacing, shadows: _shadow);

  DateTime get _date => parseKey(story.dateKey);
  String get _longDate => formatDayLongYear(story.dateKey);
  String get _dayName => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][_date.weekday - 1];

  Widget _scrim({bool top = false}) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: const [Color(0xB3000000), Color(0x00000000)],
            stops: const [0, .6],
          ),
        ),
      );

  Widget _wordmark(double u, {Color color = _white}) => Text('brewdiary', style: _serif(15 * u, color: color, italic: true));

  Widget _classic(double u) => Stack(fit: StackFit.expand, children: [
        _scrim(),
        Positioned(
          left: 22 * u,
          right: 22 * u,
          bottom: 22 * u,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_longDate.toUpperCase(), style: _sans(10 * u, spacing: 1.6 * u)),
            SizedBox(height: 6 * u),
            if (story.title != null) Text(story.title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: _serif(34 * u)),
            if (story.venue != null) Padding(padding: EdgeInsets.only(top: 4 * u), child: Text(story.venue!, style: _sans(13 * u, weight: FontWeight.w500))),
            SizedBox(height: 12 * u),
            _wordmark(u, color: _amber),
          ]),
        ),
      ]);

  Widget _mosaic(double u, List<Entry> entries) {
    final counts = countsByDate(entries);
    final dry = dryDates(entries);
    final end = _date;
    const weeks = 12;
    final start = addDays(end, -(weeks * 7 - 1));
    return Stack(fit: StackFit.expand, children: [
      _scrim(),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        bottom: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (var w = 0; w < weeks; w++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : 3 * u),
                  child: Column(children: [
                    for (var d = 0; d < 7; d++)
                      () {
                        final k = toKey(addDays(start, w * 7 + d));
                        final level = intensityLevel(counts[k] ?? 0);
                        final isDry = dry.contains(k) && level == 0;
                        return Padding(
                          padding: EdgeInsets.only(bottom: 3 * u),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: level == 0 ? const Color(0x22FFFFFF) : _amber.withValues(alpha: const [0.0, .35, .55, .78, 1.0][level]),
                                border: isDry ? Border.all(color: const Color(0x99FFFFFF), width: .8 * u) : (k == story.dateKey ? Border.all(color: _white, width: 1.2 * u) : null),
                                borderRadius: BorderRadius.circular(2 * u),
                              ),
                            ),
                          ),
                        );
                      }(),
                  ]),
                ),
              ),
          ]),
          SizedBox(height: 10 * u),
          Row(children: [
            Expanded(child: Text('Twelve weeks of nights', style: _sans(12 * u, weight: FontWeight.w500))),
            _wordmark(u, color: _amber),
          ]),
        ]),
      ),
    ]);
  }

  Widget _bigDate(double u) => Stack(fit: StackFit.expand, children: [
        _scrim(top: true),
        Positioned(
          left: 22 * u,
          top: 20 * u,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_date.day}', style: _serif(96 * u)),
            Text('${monthNames[_date.month - 1]} ${_date.year}'.toUpperCase(), style: _sans(12 * u, spacing: 2 * u)),
            SizedBox(height: 2 * u),
            Text(_dayName, style: _serif(18 * u, italic: true)),
          ]),
        ),
        Positioned(right: 20 * u, bottom: 18 * u, child: _wordmark(u)),
      ]);

  Widget _nightsKept(double u, List<Entry> entries) {
    final streak = stats(entries).current;
    return Stack(fit: StackFit.expand, children: [
      _scrim(),
      Positioned(
        left: 22 * u,
        bottom: 22 * u,
        right: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$streak', style: _serif(80 * u, color: _amber)),
          Text(streak == 1 ? 'night kept' : 'nights kept in a row', style: _sans(15 * u)),
          SizedBox(height: 4 * u),
          Text('Dry ones count too.', style: _serif(14 * u, italic: true)),
          SizedBox(height: 12 * u),
          _wordmark(u),
        ]),
      ),
    ]);
  }

  Widget _mood(double u) => Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0x40000000)),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * u),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text((story.mood ?? (story.dry ? 'clear-headed' : 'a good one')), textAlign: TextAlign.center, style: _serif(56 * u, italic: true)),
              SizedBox(height: 10 * u),
              Text(_longDate.toUpperCase(), style: _sans(10 * u, spacing: 1.6 * u)),
            ]),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 18 * u, child: Center(child: _wordmark(u))),
      ]);

  Widget _party(double u) {
    final n = story.withPeople ?? 0;
    return Stack(fit: StackFit.expand, children: [
      _scrim(),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        bottom: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TONIGHT', style: _sans(10 * u, color: _amber, spacing: 2 * u)),
          SizedBox(height: 6 * u),
          Text(story.title ?? 'The night', maxLines: 2, overflow: TextOverflow.ellipsis, style: _serif(36 * u)),
          SizedBox(height: 6 * u),
          Text([if (n > 0) 'with $n ${n == 1 ? 'friend' : 'friends'}', if (story.venue != null) story.venue!, _dayName].join(' · '), style: _sans(13 * u, weight: FontWeight.w500)),
          SizedBox(height: 12 * u),
          _wordmark(u, color: _amber),
        ]),
      ),
    ]);
  }

  Widget _place(double u) => Stack(fit: StackFit.expand, children: [
        _scrim(top: true),
        Positioned(
          left: 20 * u,
          right: 20 * u,
          top: 20 * u,
          child: Row(children: [
            Icon(PhFill.mapPin, size: 22 * u, color: _amber, shadows: _shadow),
            SizedBox(width: 8 * u),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(story.venue ?? 'Somewhere good', maxLines: 1, overflow: TextOverflow.ellipsis, style: _serif(24 * u)),
                Text(_longDate, style: _sans(11 * u, weight: FontWeight.w500)),
              ]),
            ),
          ]),
        ),
        Positioned(right: 20 * u, bottom: 18 * u, child: _wordmark(u)),
      ]);

  Widget _ticket(double u) => Stack(fit: StackFit.expand, children: [
        Positioned(
          left: 18 * u,
          right: 18 * u,
          bottom: 18 * u,
          child: Container(
            padding: EdgeInsets.all(16 * u),
            decoration: BoxDecoration(color: _white, borderRadius: BorderRadius.circular(10 * u)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ADMIT ONE', style: TextStyle(fontFamily: T.sansFamily, fontSize: 9 * u, letterSpacing: 2 * u, fontWeight: FontWeight.w700, color: const Color(0xFFB8742A))),
                  SizedBox(height: 4 * u),
                  Text(story.title ?? 'The night', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: T.serifFamily, fontSize: 24 * u, color: const Color(0xFF1B1714))),
                  SizedBox(height: 2 * u),
                  Text([if (story.venue != null) story.venue!, _longDate].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: T.sansFamily, fontSize: 11 * u, color: const Color(0xFF5D5668))),
                ]),
              ),
              Container(width: 1, height: 52 * u, margin: EdgeInsets.symmetric(horizontal: 12 * u), color: const Color(0x331B1714)),
              RotatedBox(quarterTurns: 3, child: Text('brewdiary', style: TextStyle(fontFamily: T.serifFamily, fontStyle: FontStyle.italic, fontSize: 13 * u, color: const Color(0xFF1B1714)))),
            ]),
          ),
        ),
      ]);

  Widget _polaroid(double u, Widget photo) => ColoredBox(
        color: _white,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18 * u, 18 * u, 18 * u, 0),
          child: Column(children: [
            Expanded(child: ClipRect(child: SizedBox.expand(child: photo))),
            SizedBox(
              height: 76 * u,
              child: Row(children: [
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(story.title ?? story.mood ?? 'A good night', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: T.serifFamily, fontStyle: FontStyle.italic, fontSize: 22 * u, color: const Color(0xFF1B1714))),
                    Text(_longDate, style: TextStyle(fontFamily: T.sansFamily, fontSize: 11 * u, color: const Color(0xFF5D5668))),
                  ]),
                ),
                Text('brewdiary', style: TextStyle(fontFamily: T.serifFamily, fontStyle: FontStyle.italic, fontSize: 13 * u, color: const Color(0xFFB8742A))),
              ]),
            ),
          ]),
        ),
      );

  Widget _stamp(double u) => Stack(fit: StackFit.expand, children: [
        Positioned(
          right: 22 * u,
          bottom: 26 * u,
          child: Transform.rotate(
            angle: -12 * math.pi / 180,
            child: Container(
              width: 132 * u,
              height: 132 * u,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _amber, width: 3 * u)),
              child: Container(
                margin: EdgeInsets.all(6 * u),
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _amber, width: 1 * u)),
                child: Padding(
                  padding: EdgeInsets.all(10 * u),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('BREWDIARY', style: _sans(8 * u, color: _amber, spacing: 1.6 * u)),
                    SizedBox(height: 4 * u),
                    Text((story.venue ?? story.title ?? 'Night out').toUpperCase(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: _sans(12 * u, color: _amber, weight: FontWeight.w700)),
                    SizedBox(height: 4 * u),
                    Text('${_date.day} ${monthNames[_date.month - 1].substring(0, 3).toUpperCase()} ${_date.year}', style: _sans(9 * u, color: _amber, spacing: 1 * u)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]);

  Widget _film(double u, Widget photo) {
    Widget holes() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < 9; i++) Container(width: 14 * u, height: 9 * u, decoration: BoxDecoration(color: const Color(0xFFE9E0D0), borderRadius: BorderRadius.circular(2 * u))),
        ]);
    return ColoredBox(
      color: const Color(0xFF111111),
      child: Column(children: [
        SizedBox(height: 26 * u, child: holes()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * u),
          child: Row(children: [
            Text('BREWDIARY 400', style: TextStyle(fontFamily: T.sansFamily, fontSize: 9 * u, letterSpacing: 1.6 * u, color: _amber, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${_date.day.toString().padLeft(2, '0')}·${_date.month.toString().padLeft(2, '0')}·${_date.year % 100}', style: TextStyle(fontFamily: T.sansFamily, fontSize: 9 * u, letterSpacing: 1.6 * u, color: _amber)),
          ]),
        ),
        SizedBox(height: 6 * u),
        Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 14 * u), child: ClipRect(child: SizedBox.expand(child: photo)))),
        SizedBox(height: 6 * u),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * u),
          child: Row(children: [
            Expanded(child: Text(story.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: T.serifFamily, fontStyle: FontStyle.italic, fontSize: 14 * u, color: _white))),
            if (story.venue != null) Text(story.venue!, style: TextStyle(fontFamily: T.sansFamily, fontSize: 10 * u, color: const Color(0xFFBDB3A6))),
          ]),
        ),
        SizedBox(height: 26 * u, child: holes()),
      ]),
    );
  }
}
