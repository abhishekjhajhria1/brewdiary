// The photo studio — put a brewdiary overlay on a photo from the night and share
// it, the way a run app puts your route on a selfie. Twelve designs: a receipt, a
// festival lineup, run-app stats, a menu card, the haul from a bottle shop, a
// ticket, cheers, a polaroid, film, a postcard, a passport stamp and the mosaic.
//
// What goes on it comes from the night itself: what you logged that day (and, on
// the night, the table orders the staff accepted), where, when and with whom. The
// person can tick lines off, add one, put a price on a line or the bill's total.
// The lineup of what you had is the hero — no design turns the number of drinks
// into the big headline stat (CLAUDE.md: nothing rewards drinking more).
//
// The brand is a hint, never a banner: a small mosaic mark and the wordmark.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../../data/table_order.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

/// One line on the night's bill: what, how many, and a price only if the person
/// typed one (brewdiary never knows what a venue charged).
class StoryLine {
  final String name;
  final int qty;
  final num? price;
  const StoryLine(this.name, {this.qty = 1, this.price});
  StoryLine copyWith({int? qty, num? Function()? price}) => StoryLine(name, qty: qty ?? this.qty, price: price != null ? price() : this.price);
}

/// Everything an overlay can draw from.
class NightStory {
  final String dateKey;
  final String? title; // a party's name, or the drink
  final String? venue;
  final String? mood;
  final String? note;
  final int? withPeople; // friends there, you not included
  final List<String> who;
  final bool dry;
  final List<StoryLine> lines;
  final num? total; // typed by the person, never fetched
  final String currency;
  final String? time; // "21:40", when the night's first entry was made
  final int newToYou; // drinks had for the first time tonight (variety, not volume)
  const NightStory({
    required this.dateKey,
    this.title,
    this.venue,
    this.mood,
    this.note,
    this.withPeople,
    this.who = const [],
    this.dry = false,
    this.lines = const [],
    this.total,
    this.currency = defaultCurrency,
    this.time,
    this.newToYou = 0,
  });

  /// The whole day from the diary: lines grouped by drink, the place you were at
  /// most, everyone you were with, the first entry's time.
  factory NightStory.fromDay(String dateKey, List<Entry> all, {String? title, String currency = defaultCurrency}) {
    final day = all.where((e) => e.date == dateKey).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final drinks = day.where((e) => e.type != DrinkType.none).toList();
    final byName = <String, StoryLine>{};
    for (final e in drinks) {
      final k = e.drink.trim().toLowerCase();
      final had = byName[k];
      byName[k] = had == null ? StoryLine(e.drink.trim()) : had.copyWith(qty: had.qty + 1);
    }
    final venues = <String, int>{};
    for (final e in day) {
      final v = e.venue?.trim();
      if (v != null && v.isNotEmpty) venues[v] = (venues[v] ?? 0) + 1;
    }
    final venue = venues.isEmpty ? null : (venues.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final who = <String>{for (final e in day) ...?e.whoWith}.toList();
    final before = {for (final e in all) if (e.date.compareTo(dateKey) < 0 && e.type != DrinkType.none) e.drink.trim().toLowerCase()};
    String? time;
    if (day.isNotEmpty) {
      final t = DateTime.tryParse(day.first.createdAt)?.toLocal();
      if (t != null && toKey(t) == dateKey) time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    final dry = day.isNotEmpty && drinks.isEmpty;
    return NightStory(
      dateKey: dateKey,
      title: title ?? (dry ? 'A dry night' : (drinks.isEmpty ? null : drinks.last.drink)),
      venue: venue,
      mood: day.reversed.map((e) => e.mood).whereType<String>().firstOrNull,
      note: day.map((e) => e.note).whereType<String>().where((n) => n.trim().isNotEmpty).firstOrNull,
      withPeople: who.isEmpty ? null : who.length,
      who: who,
      dry: dry,
      lines: byName.values.toList(),
      currency: currency,
      time: time,
      newToYou: byName.keys.where((k) => !before.contains(k)).length,
    );
  }

  factory NightStory.fromEntry(Entry e, [List<Entry>? all]) =>
      NightStory.fromDay(e.date, all ?? entryStore.entries, title: e.type == DrinkType.none ? 'A dry night' : e.drink, currency: PlaceStore.instance.currency);

  NightStory copyWith({List<StoryLine>? lines, num? Function()? total, String? Function()? venue}) => NightStory(
        dateKey: dateKey,
        title: title,
        venue: venue != null ? venue() : this.venue,
        mood: mood,
        note: note,
        withPeople: withPeople,
        who: who,
        dry: dry,
        lines: lines ?? this.lines,
        total: total != null ? total() : this.total,
        currency: currency,
        time: time,
        newToYou: newToYou,
      );

  /// The bill's total: what was typed, else the sum of priced lines, else none.
  num? get billTotal {
    if (total != null) return total;
    final priced = lines.where((l) => l.price != null);
    if (priced.isEmpty) return null;
    return priced.fold<num>(0, (s, l) => s + l.price! * l.qty);
  }
}

Future<void> showPhotoStudio(BuildContext context, NightStory story, {String? photo}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PhotoStudio(story: story, photo: photo)));

/// The overlays, in the order they're offered.
const overlayNames = ['Receipt', 'Lineup', 'Stats', 'Menu', 'The haul', 'Ticket', 'Cheers', 'Polaroid', 'Film', 'Postcard', 'Stamp', 'Mosaic'];

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
  late NightStory _story = widget.story;
  late final Set<int> _off = {}; // lines left off the overlay
  int _overlay = 0;
  bool _showPlace = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.story.dateKey == todayKey()) _addTonightsOrders();
  }

  /// On the night itself, the table orders the staff accepted join the bill.
  Future<void> _addTonightsOrders() async {
    try {
      final mine = await TableApi.mine();
      final known = {for (final l in _story.lines) l.name.toLowerCase()};
      final extra = <StoryLine>[
        for (final r in mine.where((r) => r.status == 'accepted'))
          for (final l in r.lines)
            if (!known.contains(l.name.toLowerCase())) StoryLine(l.name, qty: l.qty),
      ];
      if (extra.isNotEmpty && mounted) setState(() => _story = _story.copyWith(lines: [..._story.lines, ...extra]));
    } catch (_) {
      // signed out or offline: the diary's lines are enough
    }
  }

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
      final file = File('${dir.path}/brewdiary-${_story.dateKey}-${overlayNames[_overlay].toLowerCase().replaceAll(' ', '-')}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
    } catch (_) {
      if (mounted) toast(context, "Couldn't make the image — try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  NightStory get _shown {
    final lines = [for (var i = 0; i < _story.lines.length; i++) if (!_off.contains(i)) _story.lines[i]];
    return _story.copyWith(lines: lines, venue: _showPlace ? null : () => null);
  }

  Future<void> _editLines() async {
    await showBdSheet<void>(context, title: "What's on it", builder: (_) => _LinesEditor(
          story: _story,
          off: _off,
          onChanged: (story, off) => setState(() {
            _story = story;
            _off
              ..clear()
              ..addAll(off);
          }),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final shown = _shown;
    final onIt = _story.lines.length - _off.length;
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
                child: AspectRatio(aspectRatio: 4 / 5, child: OverlayFrame(photo: _photo, story: shown, overlay: _overlay)),
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
            const SizedBox(height: S.m),
            Group(children: [
              GroupTile(
                icon: Ph.receipt,
                title: "What's on it",
                subtitle: [
                  onIt == 0 ? 'Nothing logged yet — add a line' : '$onIt ${onIt == 1 ? 'line' : 'lines'}',
                  if (_story.billTotal != null) 'total ${formatMoney(_story.billTotal!, _story.currency)}',
                ].join(' · '),
                chevron: true,
                onTap: _editLines,
              ),
              if (_story.venue != null) SettingRow(title: 'Show the place', trailing: BdToggle(on: _showPlace, label: 'Show the place', onChanged: (v) => setState(() => _showPlace = v))),
            ]),
            const SizedBox(height: S.l),
            BdButton(_busy ? 'Making it…' : 'Share', icon: Ph.shareNetwork, onTap: _share),
            const SizedBox(height: S.m),
            Text('Your photo stays on your phone until you share it.', textAlign: TextAlign.center, style: T.caption(bd)),
          ]),
        ),
      ),
    );
  }
}

