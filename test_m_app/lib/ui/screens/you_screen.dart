// You — a port of src/components/you/You.tsx. Your numbers, your balance (only once
// asked for), your year, the to-try list, your words, photos, the shelf, and every
// setting: reminder, Ninkasi consent, trends, leaderboard, handle, standing,
// profile privacy, blocks, venue notes, where you are, gentle limits, extras, data.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../core/date.dart';
import '../../core/derive.dart';
import '../../core/drinks.dart';
import '../../core/handles.dart';
import '../../core/jurisdiction.dart';
import '../../core/misc.dart';
import '../../core/money.dart';
import '../../core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/friends.dart';
import '../../data/reminder.dart';
import '../../data/safety.dart';
import '../../data/settings.dart';
import '../../data/wishlist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import 'landing_screen.dart';
import 'profile_screen.dart';
import 'together_screen.dart' show DateField;

class YouScreen extends StatefulWidget {
  /// Source of the suggested to-try pick; tests seed it for stable screenshots.
  static math.Random random = math.Random();
  const YouScreen({super.key});
  @override
  State<YouScreen> createState() => _YouScreenState();
}

class _YouScreenState extends State<YouScreen> {
  final _query = TextEditingController();
  String? _mood;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

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
        final photos = [for (final e in entries) ...?e.photos];
        final q = _query.text.trim().toLowerCase();
        final filtered = entries
            .where((e) => _mood == null || e.mood?.toLowerCase() == _mood)
            .where((e) => q.isEmpty || [e.drink, e.mood, e.note, e.venue].any((f) => f?.toLowerCase().contains(q) ?? false))
            .toList()
          ..sort((a, b) {
            final c = b.date.compareTo(a.date);
            return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
          });

