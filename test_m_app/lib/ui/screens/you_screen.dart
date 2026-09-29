// You — the "you" half of src/components/you/You.tsx: your numbers, your balance
// (only once asked for), your year, the to-try list, your words, photos, your home
// bar, the journey so far, and a searchable history. Settings live on their own
// page behind the gear (settings_screen.dart).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/derive.dart';
import '../../core/drinks.dart';
import '../../core/types.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../../data/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/moments.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import 'photo_studio.dart';
import 'settings_screen.dart';
import 'taste_card.dart';

class YouScreen extends StatefulWidget {
  /// Source of the suggested to-try pick; tests seed it for stable screenshots.
  static math.Random random = math.Random();
  const YouScreen({super.key});
  @override
  State<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends State<YouScreen> {
  static const _historyPage = 25;
  final _query = TextEditingController();
  String? _mood;
  bool _allHistory = false;
  bool _allWords = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _openDay(String dateKey) => openLog(context, dateKey, yearLink: false);

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Watch(
      to: [entryStore, GoalsStore.instance],
      builder: (context) {
        final entries = entryStore.entries;
        final s = stats(entries);
        final lex = lexicon(entries);
        final yr = yearReview(entries);
        final photos = [
          for (final e in entries)
            for (final p in e.photos ?? const <Photo>[]) (photo: p, date: e.date),
        ];
        final q = _query.text.trim().toLowerCase();
        final filtered = entries
            .where((e) => _mood == null || e.mood?.toLowerCase() == _mood)
            .where((e) => q.isEmpty || [e.drink, e.mood, e.note, e.venue].any((f) => f?.toLowerCase().contains(q) ?? false))
            .toList()
          ..sort((a, b) {
            final c = b.date.compareTo(a.date);
            return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
          });
        final shown = _allHistory ? filtered : filtered.take(_historyPage).toList();

        return ScrollPage(
          title: 'You',
          titleNote: '${s.longest} night best',
          onRefresh: entryStore.reload,
          children: [
            StreakStrip(stats: s),
            _BalanceCard(entries: entries),
            if (yr.total > 0) ...[
              const SectionHeader('Your year'),
              Group(children: [
                if (yr.topDrink != null) _reviewRow(bd, 'Most poured', yr.topDrink!),
                if (yr.topMood != null) _reviewRow(bd, 'Most felt', yr.topMood!, italic: true),
                if (yr.busiestMonth != null) _reviewRow(bd, 'Busiest month', yr.busiestMonth!),
                _reviewRow(bd, 'Days logged', '${yr.days}'),
              ]),
            ],
            const _ToTry(),
            if (lex.isNotEmpty) ...[
              SectionHeader('Your words', action: _mood == null ? null : 'Clear', onAction: () => setState(() => _mood = null)),
              Wrap(spacing: S.s, children: [
                for (final m in (_allWords ? lex : lex.take(12)))
                  BdChip('${m.word}  ${m.count}', active: _mood == m.word, onTap: () => setState(() {
                        _mood = _mood == m.word ? null : m.word;
                        _allHistory = false;
                      })),
                if (!_allWords && lex.length > 12) BdChip('+${lex.length - 12} more', onTap: () => setState(() => _allWords = true)),
              ]),
              Padding(padding: const EdgeInsets.only(top: S.xs), child: Text('Tap a word to find the nights you used it.', style: T.caption(bd))),
            ],
            if (photos.isNotEmpty) ...[
              SectionHeader('Photos', action: 'Make a card', onAction: () {
                final latest = entries.where((e) => e.photos?.isNotEmpty ?? false).reduce((a, b) => a.date.compareTo(b.date) >= 0 ? a : b);
                showPhotoStudio(context, NightStory.fromEntry(latest), photo: latest.photos!.first.url);
              }),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final p in photos)
                    Semantics(
                      button: true,
                      label: 'Photo from ${formatDayLongYear(p.date)}',
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: () => _openDay(p.date),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(rCell + 2),
                          child: ColoredBox(
                            color: bd.glass,
                            child: p.photo.isLocal ? Image.file(File(p.photo.url), fit: BoxFit.cover) : Image.network(p.photo.url, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SectionHeader('Your bar'),
            const _Pantry(),
            const SizedBox(height: S.m),
            _JourneyTile(entries: entries),
            const SizedBox(height: S.m),
            Group(children: [
              GroupTile(
                icon: Ph.identificationBadge,
                title: 'Your taste passport',
                subtitle: 'Stamps for everywhere you\'ve been, and what you\'re into.',
                chevron: true,
                onTap: () => showTasteCard(context),
              ),
            ]),
            SectionHeader('History', trailing: Text('${filtered.length}', style: T.caption(bd).copyWith(fontFeatures: T.tnum))),
            GlassField(
              controller: _query,
              hint: 'Search drinks, words, notes, places',
              icon: Ph.magnifyingGlass,
              action: TextInputAction.search,
              caps: TextCapitalization.none,
              onChanged: (_) => setState(() => _allHistory = false),
            ),
            if (_mood != null) ...[
              const SizedBox(height: S.xs),
              Align(alignment: Alignment.centerLeft, child: BdChip('“$_mood”', active: true, icon: PhBold.x, onTap: () => setState(() => _mood = null))),
            ],
            const SizedBox(height: S.m),
            if (filtered.isEmpty)
              EmptyNote(entries.isEmpty ? 'Nothing logged yet — your history starts with the first square.' : 'Nothing matches that.', icon: Ph.magnifyingGlass)
            else ...[
              Group(children: [
                for (final e in shown)
                  GroupTile(
                    title: e.drink,
                    subtitle: [e.mood, e.venue].whereType<String>().join(' · ').isEmpty ? null : [e.mood, e.venue].whereType<String>().join(' · '),
                    trailing: Text(shortDay(e.date), style: T.caption(bd)),
                    onTap: () => _openDay(e.date),
                  ),
              ]),
              if (filtered.length > shown.length)
                Center(child: TextAction('Show all ${filtered.length}', accent: true, onTap: () => setState(() => _allHistory = true))),
            ],
            // Settings live right here, like the website — no gear to find.
            const SectionHeader('Settings'),
            const SettingsBody(),
          ],
        );
      },
    );
  }

  Widget _reviewRow(BD bd, String label, String value, {bool italic = false}) => GroupTile(
        title: label,
        trailing: Text(value, style: T.row(bd, color: bd.muted).copyWith(fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
      );
}

/// Balance — shows ONLY once a goal is set. A mirror, never a scold.
class _BalanceCard extends StatelessWidget {
  final List<Entry> entries;
  const _BalanceCard({required this.entries});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final g = GoalsStore.instance;
    if (!g.anySet) return const SizedBox.shrink();
    final b = weekBalance(entries);
    final over = g.weeklyLimit != null && b.drinks > g.weeklyLimit!;
    final dryMet = g.dryDays != null && b.dryDays >= g.dryDays!;
    Widget cell(int v, int of, String label, bool accent) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '$v', style: T.serif(bd, size: 34, color: accent ? bd.accentText : bd.ink)),
              TextSpan(text: ' / $of', style: T.serif(bd, size: 20, color: bd.faint)),
            ])),
            const SizedBox(height: 2),
            Text(label, style: T.caption(bd)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Your balance'),
      Glass(
        padding: const EdgeInsets.all(S.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (g.weeklyLimit != null) cell(b.drinks, g.weeklyLimit!, 'drinks this week', over),
            if (g.dryDays != null) cell(b.dryDays, g.dryDays!, 'dry days', dryMet),
          ]),
          const SizedBox(height: S.l),
          Text('A rolling seven days. Yours alone — never shared, never shown to a bar, never on a board.', style: T.caption(bd)),
        ]),
      ),
    ]);
  }
}

