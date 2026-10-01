// The taste passport — a little book you swipe through: the leather cover, the
// identity page (what you're into, the counts, a machine-readable strip), then a
// page for each year and each month with its visa stamps: a place first visited,
// a drink first tasted, a kind first tried, every dry night. Variety, never
// volume: ten nights at one bar is one stamp, and a dry night earns its own.
//
// Opened from the calendar (the month or the year you're looking at), from You,
// and from a venue's menu. Any page can be shared as a picture.
import 'dart:io';
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
import '../../data/taste_share.dart';
import '../../data/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/passport.dart';

/// [open] is 'YYYY-MM' for a month's page, 'YYYY' for a year's; null opens the
/// identity page.
Future<void> showTasteCard(BuildContext context, {String? open}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => TasteCardScreen(open: open)));

/// One page of the book.
class _Page {
  final String id; // 'cover', 'id', 'YYYY', 'YYYY-MM'
  final String title;
  const _Page(this.id, this.title);
}

class TasteCardScreen extends StatefulWidget {
  final String? open;
  const TasteCardScreen({super.key, this.open});
  @override
  State<TasteCardScreen> createState() => _TasteCardScreenState();
}

class _TasteCardScreenState extends State<TasteCardScreen> {
  static const _hiddenKey = 'brewdiary.tastecard.hidden';
  late final Set<String> _hidden = {...(Prefs.getJson<List<dynamic>>(_hiddenKey) ?? const []).map((e) => '$e')};
  bool _showPlaces = true;
  bool _sharing = false;
  late final List<_Page> _pages = _book();
  late final PageController _pc = PageController(viewportFraction: .9, initialPage: _start());
  late int _at = _start();
  final _keys = <String, GlobalKey>{};

  List<_Page> _book() {
    final months = {for (final e in entryStore.entries) e.date.substring(0, 7)}.toList()..sort((a, b) => b.compareTo(a));
    final now = appNow();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (!months.contains(thisMonth)) months.insert(0, thisMonth);
    final pages = <_Page>[const _Page('cover', 'Cover'), const _Page('id', 'Identity'), const _Page('palate', 'Palate')];
    String? year;
    for (final m in months) {
      final y = m.substring(0, 4);
      if (y != year) {
        year = y;
        pages.add(_Page(y, 'The year $y'));
      }
      final d = parseKey('$m-01');
      pages.add(_Page(m, '${monthNames[d.month - 1]} ${d.year}'));
    }
    return pages;
  }

