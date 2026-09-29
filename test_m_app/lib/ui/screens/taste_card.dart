// The taste passport — what you're into, to hold up for a bartender, and stamps
// for everywhere you've been (variety, never volume: ten nights at one bar is one
// stamp, and a dry night earns its own).
//
// It's worked out on this phone from your diary and shown on your screen, nothing
// more: brewdiary never sends it to a venue (no diary ever reaches a bar). You
// choose what shows — hide any line — and "Nothing with alcohol tonight" puts that
// first, in big type, for the nights you're sitting it out.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

Future<void> showTasteCard(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const TasteCardScreen()));

const _kindWords = {
  DrinkType.cocktail: 'Cocktails',
  DrinkType.beer: 'Beer',
  DrinkType.wine: 'Wine',
  DrinkType.spirit: 'Spirits',
  DrinkType.coffee: 'Coffee',
  DrinkType.tea: 'Tea',
  DrinkType.soft: 'Soft drinks',
  DrinkType.other: 'Something else',
};

class TasteCardScreen extends StatefulWidget {
  const TasteCardScreen({super.key});
  @override
  State<TasteCardScreen> createState() => _TasteCardScreenState();
}

class _TasteCardScreenState extends State<TasteCardScreen> {
  static const _hiddenKey = 'brewdiary.tastecard.hidden';
  late final Set<String> _hidden = {...(Prefs.getJson<List<dynamic>>(_hiddenKey) ?? const []).map((e) => '$e')};
  bool _dryTonight = false;
  bool _placesOnShare = true;
  bool _sharing = false;
  final _card = GlobalKey();

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    // Render with or without the place stamps, as chosen, then share the picture.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary = _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brewdiary-taste-passport.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: 'My taste passport on brewdiary'));
    } catch (_) {
      if (mounted) toast(context, "Couldn't make the image — try again.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _toggle(String line) {
    setState(() => _hidden.contains(line) ? _hidden.remove(line) : _hidden.add(line));
    Prefs.setJson(_hiddenKey, _hidden.toList());
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = tasteProfile(entryStore.entries);
    final name = auth.profile?.name;
    final lines = <(String key, String label, String value)>[
      if (p.favourites.isNotEmpty) ('into', 'Into', p.favourites.join(', ')),
      if (p.kinds.isNotEmpty) ('usually', 'Usually', p.kinds.map((k) => _kindWords[k] ?? k.name).join(' · ')),
      if (p.moods.isNotEmpty) ('mood', 'In the mood for', p.moods.join(', ')),
      if (p.noAlcoholShare >= .4) ('free', 'Often', 'alcohol-free — happy with a good non-alcoholic pour'),
    ];

    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SubPage(
          title: 'Taste passport',
          subtitle: 'Hold this up for the bartender.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RepaintBoundary(
              key: _card,
              child: _PassportCard(
                name: name,
                profile: p,
                passport: passport(entryStore.entries),
                lines: [for (final l in lines) if (!_hidden.contains(l.$1)) (l.$2, l.$3)],
                dryTonight: _dryTonight,
                showPlaces: _placesOnShare,
              ),
            ),
            const SizedBox(height: S.l),
            BdButton(_sharing ? 'Making it…' : 'Share my passport', icon: Ph.shareNetwork, onTap: _share),
            const SizedBox(height: S.xl),
            Group(children: [
              SettingRow(
                title: 'Nothing with alcohol tonight',
                hint: 'Puts it first, in big type.',
                trailing: BdToggle(on: _dryTonight, label: 'Nothing with alcohol tonight', onChanged: (v) => setState(() => _dryTonight = v)),
              ),
              SettingRow(
                title: 'Show place stamps',
                hint: 'Where you have been, on the card and in what you share.',
                trailing: BdToggle(on: _placesOnShare, label: 'Show place stamps', onChanged: (v) => setState(() => _placesOnShare = v)),
              ),
              for (final l in lines)
                SettingRow(
                  title: 'Show "${l.$2}"',
                  trailing: BdToggle(on: !_hidden.contains(l.$1), label: 'Show ${l.$2}', onChanged: (_) => _toggle(l.$1)),
                ),
            ]),
            const SizedBox(height: S.l),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Ph.lock, size: 16, color: bd.faint)),
              const SizedBox(width: S.s),
              Expanded(
                child: Text(
                  'Worked out on this phone from your diary. It goes nowhere unless you share it yourself — brewdiary never sends it to a venue.',
                  style: T.caption(bd),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The passport itself — the part that's shown to a bartender and shared.
class _PassportCard extends StatelessWidget {
  final String? name;
  final TasteProfile profile;
  final Passport passport;
  final List<(String, String)> lines;
  final bool dryTonight;
  final bool showPlaces;
  const _PassportCard({required this.name, required this.profile, required this.passport, required this.lines, required this.dryTonight, required this.showPlaces});

  static const _cover = Color(0xFF2A1A1E);
  static const _gold = Color(0xFFE6B25C);
  static const _cream = Color(0xFFF4ECDD);

  @override
  Widget build(BuildContext context) {
    final since = passport.since == null ? null : parseKey(passport.since!);
    TextStyle serif(double size, {Color color = _cream, bool italic = false}) => TextStyle(fontFamily: T.serifFamily, fontSize: size, color: color, height: 1.15, fontStyle: italic ? FontStyle.italic : FontStyle.normal);
    TextStyle label(Color color) => TextStyle(fontFamily: T.sansFamily, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w600, color: color);
    Widget stat(int n, String what) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n', style: serif(28, color: _gold)),
            Text(what.toUpperCase(), maxLines: 2, style: label(_cream.withValues(alpha: .7)).copyWith(letterSpacing: .8, fontSize: 9, height: 1.3)),
          ]),
        );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rTile),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A2328), _cover, Color(0xFF1C1216)]),
        border: Border.all(color: _gold.withValues(alpha: .35), width: 1),
      ),
      padding: const EdgeInsets.all(S.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('TASTE PASSPORT', style: label(_gold)),
          const Spacer(),
          Text('brewdiary', style: serif(15, color: _gold, italic: true)),
        ]),
        const SizedBox(height: S.m),
        Text(name ?? 'The bearer', style: serif(30)),
        if (since != null) Text('Keeping the diary since ${monthNames[since.month - 1]} ${since.year}', style: serif(14, color: _cream.withValues(alpha: .75), italic: true)),
        const SizedBox(height: S.l),
        Row(children: [
          if (showPlaces) stat(passport.places, passport.places == 1 ? 'place' : 'places'),
          stat(passport.kinds, 'kinds of 8'),
          stat(passport.families, 'drinks met'),
          stat(passport.dryNights, 'dry nights'),
        ]),
        if (showPlaces && passport.stamps.isNotEmpty) ...[
          const SizedBox(height: S.l),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < passport.stamps.length; i++) _Stamp(stamp: passport.stamps[i], tilt: [-8.0, 6.0, -3.0, 9.0, -6.0, 4.0][i % 6]),
          ]),
        ],
        const SizedBox(height: S.l),
        Container(height: 1, color: _gold.withValues(alpha: .25)),
        const SizedBox(height: S.m),
        if (dryTonight) ...[
          Text('NOTHING WITH ALCOHOL TONIGHT', style: label(_gold)),
          const SizedBox(height: 4),
          Text('Surprise me with something good and alcohol-free.', style: serif(22)),
          const SizedBox(height: S.m),
        ],
        if (profile.basedOn < 5 && lines.isEmpty && !dryTonight) Text('Log a few more drinks and this fills in.', style: serif(16, color: _cream.withValues(alpha: .75), italic: true)),
        for (final (k, v) in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: S.s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.toUpperCase(), style: label(_cream.withValues(alpha: .65))),
              const SizedBox(height: 2),
              Text(v, style: serif(20)),
            ]),
          ),
      ]),
    );
  }
}

class _Stamp extends StatelessWidget {
  final PassportStamp stamp;
  final double tilt;
  const _Stamp({required this.stamp, required this.tilt});
  @override
  Widget build(BuildContext context) {
    const gold = _PassportCard._gold;
    final d = parseKey(stamp.date);
    return Transform.rotate(
      angle: tilt * math.pi / 180,
      child: Container(
        width: 86,
        height: 86,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: gold.withValues(alpha: .8), width: 1.6)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(stamp.place.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: T.sansFamily, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .6, color: gold, height: 1.1)),
            const SizedBox(height: 3),
            Text('${d.day} ${monthNames[d.month - 1].substring(0, 3).toUpperCase()} ${d.year % 100}', style: TextStyle(fontFamily: T.sansFamily, fontSize: 8, letterSpacing: .8, color: gold.withValues(alpha: .85))),
          ]),
        ),
      ),
    );
  }
}
