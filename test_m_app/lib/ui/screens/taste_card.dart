// The taste passport — a game you win by drinking widely, never by drinking more.
// One calm page, in type and the mosaic:
//   • who you are: your name, your rank and miles, the line to the next rank;
//   • the taste map: every drink family as a square, one row per collection —
//     a first taste fills it, about one in six glows gilded;
//   • this week's three quests, the season, your latest stamps, your feats;
//   • at the bar: what a bartender sees, your taste, sharing, your guest card.
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

/// [open] is 'YYYY-MM' (or 'YYYY') to show that month's (year's) stamps.
Future<void> showTasteCard(BuildContext context, {String? open}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => TasteCardScreen(open: open)));

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

class TasteCardScreen extends StatelessWidget {
  final String? open;
  const TasteCardScreen({super.key, this.open});

  @override
  Widget build(BuildContext context) {
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: Listenable.merge([entryStore, WishlistStore.instance, TasteShareStore.instance]),
          builder: (context, _) {
            final entries = entryStore.entries;
            final g = passportGame(entries);
            return SubPage(
              title: 'Taste passport',
              large: false,
              actions: [IconBtn(Ph.shareNetwork, tooltip: 'Share your passport', onTap: () => _sharePoster(context, g))],
              child: _PassportBody(game: g, entries: entries, open: open),
            );
          },
        ),
      ),
    );
  }
}

class _PassportBody extends StatelessWidget {
  final PassportGame game;
  final List<Entry> entries;
  final String? open;
  const _PassportBody({required this.game, required this.entries, this.open});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final g = game;
    final p = passport(entries);
    final total = g.collections.fold<int>(0, (a, c) => a + c.total);
    final store = TasteShareStore.instance;
    final chips = tasteChips(store.payload());
    final next = nextStamps(entries, 2);

    // the stamps section: a month (or year) if one was asked for, else the latest
    final period = open == null
        ? null
        : open!.length == 4
            ? open!
            : '${monthNames[parseKey('${open!}-01').month - 1]} ${open!.substring(0, 4)}';
    final stamps = open == null ? g.ledger.take(5).toList() : g.ledger.where((e) => e.date.startsWith(open!)).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Identity(game: g, name: auth.profile?.name, entries: entries),
      const SizedBox(height: S.xl),
      _Figures(items: [('${g.families}', 'of $total tastes'), ('${p.places}', 'places'), ('${p.dryNights}', 'dry nights'), ('${g.feats.where((f) => f.earned).length}', 'feats')]),

      SectionHeader('Taste map', trailing: Text('${g.families} / $total', style: T.caption(bd).copyWith(fontFeatures: T.tnum))),
      Glass(
        padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, S.m),
        child: TasteMap(collections: g.collections, gilded: g.gilded, onOpen: (c) => _openCollection(context, c, g)),
      ),
      const SizedBox(height: S.s),
      Text('A first taste fills a square; about one in six comes out gilded. Tap a row to see what\'s in it.', style: T.caption(bd)),

      SectionHeader('This week', trailing: Text(g.questDaysLeft == 0 ? 'new ones tomorrow' : 'new in ${g.questDaysLeft} ${g.questDaysLeft == 1 ? 'day' : 'days'}', style: T.caption(bd))),
      QuestList(quests: g.quests),

      const SectionHeader('This season'),
      SeasonLine(season: g.season, onTap: () => _openSeason(context, g)),

      SectionHeader(period == null ? 'Latest stamps' : 'Stamps · $period', action: g.ledger.length > stamps.length ? 'All' : null, onAction: () => _openLedger(context, g)),
      if (stamps.isEmpty)
        Text(period == null ? 'Your first stamp comes with your first log — a drink or a dry night.' : 'No stamps in $period yet.', style: T.bodyMuted(bd))
      else
        MilesLedger(stamps),

      SectionHeader('Feats', trailing: Text('${g.feats.where((f) => f.earned).length} of ${g.feats.length}', style: T.caption(bd))),
      FeatRow(feats: g.feats),

      const SectionHeader('At the bar'),
      Group(children: [
        GroupTile(
          icon: Ph.martini,
          title: 'What the bar sees',
          subtitle: chips.isEmpty ? 'Nothing yet — add what you love' : chips.take(3).map((c) => c.$1).join(' · '),
          chevron: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TasteAtTheBarScreen())),
        ),
        if (next.isNotEmpty)
          GroupTile(
            icon: Ph.sparkle,
            title: 'Next to try',
            subtitle: next.map((n) => n.family).join(' · '),
            chevron: true,
            onTap: () => showBdSheet<void>(context, title: 'Next to try', builder: (_) => const NextStampsList()),
          ),
        GroupTile(
          icon: Ph.compass,
          title: 'Ranks and miles',
          subtitle: 'The eight ranks, and what earns a mile',
          chevron: true,
          onTap: () => _openRanks(context, g),
        ),
        if (auth.isAuthed && db != null) GroupTile(icon: Ph.identificationBadge, title: 'Your guest card', subtitle: 'A code staff type to find you', chevron: true, onTap: () => showGuestCard(context)),
      ]),
    ]);
  }
}