  int _start() {
    final i = widget.open == null ? -1 : _pages.indexWhere((p) => p.id == widget.open);
    return i >= 0 ? i : 1;
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary = _keys[_pages[_at].id]?.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brewdiary-passport-${_pages[_at].id}.png');
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

  Widget _pageView(_Page page, List<(String, String, String)> lines) {
    final entries = entryStore.entries;
    final key = _keys.putIfAbsent(page.id, GlobalKey.new);
    final Widget child = switch (page.id) {
      'cover' => PassportCover(name: auth.profile?.name),
      'id' => PassportIdentity(
          name: auth.profile?.name,
          passport: passport(entries),
          lines: [for (final l in lines) if (!_hidden.contains(l.$1)) (l.$2, l.$3)],
          dryTonight: TasteShareStore.instance.dryTonight,
          showPlaces: _showPlaces,
        ),
      'palate' => PassportPalate(notes: palate(entries), sweetness: TasteShareStore.instance.sweetness, avoid: TasteShareStore.instance.avoid),
      _ => () {
          final isYear = page.id.length == 4;
          final from = isYear ? '${page.id}-01-01' : '${page.id}-01';
          final d = parseKey(from);
          final to = isYear ? '${page.id}-12-31' : toKey(DateTime(d.year, d.month + 1, 0));
          final stamps = stampsBetween(entries, from, to).where((s) => _showPlaces || s.kind != StampKind.place).toList();
          return VisaPage(
            title: isYear ? page.id : page.title,
            stamps: stamps,
            pageNo: _pages.indexOf(page),
            max: isYear ? 12 : 9,
            empty: isYear ? 'A year of stamps starts with one night.' : 'No stamps this month yet — a new place, a first taste or a dry night earns one.',
          );
        }(),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SingleChildScrollView(physics: const ClampingScrollPhysics(), child: RepaintBoundary(key: key, child: page.id == 'cover' ? AspectRatio(aspectRatio: .7, child: child) : child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final store = TasteShareStore.instance;
    final entries = entryStore.entries;
    final lines = tasteLines(tasteProfile(entries), notes: palate(entries), loves: store.loves, avoid: store.avoid, sweetness: store.sweetness, diet: store.diet, allergies: store.allergies);
    final page = _pages[_at];
    final isMonth = page.id.length == 7;
    final isYear = page.id.length == 4;
    final from = isYear ? '${page.id}-01-01' : (isMonth ? '${page.id}-01' : null);
    final stamps = from == null
        ? const <VisaStamp>[]
        : stampsBetween(entryStore.entries, from, isYear ? '${page.id}-12-31' : toKey(DateTime(parseKey(from).year, parseKey(from).month + 1, 0)));
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SubPage(
          title: 'Taste passport',
          subtitle: 'Places, first tastes, new kinds, dry nights — swipe through the pages.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 560,
              child: PageView.builder(
                controller: _pc,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _at = i),
                itemBuilder: (_, i) => AnimatedBuilder(
                  animation: _pc,
                  child: _pageView(_pages[i], lines),
                  builder: (_, child) {
                    // A carousel: the open page sits forward, its neighbours step back.
                    final pos = _pc.hasClients && _pc.position.haveDimensions ? (_pc.page ?? _at.toDouble()) : _at.toDouble();
                    final d = (pos - i).abs().clamp(0.0, 1.0);
                    return Opacity(
                      opacity: 1 - .6 * d,
                      child: Transform.scale(scale: 1 - .06 * d, alignment: Alignment.topCenter, child: child),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: S.s),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconBtn(Ph.caretLeft, tooltip: 'Previous page', onTap: _at == 0 ? null : () => _pc.previousPage(duration: Motion.med, curve: Curves.easeOutCubic)),
              SizedBox(width: 150, child: Text(page.title, textAlign: TextAlign.center, style: T.row(bd))),
              IconBtn(Ph.caretRight, tooltip: 'Next page', onTap: _at == _pages.length - 1 ? null : () => _pc.nextPage(duration: Motion.med, curve: Curves.easeOutCubic)),
            ]),
            if (from != null) ...[const SizedBox(height: S.m), StampTally(stamps)],
            const SizedBox(height: S.l),
            BdButton(_sharing ? 'Making it…' : 'Share this page', icon: Ph.shareNetwork, onTap: _share),
            const SectionHeader('What the bar sees'),
            BarPreview(payload: store.payload()),
            const SectionHeader('Your taste'),
            TastePrefsEditor(onChanged: () => setState(() {})),
            const SectionHeader('Next stamps'),
            const NextStampsList(),
            const SectionHeader('On your passport'),
            Group(children: [
              SettingRow(
                title: 'Nothing with alcohol tonight',
                hint: 'Says so on your identity page, and to tonight\'s bartender.',
                trailing: BdToggle(on: TasteShareStore.instance.dryTonight, label: 'Nothing with alcohol tonight', onChanged: (v) async {
                  await TasteShareStore.instance.setDryTonight(v);
                  if (mounted) setState(() {});
                }),
              ),
              SettingRow(
                title: 'Show place stamps',
                hint: 'Where you have been, on the pages and in what you share.',
                trailing: BdToggle(on: _showPlaces, label: 'Show place stamps', onChanged: (v) => setState(() => _showPlaces = v)),
              ),
              for (final l in lines)
                SettingRow(
                  title: 'Show "${l.$2}"',
                  trailing: BdToggle(on: !_hidden.contains(l.$1), label: 'Show ${l.$2}', onChanged: (_) => _toggle(l.$1)),
                ),
            ]),
            if (auth.isAuthed && db != null) ...[
              const SizedBox(height: S.xl),
              const TasteShareSettings(),
              const SizedBox(height: S.m),
              BdButton('Show my guest card', kind: BtnKind.secondary, icon: Ph.identificationBadge, onTap: () => showGuestCard(context)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// The switch for sharing your taste with a venue's bartender, and tonight's shares.
class TasteShareSettings extends StatefulWidget {
  const TasteShareSettings({super.key});
  @override
  State<TasteShareSettings> createState() => _TasteShareSettingsState();
}

class _TasteShareSettingsState extends State<TasteShareSettings> {
  List<TasteShare> _live = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await TasteShareStore.instance.mine();
      if (mounted) setState(() => _live = l);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = TasteShareStore.instance;
    return Group(
      footer: 'What you\'re into, what you usually have, your mood words, and "nothing with alcohol tonight". Tonight only. Never your diary, never where else you\'ve been.',
      children: [
        SettingRow(
          title: 'Share my taste with the bartender',
          hint: 'When you open a place\'s menu or table link.',
          trailing: BdToggle(on: store.consent == true, label: 'Share my taste with the bartender', onChanged: (v) async {
            await store.setConsent(v);
            if (mounted) setState(() {});
          }),
        ),
        for (final s in _live)
          SettingRow(
            title: s.venueName,
            hint: 'Has your taste until ${TimeOfDay.fromDateTime(s.expiresAt).format(context)}${s.tableLabel == null ? '' : ' · table ${s.tableLabel}'}',
            trailing: TextAction('Stop', onTap: () async {
              await store.stop(s.venueId);
              await _load();
            }),
          ),
      ],
    );
  }
}

/// My guest card: a 6-letter code staff type at the till to find me — good for
/// ten minutes, then a new one.
Future<void> showGuestCard(BuildContext context) => showBdSheet<void>(context, title: 'Your guest card', builder: (_) => const _GuestCard());

class _GuestCard extends StatefulWidget {
  const _GuestCard();
  @override
  State<_GuestCard> createState() => _GuestCardState();
}

class _GuestCardState extends State<_GuestCard> {
  ({String code, DateTime expiresAt})? _card;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _error = null);
    try {
      final c = await TasteShareStore.instance.guestCode();
      if (mounted) setState(() => _card = c);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't get a code — check your connection.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final c = _card;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Show this to the staff when they record a visit or a perk.', style: T.bodyMuted(bd)),
      const SizedBox(height: S.l),
      PassportPaper(
        padding: const EdgeInsets.symmetric(vertical: S.xl, horizontal: S.l),
        child: Column(children: [
          Text('GUEST CARD', style: TextStyle(fontFamily: T.sansFamily, fontSize: 9, letterSpacing: 2.4, fontWeight: FontWeight.w700, color: bd.faint)),
          const SizedBox(height: S.m),
          if (c == null)
            Text(_error ?? '······', style: TextStyle(fontFamily: T.serifFamily, fontSize: _error == null ? 44 : 15, color: bd.ink))
          else
            Semantics(
              label: 'Code ${c.code.split('').join(' ')}',
              excludeSemantics: true,
              child: Text(c.code, style: TextStyle(fontFamily: T.sansFamily, fontSize: 46, letterSpacing: 10, fontWeight: FontWeight.w700, color: bd.accentText, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          const SizedBox(height: S.s),
          if (c != null) Text('Good until ${TimeOfDay.fromDateTime(c.expiresAt).format(context)}', style: TextStyle(fontFamily: T.sansFamily, fontSize: 12, color: bd.muted)),
        ]),
      ),
      const SizedBox(height: S.m),
      BdButton('New code', kind: BtnKind.secondary, icon: Ph.arrowsClockwise, onTap: _fetch),
    ]);
  }
}

/// Exactly what a bar would get tonight, drawn the way its staff see it.
class BarPreview extends StatelessWidget {
  final Map<String, Object> payload;
  const BarPreview({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    List<String> l(String k) => [for (final x in (payload[k] as List? ?? const [])) '$x'];
    Widget chip(String text, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: strong ? bd.accent.withValues(alpha: .18) : bd.glass,
            borderRadius: BorderRadius.circular(rCtl),
            border: Border.all(color: strong ? bd.accent.withValues(alpha: .5) : bd.line, width: .8),
          ),
          child: Text(text, style: T.sans(bd, size: 13, weight: strong ? FontWeight.w600 : FontWeight.w500, color: strong ? bd.accentText : bd.ink)),
        );
    final sweet = payload['sweetness'] as String?;
    final chips = <Widget>[
      if (payload['dry_tonight'] == true) chip('Nothing with alcohol tonight', strong: true),
      if (l('allergies').isNotEmpty) chip('Allergic: ${l('allergies').join(', ')}', strong: true),
      if (l('avoid').isNotEmpty) chip('Not: ${l('avoid').join(', ')}', strong: true),
      for (final d in l('diet')) chip(d),
      for (final x in l('into')) chip(x),
      if (l('flavours').isNotEmpty) chip('likes ${l('flavours').join(', ')}'),
      if (sweet != null) chip(switch (sweet) { 'dry' => 'not sweet', 'sweet' => 'on the sweet side', _ => 'balanced sweetness' }),
      for (final u in l('usually')) chip('usually $u'),
      for (final m in l('moods')) chip(m),
      if (payload['alcohol_free_often'] == true && payload['dry_tonight'] != true) chip('often alcohol-free'),
    ];
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (chips.isEmpty) Text('Nothing to share yet — log a few drinks or add what you like below.', style: T.bodyMuted(bd)) else Wrap(spacing: 6, runSpacing: 6, children: chips),
        const SizedBox(height: S.m),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Ph.lock, size: 14, color: bd.faint)),
          const SizedBox(width: S.s),
          Expanded(child: Text('Only after you\'ve said yes, only with the place whose menu you open, for 8 hours. Never your diary, never where else you\'ve been.', style: T.caption(bd))),
        ]),
      ]),
    );
  }
}

