// A venue's menu — what tapping the NFC tag (or scanning the QR) on the table
// opens. A port of src/components/menu/MenuView.tsx. Opened from a table's own link
// (bwdy.site/t/<code>, 051) it knows the table: there, if the venue switched it on,
// you can send an order and call staff. An order waits for the staff's OK; they see
// the table, never your name.
//
// "You'd probably like" is worked out on this phone from your own diary; the venue
// never learns who looked. "Log it" writes the drink straight into today with the
// venue filled in. A menu is never an offer: no discounts, by design.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/menus.dart';
import 'package:brewdiary_core/money.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/menus.dart';
import '../../data/table_order.dart';
import '../../data/taste_share.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'taste_card.dart';

class MenuScreen extends StatelessWidget {
  final String slug;
  const MenuScreen({super.key, required this.slug});

  @override
  Widget build(BuildContext context) {
    if (db == null) {
      return const SubPage(
        title: 'Menu',
        child: EmptyNote("This build isn't connected to the brewdiary cloud, so it can't fetch the menu. Ask for a paper one — or open the link in your browser.", icon: Ph.cloudSlash),
      );
    }
    return Loader<Menu?>(
      load: () => MenuApi.load(slug),
      failed: (context, retry) => SubPage(title: 'Menu', child: LoadError(onRetry: retry)),
      builder: (context, menu, loading) {
        if (menu == null) {
          return SubPage(
            title: 'Menu',
            child: loading
                ? const Column(children: [Skeleton(height: 72), SizedBox(height: S.m), Skeleton(height: 220)])
                : const EmptyNote("No menu here. The tag may be old, or this place isn't on brewdiary yet — ask for a paper menu.", icon: Ph.notebook),
          );
        }
        return MenuView(menu: menu, slug: slug);
      },
    );
  }
}

/// A table's own link (bwdy.site/t/<code>): which venue and table, then its menu.
class TableMenuScreen extends StatelessWidget {
  final String code;
  const TableMenuScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    if (db == null) {
      return const SubPage(title: 'Menu', child: EmptyNote("This build isn't connected to the brewdiary cloud — open the link in your browser, or ask for a paper menu.", icon: Ph.cloudSlash));
    }
    return Loader<(TableInfo, Menu)?>(
      load: () async {
        final t = await TableApi.info(code);
        if (t == null) return null;
        final m = await MenuApi.load(t.venueSlug);
        return m == null ? null : (t, m);
      },
      failed: (context, retry) => SubPage(title: 'Menu', child: LoadError(onRetry: retry)),
      builder: (context, data, loading) {
        if (data == null) {
          return SubPage(
            title: 'Menu',
            child: loading
                ? const Column(children: [Skeleton(height: 72), SizedBox(height: S.m), Skeleton(height: 220)])
                : const EmptyNote("This table's link isn't live — the tag may have been replaced. Ask your server for the menu.", icon: Ph.notebook),
          );
        }
        return MenuView(menu: data.$2, table: data.$1);
      },
    );
  }
}

/// Ask once: share my taste with the bartender when I open a venue's menu?
/// Returns null when dismissed (we ask again next time).
Future<bool?> askTasteShare(BuildContext context, String venueName) => showBdSheet<bool>(context, title: 'Let the bartender know your taste?', builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('When you open a place\'s menu on brewdiary, its bartender can see your taste passport — so what they make is something you\'ll like.', style: T.body(bd)),
        const SizedBox(height: S.m),
        Group(children: [
          for (final (icon, line) in const [
            (Ph.martini, 'What you\'re into, what you usually have, your mood words'),
            (Ph.leaf, '"Nothing with alcohol tonight", when you\'ve said so'),
            (Ph.moonStars, 'Tonight only — gone after 8 hours'),
            (Ph.lock, 'Never your diary, never where else you\'ve been'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.s),
              child: Row(children: [Icon(icon, size: 18, color: bd.accentText), const SizedBox(width: S.m), Expanded(child: Text(line, style: T.body(bd, color: bd.muted)))]),
            ),
        ]),
        const SizedBox(height: S.l),
        BdButton('Share with $venueName and places I visit', onTap: () => Navigator.pop(ctx, true)),
        const SizedBox(height: S.s),
        BdButton('Not now', kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, false)),
        const SizedBox(height: S.s),
        Text('You can change this in Settings, or stop it at any table.', textAlign: TextAlign.center, style: T.caption(bd)),
      ]);
    });