class _ToTry extends StatefulWidget {
  const _ToTry();
  @override
  State<_ToTry> createState() => _ToTryState();
}

class _ToTryState extends State<_ToTry> {
  final _draft = TextEditingController();
  String? _pick;
  math.Random get _rng => YouScreen.random;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  List<String> _suggestions() {
    final seen = <String>{for (final e in entryStore.entries) normalize(e.drink), for (final w in wishlist.items) normalize(w.drink)};
    return drinks.map((d) => d.canonical).where((n) => !seen.contains(normalize(n))).toList();
  }

  void _add(String v) {
    if (v.trim().isEmpty) return;
    wishlist.add(v);
    _draft.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Watch(
      to: [wishlist, entryStore],
      builder: (context) {
        final sug = _suggestions();
        if (sug.isEmpty) {
          _pick = null;
        } else if (_pick == null || !sug.contains(_pick)) {
          _pick = sug[_rng.nextInt(sug.length)];
        }
        final items = wishlist.items;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader('To try', trailing: items.isEmpty ? null : Text('${items.length}', style: T.caption(bd).copyWith(fontFeatures: T.tnum))),
          Row(children: [
            Expanded(
              child: GlassField(
                controller: _draft,
                hint: "A drink you're curious about",
                icon: Ph.plus,
                action: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: _add,
              ),
            ),
            const SizedBox(width: S.s),
            BdButton('Add', expand: false, height: 48, onTap: _draft.text.trim().isEmpty ? null : () => _add(_draft.text)),
          ]),
          if (_pick != null) ...[
            const SizedBox(height: S.m),
            Glass(
              padding: const EdgeInsets.fromLTRB(S.l, S.s, S.s, S.s),
              child: Row(children: [
                Icon(Ph.sparkle, size: 18, color: bd.accentText),
                const SizedBox(width: S.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Something new', style: T.caption(bd)),
                    Text(_pick!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.row(bd)),
                  ]),
                ),
                IconBtn(Ph.arrowsClockwise, tooltip: 'Suggest another', color: bd.muted, onTap: sug.length <= 1
                    ? null
                    : () {
                        var n = _pick;
                        while (n == _pick) {
                          n = sug[_rng.nextInt(sug.length)];
                        }
                        setState(() => _pick = n);
                      }),
                TextAction('Add', accent: true, onTap: () => wishlist.add(_pick!)),
              ]),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: S.m),
            Group(children: [
              for (final w in items)
                GroupTile(
                  icon: Ph.circle,
                  title: w.drink,
                  subtitle: 'Tried it? Tap to log it',
                  onTap: () => showBdSheet(context, title: 'Log to your diary', builder: (_) => _LogWish(item: w)),
                  trailing: IconBtn(Ph.x, tooltip: 'Remove ${w.drink}', size: 18, color: bd.faint, onTap: () => wishlist.remove(w.id)),
                ),
            ]),
          ] else if (_pick == null)
            const EmptyNote('Nothing to try yet — add a drink above.'),
        ]);
      },
    );
  }
}

