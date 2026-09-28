// A venue's menu — what tapping the NFC tag (or scanning the QR) on the table
// opens. A port of src/components/menu/MenuView.tsx.
//
// "You'd probably like" is worked out on this phone from your own diary; the venue
// never learns who looked. "Log it" writes the drink straight into today with the
// venue filled in. A menu is never an offer: no discounts, by design.
import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/menus.dart';
import '../../core/money.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/menus.dart';
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
        return MenuView(menu: menu);
      },
    );
  }
}

/// The menu itself (public so tests can render one without the cloud).
class MenuView extends StatefulWidget {
  final Menu menu;
  const MenuView({super.key, required this.menu});
  @override
  State<MenuView> createState() => MenuViewState();
}

class MenuViewState extends State<MenuView> {
  bool _noAlcohol = false;

  void _log(MenuItem item) {
    entryStore.addEntry(date: todayKey(), drink: item.name, type: item.drinkType, venue: widget.menu.venueName);
    toast(context, 'Logged ${item.name} — in today\'s square.');
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
                Text.rich(TextSpan(children: [
                  TextSpan(text: it.name, style: T.row(bd)),
                  if (it.noAlcohol) TextSpan(text: '   NO ALCOHOL', style: T.label(bd, color: bd.accentText)),
                ])),
                if (it.description != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(it.description!, style: T.body(bd, color: bd.muted))),
              ]),
            ),
            const SizedBox(width: S.m),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (it.price != null) Text(formatMoney(it.price!, menu.currency), style: T.row(bd).copyWith(fontFeatures: T.tnum)),
              if (it.kind != 'food') TextAction('Log it', accent: true, size: 13, onTap: () => _log(it)),
            ]),
          ]),
        );

    return SubPage(
      title: menu.venueName,
      actions: [IconBtn(Ph.identificationBadge, tooltip: 'Show my taste card', onTap: () => showTasteCard(context))],
      subtitle: [if (menu.venueCity != null) menu.venueCity!, menu.isStore ? 'On the shelf' : 'The menu'].join(' · '),
      child: menu.sections.isEmpty
          ? const EmptyNote("The menu isn't up yet — ask at the bar.", icon: Ph.notebook)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              const SizedBox(height: S.xl),
              Text("Opening a menu tells ${menu.venueName} nothing about you. Prices are the venue's own.", style: T.caption(bd)),
            ]),
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
    if (slug == null) return toast(context, 'That code doesn\'t look right — it\'s printed under the QR.');
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