/// Sweetness, loves, avoid, diet and allergies — kept on this phone, shared only
/// with tonight's bar.
class TastePrefsEditor extends StatelessWidget {
  final VoidCallback onChanged;
  const TastePrefsEditor({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final store = TasteShareStore.instance;
    final bd = context.bd;
    Future<void> toggle(List<String> current, String v, Future<void> Function(List<String>) save) async {
      await save(current.contains(v) ? (current.where((x) => x != v).toList()) : [...current, v]);
      onChanged();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Label('How sweet'),
      const SizedBox(height: S.s),
      Segmented<String>(
        options: const [('', 'Any'), ('dry', 'Dry'), ('balanced', 'Balanced'), ('sweet', 'Sweet')],
        value: store.sweetness ?? '',
        onChanged: (v) async {
          await store.setSweetness(v.isEmpty ? null : v);
          onChanged();
        },
      ),
      const SizedBox(height: S.l),
      _WordList(
        label: 'Love',
        hint: 'A drink you love — "mezcal", "cold brew"',
        words: store.loves,
        onChanged: (v) async {
          await store.setLoves(v);
          onChanged();
        },
      ),
      const SizedBox(height: S.l),
      _WordList(
        label: 'Rather not',
        hint: 'Something to leave out — "gin", "coconut"',
        words: store.avoid,
        onChanged: (v) async {
          await store.setAvoid(v);
          onChanged();
        },
      ),
      const SizedBox(height: S.l),
      const Label('Diet'),
      const SizedBox(height: S.s),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        for (final d in TasteShareStore.dietOptions) BdChip(d, active: store.diet.contains(d), onTap: () => toggle(store.diet, d, store.setDiet)),
      ]),
      const SizedBox(height: S.l),
      const Label('Allergies'),
      const SizedBox(height: S.s),
      Wrap(spacing: S.s, runSpacing: S.s, children: [
        for (final a in TasteShareStore.allergyOptions) BdChip(a, active: store.allergies.contains(a), onTap: () => toggle(store.allergies, a, store.setAllergies)),
      ]),
      const SizedBox(height: S.s),
      Text('Allergies go first on what the bar sees. Always tell your server too.', style: T.caption(bd)),
    ]);
  }
}

