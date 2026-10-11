// The photo studio — your photo from the night, made into something worth posting:
// a look (warm, golden, mono, noir, faded, cool, film, with grain and a vignette), a
// frame (print, Polaroid, 35 mm film, cinema, inset) and one small brewdiary sticker
// out of fifteen, in white, black or amber, on the photo or on a frosted or solid
// backing, in a serif, a sans or a mono. Styles put the three together in one tap.
// Drag the sticker, pinch to size it, turn it with two fingers; Story, Post or Square.
// "Sticker only" shares just the sticker, see-through, to lay on any photo.
//
// What goes on it comes from the night itself: what you logged that day (and, on
// the night, the table orders the staff accepted), where, when and with whom — and a
// line of your own. The person picks what shows, can tick lines off, add one, put a
// price on a line or the bill's total. No sticker turns the number of drinks into a
// headline (CLAUDE.md: nothing rewards drinking more).
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
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../../data/table_order.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'photo_frames.dart';
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

/// Everything a sticker or a frame can draw from.
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

  /// A line of the person's own ("Mira turns 30"), typed in the studio.
  final String? caption;
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
    this.caption,
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

  NightStory copyWith({
    List<StoryLine>? lines,
    num? Function()? total,
    String? Function()? venue,
    String? Function()? time,
    String? Function()? mood,
    int? Function()? withPeople,
    List<String>? who,
    String? Function()? caption,
  }) =>
      NightStory(
        dateKey: dateKey,
        title: title,
        venue: venue != null ? venue() : this.venue,
        mood: mood != null ? mood() : this.mood,
        note: note,
        withPeople: withPeople != null ? withPeople() : this.withPeople,
        who: who ?? this.who,
        dry: dry,
        lines: lines ?? this.lines,
        total: total != null ? total() : this.total,
        currency: currency,
        time: time != null ? time() : this.time,
        newToYou: newToYou,
        caption: caption != null ? caption() : this.caption,
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

const shareRatio = {ShareFormat.story: 9 / 16, ShareFormat.post: 4 / 5, ShareFormat.square: 1.0};
const _formatName = {ShareFormat.story: 'Story', ShareFormat.post: 'Post', ShareFormat.square: 'Square'};

enum _Tab { style, sticker, frame, look, text }

const _tabNames = {_Tab.style: 'Style', _Tab.sticker: 'Sticker', _Tab.frame: 'Frame', _Tab.look: 'Look', _Tab.text: 'Text'};

/// The studio remembers the last look you made, per phone.
const _lookKey = 'brewdiary.studio.look';

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
  final _caption = TextEditingController();
  late String? _photo = widget.photo;
  late NightStory _story = widget.story;
  final Set<int> _off = {}; // lines left off the sticker
  StudioLook _look = const StudioLook();
  ShareFormat _format = ShareFormat.story;
  _Tab _tab = _Tab.style;

  // what shows
  bool _showPlace = true, _showTime = true, _showDrinks = true, _showCompany = true, _showMood = true;

  // where the sticker is: null = its home; size; turn
  Alignment? _at;
  double _scale = 1, _angle = 0;
  bool _busy = false;

  // where a drag / pinch started
  Alignment _at0 = Alignment.center;
  double _scale0 = 1, _angle0 = 0;
  double _w = 300; // the preview's width

  @override
  void initState() {
    super.initState();
    try {
      final saved = Prefs.getJson<Map<String, dynamic>>(_lookKey);
      if (saved != null) _look = StudioLook.fromJson(saved);
    } catch (_) {}
    if (widget.story.dateKey == todayKey()) _addTonightsOrders();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// On the night itself, the table orders the staff accepted join the bill.
  Future<void> _addTonightsOrders() async {
    try {
      final mine = await TableApi.mine();
      final known = {for (final l in _story.lines) l.name.toLowerCase()};
      final extra = <StoryLine>[
        // What the venue took (made, ready or served) — not what's waiting or was declined.
        for (final r in mine.where((r) => const {'sent', 'making', 'ready', 'served'}.contains(r.status)))
          for (final l in r.lines)
            if (!known.contains(l.name.toLowerCase())) StoryLine(l.name, qty: l.qty),
      ];
      if (extra.isNotEmpty && mounted) setState(() => _story = _story.copyWith(lines: [..._story.lines, ...extra]));
    } catch (_) {
      // signed out or offline: the diary's lines are enough
    }
  }

  ImageProvider? get _provider => _photo == null ? null : (_photo!.startsWith('http') ? NetworkImage(_photo!) as ImageProvider : FileImage(File(_photo!)));

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 92);
      if (x != null) setState(() => _photo = x.path);
    } catch (_) {
      if (mounted) toast(context, "Couldn't open photos — check brewdiary's permission in Settings.", tone: ToastTone.error);
    }
  }

  void _setLook(StudioLook l, {bool resetPlace = false}) {
    Haptics.tick();
    setState(() {
      if (resetPlace || l.kind != _look.kind) {
        _at = null;
        _scale = 1;
        _angle = 0;
      }
      _look = l;
    });
    try {
      Prefs.setJson(_lookKey, l.toJson());
    } catch (_) {}
  }

  /// The picture as a PNG: the whole frame, or [stickerOnly] — just the sticker, see-through.
  Future<void> _share({bool stickerOnly = false}) async {
    if (_busy) return;
    if (stickerOnly && _look.kind == null) return toast(context, 'Pick a sticker first — this style has none.');
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
      final what = _look.kind == null ? frameNames[_look.frame]!.toLowerCase() : stickerNames[_look.kind]!.toLowerCase();
      final name = 'brewdiary-${_story.dateKey}-$what${stickerOnly ? '-sticker' : '-${_formatName[_format]!.toLowerCase()}'}.png';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')]));
    } catch (_) {
      if (mounted) toast(context, "Couldn't make the image — try again.", tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The night as the picture shows it: what you chose to show, and your line.
  NightStory get _shown {
    final lines = _showDrinks ? [for (var i = 0; i < _story.lines.length; i++) if (!_off.contains(i)) _story.lines[i]] : const <StoryLine>[];
    final caption = _caption.text.trim();
    return _story.copyWith(
      lines: lines,
      venue: _showPlace ? null : () => null,
      time: _showTime ? null : () => null,
      mood: _showMood ? null : () => null,
      withPeople: _showCompany ? null : () => null,
      who: _showCompany ? null : const [],
      caption: () => caption.isEmpty ? null : caption,
    );
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

  // ── moving, sizing and turning the sticker ─────────────────────────────────
  void _gestureStart(ScaleStartDetails d) {
    _at0 = _at ?? stickerHome[_look.kind] ?? Alignment.center;
    _scale0 = _scale;
    _angle0 = _angle;
  }

  void _gestureUpdate(ScaleUpdateDetails d) {
    if (_look.kind == null) return;
    final size = _stickerKey.currentContext?.size ?? const Size(200, 100);
    final photo = Composition.photoRect(_look.frame, Size(_w, _w / shareRatio[_format]!));
    final room = Size((photo.width - size.width * _scale).clamp(40, double.infinity), (photo.height - size.height * _scale).clamp(40, double.infinity));
    setState(() {
      _scale = (_scale0 * d.scale).clamp(.4, 2.8);
      var a = _angle0 + d.rotation;
      if (a.abs() < .06) a = 0; // settles straight when it's nearly straight
      _angle = a;
      _at0 = Alignment((_at0.x + d.focalPointDelta.dx * 2 / room.width).clamp(-1.0, 1.0), (_at0.y + d.focalPointDelta.dy * 2 / room.height).clamp(-1.0, 1.0));
      _at = _at0;
    });
  }

  Widget _canvas(double w) {
    final what = _look.kind == null ? '${frameNames[_look.frame]} frame' : '${stickerNames[_look.kind]} sticker';
    return Semantics(
      label: '$what on ${_photo == null ? 'a plain background' : 'your photo'}. Drag to move it, pinch to size it, turn it with two fingers, double-tap to put it back.',
      child: GestureDetector(
        onScaleStart: _gestureStart,
        onScaleUpdate: _gestureUpdate,
        onDoubleTap: () => setState(() {
          _at = null;
          _scale = 1;
          _angle = 0;
        }),
        child: RepaintBoundary(
          key: _frame,
          child: Composition(
            story: _shown,
            photo: _provider,
            look: _look,
            width: w,
            ratio: shareRatio[_format]!,
            diary: entryStore.entries,
            at: _at,
            scale: _scale,
            angle: _angle,
            stickerKey: _stickerKey,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mq = MediaQuery.of(context);
    // The picture stays put at the top (like a story editor) so a drag on it always
    // moves the sticker; the choices scroll underneath, Share stays at the bottom.
    final room = mq.size.height - mq.padding.top - kTopBarHeight - mq.padding.bottom;
    final avail = (mq.size.width - 2 * S.gutter).clamp(200.0, 560.0);
    _w = [avail, room * .46 * shareRatio[_format]!].reduce((a, b) => a < b ? a : b);
    return SubPage(
      title: 'Share the night',
      large: false,
      scroll: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: S.s),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rTile),
            child: AnimatedSize(
              duration: context.reduceMotion ? Duration.zero : Motion.med,
              curve: Motion.curve,
              child: Stack(children: [
                _canvas(_w),
                // No photo yet: an invitation on the picture — never part of what's shared.
                if (_photo == null)
                  Positioned.fill(
                    child: Align(
                      alignment: const Alignment(0, -.25),
                      child: Semantics(
                        button: true,
                        label: 'Add your photo',
                        excludeSemantics: true,
                        child: Pressable(
                          onTap: () => _pick(ImageSource.gallery),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .35),
                              borderRadius: BorderRadius.circular(rCtl),
                              border: Border.all(color: Colors.white.withValues(alpha: .35), width: .8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Ph.image, size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Text('Add your photo', style: T.sans(bd, size: 14, weight: FontWeight.w600, color: Colors.white)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: S.xs),
        Text(_look.kind == null ? 'Pick a style, a frame or a look below' : 'Drag · pinch to size · two fingers to turn · double-tap to reset', textAlign: TextAlign.center, style: T.caption(bd)),
        const SizedBox(height: S.s),
        Padding(padding: const EdgeInsets.symmetric(horizontal: S.gutter), child: _Tabs(value: _tab, onChanged: (t) => setState(() => _tab = t))),
        Expanded(
          child: ListView(
            key: ValueKey(_tab), // each tab its own list (and its own scroll)
            padding: const EdgeInsets.fromLTRB(S.gutter, S.m, S.gutter, S.m),
            children: switch (_tab) {
              _Tab.style => _stylePanel(context),
              _Tab.sticker => _stickerPanel(context),
              _Tab.frame => _framePanel(context),
              _Tab.look => _lookPanel(context),
              _Tab.text => _textPanel(context),
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(S.gutter, S.s, S.gutter, mq.padding.bottom + S.s),
          child: Row(children: [
            Expanded(child: BdButton(_busy ? 'Making it…' : 'Share', icon: Ph.shareNetwork, onTap: _share)),
            const SizedBox(width: S.s),
            IconBtn(Ph.image, glass: true, tooltip: _photo == null ? 'Choose a photo' : 'Choose another photo', onTap: () => _pick(ImageSource.gallery)),
            IconBtn(Ph.camera, glass: true, tooltip: 'Take a photo', onTap: () => _pick(ImageSource.camera)),
          ]),
        ),
      ]),
    );
  }

  // ── the panels ──────────────────────────────────────────────────────────────
  double get _ratio => shareRatio[_format]!;

  Widget _strip<I>({required List<I> items, required double height, required Widget Function(I) item}) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: S.s),
          itemBuilder: (_, i) => item(items[i]),
        ),
      );

  List<Widget> _stylePanel(BuildContext context) {
    const tw = 66.0;
    final th = tw / _ratio;
    return [
      _strip<(String, StudioLook)>(
        items: studioStyles,
        height: th + 30,
        item: (s) => _Thumb(
          name: s.$1,
          semantic: '${s.$1} style',
          active: s.$2 == _look,
          width: tw,
          height: th,
          onTap: () => _setLook(s.$2, resetPlace: true),
          child: Composition(story: _shown, photo: _provider, look: s.$2, width: tw, ratio: _ratio, diary: entryStore.entries),
        ),
      ),
      const SizedBox(height: S.m),
      Text('A style is a starting point — change the sticker, frame, look or text after.', style: T.caption(context.bd)),
    ];
  }

  List<Widget> _stickerPanel(BuildContext context) {
    final bd = context.bd;
    final k = _look.kind;
    final story = _shown;
    final paper = _look.ink == StickerInk.dark;
    return [
      _strip<StickerKind?>(
        items: [null, ...StickerKind.values],
        height: 104,
        item: (kind) => _Thumb(
          name: kind == null ? 'None' : stickerNames[kind]!,
          semantic: kind == null ? 'No sticker' : '${stickerNames[kind]} sticker',
          active: kind == k,
          width: 76,
          height: 76,
          background: paper ? paperTone : nightTone,
          padding: 9,
          onTap: () => _setLook(_look.copyWith(kind: () => kind)),
          child: kind == null
              ? Icon(Ph.prohibit, size: 26, color: paper ? const Color(0xFF6A665E) : const Color(0xFF8A867E))
              : FittedBox(child: Sticker(kind: kind, story: story, ink: _look.ink, plate: _look.plate, face: _look.face, u: 1, diary: entryStore.entries)),
        ),
      ),
      const SizedBox(height: S.m),
      _row('Ink', Row(mainAxisSize: MainAxisSize.min, children: [
        for (final ink in StickerInk.values) _InkDot(ink: ink, active: ink == _look.ink, onTap: () => _setLook(_look.copyWith(ink: ink))),
      ])),
      if (k != null && takesPlate(k)) ...[
        const SizedBox(height: S.s),
        _row('Backing', Segmented<StickerPlate>(compact: true, options: [for (final p in StickerPlate.values) (p, plateNames[p]!)], value: _look.plate, onChanged: (p) => _setLook(_look.copyWith(plate: p)))),
      ],
      if (k != null && takesFace(k)) ...[
        const SizedBox(height: S.s),
        _row('Type', Segmented<StickerFace>(compact: true, options: [for (final f in StickerFace.values) (f, faceNames[f]!)], value: _look.face, onChanged: (f) => _setLook(_look.copyWith(face: f)))),
      ],
      const SizedBox(height: S.l),
      BdButton('Sticker only', icon: Ph.sticker, kind: BtnKind.secondary, onTap: k == null ? null : () => _share(stickerOnly: true)),
      const SizedBox(height: S.s),
      Text('"Sticker only" is see-through — lay it on any photo in Instagram or WhatsApp.', textAlign: TextAlign.center, style: T.caption(bd)),
    ];
  }

  List<Widget> _framePanel(BuildContext context) {
    const tw = 62.0;
    final th = tw / _ratio;
    return [
      Segmented<ShareFormat>(options: [for (final f in ShareFormat.values) (f, _formatName[f]!)], value: _format, onChanged: (f) => setState(() => _format = f)),
      const SizedBox(height: S.m),
      _strip<PhotoFrame>(
        items: PhotoFrame.values,
        height: th + 30,
        item: (f) => _Thumb(
          name: frameNames[f]!,
          semantic: '${frameNames[f]} frame',
          active: f == _look.frame,
          width: tw,
          height: th,
          onTap: () => _setLook(_look.copyWith(frame: f)),
          child: Composition(story: _shown, photo: _provider, look: _look.copyWith(frame: f, kind: () => null), width: tw, ratio: _ratio),
        ),
      ),
      if (frameHasTone(_look.frame)) ...[
        const SizedBox(height: S.m),
        _row('Border', Segmented<bool>(compact: true, options: const [(false, 'Paper'), (true, 'Black')], value: _look.frameDark, onChanged: (v) => _setLook(_look.copyWith(frameDark: v)))),
      ],
    ];
  }

  List<Widget> _lookPanel(BuildContext context) {
    const tw = 66.0;
    return [
      _strip<PhotoLook>(
        items: PhotoLook.values,
        height: tw + 30,
        item: (l) => _Thumb(
          name: lookNames[l]!,
          semantic: '${lookNames[l]} look',
          active: l == _look.look,
          width: tw,
          height: tw,
          onTap: () => _setLook(_look.copyWith(look: l)),
          child: Composition(story: _shown, photo: _provider, look: StudioLook(kind: null, look: l, ink: _look.ink), width: tw, ratio: 1),
        ),
      ),
      if (_photo == null) ...[
        const SizedBox(height: S.s),
        Text('Looks colour your photo — add one with the buttons below.', style: T.caption(context.bd)),
      ],
      const SizedBox(height: S.s),
      Group(children: [
        SettingRow(title: 'Grain', trailing: BdToggle(on: _look.grain, label: 'Grain', onChanged: (v) => _setLook(_look.copyWith(grain: v)))),
        SettingRow(title: 'Vignette', trailing: BdToggle(on: _look.vignette, label: 'Vignette', onChanged: (v) => _setLook(_look.copyWith(vignette: v)))),
      ]),
    ];
  }

  List<Widget> _textPanel(BuildContext context) {
    final bd = context.bd;
    final onIt = _story.lines.length - _off.length;
    Widget toggle(String title, bool on, ValueChanged<bool> set) => SettingRow(title: title, trailing: BdToggle(on: on, label: title, onChanged: (v) => setState(() => set(v))));
    return [
      const Label('Your line'),
      const SizedBox(height: S.s),
      GlassField(
        controller: _caption,
        hint: _story.title == null ? 'Mira turns 30 — or leave it to the night' : 'Leave empty for "${_story.title}"',
        maxLength: 60,
        caps: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: S.s),
      Text('Shows on Line, Caption, Cover and Ticket, and on Polaroid and Cinema frames.', style: T.caption(bd)),
      const SizedBox(height: S.l),
      const Label('What shows'),
      const SizedBox(height: S.s),
      Group(children: [
        if (_story.venue != null) toggle('The place', _showPlace, (v) => _showPlace = v),
        if (_story.time != null) toggle('The time', _showTime, (v) => _showTime = v),
        if (_story.lines.isNotEmpty) toggle('What you had', _showDrinks, (v) => _showDrinks = v),
        if ((_story.withPeople ?? 0) > 0) toggle('Who you were with', _showCompany, (v) => _showCompany = v),
        if (_story.mood != null) toggle('The mood', _showMood, (v) => _showMood = v),
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
      ]),
      const SizedBox(height: S.m),
      Text('Your photo stays on your phone until you share it. Nothing here counts your drinks.', textAlign: TextAlign.center, style: T.caption(bd)),
    ];
  }

  Widget _row(String label, Widget control) => Row(children: [
        SizedBox(width: 76, child: Text(label.toUpperCase(), style: T.section(context.bd))),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: control)),
      ]);
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

/// Style · Sticker · Frame · Look · Text — spaced capitals, the chosen one underlined.
class _Tabs extends StatelessWidget {
  final _Tab value;
  final ValueChanged<_Tab> onChanged;
  const _Tabs({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.line, width: .8))),
      child: Row(children: [
        for (final t in _Tab.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: t == value,
              label: _tabNames[t],
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (t == value) return;
                  Haptics.tick();
                  onChanged(t);
                },
                child: SizedBox(
                  height: S.tap,
                  child: Stack(alignment: Alignment.center, children: [
                    AnimatedDefaultTextStyle(
                      duration: Motion.fast,
                      style: T.sans(bd, size: 11.5, weight: t == value ? FontWeight.w600 : FontWeight.w500, spacing: 11.5 * .14, color: t == value ? bd.ink : bd.faint),
                      child: FittedBox(fit: BoxFit.scaleDown, child: Text(_tabNames[t]!.toUpperCase(), maxLines: 1)),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 0,
                      child: AnimatedContainer(duration: Motion.fast, height: 2, color: t == value ? bd.accent : Colors.transparent),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A choice shown as a small picture with its name under it.
class _Thumb extends StatelessWidget {
  final String name;
  final String semantic;
  final bool active;
  final double width;
  final double height;
  final VoidCallback onTap;
  final Widget child;
  final Color? background;
  final double padding;
  const _Thumb({required this.name, required this.semantic, required this.active, required this.width, required this.height, required this.onTap, required this.child, this.background, this.padding = 0});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      button: true,
      selected: active,
      label: semantic,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Column(children: [
          AnimatedContainer(
            key: ValueKey('${width}x$height'), // a new size is a new tile, never a growing one
            duration: Motion.fast,
            width: width + 4,
            height: height + 4,
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? bd.accent : bd.line, width: active ? 2 : 1)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9.5),
              child: Container(
                color: background,
                padding: EdgeInsets.all(padding),
                child: IgnorePointer(child: Center(child: child)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(name, maxLines: 1, style: T.sans(bd, size: 12, weight: active ? FontWeight.w600 : FontWeight.w400, color: active ? bd.accentText : bd.muted)),
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
        onTap: onTap,
        child: SizedBox(
          width: 44,
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
