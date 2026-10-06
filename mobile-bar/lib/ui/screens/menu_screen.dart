// The menu (a shelf at a shop, the counter at a sweet shop) — what a guest sees when
// they tap the tag on the table. A menu is NOT an offer: a name, a section, a price,
// and nothing else — no discount, no "today only". Marking an item sold out (86) takes
// it off the guest's menu at once.
import 'package:brewdiary_core/menus.dart' show menuUrl;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/venue_kinds.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

const menuKinds = [
  ('cocktail', 'Cocktail'),
  ('beer', 'Beer'),
  ('wine', 'Wine'),
  ('spirit', 'Spirit'),
  ('coffee', 'Coffee'),
  ('tea', 'Tea'),
  ('soft', 'Soft drink'),
  ('food', 'Food'),
  ('other', 'Other'),
];

class MenuScreen extends StatelessWidget {
  final Venue venue;
  const MenuScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final word = menuWord(venue.kind);
    return ScrollPage(
      title: word,
      subtitle: venue.name,
      actions: [
        IconBtn(Ph.shareNetwork, tooltip: 'Share the menu', onTap: () => _tags(context)),
      ],
      onRefresh: () async => menuRev.bump(),
      children: [
        const DemoNote(),
        if (!venue.verified)
          Padding(
            padding: const EdgeInsets.only(bottom: S.l),
            child: Text('Draft away — guests see your ${word.toLowerCase()} once brewdiary verifies you.', style: T.caption(bd)),
          ),
        Loader<List<MenuItem>>(
          load: () => Backend.i.menu(venue.id),
          refresh: menuRev,
          retry: true,
          builder: (context, items, loading) {
            if (items == null) return const Skeleton(height: 200);
            if (items.isEmpty) return EmptyNote('Nothing on the ${word.toLowerCase()} yet.', action: s.can(Cap.editMenu) ? 'Add the first item' : null, onAction: () => _edit(context, null, 0));
            final sections = <String, List<MenuItem>>{};
            for (final i in items) {
              (sections[i.section] ??= []).add(i);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final e in sections.entries) ...[
                SectionHeader(e.key, padding: const EdgeInsets.only(top: S.l, bottom: S.s)),
                Group(children: [for (final i in e.value) _ItemRow(venue: venue, item: i, onEdit: () => _edit(context, i, i.position))]),
              ],
              if (s.can(Cap.editMenu)) ...[
                const SizedBox(height: S.xl),
                BdButton('Add an item', icon: Ph.plus, kind: BtnKind.secondary, onTap: () => _edit(context, null, items.length)),
              ],
            ]);
          },
        ),
      ],
    );
  }

  void _tags(BuildContext context) {
    final url = menuUrl(venue.slug, Config.siteUrl);
    showBdSheet<void>(context, title: 'Share the ${menuWord(venue.kind).toLowerCase()}', builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('One link for anywhere — your socials, a poster, a message. On a table, use the table\'s own QR (More › Floor setup): it opens this menu with the table known, so guests can order and call staff from it.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.m),
        Text('Every table gets one plain link. Write it to an NFC sticker (NTAG213 or better) and print this QR beside it for phones without NFC — with the app it opens in the app, without it the website.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.l),
        Center(child: QrBox(url)),
        const SizedBox(height: S.m),
        SelectableText(url, textAlign: TextAlign.center, style: T.sans(bd, size: 14, color: bd.muted)),
        const SizedBox(height: S.l),
        BdButton('Share the link', icon: Ph.shareNetwork, onTap: () => SharePlus.instance.share(ShareParams(text: '${venue.name} — the ${menuWord(venue.kind).toLowerCase()}: $url'))),
      ]);
    });
  }

  Future<void> _edit(BuildContext context, MenuItem? item, int position) async {
    if (!Session.instance.can(Cap.editMenu)) return;
    final name = TextEditingController(text: item?.name ?? '');
    final section = TextEditingController(text: item?.section ?? (venue.kind.isCounter ? 'Counter' : 'Drinks'));
    final desc = TextEditingController(text: item?.description ?? '');
    final price = TextEditingController(text: item?.price == null ? '' : item!.price!.toStringAsFixed(item.price! % 1 == 0 ? 0 : 2));
    var kind = item?.kind ?? (venue.sellsAlcohol ? 'cocktail' : 'food');
    var noAlcohol = item?.noAlcohol ?? !venue.sellsAlcohol;
    var station = item?.station ?? (kind == 'food' ? 'kitchen' : 'bar');
    String? diet = item?.diet;
    final allergens = {...?item?.allergens};
    await showBdSheet<void>(context, title: item == null ? 'New item' : 'Edit item', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LineField(controller: name, label: 'Name', hint: 'Negroni', caps: TextCapitalization.words, maxLength: 80, autofocus: item == null),
          const SizedBox(height: S.l),
          LineField(controller: section, label: 'Section', hint: 'Cocktails', caps: TextCapitalization.words, maxLength: 40),
          const SizedBox(height: S.l),
          LineField(controller: desc, label: 'Description (optional)', hint: 'Gin, Campari, vermouth', maxLength: 240),
          const SizedBox(height: S.l),
          LineField(controller: price, label: 'Price (${venue.currency})', hint: '450', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: S.l),
          const Label('Kind'),
          const SizedBox(height: 6),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final k in menuKinds) BdChip(k.$2, active: kind == k.$1, onTap: () => set(() {
                  kind = k.$1;
                  station = kind == 'food' ? 'kitchen' : 'bar';
                })),
          ]),
          if (!venue.kind.isCounter) ...[
            const SizedBox(height: S.l),
            const Label('Its ticket goes to'),
            const SizedBox(height: 6),
            Wrap(spacing: S.s, runSpacing: S.s, children: [
              for (final st in const [('bar', 'The bar'), ('kitchen', 'The kitchen'), ('none', 'Nowhere — served as is')]) BdChip(st.$2, active: station == st.$1, onTap: () => set(() => station = st.$1)),
            ]),
          ],
          const SizedBox(height: S.l),
          const Label('Mark'),
          const SizedBox(height: 6),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final d in const [(null, 'None'), ('veg', 'Veg'), ('non_veg', 'Non-veg'), ('egg', 'Egg'), ('vegan', 'Vegan')]) BdChip(d.$2, active: diet == d.$1, onTap: () => set(() => diet = d.$1)),
          ]),
          const SizedBox(height: S.l),
          const Label('Allergens'),
          const SizedBox(height: 6),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final a in menuAllergens) BdChip(a.$2, active: allergens.contains(a.$1), onTap: () => set(() => allergens.contains(a.$1) ? allergens.remove(a.$1) : allergens.add(a.$1))),
          ]),
          if (venue.sellsAlcohol)
            SettingRow(
              title: 'No alcohol',
              hint: 'Shown as alcohol-free — so a guest sitting it out finds it first.',
              trailing: BdToggle(on: noAlcohol, label: 'No alcohol', onChanged: (v) => set(() => noAlcohol = v)),
            ),
          const SizedBox(height: S.xl),
          BdButton('Save', onTap: () async {
            final p = price.text.trim().isEmpty ? null : double.tryParse(price.text.replaceAll(',', '').trim());
            if (name.text.trim().isEmpty) return toast(ctx, 'Give it a name.', tone: ToastTone.error);
            if (price.text.trim().isNotEmpty && (p == null || p < 0)) return toast(ctx, 'That price doesn\'t look right.', tone: ToastTone.error);
            final next = MenuItem(
              id: item?.id ?? newId(),
              section: section.text.trim().isEmpty ? 'Menu' : section.text.trim(),
              name: name.text.trim(),
              description: desc.text.trim().isEmpty ? null : desc.text.trim(),
              price: p,
              kind: kind,
              noAlcohol: venue.sellsAlcohol ? noAlcohol : true,
              available: item?.available ?? true,
              position: position,
              station: station,
              diet: diet,
              allergens: [for (final a in menuAllergens) if (allergens.contains(a.$1)) a.$1],
            );
            final ok = await runAction(ctx, () => Backend.i.saveMenuItem(venue.id, next, isNew: item == null), done: 'Saved.');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
          if (item != null) ...[
            const SizedBox(height: S.s),
            BdButton('Remove from the ${menuWord(venue.kind).toLowerCase()}', kind: BtnKind.quiet, onTap: () async {
              final yes = await confirm(ctx, title: 'Remove ${item.name}?', body: 'It disappears from the guests\' menu too.', yes: 'Remove');
              if (!yes || !ctx.mounted) return;
              final ok = await runAction(ctx, () => Backend.i.removeMenuItem(item.id), done: 'Removed.');
              if (ok && ctx.mounted) Navigator.pop(ctx);
            }),
          ],
          Padding(
            padding: const EdgeInsets.only(top: S.s),
            child: Text('A menu is never an offer: no discounts, no "today only". The price is the price.', style: T.caption(bd)),
          ),
        ]);
      });
    });
    for (final c in [name, section, desc, price]) {
      c.dispose();
    }
  }
}

