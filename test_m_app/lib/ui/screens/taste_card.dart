// The taste passport — a game you play by drinking widely, never by drinking
// more. On top, the passport card: your rank, your miles, the bar to the next rank
// (tap it to see what a bartender would see). Below, four tabs:
//   Journey    — this week's three quests, the season stamp, the road of ranks,
//                your latest miles and how miles are earned.
//   Collection — eight sets to fill, one slot per drink family; a few come gilded.
//   Stamps     — feats, season stamps, and the stamp book: a page a month.
//   Taste      — your palate, what the bar sees, what you love and avoid.
// The rules (brewdiary_core/game.dart) are derived from the diary, never stored.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/drinks.dart';
import 'package:brewdiary_core/game.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/taste_share.dart';
import '../../data/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/game.dart';
import '../widgets/page.dart';
import '../widgets/passport.dart';

enum PassportTab { journey, collection, stamps, taste }

/// [open] is 'YYYY-MM' or 'YYYY' to open the stamp book; [tab] picks a tab.
Future<void> showTasteCard(BuildContext context, {String? open, PassportTab? tab}) => Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => TasteCardScreen(tab: tab ?? (open != null ? PassportTab.stamps : PassportTab.journey))),
    );

/// The bar's view of the taste card as (text, strong) chips — allergies and
/// "nothing with alcohol tonight" first.
List<(String, bool)> tasteChips(Map<String, Object> payload) {
  List<String> l(String k) => [for (final x in (payload[k] as List? ?? const [])) '$x'];
  final sweet = payload['sweetness'] as String?;
  return [
    if (payload['dry_tonight'] == true) ('Nothing with alcohol tonight', true),
    if (l('allergies').isNotEmpty) ('Allergic: ${l('allergies').join(', ')}', true),
    if (l('avoid').isNotEmpty) ('Not: ${l('avoid').join(', ')}', true),
    for (final d in l('diet')) (d, false),
    for (final x in l('into')) (x, false),
    if (l('flavours').isNotEmpty) ('likes ${l('flavours').join(', ')}', false),
    if (sweet != null) (switch (sweet) { 'dry' => 'not sweet', 'sweet' => 'on the sweet side', _ => 'balanced sweetness' }, false),
    for (final u in l('usually')) ('usually $u', false),
    for (final m in l('moods')) (m, false),
    if (payload['alcohol_free_often'] == true && payload['dry_tonight'] != true) ('often alcohol-free', false),
  ];
}

class TasteCardScreen extends StatefulWidget {
  final PassportTab tab;
  const TasteCardScreen({super.key, this.tab = PassportTab.journey});
  @override
  State<TasteCardScreen> createState() => _TasteCardScreenState();
}

class _TasteCardScreenState extends State<TasteCardScreen> {
  late final Set<String> _hidden = {...(Prefs.getJson<List<dynamic>>(TasteShareStore.hiddenKey) ?? const []).map((e) => '$e')};
  late PassportTab _tab = widget.tab;
  bool _showPlaces = true;
  bool _sharing = false;
  final _cardKey = GlobalKey();