        Widget metric(int v, String label) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(children: [
                  Text('$v', style: T.sans(bd, size: 24, weight: FontWeight.w600, height: 1).copyWith(fontFeatures: T.tnum)),
                  const SizedBox(height: 6),
                  Label(label),
                ]),
              ),
            );

        return ScrollPage(
          title: 'You',
          subtitle: s.longest > 0 ? 'Your longest run: ${s.longest} ${s.longest == 1 ? 'night' : 'nights'}.' : null,
          onRefresh: entryStore.reload,
          children: [
          Glass(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Row(children: [metric(s.current, 'streak'), metric(s.total, 'logged'), metric(s.kinds, 'kinds')]),
              if (s.total > 0) ...[Divider(height: 24, color: bd.line), MilestoneMeter(total: s.total)],
            ]),
          ),
          _BalanceCard(entries: entries),
          if (yr.total > 0) ...[
            const SizedBox(height: 40),
            const Label('Your year'),
            const SizedBox(height: 12),
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                if (yr.topDrink != null) _reviewRow(bd, 'Most poured', yr.topDrink!),
                if (yr.topMood != null) _reviewRow(bd, 'Most-felt', yr.topMood!, italic: true),
                if (yr.busiestMonth != null) _reviewRow(bd, 'Busiest month', yr.busiestMonth!),
                _reviewRow(bd, 'Days logged', '${yr.days}', last: true),
              ]),
            ),
          ],
          const _ToTry(),
          if (lex.isNotEmpty) ...[
            const SizedBox(height: 40),
            const Label('Your words'),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in lex) BdChip('${m.word}  ${m.count}', active: _mood == m.word, onTap: () => setState(() => _mood = _mood == m.word ? null : m.word)),
            ]),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 40),
            const Label('Photos'),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final p in photos) ClipRRect(borderRadius: BorderRadius.circular(rCell), child: p.isLocal ? Image.file(File(p.url), fit: BoxFit.cover) : Image.network(p.url, fit: BoxFit.cover)),
              ],
            ),
          ],
          const SizedBox(height: 40),
          Row(children: [
            const Expanded(child: Label('Shelf')),
            if (_mood != null || _query.text.isNotEmpty)
              TextAction('clear', size: 12, faint: true, onTap: () => setState(() {
                    _mood = null;
                    _query.clear();
                  })),
          ]),
          const SizedBox(height: 12),
          const _Pantry(),
          const SizedBox(height: 12),
          _JourneyTile(entries: entries),
          const SizedBox(height: 12),
          LineField(controller: _query, size: 14, hint: 'Search your drinks…', onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const EmptyNote('Nothing here yet.')
          else
            Glass(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                for (var i = 0; i < filtered.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: bd.line))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(filtered[i].drink, overflow: TextOverflow.ellipsis, style: T.sans(bd)),
                          if (filtered[i].mood != null || filtered[i].venue != null)
                            Text(
                              [filtered[i].mood, filtered[i].venue].whereType<String>().join(' · '),
                              style: T.sans(bd, size: 12, color: bd.muted),
                            ),
                        ]),
                      ),
                      Text(shortDay(filtered[i].date), style: T.sans(bd, size: 12, color: bd.faint)),
                    ]),
                  ),
              ]),
            ),
          const _Settings(),
        ]);
      },
    );
  }

  Widget _reviewRow(BD bd, String label, String value, {bool italic = false, bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: bd.line))),
        child: Row(children: [
          Expanded(child: Label(label)),
          Text(value, style: T.sans(bd).copyWith(fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
        ]),
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
              TextSpan(text: '$v', style: T.serif(bd, size: 32, color: accent ? bd.accent : bd.ink)),
              TextSpan(text: ' / $of', style: T.serif(bd, size: 18, color: bd.faint)),
            ])),
            Text(label, style: T.sans(bd, size: 12, color: bd.faint)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Label('Your balance'),
        const SizedBox(height: 12),
        Glass(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (g.weeklyLimit != null) cell(b.drinks, g.weeklyLimit!, 'drinks this week', over),
              if (g.dryDays != null) cell(b.dryDays, g.dryDays!, 'dry days', dryMet),
            ]),
            const SizedBox(height: 16),
            Text('A rolling seven days. Yours alone — never shared, never shown to a bar, never on a board.', style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
          ]),
        ),
      ]),
    );
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

  List<String> _suggestions() {
    final seen = <String>{for (final e in entryStore.entries) normalize(e.drink), for (final w in wishlist.items) normalize(w.drink)};
    return drinks.map((d) => d.canonical).where((n) => !seen.contains(normalize(n))).toList();
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
        return Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Label('To try'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: LineField(controller: _draft, size: 14, hint: "Add a drink you're curious about…", onChanged: (_) => setState(() {}), onSubmitted: (v) {
                wishlist.add(v);
                _draft.clear();
              })),
              const SizedBox(width: 8),
              SizedBox(width: 64, child: InkButton('Add', height: 32, onTap: _draft.text.trim().isEmpty ? null : () {
                wishlist.add(_draft.text);
                _draft.clear();
                setState(() {});
              })),
            ]),
            const SizedBox(height: 12),
            if (_pick == null && items.isEmpty)
              Text('Nothing to try yet — add a drink above.', style: T.sans(bd, size: 14, color: bd.faint))
            else
              Glass(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                    if (_pick != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Label('suggested', color: bd.faint),
                              Text(_pick!, style: T.sans(bd)),
                            ]),
                          ),
                          TextAction('Another', size: 12, faint: true, onTap: () {
                            if (sug.length <= 1) return;
                            var n = _pick;
                            while (n == _pick) {
                              n = sug[_rng.nextInt(sug.length)];
                            }
                            setState(() => _pick = n);
                          }),
                          const SizedBox(width: 10),
                          SizedBox(width: 60, child: InkButton('Add', height: 30, onTap: () => wishlist.add(_pick!))),
                        ]),
                      ),
                    for (final w in items)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: bd.line))),
                        child: Row(children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => showBdSheet(context, builder: (_) => _LogWish(item: w)),
                              child: Row(children: [
                                Container(width: 16, height: 16, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: bd.lineStrong))),
                                const SizedBox(width: 10),
                                Expanded(child: Text(w.drink, overflow: TextOverflow.ellipsis, style: T.sans(bd))),
                              ]),
                            ),
                          ),
                          TextAction('Remove', faint: true, onTap: () => wishlist.remove(w.id)),
                        ]),
                      ),
                  ]),
                ),
              ),
          ]),
        );
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Label('Log to your diary', color: bd.faint),
      const SizedBox(height: 4),
      Text(widget.item.drink, style: T.serif(bd, size: 30)),
      const SizedBox(height: 20),
      Text('Which day', style: T.sans(bd, size: 12, color: bd.muted)),
      const SizedBox(height: 6),
      DateField(value: _date, last: appNow(), onChanged: (d) => setState(() => _date = d)),
      const SizedBox(height: 20),
      InkButton('Log it', uppercase: false, onTap: () {
        entryStore.addEntry(date: toKey(_date), drink: widget.item.drink, type: canonicalize(widget.item.drink).type);
        wishlist.remove(widget.item.id);
        Navigator.pop(context);
      }),
      const SizedBox(height: 8),
      Center(child: TextAction('Cancel', faint: true, onTap: () => Navigator.pop(context))),
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
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: PantryStore.instance,
      builder: (context, _) {
        final items = PantryStore.instance.items;
        return Glass(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Label('Your bar', color: bd.faint)),
              Text(items.isNotEmpty ? '${items.length} on hand' : "what's at home", style: T.sans(bd, size: 12, color: bd.faint)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: LineField(controller: _draft, size: 14, hint: 'Add an ingredient — gin, lime, tonic…', onChanged: (_) => setState(() {}), onSubmitted: (v) {
                PantryStore.instance.add(v);
                _draft.clear();
              })),
              const SizedBox(width: 8),
              SizedBox(width: 64, child: InkButton('Add', height: 32, onTap: _draft.text.trim().isEmpty ? null : () {
                PantryStore.instance.add(_draft.text);
                _draft.clear();
                setState(() {});
              })),
            ]),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final it in items) BdChip('$it  ×', onTap: () => PantryStore.instance.remove(it))]),
            ],
            const SizedBox(height: 10),
            Text('Ninkasi will use this to suggest what you can make at home — coming soon.', style: T.sans(bd, size: 12, color: bd.faint)),
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
    final bd = context.bd;
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
    return Glass(
      padding: const EdgeInsets.all(16),
      onTap: () => showBdSheet(context, builder: (ctx) {
        Widget stat(int n, String label) => Expanded(
              child: Glass(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$n', style: T.serif(bd, size: 32)),
                  const SizedBox(height: 4),
                  Text(label, style: T.sans(bd, size: 12, color: bd.faint)),
                ]),
              ),
            );
        final since = first == null ? null : parseKey(first);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Label('Your journey', color: bd.faint),
          const SizedBox(height: 4),
          Text('The story so far', style: T.serif(bd, size: 26)),
          const SizedBox(height: 16),
          Row(children: [stat(days.length, 'days kept'), const SizedBox(width: 12), stat(drinksMet.length, 'drinks met')]),
          const SizedBox(height: 12),
          Row(children: [stat(places.length, 'places been'), const SizedBox(width: 12), stat(people.length, 'alongside')]),
          if (since != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Since ${monthNames[since.month - 1]} ${since.year}.', style: T.sans(bd, size: 12, color: bd.faint))),
        ]);
      }),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Label('Your journey', color: bd.faint),
            const SizedBox(height: 2),
            Text(
              days.isNotEmpty ? '${pl(places.length, 'place', 'places')} · ${pl(people.length, 'person', 'people')} · ${pl(drinksMet.length, 'drink', 'drinks')}' : 'Your story so far',
              overflow: TextOverflow.ellipsis,
              style: T.sans(bd),
            ),
          ]),
        ),
        Text('Open →', style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.accent)),
      ]),
    );
  }
}