/// Tick lines on or off, add one, price a line, type the bill's total.
class _LinesEditor extends StatefulWidget {
  final NightStory story;
  final Set<int> off;
  final void Function(NightStory story, Set<int> off) onChanged;
  const _LinesEditor({required this.story, required this.off, required this.onChanged});
  @override
  State<_LinesEditor> createState() => _LinesEditorState();
}

class _LinesEditorState extends State<_LinesEditor> {
  late NightStory _s = widget.story;
  late final Set<int> _off = {...widget.off};
  final _name = TextEditingController();
  late final _total = TextEditingController(text: widget.story.total?.toString() ?? '');

  @override
  void dispose() {
    _name.dispose();
    _total.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_s, _off);

  void _add() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    setState(() => _s = _s.copyWith(lines: [..._s.lines, StoryLine(n)]));
    _name.clear();
    _emit();
  }

  Future<void> _price(int i) async {
    final line = _s.lines[i];
    final c = TextEditingController(text: line.price?.toString() ?? '');
    final v = await showBdSheet<String>(context, title: 'Price of ${line.name}', builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GlassField(controller: c, hint: 'Each, in ${_s.currency}', keyboard: const TextInputType.numberWithOptions(decimal: true), autofocus: true, onSubmitted: (t) => Navigator.pop(ctx, t)),
          const SizedBox(height: S.m),
          BdButton('Done', onTap: () => Navigator.pop(ctx, c.text)),
        ]));
    c.dispose();
    if (v == null) return;
    final p = num.tryParse(v.replaceAll(',', '').trim());
    setState(() => _s = _s.copyWith(lines: [for (var j = 0; j < _s.lines.length; j++) j == i ? _s.lines[j].copyWith(price: () => p) : _s.lines[j]]));
    _emit();
  }

  void _qty(int i, int d) {
    final q = (_s.lines[i].qty + d).clamp(1, 20);
    setState(() => _s = _s.copyWith(lines: [for (var j = 0; j < _s.lines.length; j++) j == i ? _s.lines[j].copyWith(qty: q) : _s.lines[j]]));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_s.lines.isNotEmpty)
        Group(children: [
          for (var i = 0; i < _s.lines.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                IconBtn(
                  _off.contains(i) ? Ph.circle : PhFill.checkCircle,
                  tooltip: _off.contains(i) ? 'Put ${_s.lines[i].name} on' : 'Leave ${_s.lines[i].name} off',
                  color: _off.contains(i) ? bd.faint : bd.accentText,
                  onTap: () {
                    setState(() => _off.contains(i) ? _off.remove(i) : _off.add(i));
                    _emit();
                  },
                ),
                const SizedBox(width: S.s),
                Expanded(child: Text(_s.lines[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.row(bd))),
                IconBtn(Ph.minus, tooltip: 'One less', size: 16, onTap: _s.lines[i].qty > 1 ? () => _qty(i, -1) : null),
                Text('${_s.lines[i].qty}', style: T.row(bd)),
                IconBtn(Ph.plus, tooltip: 'One more', size: 16, onTap: () => _qty(i, 1)),
                TextAction(_s.lines[i].price == null ? 'Price' : formatMoney(_s.lines[i].price!, _s.currency), faint: _s.lines[i].price == null, onTap: () => _price(i)),
              ]),
            ),
        ]),
      const SizedBox(height: S.m),
      Row(children: [
        Expanded(child: GlassField(controller: _name, hint: 'Add a line — a dish, a bottle, a round', action: TextInputAction.done, onSubmitted: (_) => _add())),
        const SizedBox(width: S.s),
        BdButton('Add', kind: BtnKind.secondary, height: 48, onTap: _add),
      ]),
      const SizedBox(height: S.l),
      const Label('The bill'),
      const SizedBox(height: S.s),
      GlassField(
        controller: _total,
        hint: _s.lines.any((l) => l.price != null) ? 'Total — or leave it to add up the prices' : 'Total, if you want it on (optional)',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (t) {
          final v = num.tryParse(t.replaceAll(',', '').trim());
          _s = _s.copyWith(total: () => v);
          _emit();
        },
      ),
      const SizedBox(height: S.s),
      Text('Only you type prices — brewdiary never sees what a place charged. Nothing here is saved; it lives on the picture.', style: T.caption(bd)),
    ]);
  }
}