  void _toggle(String line) {
    setState(() => _hidden.contains(line) ? _hidden.remove(line) : _hidden.add(line));
    Prefs.setJson(TasteShareStore.hiddenKey, _hidden.toList());
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brewdiary-passport.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: 'My taste passport on brewdiary'));
    } catch (_) {
      if (mounted) toast(context, "Couldn't make the image — try again.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _wish(String family) {
    final listed = WishlistStore.instance.items.any((w) => w.drink.toLowerCase() == family.toLowerCase());
    if (listed) {
      toast(context, '$family is already on your to-try list.');
      return;
    }
    WishlistStore.instance.add(family);
    toast(context, '$family is on your to-try list.');
  }

  String? _since(List<Entry> entries) {
    if (entries.isEmpty) return null;
    final first = entries.map((e) => e.date).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    final d = parseKey(first);
    return '${monthNames[d.month - 1].substring(0, 3)} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: Listenable.merge([entryStore, WishlistStore.instance, TasteShareStore.instance]),
          builder: (context, _) {
            final entries = entryStore.entries;
            final g = passportGame(entries);
            final store = TasteShareStore.instance;
            return SubPage(
              title: 'Taste passport',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                RepaintBoundary(
                  key: _cardKey,
                  child: PassportCard(game: g, name: auth.profile?.name, since: _since(entries), back: CardChips(tasteChips(store.payload()))),
                ),
                const SizedBox(height: S.m),
                Row(children: [
                  Icon(Ph.handTap, size: 14, color: bd.faint),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Tap the card to see what a bartender sees.', style: T.caption(bd))),
                  TextAction(_sharing ? 'Making it…' : 'Share', accent: true, onTap: _share),
                ]),
                const SizedBox(height: S.l),
                _Stats(game: g, entries: entries),
                const SizedBox(height: S.xl),
                Segmented<PassportTab>(
                  options: const [(PassportTab.journey, 'Journey'), (PassportTab.collection, 'Collection'), (PassportTab.stamps, 'Stamps'), (PassportTab.taste, 'Taste')],
                  value: _tab,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                AnimatedSwitcher(
                  duration: Motion.med,
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: switch (_tab) {
                      PassportTab.journey => _journey(g),
                      PassportTab.collection => _collection(g),
                      PassportTab.stamps => _stamps(g, entries),
                      PassportTab.taste => _taste(entries),
                    },
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Set<String> get _listed => {for (final w in WishlistStore.instance.items) w.drink.toLowerCase()};

  Widget _journey(PassportGame g) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('This week'),
      QuestCard(quests: g.quests, daysLeft: g.questDaysLeft),
      const SectionHeader('This season'),
      SeasonCard(season: g.season, onPick: _wish, onList: _listed),
      SectionHeader('Your road', trailing: Text('Rank ${g.rank.index + 1} of ${ranks.length}', style: T.caption(bd))),
      RankRoad(game: g),
      const SizedBox(height: S.s),
      Text(g.rank.line, style: T.serif(bd, size: 17, italic: true, color: bd.muted, height: 1.3)),
      const SectionHeader('Recent miles'),
      MilesLedger(g.ledger.take(8).toList()),
      const SectionHeader('How miles work'),
      const MilesGuide(),
    ]);
  }

  Widget _collection(PassportGame g) {
    final bd = context.bd;
    final total = collections.fold<int>(0, (s, c) => s + c.families.length);
    final sets = g.collections.where((c) => c.complete).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: S.xl),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text('${g.families}', style: T.serif(bd, size: 40, color: bd.accentText)),
        Text(' / $total', style: T.serif(bd, size: 22, color: bd.muted)),
        const SizedBox(width: S.m),
        Expanded(child: Text('drink families met · $sets ${sets == 1 ? 'set' : 'sets'} complete', style: T.caption(bd))),
      ]),
      const SizedBox(height: S.s),
      Text('Each square is a family. A first taste fills it; about one in six comes out gilded.', style: T.caption(bd)),
      const SizedBox(height: S.l),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - S.m) / 2;
        return Wrap(spacing: S.m, runSpacing: S.m, children: [
          for (final col in g.collections) SizedBox(width: w, child: CollectionTile(state: col, gilded: g.gilded, onTap: () => _openCollection(col, g))),
        ]);
      }),
      const SectionHeader('Next stamps'),
      const NextStampsList(),
    ]);
  }

  void _openCollection(CollectionState col, PassportGame g) {
    showBdSheet<void>(context, title: col.collection.title, builder: (sheet) {
      final bd = sheet.bd;
      return ListenableBuilder(
        listenable: WishlistStore.instance,
        builder: (sheet, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(col.complete ? 'Complete since ${formatDayLongYear(col.completedOn!)}.' : '${col.have} of ${col.total}. A full set is +$milesCollection miles.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          Group(children: [
            for (final f in col.collection.families)
              GroupTile(
                icon: col.tried.containsKey(f) ? (g.gilded.contains(f) ? PhFill.sparkle : Ph.checkCircle) : Ph.circle,
                title: f,
                subtitle: col.tried.containsKey(f)
                    ? 'First tasted ${formatDayLongYear(col.tried[f]!)}${g.gilded.contains(f) ? ' · gilded' : ''}'
                    : (flavours[f] ?? const []).join(', ').ifBlank('not tried yet'),
                trailing: col.tried.containsKey(f)
                    ? null
                    : _listed.contains(f.toLowerCase())
                        ? Text('On your list', style: T.caption(bd))
                        : TextAction('To try', accent: true, onTap: () => _wish(f)),
              ),
          ]),
        ]),
      );
    });
  }

  Widget _stamps(PassportGame g, List<Entry> entries) {
    final bd = context.bd;
    final earned = g.feats.where((f) => f.earned).length;
    final months = {for (final e in entries) e.date.substring(0, 7)}.toList()..sort((a, b) => b.compareTo(a));
    final now = appNow();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (!months.contains(thisMonth)) months.insert(0, thisMonth);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader('Feats', trailing: Text('$earned of ${g.feats.length}', style: T.caption(bd))),
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - S.m * 2) / 3;
        final sorted = [...g.feats.where((f) => f.earned), ...g.feats.where((f) => !f.earned)];
        return Wrap(spacing: S.m, runSpacing: S.l, children: [for (final f in sorted) SizedBox(width: w, child: FeatMedal(f))]);
      }),
      if (g.seasonsEarned.isNotEmpty) ...[
        const SectionHeader('Season stamps'),
        Wrap(spacing: S.l, runSpacing: S.m, children: [
          for (final s in g.seasonsEarned.reversed)
            Column(children: [
              SeasonMotif(s.def.id, earned: true, size: 56),
              const SizedBox(height: 6),
              Text(s.label, style: T.sans(bd, size: 12, weight: FontWeight.w600)),
            ]),
        ]),
      ],
      const SectionHeader('Stamp book'),
      Row(children: [
        Expanded(child: Text('A page a month: places, first tastes, new kinds, dry nights.', style: T.caption(bd))),
        TextAction(_showPlaces ? 'Hide places' : 'Show places', onTap: () => setState(() => _showPlaces = !_showPlaces)),
      ]),
      const SizedBox(height: S.m),
      for (final m in months.take(12)) ...[
        () {
          final d = parseKey('$m-01');
          final stamps = stampsBetween(entries, '$m-01', toKey(DateTime(d.year, d.month + 1, 0))).where((s) => _showPlaces || s.kind != StampKind.place).toList();
          return VisaPage(title: '${monthNames[d.month - 1]} ${d.year}', stamps: stamps, max: 9, empty: 'No stamps this month yet — a new place, a first taste or a dry night earns one.');
        }(),
        const SizedBox(height: S.m),
      ],
    ]);
  }

  Widget _taste(List<Entry> entries) {
    final store = TasteShareStore.instance;
    final lines = tasteLines(tasteProfile(entries), notes: palate(entries), loves: store.loves, avoid: store.avoid, sweetness: store.sweetness, diet: store.diet, allergies: store.allergies);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Palate'),
      PassportPalate(notes: palate(entries), sweetness: store.sweetness, avoid: store.avoid),
      const SectionHeader('What the bar sees'),
      BarPreview(payload: store.payload()),
      const SectionHeader('Your taste'),
      TastePrefsEditor(onChanged: () => setState(() {})),
      const SectionHeader('Sharing'),
      Group(children: [
        SettingRow(
          title: 'Nothing with alcohol tonight',
          hint: 'Goes first on what tonight\'s bartender sees.',
          trailing: BdToggle(on: store.dryTonight, label: 'Nothing with alcohol tonight', onChanged: (v) async {
            await store.setDryTonight(v);
            if (mounted) setState(() {});
          }),
        ),
        for (final l in lines)
          SettingRow(
            title: 'Share "${l.$2}"',
            hint: l.$3,
            trailing: BdToggle(on: !_hidden.contains(l.$1), label: 'Share ${l.$2}', onChanged: (_) => _toggle(l.$1)),
          ),
      ]),
      if (auth.isAuthed && db != null) ...[
        const SizedBox(height: S.xl),
        const TasteShareSettings(),
        const SizedBox(height: S.m),
        BdButton('Show my guest card', kind: BtnKind.secondary, icon: Ph.identificationBadge, onTap: () => showGuestCard(context)),
      ],
    ]);
  }
}