// ── settings ─────────────────────────────────────────────────────────────────
class _Settings extends StatelessWidget {
  const _Settings();

  Future<void> _exportLocal(BuildContext context) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/brewdiary-${todayKey()}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(entryStore.entries.map((e) => e.toJson()).toList()));
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')]));
  }

  Future<void> _import(BuildContext context) async {
    try {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (r.isEmpty || r.first.path == null) return;
      final bytes = await File(r.first.path!).readAsBytes();
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! List) throw const FormatException();
      final clean = data.map(Entry.tryParse).whereType<Entry>().toList();
      if (!context.mounted) return;
      if (await confirm(context, title: 'Replace your diary?', body: 'This swaps your diary for the ${clean.length} entries in that file.', yes: 'Replace')) {
        entryStore.replaceAll(clean);
      }
    } catch (_) {
      if (context.mounted) toast(context, "That file couldn't be read.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final profile = auth.profile;
    final cloud = profile != null && db != null;
    return Glass(
      margin: const EdgeInsets.only(top: 48),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Label('Settings'),
        const SizedBox(height: 16),
        if (profile != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: 'Signed in as ', style: T.sans(bd, size: 14, color: bd.muted)),
              TextSpan(text: profile.name, style: T.sans(bd, size: 14)),
            ])),
          ),
        ListenableBuilder(
          listenable: ThemeStore.instance,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: S.s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Appearance', style: T.row(bd)),
              const SizedBox(height: S.xs),
              Segmented<ThemeMode>(
                options: const [(ThemeMode.dark, 'Dark'), (ThemeMode.light, 'Light'), (ThemeMode.system, 'System')],
                value: ThemeStore.instance.mode,
                onChanged: ThemeStore.instance.set,
              ),
            ]),
          ),
        ),
        const _Hair(),
        const _ReminderRow(),
        const _Hair(),
        ListenableBuilder(
          listenable: TrainingStore.instance,
          builder: (context, _) {
            final t = TrainingStore.instance;
            return SettingRow(
              title: 'Help train Ninkasi',
              hint: 'Keep your chats with Ninkasi on this device to teach her your taste${t.count > 0 ? ' · ${t.count} saved' : ''}.',
              trailing: BdToggle(on: t.collecting, onChanged: t.setCollecting),
            );
          },
        ),
        if (cloud) ...[
          const _Hair(),
          const _ProfileToggles(),
          const _Hair(),
          const _VenueScreenNote(),
          if (profile.handle.isNotEmpty) ...[const _Hair(), _HandleCard(handle: profile.handle)],
          const _Hair(),
          const _TrustCard(),
          const _Hair(),
          _ProfilePrivacy(handle: profile.handle),
          const _BlockedPeople(),
          const _VenueBooks(),
        ],
        const _Hair(),
        const _WhereYouAre(),
        const _Hair(),
        const _GoalsSettings(),
        const _Hair(),
        const _ExtrasSettings(),
        if (cloud) ...[const _Hair(), const _DataRights()],
        const SizedBox(height: 20),
        Wrap(spacing: 18, runSpacing: 4, children: [
          TextAction('export data', size: 12, faint: true, onTap: () => _exportLocal(context)),
          TextAction('import data', size: 12, faint: true, onTap: () => _import(context)),
          TextAction('reseed demo', size: 12, faint: true, onTap: () async {
            if (await confirm(context, title: 'Reseed the demo?', body: 'Your diary is replaced with a sample month.', yes: 'Reseed')) entryStore.reseed();
          }),
          TextAction('reset diary', size: 12, faint: true, onTap: () async {
            if (await confirm(context, title: 'Reset your diary?', body: 'Every entry is removed. This cannot be undone.', yes: 'Reset')) entryStore.resetAll();
          }),
          ListenableBuilder(
            listenable: TrainingStore.instance,
            builder: (c, _) => TrainingStore.instance.count > 0 ? TextAction('clear ninkasi data', size: 12, faint: true, onTap: TrainingStore.instance.clear) : const SizedBox.shrink(),
          ),
          if (profile != null)
            TextAction('sign out', size: 12, faint: true, onTap: auth.signOut)
          else
            TextAction('sign in', size: 12, faint: true, onTap: () => showAuthSheet(context, signup: false)),
          TextAction('privacy', size: 12, faint: true, onTap: () => launchUrl(Config.api('/privacy'), mode: LaunchMode.externalApplication)),
          TextAction('terms', size: 12, faint: true, onTap: () => launchUrl(Config.api('/terms'), mode: LaunchMode.externalApplication)),
        ]),
      ]),
    );
  }
}

