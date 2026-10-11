// The photo studio — your photo from the night, with one small brewdiary sticker on
// it, shared the way a run app puts the run on a selfie. Six stickers (stickers.dart):
// Stats, Line, Mosaic, Stamp, Receipt, Date. Drag the sticker where you want it, pinch
// to size it, pick white, black or amber ink, and a Story, Post or Square frame.
// "Sticker only" shares just the sticker, see-through, to lay on any photo in
// Instagram or WhatsApp.
//
// What goes on it comes from the night itself: what you logged that day (and, on
// the night, the table orders the staff accepted), where, when and with whom. The
// person can tick lines off, add one, put a price on a line or the bill's total.
// No sticker turns the number of drinks into a headline (CLAUDE.md: nothing
// rewards drinking more).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../../data/table_order.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'stickers.dart';

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

/// The frame the picture is made in: a Story (9:16), a Post (4:5) or a Square.
enum ShareFormat { story, post, square }

const _ratio = {ShareFormat.story: 9 / 16, ShareFormat.post: 4 / 5, ShareFormat.square: 1.0};
const _formatName = {ShareFormat.story: 'Story', ShareFormat.post: 'Post', ShareFormat.square: 'Square'};

/// Without a photo: a plain night (white ink) or plain paper (black ink). No made-up scene.
const _night = Color(0xFF111216);
const _paperBg = Color(0xFFEFEAE2);

class PhotoStudio extends StatefulWidget {
  final NightStory story;
  final String? photo;
  const PhotoStudio({super.key, required this.story, this.photo});
  @override
  State<PhotoStudio> createState() => _PhotoStudioState();
}

class _PhotoStudioState extends State<PhotoStudio> {
  final _frame = GlobalKey(); // the whole picture
  final _stickerKey = GlobalKey(); // the sticker alone, for "Sticker only"
  late String? _photo = widget.photo;
  late NightStory _story = widget.story;
  late final Set<int> _off = {}; // lines left off the sticker
  StickerKind _kind = StickerKind.stats;
  StickerInk _ink = StickerInk.light;
  ShareFormat _format = ShareFormat.story;
  Alignment _at = stickerHome[StickerKind.stats]!;
  double _scale = 1;
  bool _showPlace = true;
  bool _busy = false;