/// "Your taste is with (the venue) tonight · Stop", or an offer to share.
class _TasteLine extends StatelessWidget {
  final String venue;
  final TasteShare? shared;
  final bool busy;
  final VoidCallback onShare;
  final VoidCallback onStop;
  const _TasteLine({required this.venue, required this.shared, required this.busy, required this.onShare, required this.onStop});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final on = shared != null;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.s, S.xs, S.s),
      child: Row(children: [
        Icon(on ? PhFill.checkCircle : Ph.identificationBadge, size: 20, color: bd.accentText),
        const SizedBox(width: S.m),
        Expanded(
          child: Text(
            on ? 'Your taste is with $venue tonight — the bartender can make you something you\'ll like.' : (busy ? 'Sharing your taste…' : 'Let the bartender know your taste tonight?'),
            style: T.body(bd),
          ),
        ),
        TextAction(on ? 'Stop' : 'Share', accent: !on, faint: on, onTap: busy ? null : (on ? onStop : onShare)),
      ]),
    );
  }
}

const _allergenWords = {
  'gluten': 'gluten',
  'crustaceans': 'crustaceans',
  'eggs': 'eggs',
  'fish': 'fish',
  'peanuts': 'peanuts',
  'soy': 'soy',
  'milk': 'milk',
  'nuts': 'tree nuts',
  'celery': 'celery',
  'mustard': 'mustard',
  'sesame': 'sesame',
  'sulphites': 'sulphites',
  'lupin': 'lupin',
  'molluscs': 'molluscs',
};

/// India's menu mark: a square with a dot, green for veg, brown for non-veg.
class DietMark extends StatelessWidget {
  final String diet;
  const DietMark(this.diet, {super.key});
  @override
  Widget build(BuildContext context) {
    final color = switch (diet) { 'veg' || 'vegan' => const Color(0xFF3E8E5E), 'egg' => const Color(0xFFB08A2E), _ => const Color(0xFFA0472F) };
    return Semantics(
      label: switch (diet) { 'veg' => 'vegetarian', 'vegan' => 'vegan', 'egg' => 'contains egg', _ => 'non-vegetarian' },
      child: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(right: 8, top: 3),
        decoration: BoxDecoration(border: Border.all(color: color, width: 1.4), borderRadius: BorderRadius.circular(2)),
        alignment: Alignment.center,
        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: diet == 'non_veg' ? BoxShape.rectangle : BoxShape.circle)),
      ),
    );
  }
}

/// The menu itself (public so tests can render one without the cloud).
class MenuView extends StatefulWidget {
  final Menu menu;

  /// Set when opened from a table's own link.
  final TableInfo? table;

  /// The venue's menu slug, when opened from `bwdy.site/m/<slug>`.
  final String? slug;

  /// Draw the table's ordering controls without the cloud (tests and screenshots).
  final bool previewOrdering;
  const MenuView({super.key, required this.menu, this.table, this.slug, this.previewOrdering = false});
  @override
  State<MenuView> createState() => MenuViewState();
}

class MenuViewState extends State<MenuView> {
  bool _noAlcohol = false;
  final Map<String, int> _basket = {};
  bool _sending = false;
  List<MyRequest> _mine = const [];
  Timer? _poll;

  bool get _ordering => widget.table?.tableService == true && ((auth.isAuthed && db != null) || widget.previewOrdering);

  /// When each kind of call last went through: the chip says "called" for a while
  /// (so nobody taps it five times wondering), and the 15-second poll clears it.
  final Map<String, DateTime> _calledAt = {};
  static const _callHolds = Duration(seconds: 45);
  bool _called(String kind) => _calledAt[kind] != null && DateTime.now().difference(_calledAt[kind]!) < _callHolds;

  void _changeQty(MenuItem it, int delta) {
    Haptics.tick();
    setState(() {
      final q = ((_basket[it.id] ?? 0) + delta).clamp(0, 20);
      q <= 0 ? _basket.remove(it.id) : _basket[it.id] = q;
    });
  }

  TasteShare? _shared;
  bool _sharing = false;

  /// Opening a venue's menu shares your taste with its bartender — after you've
  /// said yes once (056).
  Future<void> _maybeShareTaste() async {
    final store = TasteShareStore.instance;
    if (!auth.isAuthed || db == null || (widget.table == null && widget.slug == null)) return;
    var yes = store.consent;
    if (yes == null) {
      yes = await askTasteShare(context, widget.menu.venueName);
      if (yes == null) return; // dismissed: ask again next time
      await store.setConsent(yes);
    }
    if (yes) await _shareNow();
  }