class _Hair extends StatelessWidget {
  const _Hair();
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: context.bd.line));
}

/// The nightly reminder — a real scheduled notification on the phone.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final r = ReminderStore.instance;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SettingRow(
          title: 'Nightly reminder',
          hint: 'A gentle nudge to log before bed.',
          trailing: BdToggle(on: r.on, onChanged: (v) async {
            final ok = await r.setOn(v);
            if (!ok && context.mounted) toast(context, 'Notifications are off for brewdiary — allow them in your phone settings.');
          }),
        ),
        if (r.on)
          Row(children: [
            Text('At', style: T.sans(bd, size: 12, color: bd.faint)),
            const SizedBox(width: 8),
            TextAction(r.time.format(context), accent: true, onTap: () async {
              final t = await pickTime(context, title: 'Remind me at', initial: r.time);
              if (t != null) r.setTime(t);
            }),
          ]),
      ]),
    );
  }
}

/// Anonymous trends (+ optional coarse area) and the leaderboard — both default OFF.
class _ProfileToggles extends StatefulWidget {
  const _ProfileToggles();
  @override
  State<_ProfileToggles> createState() => _ProfileTogglesState();
}

class _ProfileTogglesState extends State<_ProfileToggles> {
  bool _busy = false;
  String? _msg;

  Future<void> _setArea() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _msg = 'Location permission was declined — no worries, it stays off.';
      } else {
        final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)));
        await ProfileApi.setTrendsGeo(encodeGeohash(p.latitude, p.longitude));
      }
    } catch (_) {
      _msg = "Couldn't read a location just now. Try again.";
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<ProfileSettings>(
      refresh: profileRev,
      load: ProfileApi.settings,
      builder: (context, s, loading) {
        final settings = s ?? const ProfileSettings();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingRow(
            title: 'Anonymous taste trends',
            hint: 'Count my logs in the "what\'s pouring" trends — counts only, never my name or notes.',
            trailing: BdToggle(on: settings.shareTrends, onChanged: ProfileApi.setShareTrends),
          ),
          if (settings.shareTrends)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: settings.trendsGeo != null
                  ? Row(children: [
                      Text('Area set', style: T.sans(bd, size: 12, color: bd.accent)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('a rough ~40 km cell — never your exact spot', style: T.sans(bd, size: 12, color: bd.faint))),
                      TextAction('Clear', size: 12, faint: true, onTap: () => ProfileApi.setTrendsGeo(null)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Set your area from your location so nearby bars can read the local taste — never your exact spot.', style: T.sans(bd, size: 12, color: bd.muted)),
                      const SizedBox(height: 6),
                      SizedBox(width: 230, child: InkButton(_busy ? 'Locating…' : 'Set my area from location', height: 38, uppercase: false, busy: _busy, onTap: _setArea)),
                      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, style: T.sans(bd, size: 12, color: bd.accent))),
                    ]),
            ),
          const _Hair(),
          SettingRow(
            title: 'Leaderboard in Together',
            hint: 'Show the board — and put me on it, next to friends who also opted in. Off by default; never your spend.',
            trailing: BdToggle(on: settings.competeVisible, onChanged: PointsApiShim.setCompete),
          ),
        ]);
      },
    );
  }
}