/// A few words as removable chips, with a field to add one.
class _WordList extends StatefulWidget {
  final String label;
  final String hint;
  final List<String> words;
  final ValueChanged<List<String>> onChanged;
  const _WordList({required this.label, required this.hint, required this.words, required this.onChanged});
  @override
  State<_WordList> createState() => _WordListState();
}

class _WordListState extends State<_WordList> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _add() {
    final w = _c.text.trim();
    if (w.isEmpty || widget.words.length >= 8 || widget.words.any((x) => x.toLowerCase() == w.toLowerCase())) return;
    widget.onChanged([...widget.words, w.length > 40 ? w.substring(0, 40) : w]);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Label(widget.label),
      const SizedBox(height: S.s),
      if (widget.words.isNotEmpty) ...[
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final w in widget.words) BdChip(w, active: true, icon: Ph.x, onTap: () => widget.onChanged(widget.words.where((x) => x != w).toList())),
        ]),
        const SizedBox(height: S.s),
      ],
      GlassField(controller: _c, hint: widget.hint, action: TextInputAction.done, onSubmitted: (_) => _add(), icon: Ph.plus),
    ]);
  }
}

/// Things you haven't had that you might like — add one to your to-try list.
class NextStampsList extends StatelessWidget {
  const NextStampsList({super.key});

  static const _icons = {
    DrinkType.coffee: Ph.coffee,
    DrinkType.tea: Ph.leaf,
    DrinkType.soft: Ph.drop,
    DrinkType.beer: Ph.beerBottle,
    DrinkType.wine: Ph.wine,
    DrinkType.cocktail: Ph.martini,
    DrinkType.spirit: Ph.brandy,
  };

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: WishlistStore.instance,
      builder: (context, _) {
        final wish = {for (final w in WishlistStore.instance.items) w.drink.toLowerCase()};
        final next = nextStamps(entryStore.entries);
        if (next.isEmpty) return Text('You\'ve met every family we know. Impressive.', style: T.bodyMuted(bd));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Group(children: [
            for (final n in next)
              GroupTile(
                icon: _icons[n.type] ?? Ph.sparkle,
                title: n.family,
                subtitle: n.why,
                trailing: wish.contains(n.family.toLowerCase())
                    ? Text('On your list', style: T.caption(bd))
                    : TextAction('To try', accent: true, onTap: () {
                        WishlistStore.instance.add(n.family);
                        toast(context, '${n.family} is on your to-try list.');
                      }),
              ),
          ]),
          const SizedBox(height: S.s),
          Text('Each one would be a first-taste stamp. There\'s always something alcohol-free.', style: T.caption(bd)),
        ]);
      },
    );
  }
}