class _ItemRow extends StatelessWidget {
  final Venue venue;
  final MenuItem item;
  final VoidCallback onEdit;
  const _ItemRow({required this.venue, required this.item, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: T.row(bd, color: item.available ? bd.ink : bd.faint).copyWith(decoration: item.available ? null : TextDecoration.lineThrough)),
              if (item.description != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.description!, style: T.caption(bd), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (item.noAlcohol && venue.sellsAlcohol) const Padding(padding: EdgeInsets.only(top: 4), child: ToneTag('no alcohol', Tone.info)),
            ]),
          ),
          if (item.price != null) Padding(padding: const EdgeInsets.only(left: S.s), child: Text(money(item.price!, venue.currency, round: false), style: T.row(bd).copyWith(fontFeatures: T.tnum))),
          if (s.can(Cap.mark86))
            Padding(
              padding: const EdgeInsets.only(left: S.s),
              child: BdToggle(
                on: item.available,
                label: item.available ? '${item.name} available' : '${item.name} sold out',
                onChanged: (on) => runAction(context, () => Backend.i.saveMenuItem(venue.id, item.copyWith(available: on)), done: on ? '${item.name} is back.' : '${item.name} is off the menu (86).'),
              ),
            ),
        ]),
      ),
    );
    return s.can(Cap.editMenu) ? Semantics(button: true, child: Pressable(onTap: onEdit, child: row)) : row;
  }
}

/// The EU's 14 allergens (051) — the widest list any market asks for.
const menuAllergens = [
  ('gluten', 'Gluten'),
  ('crustaceans', 'Crustaceans'),
  ('eggs', 'Eggs'),
  ('fish', 'Fish'),
  ('peanuts', 'Peanuts'),
  ('soy', 'Soy'),
  ('milk', 'Milk'),
  ('nuts', 'Tree nuts'),
  ('celery', 'Celery'),
  ('mustard', 'Mustard'),
  ('sesame', 'Sesame'),
  ('sulphites', 'Sulphites'),
  ('lupin', 'Lupin'),
  ('molluscs', 'Molluscs'),
];