/// Thin indirection so settings doesn't import the whole parties module.
class PointsApiShim {
  static Future<void> setCompete(bool v) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('profiles').update({'compete_visible': v}).eq('id', me);
    profileRev.bump();
    pointsRev.bump();
  }
}

class _VenueScreenNote extends StatelessWidget {
  const _VenueScreenNote();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Venue screens', style: T.sans(bd, size: 14)),
        const SizedBox(height: 3),
        Text(
          "There is no always-on switch for this. When you are in a bar's room, you can choose — for that night only — to appear on its screen, and whether your tab shows. It clears when the night ends.",
          style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
        ),
      ]),
    );
  }
}

/// Trade your handle for one we spin up — you never type it, so it stays clean.
class _HandleCard extends StatefulWidget {
  final String handle;
  const _HandleCard({required this.handle});
  @override
  State<_HandleCard> createState() => _HandleCardState();
}

class _HandleCardState extends State<_HandleCard> {
  String? _candidate;
  bool _busy = false;
  String? _note;
  int _taken = 0;

  Future<void> _save() async {
    if (_candidate == null) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    final res = await auth.updateHandle(_candidate!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _candidate = null;
        _taken = 0;
      } else if (res.error == 'taken') {
        _taken++;
        _candidate = reroll(_candidate ?? widget.handle, attempt: _taken);
        _note = "Someone just took that one — here's another.";
      } else {
        _note = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Your handle', style: T.sans(bd, size: 14)),
        const SizedBox(height: 3),
        Text('How friends find you, and your address at /u/<handle>. Trade it for another whenever you like — you pick from ones we spin up, so it stays clean.',
            style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
        const SizedBox(height: 12),
        if (_candidate == null)
          Row(children: [
            Expanded(child: Text('@${widget.handle}', style: T.serif(bd, size: 19))),
            Glass(radius: rCtl, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), onTap: () => setState(() {
                  _note = null;
                  _taken = 0;
                  _candidate = reroll(widget.handle);
                }), child: Text('Change', style: T.sans(bd, size: 14, color: bd.muted))),
          ])
        else ...[
          Row(children: [
            Expanded(child: Text('@$_candidate', style: T.serif(bd, size: 19, color: bd.accent))),
            Glass(
              radius: rCtl,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              onTap: _busy ? null : () => setState(() => _candidate = reroll(_candidate!, attempt: _taken)),
              child: Text('Try another', style: T.sans(bd, size: 14, color: bd.muted)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 110, child: InkButton(_busy ? 'Saving…' : 'Use this', height: 38, uppercase: false, busy: _busy, onTap: _save)),
            const SizedBox(width: 12),
            TextAction('Keep @${widget.handle}', faint: true, onTap: _busy ? null : () => setState(() => _candidate = null)),
          ]),
        ],
        if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, style: T.sans(bd, size: 12, color: bd.accent))),
      ]),
    );
  }
}