  // where a drag / pinch started
  Alignment _at0 = Alignment.center;
  double _scale0 = 1;
  double _w = 300; // the preview's width, for turning a drag into a move

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
      final x = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 90);
      if (x != null) setState(() => _photo = x.path);
    } catch (_) {
      if (mounted) toast(context, "Couldn't open photos — check brewdiary's permission in Settings.", tone: ToastTone.error);
    }
  }

  void _choose(StickerKind k) => setState(() {
        _kind = k;
        _at = stickerHome[k]!;
        _scale = 1;
      });

  /// The picture as a PNG: the whole frame, or [stickerOnly] — just the sticker, see-through.
  Future<void> _share({bool stickerOnly = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final key = stickerOnly ? _stickerKey : _frame;
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ratio = 1080 / _w * (stickerOnly ? (_scale < 1 ? 1 : _scale) * 1.25 : 1);
      final image = await boundary.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final name = 'brewdiary-${_story.dateKey}-${stickerNames[_kind]!.toLowerCase()}${stickerOnly ? '-sticker' : '-${_formatName[_format]!.toLowerCase()}'}.png';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
    } catch (_) {
      if (mounted) toast(context, "Couldn't make the image — try again.", tone: ToastTone.error);
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

  // ── moving the sticker ──────────────────────────────────────────────────────
  void _gestureStart(ScaleStartDetails d) {
    _at0 = _at;
    _scale0 = _scale;
  }

  void _gestureUpdate(ScaleUpdateDetails d) {
    final size = _stickerKey.currentContext?.size ?? const Size(200, 100);
    final room = Size((_w - size.width * _scale).clamp(40, double.infinity), (_w / _ratio[_format]! - size.height * _scale).clamp(40, double.infinity));
    setState(() {
      _scale = (_scale0 * d.scale).clamp(.5, 2.6);
      _at0 = Alignment((_at0.x + d.focalPointDelta.dx * 2 / room.width).clamp(-1.0, 1.0), (_at0.y + d.focalPointDelta.dy * 2 / room.height).clamp(-1.0, 1.0));
      _at = _at0;
    });
  }

  Widget _canvas(double w) {
    final u = w / 360;
    final bg = _photo == null
        ? ColoredBox(color: _ink == StickerInk.dark ? _paperBg : _night)
        : Image(image: _photo!.startsWith('http') ? NetworkImage(_photo!) as ImageProvider : FileImage(File(_photo!)), fit: BoxFit.cover);
    return Semantics(
      label: '${stickerNames[_kind]} sticker on ${_photo == null ? 'a plain background' : 'your photo'}. Drag to move it, pinch to size it, double-tap to put it back.',
      child: GestureDetector(
        onScaleStart: _gestureStart,
        onScaleUpdate: _gestureUpdate,
        onDoubleTap: () => setState(() {
          _at = stickerHome[_kind]!;
          _scale = 1;
        }),
        child: RepaintBoundary(
          key: _frame,
          child: SizedBox(
            width: w,
            height: w / _ratio[_format]!,
            child: ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                bg,
                Padding(
                  padding: EdgeInsets.all(18 * u),
                  child: Align(
                    alignment: _at,
                    child: Transform.scale(
                      scale: _scale,
                      child: RepaintBoundary(
                        key: _stickerKey,
                        child: Padding(
                          padding: EdgeInsets.all(8 * u), // room for a tilted stamp or a shadow
                          child: Sticker(kind: _kind, story: _shown, ink: _ink, u: u, diary: entryStore.entries),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final onIt = _story.lines.length - _off.length;
    final mq = MediaQuery.of(context);
    // The picture stays put at the top (like a story editor) so a drag on it always
    // moves the sticker; the controls scroll underneath.
    final room = mq.size.height - mq.padding.top - kTopBarHeight - mq.padding.bottom;
    final avail = (mq.size.width - 2 * S.gutter).clamp(200.0, 560.0);
    _w = [avail, room * .5 * _ratio[_format]!].reduce((a, b) => a < b ? a : b);
    return SubPage(
      title: 'Share the night',
      large: false,
      scroll: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: S.s),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rTile),
            child: AnimatedSize(duration: context.reduceMotion ? Duration.zero : Motion.med, curve: Motion.curve, child: _canvas(_w)),
          ),
        ),
        const SizedBox(height: S.xs),
        Text('Drag the sticker · pinch to size it · double-tap to put it back', textAlign: TextAlign.center, style: T.caption(bd)),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(S.gutter, S.m, S.gutter, mq.padding.bottom + S.xl),
            children: [
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: StickerKind.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: S.s),
                  itemBuilder: (_, i) {
                    final k = StickerKind.values[i];
                    return _StickerThumb(name: stickerNames[k]!, active: k == _kind, onTap: () => _choose(k), paper: _ink == StickerInk.dark, child: Sticker(kind: k, story: _shown, ink: _ink, u: 1, diary: entryStore.entries));
                  },
                ),
              ),
              const SizedBox(height: S.m),
              Row(children: [
                Expanded(child: Segmented<ShareFormat>(options: [for (final f in ShareFormat.values) (f, _formatName[f]!)], value: _format, onChanged: (f) => setState(() => _format = f))),
                const SizedBox(width: S.m),
                for (final ink in StickerInk.values) _InkDot(ink: ink, active: ink == _ink, onTap: () => setState(() => _ink = ink)),
              ]),
              const SizedBox(height: S.l),
              BdButton(_busy ? 'Making it…' : 'Share', icon: Ph.shareNetwork, onTap: _share),
              const SizedBox(height: S.s),
              Row(children: [
                Expanded(child: BdButton('Sticker only', kind: BtnKind.secondary, onTap: () => _share(stickerOnly: true))),
                const SizedBox(width: S.s),
                Expanded(child: BdButton(_photo == null ? 'Add photo' : 'New photo', kind: BtnKind.secondary, onTap: () => _pick(ImageSource.gallery))),
                const SizedBox(width: S.s),
                IconBtn(Ph.camera, glass: true, tooltip: 'Take a photo', onTap: () => _pick(ImageSource.camera)),
              ]),
              const SizedBox(height: S.l),
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
              const SizedBox(height: S.m),
              Text('"Sticker only" is see-through — lay it on any photo in Instagram or WhatsApp. Your photo stays on your phone until you share it.', textAlign: TextAlign.center, style: T.caption(bd)),
            ],
          ),
        ),
      ]),
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

/// A sticker to pick, shown alone on a small tile.
class _StickerThumb extends StatelessWidget {
  final String name;
  final bool active;
  final VoidCallback onTap;
  final Widget child;
  final bool paper;
  const _StickerThumb({required this.name, required this.active, required this.onTap, required this.child, required this.paper});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      button: true,
      selected: active,
      label: '$name sticker',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Column(children: [
          AnimatedContainer(
            duration: Motion.fast,
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: paper ? _paperBg : _night,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? bd.accent : bd.line, width: active ? 2 : 1),
            ),
            child: IgnorePointer(child: FittedBox(child: child)),
          ),
          const SizedBox(height: 6),
          Text(name, style: T.sans(bd, size: 12, weight: active ? FontWeight.w600 : FontWeight.w400, color: active ? bd.accentText : bd.muted)),
        ]),
      ),
    );
  }
}

/// White, black or amber ink.
class _InkDot extends StatelessWidget {
  final StickerInk ink;
  final bool active;
  final VoidCallback onTap;
  const _InkDot({required this.ink, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final name = switch (ink) { StickerInk.light => 'White', StickerInk.dark => 'Black', StickerInk.amber => 'Amber' };
    return Semantics(
      button: true,
      selected: active,
      label: '$name ink',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tick();
          onTap();
        },
        child: SizedBox(
          width: 40,
          height: S.tap,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.fast,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: inkColor(ink),
                shape: BoxShape.circle,
                border: Border.all(color: active ? bd.accent : bd.lineStrong, width: active ? 2.5 : 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