/// A photo (or a warm placeholder) with one overlay on top. Sized by its parent;
/// every measure is in units of a 360-wide frame so a 1080 export is just bigger.
class OverlayFrame extends StatelessWidget {
  final String? photo;
  final NightStory story;
  final int overlay;

  /// A ready image instead of [photo] (tests and previews).
  final ImageProvider? image;
  const OverlayFrame({super.key, required this.photo, required this.story, required this.overlay, this.image});

  @override
  Widget build(BuildContext context) {
    final entries = entryStore.entries;
    return LayoutBuilder(builder: (context, box) {
      final u = box.maxWidth / 360;
      final bg = image != null
          ? Image(image: image!, fit: BoxFit.cover)
          : photo == null
          ? const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A2614), Color(0xFF15141B), Color(0xFF3B1E2B)])))
          : Image(image: photo!.startsWith('http') ? NetworkImage(photo!) as ImageProvider : FileImage(File(photo!)), fit: BoxFit.cover);
      final o = _Overlays(u, story, entries);
      return switch (overlay) {
        0 => Stack(fit: StackFit.expand, children: [bg, o.receipt()]),
        1 => Stack(fit: StackFit.expand, children: [bg, o.lineup()]),
        2 => Stack(fit: StackFit.expand, children: [bg, o.runStats()]),
        3 => Stack(fit: StackFit.expand, children: [bg, o.menu()]),
        4 => Stack(fit: StackFit.expand, children: [bg, o.haul()]),
        5 => Stack(fit: StackFit.expand, children: [bg, o.ticket()]),
        6 => Stack(fit: StackFit.expand, children: [bg, o.cheers()]),
        7 => o.polaroid(bg),
        8 => o.film(bg),
        9 => o.postcard(bg),
        10 => Stack(fit: StackFit.expand, children: [bg, o.stamp()]),
        _ => Stack(fit: StackFit.expand, children: [bg, o.mosaic()]),
      };
    });
  }
}

class _Overlays {
  final double u;
  final NightStory s;
  final List<Entry> entries;
  _Overlays(this.u, this.s, this.entries);

  // ── palette and type ──────────────────────────────────────────────────────
  static const white = Color(0xFFFAF6EE);
  static const paper = Color(0xFFF6F1E7);
  static const ink = Color(0xFF1B1714);
  static const inkSoft = Color(0xFF6A6058);
  static const amber = Color(0xFFE6A64B);
  static const amberDeep = Color(0xFFB8742A);
  static const shadow = [Shadow(color: Color(0x8C000000), blurRadius: 14)];

  TextStyle serif(double size, {Color color = white, bool italic = false, double height = 1.05, bool shade = true, FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: T.serifFamily, fontSize: size * u, color: color, height: height, fontWeight: weight, fontStyle: italic ? FontStyle.italic : FontStyle.normal, shadows: shade ? shadow : null);
  TextStyle sans(double size, {Color color = white, FontWeight weight = FontWeight.w600, double spacing = 0, bool shade = true, double? height}) => TextStyle(
      fontFamily: T.sansFamily,
      fontSize: size * u,
      color: color,
      fontWeight: weight,
      letterSpacing: spacing * u,
      height: height,
      shadows: shade ? shadow : null,
      fontFeatures: const [ui.FontFeature.tabularFigures()]);
  // Money in the serif — it carries the ₹ glyph.
  TextStyle money(double size, {Color color = white, bool shade = true, FontWeight weight = FontWeight.w500}) => serif(size, color: color, shade: shade, weight: weight, height: 1.1);

  // ── the night, in words ───────────────────────────────────────────────────
  DateTime get date => parseKey(s.dateKey);
  String get longDate => formatDayLongYear(s.dateKey);
  String get dayName => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][date.weekday - 1];
  String get mon => monthNames[date.month - 1].substring(0, 3).toUpperCase();
  String get shortDate => '${date.day} $mon ${date.year}';
  String get heading => s.title ?? s.venue ?? (s.dry ? 'A dry night' : 'The night');
  String get place => s.venue ?? 'Somewhere good';
  List<StoryLine> get lines => s.lines.isEmpty ? [StoryLine(s.dry ? 'Nothing with alcohol' : heading)] : s.lines;
  String? get total => s.billTotal == null ? null : formatMoney(s.billTotal!, s.currency);
  String people({String none = 'Just me'}) {
    final w = s.who;
    if (w.isEmpty) return (s.withPeople ?? 0) > 0 ? '${s.withPeople} friends' : none;
    if (w.length <= 2) return w.join(' & ');
    return '${w.take(2).join(', ')} +${w.length - 2}';
  }