/// Your standing — a quiet, coarse trust signal, never a score of you as a person.
class _TrustCard extends StatelessWidget {
  const _TrustCard();
  static const _nextAt = {TrustLevel.fresh: 4.0, TrustLevel.active: 14.0, TrustLevel.established: 34.0};
  static const _nextLevel = {TrustLevel.fresh: TrustLevel.active, TrustLevel.active: TrustLevel.established, TrustLevel.established: TrustLevel.trusted};

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final profile = auth.profile!;
    return Loader<(int, int)>(
      refresh: Listenable.merge([vouchRev, friendsRev]),
      load: () async => ((await FriendsApi.friends()).length, await VouchApi.myCount()),
      builder: (context, data, _) {
        final created = DateTime.tryParse(profile.createdAt) ?? appNow();
        final signals = TrustSignals(
          tenureDays: math.max(0, appNow().difference(created).inDays),
          activeDays: entryStore.entries.map((e) => e.date).toSet().length,
          friends: data?.$1 ?? 0,
          presenceChecked: profile.presenceChecked,
          vouches: data?.$2 ?? 0,
        );
        final level = trustLevelFrom(signals);
        final score = trustScore(signals);
        final nextAt = _nextAt[level];
        final pct = nextAt == null ? 1.0 : math.min(1.0, score / nextAt);
        Widget sig(String l, int v) => Expanded(
              child: Row(children: [
                Expanded(child: Text(l, style: T.sans(bd, size: 12, color: bd.faint))),
                Text('$v', style: T.sans(bd, size: 12, color: bd.muted)),
                const SizedBox(width: 16),
              ]),
            );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Your standing', style: T.sans(bd, size: 14))),
              Glass(radius: rCtl, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text(trustLabel[level]!, style: T.sans(bd, size: 12, weight: FontWeight.w500, color: bd.muted))),
            ]),
            const SizedBox(height: 4),
            Text(
              "A quiet signal that you're a real, settled person — it grows as you use brewdiary and connect with friends. It helps others feel comfortable meeting up. It's never a score of you as a person, and nobody sees a ranking.",
              style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(children: [sig('Days here', signals.tenureDays), sig('Days logged', signals.activeDays)]),
            const SizedBox(height: 6),
            Row(children: [sig('Friends', signals.friends), sig('Vouches', signals.vouches)]),
            if (nextAt != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Stack(children: [
                  Container(height: 6, color: bd.ink.withValues(alpha: .1)),
                  FractionallySizedBox(widthFactor: pct, child: Container(height: 6, color: bd.accent)),
                ]),
              ),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Keep logging and connecting to reach ', style: T.sans(bd, size: 12, color: bd.faint)),
                TextSpan(text: trustLabel[_nextLevel[level]]!, style: T.sans(bd, size: 12, color: bd.muted)),
                TextSpan(text: '.', style: T.sans(bd, size: 12, color: bd.faint)),
              ])),
            ],
            if (signals.vouches > 0)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('${signals.vouches} ${signals.vouches == 1 ? 'friend vouches' : 'friends vouch'} for you.', style: T.sans(bd, size: 12, color: bd.faint))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('Photo-ID verification', style: T.sans(bd, size: 12, color: bd.faint))),
              Text('Coming soon', style: T.sans(bd, size: 12, color: bd.faint)),
            ]),
          ]),
        );
      },
    );
  }
}

class _ProfilePrivacy extends StatefulWidget {
  final String handle;
  const _ProfilePrivacy({required this.handle});
  @override
  State<_ProfilePrivacy> createState() => _ProfilePrivacyState();
}

class _ProfilePrivacyState extends State<_ProfilePrivacy> {
  final _link = TextEditingController();
  bool _loadedLink = false;
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<ProfileSettings>(
      refresh: profileRev,
      load: ProfileApi.settings,
      builder: (context, s, loading) {
        final vis = s?.visibility ?? ProfileVisibility.friends;
        if (s != null && !_loadedLink) {
          _loadedLink = true;
          _link.text = s.socialHandle;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Public profile', style: T.sans(bd, size: 14)),
            const SizedBox(height: 3),
            Text('Who can open your profile at /u/${widget.handle}. Any of these shows a streak mosaic and totals — never your notes, never your spend, never where you were.',
                style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in ProfileVisibility.values)
                BdChip(const {ProfileVisibility.friends: 'Friends only', ProfileVisibility.fof: 'Friends of friends', ProfileVisibility.public: 'Public'}[v]!,
                    active: vis == v, onTap: () => ProfileApi.setVisibility(v)),
            ]),
            if (vis != ProfileVisibility.friends)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicProfileScreen(handle: widget.handle))),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: vis == ProfileVisibility.public ? 'Live to anyone at ' : 'Open to your friends and their friends at ', style: T.sans(bd, size: 12, color: bd.faint)),
                    TextSpan(text: '/u/${widget.handle}', style: T.sans(bd, size: 12, color: bd.accent)),
                  ])),
                ),
              ),
            const SizedBox(height: 16),
            Label('One social link', color: bd.faint),
            const SizedBox(height: 4),
            Text("Anyone who can see your profile will see this. Add only a handle you're fine with strangers finding — never your phone, email, or address.",
                style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: GlassField(controller: _link, hint: '@you or https://…', caps: TextCapitalization.none)),
              const SizedBox(width: 8),
              TextAction(_saved ? 'Saved' : 'Save', accent: _saved, onTap: () async {
                await ProfileApi.setSocialHandle(_link.text);
                if (!mounted) return;
                setState(() => _saved = true);
                Future.delayed(const Duration(milliseconds: 1600), () {
                  if (mounted) setState(() => _saved = false);
                });
              }),
            ]),
          ]),
        );
      },
    );
  }
}

class _BlockedPeople extends StatelessWidget {
  const _BlockedPeople();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<BlockedPerson>>(
      refresh: safetyRev,
      load: SafetyApi.blocks,
      builder: (context, list, _) {
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Hair(),
          Text('Blocked people', style: T.sans(bd, size: 14)),
          const SizedBox(height: 3),
          Text("You don't see each other's plans, and neither of you turns up in the other's search. Unblock to undo that.", style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
          const SizedBox(height: 8),
          for (final p in list)
            Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${p.name} ', style: T.sans(bd)),
                  TextSpan(text: '@${p.handle}', style: T.sans(bd, size: 12, color: bd.faint)),
                ])),
              ),
              TextAction('Unblock', faint: true, onTap: () => SafetyApi.unblock(p.id)),
            ]),
        ]);
      },
    );
  }
}