  Future<void> _shareNow() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final s = await TasteShareStore.instance.share(code: widget.table?.code, slug: widget.table == null ? widget.slug : null);
      if (mounted) setState(() => _shared = s);
    } catch (_) {
      // the menu still works; the bartender just won't see your taste tonight
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _stopSharing() async {
    final s = _shared;
    if (s == null) return;
    await TasteShareStore.instance.stop(s.venueId);
    if (mounted) setState(() => _shared = null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShareTaste();
    });
    if (_ordering) {
      _refreshMine();
      _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refreshMine());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshMine() async {
    try {
      final r = await TableApi.mine();
      if (mounted) setState(() => _mine = r);
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = widget.table;
    if (t == null || _basket.isEmpty) return;
    setState(() => _sending = true);
    try {
      await TableApi.order(t.code, [for (final e in _basket.entries) {'item': e.key, 'qty': e.value}]);
      if (!mounted) return;
      setState(() => _basket.clear());
      toast(context, 'Sent — the staff will confirm it.', tone: ToastTone.success);
      await _refreshMine();
    } catch (e) {
      if (mounted) toast(context, tableError(e), tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _call(String kind) async {
    final t = widget.table;
    if (t == null) return;
    if (_called(kind)) return toast(context, 'Already asked — they\'re on their way.');
    try {
      await TableApi.call(t.code, kind);
      if (mounted) setState(() => _calledAt[kind] = DateTime.now());
      if (mounted) toast(context, switch (kind) { 'bill' => 'They\'re bringing the bill.', 'water' => 'Water\'s on its way.', _ => 'Someone\'s coming over.' }, tone: ToastTone.success);
    } catch (e) {
      if (mounted) toast(context, tableError(e), tone: ToastTone.error);
    }
  }

  void _log(MenuItem item) {
    entryStore.addEntry(date: todayKey(), drink: item.name, type: item.drinkType, venue: widget.menu.venueName);
    toast(context, 'Logged ${item.name} — in today\'s square.', tone: ToastTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final menu = widget.menu;
    final byId = {for (final s in menu.sections) for (final i in s.items) i.id: i};
    final picks = [for (final id in menuPicks(menu, entryStore.entries)) if (byId[id] != null) byId[id]!];
    final hasNoAlcohol = menu.sections.any((s) => s.items.any((i) => i.noAlcohol));
    final sections = [
      for (final s in menu.sections)
        if ((_noAlcohol ? s.items.where((i) => i.noAlcohol) : s.items).isNotEmpty) MenuSection(s.name, _noAlcohol ? s.items.where((i) => i.noAlcohol).toList() : s.items),
    ];

    Widget row(MenuItem it) => Padding(
          padding: const EdgeInsets.symmetric(vertical: S.m),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (it.diet != null) DietMark(it.diet!),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: it.name, style: T.row(bd)),
                      if (it.noAlcohol) TextSpan(text: '   NO ALCOHOL', style: T.label(bd, color: bd.accentText)),
                    ])),
                  ),
                ]),
                if (it.description != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(it.description!, style: T.body(bd, color: bd.muted))),
                if (it.allergens.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Contains ${it.allergens.map((a) => _allergenWords[a] ?? a).join(', ')}', style: T.caption(bd))),
              ]),
            ),
            const SizedBox(width: S.m),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (it.price != null) Text(formatMoney(it.price!, menu.currency), style: T.row(bd).copyWith(fontFeatures: T.tnum)),
              if (_ordering)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSize(
                    duration: context.reduceMotion ? Duration.zero : Motion.med,
                    curve: Easing.emphasizedDecelerate,
                    child: (_basket[it.id] ?? 0) > 0
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconBtn(Ph.minus, tooltip: 'One fewer ${it.name}', onTap: () => _changeQty(it, -1)),
                            SizedBox(width: 22, child: RollingNumber(_basket[it.id] ?? 0, textAlign: TextAlign.center, style: T.row(bd))),
                          ])
                        : const SizedBox.shrink(),
                  ),
                  IconBtn(Ph.plus, tooltip: 'Add ${it.name}', onTap: () => _changeQty(it, 1)),
                ])
              else if (it.kind != 'food')
                TextAction('Log it', accent: true, size: 13, onTap: () => _log(it)),
            ]),
          ]),
        );

    final count = _basket.values.fold<int>(0, (a, b) => a + b);
    final total = _basket.entries.fold<double>(0, (s, e) => s + (byId[e.key]?.price ?? 0) * e.value);
    final page = SubPage(
      title: menu.venueName,
      actions: [IconBtn(Ph.identificationBadge, tooltip: 'Show my taste passport', onTap: () => showTasteCard(context))],
      subtitle: [if (widget.table != null) 'Table ${widget.table!.tableLabel}', if (menu.venueCity != null) menu.venueCity!, menu.isStore ? 'On the shelf' : 'The menu'].join(' · '),
      child: menu.sections.isEmpty
          ? const EmptyNote("The menu isn't up yet — ask at the bar.", icon: Ph.notebook)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (auth.isAuthed && db != null && (widget.table != null || widget.slug != null)) ...[
                _TasteLine(venue: menu.venueName, shared: _shared, busy: _sharing, onShare: _shareNow, onStop: _stopSharing),
                const SizedBox(height: S.l),
              ],
              if (picks.isNotEmpty && !_noAlcohol) ...[
                const SectionHeader("You'd probably like", padding: EdgeInsets.only(bottom: S.m)),
                Group(footer: "From your own diary, worked out on this phone. ${menu.venueName} doesn't see it.", children: [for (final p in picks) row(p)]),
              ],
              if (hasNoAlcohol)
                Padding(
                  padding: const EdgeInsets.only(top: S.xl),
                  child: Align(alignment: Alignment.centerLeft, child: BdChip('No alcohol only', active: _noAlcohol, onTap: () => setState(() => _noAlcohol = !_noAlcohol))),
                ),
              for (final s in sections) ...[
                SectionHeader(s.name),
                Group(children: [for (final it in s.items) row(it)]),
              ],
              if (widget.table != null && widget.table!.tableService && !auth.isAuthed) ...[
                const SizedBox(height: S.xl),
                const EmptyNote('Sign in to brewdiary to order from the table or call staff — or just wave; they\'ll see you.', icon: Ph.handWaving),
              ],
              if (_ordering) ...[
                SectionHeader('At table ${widget.table!.tableLabel}'),
                Wrap(spacing: S.s, runSpacing: S.s, children: [
                  BdChip(_called('staff') ? 'Staff called' : 'Call staff', active: _called('staff'), icon: _called('staff') ? PhBold.check : Ph.handWaving, onTap: () => _call('staff')),
                  BdChip(_called('bill') ? 'Bill asked for' : 'Bill please', active: _called('bill'), icon: _called('bill') ? PhBold.check : Ph.receipt, onTap: () => _call('bill')),
                  BdChip(_called('water') ? 'Water asked for' : 'Water', active: _called('water'), icon: _called('water') ? PhBold.check : Ph.drop, onTap: () => _call('water')),
                ]),
                if (_mine.isNotEmpty) ...[
                  const SizedBox(height: S.l),
                  Group(children: [
                    for (final r in _mine)
                      GroupTile(
                        title: r.lines.map((l) => '${l.qty} × ${l.name}').join(', '),
                        subtitle: r.statusWords,
                        trailing: r.status == 'pending'
                            ? TextAction('Cancel', faint: true, size: 13, onTap: () async {
                                try {
                                  await TableApi.withdraw(r.id);
                                  if (context.mounted) toast(context, 'Cancelled.');
                                } catch (e) {
                                  if (context.mounted) toast(context, tableError(e), tone: ToastTone.error);
                                }
                                await _refreshMine();
                              })
                            : null,
                      ),
                  ]),
                ],
              ],
              // Room for the basket bar, so it never sits on the last item.
              if (_basket.isNotEmpty) const SizedBox(height: 76),
              const SizedBox(height: S.xl),
              Text(
                "Opening a menu tells ${menu.venueName} nothing about you. Prices are the venue's own.${_ordering ? ' An order waits for the staff to confirm it; they see the table, never your name.' : ''}",
                style: T.caption(bd),
              ),
            ]),
    );
    if (!_ordering) return page;
    // The basket rides up from the bottom the moment there's something in it —
    // wherever you are in a long menu, what you've picked and the way to send it
    // are under your thumb.
    return Stack(children: [
      page,
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: IgnorePointer(
          ignoring: _basket.isEmpty,
          child: AnimatedSlide(
            offset: _basket.isEmpty ? const Offset(0, 1.3) : Offset.zero,
            duration: context.reduceMotion ? Duration.zero : Motion.slow,
            curve: _basket.isEmpty ? Curves.easeInCubic : Easing.emphasizedDecelerate,
            child: Padding(
              padding: EdgeInsets.fromLTRB(sideGutter(context), 0, sideGutter(context), MediaQuery.paddingOf(context).bottom + S.m),
              // Above the page's Scaffold, so it brings its own Material for text and ink.
              child: Material(type: MaterialType.transparency, child: _BasketBar(count: count, total: formatMoney(total, menu.currency), busy: _sending, onSend: _send)),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// "3 to send · ₹1,150 — Send to the staff": the basket, under your thumb.
class _BasketBar extends StatelessWidget {
  final int count;
  final String total;
  final bool busy;
  final VoidCallback onSend;
  const _BasketBar({required this.count, required this.total, required this.busy, required this.onSend});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      container: true,
      label: '$count to send, $total',
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.l, S.s, S.s, S.s),
        decoration: BoxDecoration(color: bd.sheet, borderRadius: BorderRadius.circular(rTile), border: Border.all(color: bd.glassBorder, width: .8)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              RollingText('$count to send', style: T.sans(bd, size: 15, weight: FontWeight.w600)),
              RollingText(total, style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
            ]),
          ),
          BdButton(busy ? 'Sending…' : 'Send to the staff', kind: BtnKind.accent, expand: false, height: 46, busy: busy, onTap: onSend),
        ]),
      ),
    );
  }
}