/// Trying something new belongs on a day — log it and take it off the list.
class _LogWish extends StatefulWidget {
  final WishItem item;
  const _LogWish({required this.item});
  @override
  State<_LogWish> createState() => _LogWishState();
}

class _LogWishState extends State<_LogWish> {
  DateTime _date = appNow();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final now = appNow();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.item.drink, style: T.serif(bd, size: 30, height: 1.1)),
      const SizedBox(height: S.xl),
      PickerField(
        label: 'Which day',
        value: toKey(_date) == todayKey() ? 'Today' : writtenDate(_date),
        icon: Ph.calendarBlank,
        onTap: () async {
          final d = await pickDate(context, title: 'Which day', initial: _date, first: DateTime(now.year - 5), last: now);
          if (d != null) setState(() => _date = d);
        },
      ),
      const SizedBox(height: S.xxl),
      BdButton('Log it', onTap: () {
        entryStore.addEntry(date: toKey(_date), drink: widget.item.drink, type: canonicalize(widget.item.drink).type);
        wishlist.remove(widget.item.id);
        Navigator.pop(context);
        toast(context, 'Logged ${widget.item.drink} — and off the list.');
      }),
    ]);
  }
}

/// Your bar — what you keep at home. Feeds Ninkasi later.
class _Pantry extends StatefulWidget {
  const _Pantry();
  @override
  State<_Pantry> createState() => _PantryState();
}