/// Transparency: every venue that keeps a first-party note on you, and a Forget button.
class _VenueBooks extends StatefulWidget {
  const _VenueBooks();
  @override
  State<_VenueBooks> createState() => _VenueBooksState();
}

class _VenueBooksState extends State<_VenueBooks> {
  final _rev = Rev();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<VenueBook>>(
      refresh: _rev,
      load: VenueBooksApi.mine,
      builder: (context, books, _) {
        if (books == null || books.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Hair(),
          Text('Notes venues keep on you', style: T.sans(bd, size: 14)),
          const SizedBox(height: 3),
          Text("A bar you've visited can keep its own notes on you — never your diary or what you do elsewhere. Here's every one, and you can erase any of them.",
              style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
          const SizedBox(height: 8),
          for (final b in books)
            Glass(
              radius: rCtl,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.venueName, style: T.sans(bd, size: 14)),
                    if (b.body.isNotEmpty) Text(b.body, style: T.sans(bd, size: 12, color: bd.muted, height: 1.4)),
                    if (b.tags.isNotEmpty) Text(b.tags.map((t) => '#$t').join(' '), style: T.sans(bd, size: 12, color: bd.faint)),
                  ]),
                ),
                TextAction('Forget', size: 12, faint: true, onTap: () async {
                  await VenueBooksApi.forget(b.venueId);
                  _rev.bump();
                }),
              ]),
            ),
        ]);
      },
    );
  }
}

/// The traveller's switch — what YOU can do follows where you ARE.
class _WhereYouAre extends StatefulWidget {
  const _WhereYouAre();
  @override
  State<_WhereYouAre> createState() => _WhereYouAreState();
}

class _WhereYouAreState extends State<_WhereYouAre> {
  late String _country = PlaceStore.instance.country ?? 'IN';
  int? _needsAge;
  DateTime? _dob;

  void _pick(String next) {
    setState(() => _needsAge = null);
    final needs = PlaceStore.instance.moveTo(next);
    setState(() => _country = next);
    if (needs != null) {
      setState(() => _needsAge = needs);
      return;
    }
    toast(context, 'Saved.');
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: PlaceStore.instance,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Where you are', style: T.sans(bd, size: 14)),
          const SizedBox(height: 3),
          Text("Travelling? Set this to the country you're in. It sets your currency, and the legal drinking age we hold you to — that follows where you are, not where you're from.",
              style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
          const SizedBox(height: S.s),
          PickerField(
            value: knownCountries.any((c) => c.$1 == _country) ? countryLabel(_country) : 'Somewhere else',
            onTap: () async {
              final c = await pickCountry(context, current: knownCountries.any((c) => c.$1 == _country) ? _country : 'ZZ');
              if (c != null) _pick(c);
            },
          ),
          if (_needsAge != null)
            Glass(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text("The legal drinking age there is $_needsAge+, which is higher than the one you confirmed. Confirm your date of birth again and we'll move you.",
                    style: T.sans(bd, size: 12, color: bd.muted, height: 1.5)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextAction(_dob == null ? 'Choose date of birth' : writtenDate(_dob!), accent: _dob == null, onTap: () async {
                      final now = appNow();
                      final d = await pickDate(context, title: 'Date of birth', initial: _dob ?? DateTime(now.year - 25, now.month, now.day), first: DateTime(now.year - 110), last: now);
                      if (d != null) setState(() => _dob = d);
                    }),
                  ),
                  SizedBox(width: 100, child: InkButton('Confirm', height: 36, uppercase: false, onTap: _dob == null
                      ? null
                      : () {
                          if (PlaceStore.instance.confirmAge(_dob!, _country == 'ZZ' ? null : _country)) {
                            setState(() {
                              _needsAge = null;
                              _dob = null;
                            });
                            toast(context, 'Saved.');
                          } else {
                            setState(() => _needsAge = PlaceStore.instance.legalAgeFor(_country));
                          }
                        })),
                ]),
              ]),
            ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Currency for Split',
            value: '${PlaceStore.instance.currency}  ${currencySymbol(PlaceStore.instance.currency)}',
            onTap: () async {
              final c = await pickCurrency(context, current: PlaceStore.instance.currency);
              if (c != null) PlaceStore.instance.saveCurrency(c);
            },
          ),
        ]),
      ),
    );
  }
}

/// Gentle limits — both OFF by default, both on-device only.
class _GoalsSettings extends StatefulWidget {
  const _GoalsSettings();
  @override
  State<_GoalsSettings> createState() => _GoalsSettingsState();
}