/// Who you are, in type: your name, your rank and miles, the line to the next.
class _Identity extends StatelessWidget {
  final PassportGame game;
  final String? name;
  final List<Entry> entries;
  const _Identity({required this.game, required this.name, required this.entries});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final g = game;
    String? since;
    if (entries.isNotEmpty) {
      final d = parseKey(entries.map((e) => e.date).reduce((a, b) => a.compareTo(b) < 0 ? a : b));
      since = 'since ${monthNames[d.month - 1]} ${d.year}';
    }
    return Semantics(
      label: '${(name ?? '').trim().isEmpty ? 'Your passport' : name}. ${g.rank.title}, ${g.miles} miles${g.next == null ? '' : ', ${g.toNext} to ${g.next!.title}'}.',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TASTE PASSPORT', style: T.label(bd, color: bd.accentText)),
              const SizedBox(height: 6),
              Text((name ?? '').trim().isEmpty ? 'Your passport' : name!.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.serif(bd, size: 42, height: 1.0)),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(text: g.rank.title, style: T.serif(bd, size: 20, italic: true, color: bd.accentText)),
                TextSpan(text: '   ${g.miles} miles', style: T.sans(bd, size: 14, color: bd.muted).copyWith(fontFeatures: T.tnum)),
              ])),
            ]),
          ),
          RankEmblem(g.rank.index, size: 54),
        ]),
        const SizedBox(height: S.l),
        RankLine(g.progress),
        const SizedBox(height: S.s),
        Row(children: [
          Text(since ?? 'a fresh passport', style: T.caption(bd)),
          const Spacer(),
          Text(g.next == null ? 'the top of the map' : '${g.toNext} miles to ${g.next!.title}', style: T.caption(bd)),
        ]),
      ]),
    );
  }
}

/// A row of small figures with hairlines between them.
class _Figures extends StatelessWidget {
  final List<(String, String)> items;
  const _Figures({required this.items});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) Container(width: .8, height: 26, color: bd.line),
        Expanded(
          child: Column(children: [
            Text(items[i].$1, style: T.serif(bd, size: 24, height: 1).copyWith(fontFeatures: T.tnum)),
            const SizedBox(height: 4),
            Text(items[i].$2, textAlign: TextAlign.center, style: T.sans(bd, size: 11.5, color: bd.muted)),
          ]),
        ),
      ],
    ]);
  }
}

void _wish(BuildContext context, String family) {
  final listed = WishlistStore.instance.items.any((w) => w.drink.toLowerCase() == family.toLowerCase());
  if (listed) {
    toast(context, '$family is already on your to-try list.');
    return;
  }
  WishlistStore.instance.add(family);
  toast(context, '$family is on your to-try list.');
}

Set<String> get _listed => {for (final w in WishlistStore.instance.items) w.drink.toLowerCase()};