class _PantryState extends State<_Pantry> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _add(String v) {
    PantryStore.instance.add(v);
    _draft.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: PantryStore.instance,
      builder: (context, _) {
        final items = PantryStore.instance.items;
        return Glass(
          padding: const EdgeInsets.all(S.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(items.isNotEmpty ? '${items.length} on hand' : "What's at home", style: T.row(bd)),
            const SizedBox(height: S.s),
            Row(children: [
              Expanded(
                child: GlassField(
                  controller: _draft,
                  hint: 'Gin, lime, tonic…',
                  action: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _add,
                ),
              ),
              const SizedBox(width: S.s),
              BdButton('Add', expand: false, height: 48, kind: BtnKind.secondary, onTap: _draft.text.trim().isEmpty ? null : () => _add(_draft.text)),
            ]),
            if (items.isNotEmpty) ...[
              const SizedBox(height: S.xs),
              Wrap(spacing: S.s, children: [for (final it in items) BdChip(it, icon: PhBold.x, onTap: () => PantryStore.instance.remove(it))]),
            ],
            const SizedBox(height: S.s),
            Text('Ninkasi will use this to suggest what you can make at home — coming soon.', style: T.caption(bd)),
          ]),
        );
      },
    );
  }
}

class _JourneyTile extends StatelessWidget {
  final List<Entry> entries;
  const _JourneyTile({required this.entries});
  @override
  Widget build(BuildContext context) {
    final places = <String>{}, people = <String>{}, drinksMet = <String>{}, days = <String>{};
    String? first;
    for (final e in entries) {
      if (e.venue?.trim().isNotEmpty ?? false) places.add(e.venue!.trim().toLowerCase());
      for (final w in e.whoWith ?? const <String>[]) {
        if (w.trim().isNotEmpty) people.add(w.trim().toLowerCase());
      }
      if (e.drink.trim().isNotEmpty && e.type != DrinkType.none) drinksMet.add(e.drink.trim().toLowerCase());
      days.add(e.date);
      if (first == null || e.date.compareTo(first) < 0) first = e.date;
    }
    String pl(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    return Group(children: [
      GroupTile(
        icon: Ph.mapTrifold,
        title: 'Your journey',
        subtitle: days.isNotEmpty ? '${pl(places.length, 'place', 'places')} · ${pl(people.length, 'person', 'people')} · ${pl(drinksMet.length, 'drink', 'drinks')}' : 'Your story so far',
        chevron: true,
        onTap: () => showBdSheet(context, title: 'Your journey', builder: (ctx) {
          final bd = ctx.bd;
          Widget stat(int n, String label) => Expanded(
                child: Glass(
                  padding: const EdgeInsets.all(S.l),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$n', style: T.serif(bd, size: 34)),
                    const SizedBox(height: 2),
                    Text(label, style: T.caption(bd)),
                  ]),
                ),
              );
          final since = first == null ? null : parseKey(first);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('The story so far', style: T.bodyMuted(bd)),
            const SizedBox(height: S.l),
            Row(children: [stat(days.length, 'days kept'), const SizedBox(width: S.m), stat(drinksMet.length, 'drinks met')]),
            const SizedBox(height: S.m),
            Row(children: [stat(places.length, 'places been'), const SizedBox(width: S.m), stat(people.length, 'alongside')]),
            if (since != null) Padding(padding: const EdgeInsets.only(top: S.l), child: Text('Since ${monthNames[since.month - 1]} ${since.year}.', style: T.caption(bd))),
          ]);
        }),
      ),
    ]);
  }
}