  int get streak => stats(entries).current;

  // ── shared pieces ─────────────────────────────────────────────────────────
  /// The brand, as a hint: a 2×2 mosaic mark and the wordmark.
  Widget mark({Color color = white, double scale = 1, bool shade = true}) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 11 * u * scale,
          height: 11 * u * scale,
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 1.2 * u * scale,
            crossAxisSpacing: 1.2 * u * scale,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              for (final a in const [.35, .6, .8, 1.0]) DecoratedBox(decoration: BoxDecoration(color: amber.withValues(alpha: a), borderRadius: BorderRadius.circular(1 * u * scale))),
            ],
          ),
        ),
        SizedBox(width: 5 * u * scale),
        Text('brewdiary', style: serif(13 * scale, color: color, italic: true, shade: shade)),
      ]);

  Widget scrim({bool top = false, double strength = .72, double reach = .62}) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: strength), Colors.black.withValues(alpha: 0)],
            stops: [0, reach],
          ),
        ),
      );

  Widget dashes({Color color = inkSoft, double gap = 3}) => LayoutBuilder(builder: (_, c) {
        final n = (c.maxWidth / ((gap + 3) * u)).floor();
        return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (var i = 0; i < n; i++) Container(width: 3 * u, height: .9 * u, color: color)]);
      });

  Widget leader(String left, String right, TextStyle l, TextStyle r) => LayoutBuilder(
        builder: (_, c) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth * .66), child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: l)),
          Expanded(child: Padding(padding: EdgeInsets.only(left: 5 * u, right: 5 * u, bottom: 3 * u), child: _Dots(color: (r.color ?? white).withValues(alpha: .45), u: u))),
          Text(right, style: r),
        ]),
      );

  /// A small field: a spaced label over a value.
  Widget field(String label, String value, {Color labelColor = const Color(0xB3FFFFFF), Color color = white, double size = 20, bool shade = true, bool serifValue = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: sans(7.5, color: labelColor, spacing: 1.4, weight: FontWeight.w600, shade: shade)),
        SizedBox(height: 3 * u),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: serifValue ? serif(size, color: color, shade: shade) : sans(size, color: color, weight: FontWeight.w600, shade: shade, height: 1.05)),
      ]);

  // ── 1. Receipt ────────────────────────────────────────────────────────────
  Widget receipt() {
    final shown = lines.take(7).toList();
    final more = lines.length - shown.length;
    final t = total;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .35, reach: .5),
      Positioned(
        right: 20 * u,
        bottom: 22 * u,
        width: 186 * u,
        child: Transform.rotate(
          angle: -2.4 * math.pi / 180,
          child: DecoratedBox(
            decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 18 * u, offset: Offset(0, 6 * u))]),
            child: ClipPath(
              clipper: _Zigzag(4.5 * u),
              child: Container(
                color: paper,
                padding: EdgeInsets.fromLTRB(14 * u, 16 * u, 14 * u, 14 * u),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Text(place.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, style: sans(11, color: ink, spacing: 1.6, weight: FontWeight.w700, shade: false, height: 1.2)),
                  SizedBox(height: 3 * u),
                  Text([shortDate, ?s.time].join('  ·  '), textAlign: TextAlign.center, style: sans(7.5, color: inkSoft, spacing: .8, weight: FontWeight.w500, shade: false)),
                  SizedBox(height: 9 * u),
                  dashes(),
                  SizedBox(height: 8 * u),
                  for (final l in shown)
                    Padding(
                      padding: EdgeInsets.only(bottom: 4 * u),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 18 * u, child: Text('${l.qty}×', style: sans(8.5, color: inkSoft, weight: FontWeight.w500, shade: false))),
                        Expanded(child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(9, color: ink, weight: FontWeight.w500, shade: false))),
                        if (l.price != null) Text(formatMoney(l.price! * l.qty, s.currency), style: money(9.5, color: ink, shade: false)),
                      ]),
                    ),
                  if (more > 0) Text('+ $more more', style: sans(8, color: inkSoft, weight: FontWeight.w500, shade: false)),
                  SizedBox(height: 4 * u),
                  dashes(),
                  SizedBox(height: 7 * u),
                  if (t != null)
                    Row(children: [
                      Text('TOTAL', style: sans(9, color: ink, spacing: 1.4, weight: FontWeight.w700, shade: false)),
                      const Spacer(),
                      Text(t, style: money(15, color: ink, shade: false, weight: FontWeight.w600)),
                    ])
                  else
                    Text('THANK YOU, COME AGAIN', textAlign: TextAlign.center, style: sans(7.5, color: inkSoft, spacing: 1.4, weight: FontWeight.w600, shade: false)),
                  SizedBox(height: 10 * u),
                  SizedBox(height: 22 * u, child: CustomPaint(painter: _Barcode(s.dateKey.hashCode ^ place.hashCode, ink))),
                  SizedBox(height: 6 * u),
                  Center(child: mark(color: ink, scale: .8, shade: false)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  // ── 2. Lineup — a festival poster of the night ────────────────────────────
  Widget lineup() {
    final ls = lines.take(6).toList();
    final size = ls.length <= 2 ? 40.0 : ls.length <= 4 ? 30.0 : 23.0;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .82, reach: .78),
      scrim(top: true, strength: .45, reach: .35),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        top: 22 * u,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TONIGHT AT', style: sans(8, color: amber, spacing: 2.2)),
              SizedBox(height: 3 * u),
              Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(18, italic: true)),
            ]),
          ),
          Text(s.time ?? dayName.substring(0, 3).toUpperCase(), style: sans(10, spacing: 1.2)),
        ]),
      ),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        bottom: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < ls.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: 2 * u),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22 * u, child: Padding(padding: EdgeInsets.only(top: size * .22 * u), child: Text((i + 1).toString().padLeft(2, '0'), style: sans(8.5, color: amber, spacing: .6)))),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: ls[i].name),
                      if (ls[i].qty > 1) TextSpan(text: '  ×${ls[i].qty}', style: sans(size * .34, color: const Color(0xCCFFFFFF), weight: FontWeight.w500)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: serif(size, height: 1.08, weight: i == 0 ? FontWeight.w500 : FontWeight.w400),
                  ),
                ),
              ]),
            ),
          SizedBox(height: 12 * u),
          Container(height: .8 * u, color: const Color(0x55FFFFFF)),
          SizedBox(height: 9 * u),
          Row(children: [
            Expanded(child: Text([dayName, longDate].join('  ·  ').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(8, spacing: 1.4, weight: FontWeight.w500))),
            mark(scale: .9),
          ]),
        ]),
      ),
    ]);
  }

  // ── 3. Stats — the run-app look ───────────────────────────────────────────
  Widget runStats() {
    Widget cell(String l, String v) => Expanded(child: field(l, v, size: 19));
    final kept = streak;
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .8, reach: .6),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        bottom: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(longDate.toUpperCase(), style: sans(8, color: amber, spacing: 1.8)),
          SizedBox(height: 5 * u),
          Text(heading, maxLines: 2, overflow: TextOverflow.ellipsis, style: serif(28)),
          SizedBox(height: 16 * u),
          Row(children: [cell('PLACE', s.venue ?? '—'), cell('STARTED', s.time ?? '—'), cell('WITH', people(none: 'Solo'))]),
          SizedBox(height: 12 * u),
          Row(children: [
            cell('NEW TO YOU', '${s.newToYou}'),
            cell('NIGHTS KEPT', '$kept'),
            cell('MOOD', s.mood ?? (s.dry ? 'clear' : '—')),
          ]),
          SizedBox(height: 16 * u),
          Row(children: [
            Expanded(child: Text(lines.map((l) => l.name).take(4).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(12, italic: true, color: const Color(0xD9FFFFFF)))),
            SizedBox(width: 10 * u),
            mark(scale: .9),
          ]),
        ]),
      ),
    ]);
  }

  // ── 4. Menu — tonight, set like a menu card ───────────────────────────────
  Widget menu() {
    final ls = lines.take(6).toList();
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Color(0x33000000)),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4 * u),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 252 * u,
              padding: EdgeInsets.fromLTRB(22 * u, 24 * u, 22 * u, 18 * u),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .38), border: Border.all(color: const Color(0x66FAF6EE), width: .8 * u)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(place.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, style: sans(10.5, spacing: 2.6, weight: FontWeight.w600, height: 1.3)),
                SizedBox(height: 10 * u),
                _Ornament(u: u, color: amber),
                SizedBox(height: 10 * u),
                Text('Tonight', style: serif(22, italic: true)),
                SizedBox(height: 14 * u),
                for (final l in ls)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8 * u),
                    child: leader(l.name, l.price != null ? formatMoney(l.price! * l.qty, s.currency) : (l.qty > 1 ? '×${l.qty}' : ''), serif(15), l.price != null ? money(12.5, color: amber) : sans(10, color: amber)),
                  ),
                if (total != null) ...[
                  SizedBox(height: 4 * u),
                  Container(height: .8 * u, color: const Color(0x44FAF6EE)),
                  SizedBox(height: 8 * u),
                  leader('The bill', total!, serif(14, italic: true), money(15, color: amber, weight: FontWeight.w600)),
                ],
                SizedBox(height: 12 * u),
                Text(longDate, style: sans(8, spacing: 1, weight: FontWeight.w500, color: const Color(0xCCFFFFFF))),
                SizedBox(height: 10 * u),
                mark(scale: .8),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  // ── 5. The haul — bottles from a shop ─────────────────────────────────────
  Widget haul() {
    final ls = lines.take(5).toList();
    return Stack(fit: StackFit.expand, children: [
      scrim(top: true, strength: .6, reach: .45),
      scrim(strength: .7, reach: .5),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        top: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('THE HAUL', style: sans(9, color: amber, spacing: 2.6)),
          SizedBox(height: 4 * u),
          Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(28)),
          SizedBox(height: 2 * u),
          Text(longDate, style: sans(9, weight: FontWeight.w500, spacing: .4)),
        ]),
      ),
      Positioned(
        left: 18 * u,
        right: 18 * u,
        bottom: 20 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < ls.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3 * u),
                  child: _Bottle(u: u, name: ls[i].name, qty: ls[i].qty, tall: i.isEven, tint: const [Color(0xFFF6F1E7), Color(0xFFEFD9B4), Color(0xFFF2E4D0), Color(0xFFE9C990), Color(0xFFF6F1E7)][i % 5]),
                ),
              ),
            if (ls.length < 3) const Spacer(),
          ]),
          SizedBox(height: 12 * u),
          Row(children: [
            mark(scale: .9),
            const Spacer(),
            if (total != null) Text(total!, style: money(22, weight: FontWeight.w500)),
          ]),
        ]),
      ),
    ]);
  }

  // ── 6. Ticket ─────────────────────────────────────────────────────────────
  Widget ticket() {
    final admit = 1 + s.who.length.clamp(0, 98) + (s.who.isEmpty ? (s.withPeople ?? 0) : 0);
    Widget f(String l, String v) => Expanded(child: field(l, v, labelColor: inkSoft, color: ink, size: 11.5, shade: false));
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .45, reach: .5),
      Positioned(
        left: 18 * u,
        right: 18 * u,
        bottom: 20 * u,
        height: 128 * u,
        child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 18 * u, offset: Offset(0, 6 * u))]),
          child: ClipPath(
            clipper: _TicketClip(stubAt: 248 * u, notch: 9 * u, radius: 10 * u),
            child: ColoredBox(
              color: paper,
              child: Row(children: [
                SizedBox(
                  width: 248 * u,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16 * u, 14 * u, 14 * u, 12 * u),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ADMIT ${admit > 99 ? '99+' : admit}', style: sans(8, color: amberDeep, spacing: 2, weight: FontWeight.w700, shade: false)),
                      SizedBox(height: 5 * u),
                      Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(24, color: ink, shade: false)),
                      const Spacer(),
                      Row(children: [f('DATE', shortDate), f('DOORS', s.time ?? '—'), f('AT', s.venue ?? '—')]),
                    ]),
                  ),
                ),
                CustomPaint(size: Size(1, 128 * u), painter: _Perforation(u, inkSoft.withValues(alpha: .5))),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12 * u, horizontal: 8 * u),
                    child: Row(children: [
                      Expanded(child: CustomPaint(size: Size.infinite, painter: _Barcode(s.dateKey.hashCode, ink, vertical: true))),
                      SizedBox(width: 6 * u),
                      RotatedBox(quarterTurns: 3, child: mark(color: ink, scale: .78, shade: false)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  // ── 7. Cheers — who you were with ─────────────────────────────────────────
  Widget cheers() {
    final names = s.who.isEmpty ? (s.withPeople != null && s.withPeople! > 0 ? ['${s.withPeople} friends'] : ['the night']) : s.who.take(4).toList();
    final big = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Color(0x47000000)),
      Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 26 * u),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Cheers to', style: serif(20, italic: true, color: amber)),
            SizedBox(height: 6 * u),
            Text(big, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: serif(names.length > 2 ? 32 : 42, height: 1.05)),
            SizedBox(height: 16 * u),
            Text(lines.map((l) => l.name).take(4).join('  ·  '), textAlign: TextAlign.center, maxLines: 2, style: sans(10.5, weight: FontWeight.w500, spacing: .3, height: 1.4)),
            SizedBox(height: 6 * u),
            Text([?s.venue, shortDate].join('  ·  ').toUpperCase(), textAlign: TextAlign.center, style: sans(8, spacing: 1.6, color: const Color(0xCCFFFFFF))),
          ]),
        ),
      ),
      Positioned(left: 0, right: 0, bottom: 18 * u, child: Center(child: mark(scale: .9))),
    ]);
  }

  // ── 8. Polaroid ───────────────────────────────────────────────────────────
  Widget polaroid(Widget photo) => ColoredBox(
        color: const Color(0xFF2A241F),
        child: Center(
          child: Transform.rotate(
            angle: 1.6 * math.pi / 180,
            child: Container(
              margin: EdgeInsets.all(22 * u),
              decoration: BoxDecoration(color: white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 16 * u, offset: Offset(0, 6 * u))]),
              padding: EdgeInsets.fromLTRB(14 * u, 14 * u, 14 * u, 0),
              child: Column(children: [
                Expanded(child: ClipRect(child: SizedBox.expand(child: photo))),
                SizedBox(
                  height: 72 * u,
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(lines.map((l) => l.name).take(3).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(19, italic: true, color: ink, shade: false)),
                        SizedBox(height: 3 * u),
                        Text([?s.venue, longDate].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(8.5, color: inkSoft, weight: FontWeight.w500, shade: false)),
                      ]),
                    ),
                    mark(color: ink, scale: .8, shade: false),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );

  // ── 9. Film — a frame from a roll, with the camera's date stamp ───────────
  Widget film(Widget photo) {
    Widget holes() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < 9; i++) Container(width: 14 * u, height: 9 * u, decoration: BoxDecoration(color: const Color(0xFFE9E0D0), borderRadius: BorderRadius.circular(2 * u))),
        ]);
    const orange = Color(0xFFFF8A3D);
    final frameNo = '${(date.day % 36) + 1}A';
    return ColoredBox(
      color: const Color(0xFF111111),
      child: Column(children: [
        SizedBox(height: 26 * u, child: holes()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * u),
          child: Row(children: [
            Text('BREWDIARY 400', style: sans(8, color: amber, spacing: 1.6, weight: FontWeight.w700, shade: false)),
            const Spacer(),
            Text('▸ $frameNo', style: sans(8, color: amber, spacing: 1.2, shade: false)),
          ]),
        ),
        SizedBox(height: 6 * u),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * u),
            child: Stack(fit: StackFit.expand, children: [
              ClipRect(child: SizedBox.expand(child: photo)),
              Positioned(
                right: 12 * u,
                bottom: 10 * u,
                child: Text("'${(date.year % 100).toString().padLeft(2, '0')}  ${date.month}  ${date.day}",
                    style: sans(14, color: orange, weight: FontWeight.w700, spacing: 1.2, shade: false).copyWith(shadows: [Shadow(color: orange.withValues(alpha: .7), blurRadius: 6 * u)])),
              ),
            ]),
          ),
        ),
        SizedBox(height: 7 * u),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * u),
          child: Row(children: [
            Expanded(child: Text(lines.map((l) => l.name).take(3).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(13, italic: true, shade: false))),
            if (s.venue != null) Text(s.venue!, style: sans(9, color: const Color(0xFFBDB3A6), weight: FontWeight.w500, shade: false)),
          ]),
        ),
        SizedBox(height: 26 * u, child: holes()),
      ]),
    );
  }

  // ── 10. Postcard ──────────────────────────────────────────────────────────
  Widget postcard(Widget photo) {
    final words = s.note ?? (s.mood != null ? 'A ${s.mood} one.' : null) ?? (s.dry ? 'Clear-headed and glad of it.' : 'Wish you were here.');
    return ColoredBox(
      color: paper,
      child: Column(children: [
        Expanded(
          flex: 62,
          child: Stack(fit: StackFit.expand, children: [
            ClipRect(child: SizedBox.expand(child: photo)),
            Positioned.fill(child: scrim(strength: .55, reach: .5)),
            Positioned(
              left: 16 * u,
              right: 16 * u,
              bottom: 12 * u,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Greetings from', style: serif(14, italic: true, color: amber)),
                SizedBox(height: 2 * u),
                Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(32, weight: FontWeight.w500).copyWith(height: .95)),
              ]),
            ),
          ]),
        ),
        Expanded(
          flex: 38,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 * u, 12 * u, 16 * u, 12 * u),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(words, maxLines: 4, overflow: TextOverflow.ellipsis, style: serif(15, italic: true, color: ink, shade: false, height: 1.3))),
                  Text(lines.map((l) => l.name).take(3).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(8.5, color: inkSoft, weight: FontWeight.w500, shade: false)),
                ]),
              ),
              Container(width: .8 * u, margin: EdgeInsets.symmetric(horizontal: 12 * u), color: const Color(0x331B1714)),
              SizedBox(
                width: 104 * u,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  SizedBox(
                    height: 52 * u,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.topRight, children: [
                      _PostStamp(u: u, entries: entries, dateKey: s.dateKey),
                      Positioned(right: 24 * u, top: 14 * u, child: CustomPaint(size: Size(70 * u, 28 * u), painter: _Postmark(u, inkSoft.withValues(alpha: .55)))),
                    ]),
                  ),
                  const Spacer(),
                  for (final line in [s.time == null ? shortDate : '$shortDate · ${s.time}', 'to: future me'])
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.only(bottom: 2 * u, top: 5 * u),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x331B1714)))),
                      child: Text(line, maxLines: 1, style: sans(8, color: ink, weight: FontWeight.w500, shade: false)),
                    ),
                  SizedBox(height: 8 * u),
                  mark(color: ink, scale: .72, shade: false),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── 11. Stamp — a passport stamp for the place ────────────────────────────
  Widget stamp() => Stack(fit: StackFit.expand, children: [
        scrim(strength: .35, reach: .55),
        Positioned(
          right: 24 * u,
          bottom: 30 * u,
          child: Transform.rotate(
            angle: -11 * math.pi / 180,
            child: Opacity(
              opacity: .92,
              child: Container(
                width: 150 * u,
                height: 150 * u,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: amber, width: 3 * u)),
                child: Container(
                  margin: EdgeInsets.all(6 * u),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: amber, width: 1 * u)),
                  child: Padding(
                    padding: EdgeInsets.all(14 * u),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('★  BREWDIARY  ★', style: sans(6.5, color: amber, spacing: 1.4, shade: false)),
                      SizedBox(height: 6 * u),
                      Text(place.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: sans(12.5, color: amber, weight: FontWeight.w800, spacing: .6, shade: false, height: 1.1)),
                      SizedBox(height: 5 * u),
                      Container(height: 1 * u, width: 70 * u, color: amber),
                      SizedBox(height: 5 * u),
                      Text(shortDate, style: sans(9.5, color: amber, spacing: 1.2, weight: FontWeight.w700, shade: false)),
                      SizedBox(height: 3 * u),
                      Text(s.dry ? 'DRY NIGHT · KEPT' : 'NIGHT KEPT', style: sans(6.5, color: amber, spacing: 1.6, shade: false)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 22 * u,
          bottom: 26 * u,
          right: 190 * u,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lines.map((l) => l.name).take(3).join('\n'), maxLines: 3, style: serif(16, height: 1.2)),
          ]),
        ),
      ]);

  // ── 12. Mosaic — twelve weeks, tonight lit ────────────────────────────────
  Widget mosaic() {
    final counts = countsByDate(entries);
    final dry = dryDates(entries);
    final end = date;
    const weeks = 15;
    final start = addDays(end, -(weeks * 7 - 1));
    return Stack(fit: StackFit.expand, children: [
      scrim(strength: .8, reach: .65),
      Positioned(
        left: 22 * u,
        right: 22 * u,
        bottom: 22 * u,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(26)),
          SizedBox(height: 3 * u),
          Text([?s.venue, longDate].join('  ·  '), style: sans(9, weight: FontWeight.w500, spacing: .3)),
          SizedBox(height: 14 * u),
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
                        final tonight = k == s.dateKey;
                        return Padding(
                          padding: EdgeInsets.only(bottom: 3 * u),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: level == 0 ? const Color(0x24FFFFFF) : amber.withValues(alpha: const [0.0, .35, .55, .78, 1.0][level]),
                                border: tonight ? Border.all(color: white, width: 1.4 * u) : (isDry ? Border.all(color: const Color(0x99FFFFFF), width: .8 * u) : null),
                                borderRadius: BorderRadius.circular(2 * u),
                                boxShadow: tonight ? [BoxShadow(color: amber.withValues(alpha: .8), blurRadius: 8 * u)] : null,
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
            Expanded(child: Text('${streak == 1 ? 'One night' : '$streak nights'} kept · dry ones count', style: sans(9.5, weight: FontWeight.w500))),
            mark(scale: .9),
          ]),
        ]),
      ),
    ]);
  }
}