class _GoalsSettingsState extends State<_GoalsSettings> {
  late final _limit = TextEditingController(text: GoalsStore.instance.weeklyLimit?.toString() ?? '');
  late final _dry = TextEditingController(text: GoalsStore.instance.dryDays?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget field(String label, String hint, TextEditingController c, GoalKey key) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: T.sans(bd, size: 12, color: bd.muted)),
            const SizedBox(height: 4),
            GlassField(controller: c, hint: 'off', keyboard: TextInputType.number, onChanged: (v) => GoalsStore.instance.set(key, int.tryParse(v.trim()))),
            const SizedBox(height: 4),
            Text(hint, style: T.sans(bd, size: 12, color: bd.faint)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Gentle limits', style: T.sans(bd, size: 14)),
        const SizedBox(height: 3),
        Text('Optional, and off unless you set one. Stays on this device — a private intention never leaves it.', style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          field('Weekly limit', 'Alcoholic drinks in a rolling 7 days.', _limit, GoalKey.weeklyLimit),
          const SizedBox(width: 16),
          field('Dry days', 'Days with nothing alcoholic, per week.', _dry, GoalKey.dryDays),
        ]),
      ]),
    );
  }
}

class _ExtrasSettings extends StatefulWidget {
  const _ExtrasSettings();
  @override
  State<_ExtrasSettings> createState() => _ExtrasSettingsState();
}

class _ExtrasSettingsState extends State<_ExtrasSettings> {
  late final _ml = TextEditingController(text: ExtrasStore.instance.waterMl?.toString() ?? '');
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final x = ExtrasStore.instance;
    return ListenableBuilder(
      listenable: x,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Label('Extras'),
        const SizedBox(height: 4),
        Text('Optional trackers. Turn one on and a small counter shows up on each day in your log.', style: T.sans(bd, size: 12, color: bd.faint)),
        for (final e in extras) ...[
          SettingRow(title: e.label, hint: e.hint, trailing: BdToggle(on: x.isOn(e.key), onChanged: (v) => x.set(e.key, v))),
          if (e.key == ExtraKey.water && x.isOn(ExtraKey.water))
            Row(children: [
              Expanded(child: Text('Glass size (ml) — optional, adds a volume', style: T.sans(bd, size: 12, color: bd.faint))),
              SizedBox(width: 100, child: GlassField(controller: _ml, hint: 'glasses', keyboard: TextInputType.number, onChanged: (v) => x.setWaterMl(int.tryParse(v.trim())))),
            ]),
        ],
      ]),
    );
  }
}

/// Take a copy of everything, or delete the account outright (GDPR / DPDP / stores).
class _DataRights extends StatefulWidget {
  const _DataRights();
  @override
  State<_DataRights> createState() => _DataRightsState();
}

class _DataRightsState extends State<_DataRights> {
  bool _busy = false;
  bool _asking = false;
  String? _error;

  Future<void> _export() async {
    setState(() => _busy = true);
    final r = await AccountApi.exportEverything();
    if (r.json != null) {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/brewdiary-everything-${todayKey()}.json');
      await f.writeAsString(r.json!);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')]));
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Your data', style: T.sans(bd, size: 14)),
        const SizedBox(height: 3),
        Text('Take a copy of everything we hold about you, or delete your account outright. Deleting is immediate and permanent — the diary, the photos, the points, all of it.',
            style: T.sans(bd, size: 12, color: bd.faint, height: 1.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Glass(radius: rCtl, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), onTap: _busy ? null : _export, child: Text('Download my data', style: T.sans(bd, size: 14, color: bd.muted))),
          Pressable(
            onTap: () => setState(() => _asking = true),
            enabled: !_busy,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.line)),
              child: Text('Delete my account', style: T.sans(bd, size: 14, color: bd.muted)),
            ),
          ),
        ]),
        if (_asking)
          Glass(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Delete everything?', style: T.sans(bd, size: 14)),
              const SizedBox(height: 4),
              Text("Every entry, photo, friendship and point is destroyed. This cannot be undone, and we can't get it back for you. Download your data first if you want to keep it.",
                  style: T.sans(bd, size: 12, color: bd.muted, height: 1.5)),
              const SizedBox(height: 12),
              Row(children: [
                Pressable(
                  enabled: !_busy,
                  onTap: () async {
                    setState(() => _busy = true);
                    final err = await AccountApi.deleteAccount();
                    if (mounted) {
                      setState(() {
                        _busy = false;
                        _error = err;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(rCtl)),
                    child: Text(_busy ? 'Deleting…' : 'Yes, delete it all', style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.accentContrast)),
                  ),
                ),
                const SizedBox(width: 10),
                TextAction('Keep my account', onTap: () => setState(() => _asking = false)),
              ]),
            ]),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accent))),
      ]),
    );
  }
}