extension on String {
  String ifBlank(String other) => trim().isEmpty ? other : this;
}

/// Four numbers under the card.
class _Stats extends StatelessWidget {
  final PassportGame game;
  final List<Entry> entries;
  const _Stats({required this.game, required this.entries});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = passport(entries);
    Widget cell(String n, String label) => Expanded(
          child: Column(children: [
            Text(n, style: T.serif(bd, size: 26, height: 1).copyWith(fontFeatures: T.tnum)),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: T.sans(bd, size: 11.5, color: bd.muted)),
          ]),
        );
    Widget rule() => Container(width: 1, height: 30, color: bd.line);
    return Glass(
      padding: const EdgeInsets.symmetric(vertical: S.l),
      child: Row(children: [
        cell('${game.families}', 'tastes'),
        rule(),
        cell('${p.places}', 'places'),
        rule(),
        cell('${p.dryNights}', 'dry nights'),
        rule(),
        cell('${game.feats.where((f) => f.earned).length}', 'feats'),
      ]),
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
          Text('GUEST CARD', style: TextStyle(fontFamily: T.sansFamily, fontFamilyFallback: T.fallback, fontSize: 9, letterSpacing: 2.4, fontWeight: FontWeight.w700, color: bd.faint)),
          const SizedBox(height: S.m),
          if (c == null)
            Text(_error ?? '······', style: TextStyle(fontFamily: T.serifFamily, fontSize: _error == null ? 44 : 15, color: bd.ink))
          else
            Semantics(
              label: 'Code ${c.code.split('').join(' ')}',
              excludeSemantics: true,
              child: Text(c.code, style: TextStyle(fontFamily: T.sansFamily, fontFamilyFallback: T.fallback, fontSize: 46, letterSpacing: 10, fontWeight: FontWeight.w700, color: bd.accentText, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          const SizedBox(height: S.s),
          if (c != null) Text('Good until ${TimeOfDay.fromDateTime(c.expiresAt).format(context)}', style: TextStyle(fontFamily: T.sansFamily, fontFamilyFallback: T.fallback, fontSize: 12, color: bd.muted)),
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
    Widget chip(String text, {bool strong = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: strong ? bd.accent.withValues(alpha: .18) : bd.glass,
            borderRadius: BorderRadius.circular(rCtl),
            border: Border.all(color: strong ? bd.accent.withValues(alpha: .5) : bd.line, width: .8),
          ),
          child: Text(text, style: T.sans(bd, size: 13, weight: strong ? FontWeight.w600 : FontWeight.w500, color: strong ? bd.accentText : bd.ink)),
        );
    final chips = [for (final (t, strong) in tasteChips(payload)) chip(t, strong: strong)];
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