// ── small painters and pieces ────────────────────────────────────────────────

class _Dots extends StatelessWidget {
  final Color color;
  final double u;
  const _Dots({required this.color, required this.u});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final n = (c.maxWidth / (4 * u)).floor().clamp(0, 200);
        return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (var i = 0; i < n; i++) Container(width: 1.2 * u, height: 1.2 * u, decoration: BoxDecoration(color: color, shape: BoxShape.circle))]);
      });
}

class _Ornament extends StatelessWidget {
  final double u;
  final Color color;
  const _Ornament({required this.u, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 28 * u, height: .8 * u, color: color),
        SizedBox(width: 6 * u),
        Transform.rotate(angle: math.pi / 4, child: Container(width: 5 * u, height: 5 * u, color: color)),
        SizedBox(width: 6 * u),
        Container(width: 28 * u, height: .8 * u, color: color),
      ]);
}

/// A label-shaped bottle tag for the haul.
class _Bottle extends StatelessWidget {
  final double u;
  final String name;
  final int qty;
  final bool tall;
  final Color tint;
  const _Bottle({required this.u, required this.name, required this.qty, required this.tall, required this.tint});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14 * u, height: (tall ? 20 : 12) * u, decoration: BoxDecoration(color: tint.withValues(alpha: .92), borderRadius: BorderRadius.vertical(top: Radius.circular(3 * u)))),
        Container(
          height: (tall ? 104 : 88) * u,
          padding: EdgeInsets.fromLTRB(6 * u, 14 * u, 6 * u, 8 * u),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: .94),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18 * u), bottom: Radius.circular(5 * u)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 10 * u, offset: Offset(0, 4 * u))],
          ),
          child: Column(children: [
            Container(height: .8 * u, color: const Color(0x551B1714)),
            SizedBox(height: 6 * u),
            Expanded(
              child: Center(
                child: Text(name, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: T.serifFamily, fontSize: 10.5 * u, height: 1.1, color: _Overlays.ink)),
              ),
            ),
            if (qty > 1) Text('×$qty', style: TextStyle(fontFamily: T.sansFamily, fontSize: 8 * u, fontWeight: FontWeight.w700, color: _Overlays.amberDeep)),
            SizedBox(height: 4 * u),
            Container(height: .8 * u, color: const Color(0x551B1714)),
          ]),
        ),
      ]);
}