void _openCollection(BuildContext context, CollectionState col, PassportGame g) {
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
                  : (flavours[f] ?? const []).isEmpty
                      ? 'not tried yet'
                      : (flavours[f] ?? const []).join(', '),
              trailing: col.tried.containsKey(f)
                  ? null
                  : _listed.contains(f.toLowerCase())
                      ? Text('On your list', style: T.caption(bd))
                      : TextAction('To try', accent: true, onTap: () => _wish(sheet, f)),
            ),
        ]),
      ]),
    );
  });
}

void _openSeason(BuildContext context, PassportGame g) => showBdSheet<void>(
      context,
      builder: (sheet) => ListenableBuilder(
        listenable: WishlistStore.instance,
        builder: (sheet, _) => SeasonCard(season: g.season, onPick: (f) => _wish(sheet, f), onList: _listed),
      ),
    );

void _openLedger(BuildContext context, PassportGame g) => showBdSheet<void>(context, title: 'Every stamp', builder: (_) => MilesLedger(g.ledger));

void _openRanks(BuildContext context, PassportGame g) => showBdSheet<void>(
      context,
      title: 'Ranks and miles',
      builder: (sheet) {
        final bd = sheet.bd;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${g.rank.title} — ${g.rank.line}', style: T.serif(bd, size: 18, italic: true, color: bd.muted, height: 1.3)),
          const SizedBox(height: S.l),
          RankRoad(game: g),
          const SizedBox(height: S.xl),
          const MilesGuide(),
        ]);
      },
    );

/// Share the passport as a picture: your name, rank and taste map.
Future<void> _sharePoster(BuildContext context, PassportGame g) => showBdSheet<void>(context, title: 'Share your passport', builder: (_) => _PosterSheet(game: g));

class _PosterSheet extends StatefulWidget {
  final PassportGame game;
  const _PosterSheet({required this.game});
  @override
  State<_PosterSheet> createState() => _PosterSheetState();
}

class _PosterSheetState extends State<_PosterSheet> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(rTile),
        child: RepaintBoundary(key: _key, child: PassportPoster(game: widget.game, name: auth.profile?.name)),
      ),
      const SizedBox(height: S.s),
      Text('Your rank and your taste map — never what or how much you drank.', textAlign: TextAlign.center, style: T.caption(bd)),
      const SizedBox(height: S.l),
      BdButton(_busy ? 'Making it…' : 'Share', icon: Ph.export, onTap: _share),
    ]);
  }
}

/// At the bar: your palate, exactly what a bartender would see, what you love and
/// avoid, which lines go to the bar, and your guest card.
class TasteAtTheBarScreen extends StatefulWidget {
  const TasteAtTheBarScreen({super.key});
  @override
  State<TasteAtTheBarScreen> createState() => _TasteAtTheBarScreenState();
}

class _TasteAtTheBarScreenState extends State<TasteAtTheBarScreen> {
  late final Set<String> _hidden = {...(Prefs.getJson<List<dynamic>>(TasteShareStore.hiddenKey) ?? const []).map((e) => '$e')};

  void _toggle(String line) {
    setState(() => _hidden.contains(line) ? _hidden.remove(line) : _hidden.add(line));
    Prefs.setJson(TasteShareStore.hiddenKey, _hidden.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListenableBuilder(
          listenable: Listenable.merge([entryStore, TasteShareStore.instance]),
          builder: (context, _) {
            final entries = entryStore.entries;
            final store = TasteShareStore.instance;
            final lines = tasteLines(tasteProfile(entries), notes: palate(entries), loves: store.loves, avoid: store.avoid, sweetness: store.sweetness, diet: store.diet, allergies: store.allergies);
            return SubPage(
              title: 'At the bar',
              subtitle: 'What a bartender sees when you open their menu — and what you tell them.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionHeader('What the bar sees', padding: EdgeInsets.only(top: S.s, bottom: S.m)),
                BarPreview(payload: store.payload()),
                const SectionHeader('Palate'),
                PassportPalate(notes: palate(entries), sweetness: store.sweetness, avoid: store.avoid),
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
              ]),
            );
          },
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