/// "At a table?" — how to open a menu: tap the tag, scan the QR, or type the code.
class TableMenuCard extends StatelessWidget {
  const TableMenuCard({super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      onTap: () => showBdSheet(context, title: 'Open the menu', builder: (_) => const _TableMenuSheet()),
      semanticLabel: 'At a table? Open the menu',
      padding: const EdgeInsets.fromLTRB(S.l, S.l, S.m, S.l),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bd.accent.withValues(alpha: .16)),
          child: Icon(Ph.contactlessPayment, size: 20, color: bd.accentText),
        ),
        const SizedBox(width: S.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('At a table?', style: T.row(bd)),
            const SizedBox(height: 2),
            Text('Tap the brewdiary tag and the menu opens — with picks from your diary.', style: T.caption(bd)),
          ]),
        ),
        Icon(Ph.caretRight, size: 16, color: bd.faint),
      ]),
    );
  }
}

class _TableMenuSheet extends StatefulWidget {
  const _TableMenuSheet();
  @override
  State<_TableMenuSheet> createState() => _TableMenuSheetState();
}

class _TableMenuSheetState extends State<_TableMenuSheet> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _open() {
    final typed = _code.text.trim().toLowerCase();
    final slug = menuSlugFrom(Uri.parse('https://bwdy.site/m/${Uri.encodeComponent(typed)}'));
    if (slug == null) return toast(context, 'That code doesn\'t look right — it\'s printed under the QR.', tone: ToastTone.error);
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => MenuScreen(slug: slug)));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget step(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: S.m),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 22, color: bd.accentText),
            const SizedBox(width: S.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: T.row(bd)),
                const SizedBox(height: 2),
                Text(body, style: T.body(bd, color: bd.muted)),
              ]),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      step(Ph.contactlessPayment, 'Tap the tag', 'Hold the top of your phone near the brewdiary sticker on the table. The menu opens on its own — no need to open anything first.'),
      step(Ph.qrCode, 'Or scan the QR', 'Point your phone\'s camera at the code on the table and tap the link.'),
      const SizedBox(height: S.m),
      Text('OR TYPE THE CODE UNDER IT', style: T.label(bd)),
      const SizedBox(height: S.s),
      TextField(
        controller: _code,
        autocorrect: false,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _open(),
        style: T.body(bd),
        decoration: InputDecoration(hintText: 'e.g. soka-indiranagar', hintStyle: T.body(bd, color: bd.faint)),
      ),
      const SizedBox(height: S.l),
      BdButton('Open the menu', onTap: _open),
      const SizedBox(height: S.m),
      Text('Opening a menu tells the venue nothing about you.', textAlign: TextAlign.center, style: T.caption(bd)),
    ]);
  }
}