/// A postage stamp holding this month's mosaic.
class _PostStamp extends StatelessWidget {
  final double u;
  final List<Entry> entries;
  final String dateKey;
  const _PostStamp({required this.u, required this.entries, required this.dateKey});
  @override
  Widget build(BuildContext context) {
    final d = parseKey(dateKey);
    final counts = countsByDate(entries);
    final days = DateTime(d.year, d.month + 1, 0).day;
    return Container(
      width: 44 * u,
      height: 52 * u,
      padding: EdgeInsets.all(3 * u),
      decoration: BoxDecoration(color: _Overlays.white, border: Border.all(color: const Color(0x661B1714), width: .8 * u)),
      child: Container(
        color: const Color(0xFF1E1A17),
        padding: EdgeInsets.all(3 * u),
        child: Wrap(spacing: 1.2 * u, runSpacing: 1.2 * u, children: [
          for (var i = 1; i <= days; i++)
            () {
              final k = toKey(DateTime(d.year, d.month, i));
              final level = intensityLevel(counts[k] ?? 0);
              return Container(
                width: 3.6 * u,
                height: 3.6 * u,
                decoration: BoxDecoration(
                  color: level == 0 ? const Color(0x22FFFFFF) : _Overlays.amber.withValues(alpha: const [0.0, .4, .6, .8, 1.0][level]),
                  border: k == dateKey ? Border.all(color: _Overlays.white, width: .6 * u) : null,
                ),
              );
            }(),
        ]),
      ),
    );
  }
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
  final bool vertical; // bars run across a tall strip
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

/// The wavy cancellation lines of a postmark.
class _Postmark extends CustomPainter {
  final double u;
  final Color color;
  _Postmark(this.u, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * u;
    for (var row = 0; row < 4; row++) {
      final y0 = 4 * u + row * 6 * u;
      final path = Path()..moveTo(0, y0);
      for (var x = 0.0; x <= size.width; x += 2) {
        path.lineTo(x, y0 + math.sin(x / (5 * u)) * 1.8 * u);
      }
      canvas.drawPath(path, p);
    }
    canvas.drawCircle(Offset(size.width - 10 * u, size.height / 2), 11 * u, p);
  }

  @override
  bool shouldRepaint(_Postmark old) => false;
}
