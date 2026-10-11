// A counter's shelf — a liquor store, a sweet shop, a bakery, a shop (059): what's in
// stock at its price, never how many are left. Make a list on the way, then show its QR
// at the till: the staff scan it and it's in their basket. Nothing is ordered or paid
// here — at a liquor store the law puts an ID check on every bottle at the counter, and
// a list keeps that where it belongs. The list stays on this phone (one per shop).
import 'package:brewdiary_core/links.dart';
import 'package:brewdiary_core/money.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/base.dart';
import '../../data/table_order.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

const _categoryWords = {
  'spirit': 'Spirits',
  'beer': 'Beer',
  'wine': 'Wine',
  'other_alcohol': 'Other alcohol',
  'soft': 'Soft drinks',
  'food': 'Food',
  'sweet': 'Sweets',
  'other': 'Other',
};

/// The list for a shop, kept on the phone: product id → how many.
Map<String, int> savedList(String slug) {
  final raw = Prefs.getJson<Map<String, dynamic>>('brewdiary.list.$slug') ?? const {};
  return {for (final e in raw.entries) if (e.value is num && (e.value as num) > 0) e.key: (e.value as num).toInt().clamp(1, 99)};
}

Future<void> saveList(String slug, Map<String, int> list) => list.isEmpty ? Prefs.remove('brewdiary.list.$slug') : Prefs.setJson('brewdiary.list.$slug', list);

class ShelfScreen extends StatelessWidget {
  final String slug;

  /// For tests and screenshots: a shelf without the cloud.
  final Shelf? preview;
  const ShelfScreen({super.key, required this.slug, this.preview});

  @override
  Widget build(BuildContext context) {
    if (preview != null) return ShelfView(slug: slug, shelf: preview!);
    if (db == null) return const SubPage(title: 'The shelf', child: EmptyNote("This build isn't connected to the brewdiary cloud — ask at the counter.", icon: Ph.cloudSlash));
    return Loader<Shelf?>(
      load: () => ShelfApi.load(slug),
      failed: (context, retry) => SubPage(title: 'The shelf', child: LoadError(onRetry: retry)),
      builder: (context, shelf, loading) {
        if (shelf == null) {
          return SubPage(
            title: 'The shelf',
            child: loading
                ? const Column(children: [Skeleton(height: 72), SizedBox(height: S.m), Skeleton(height: 220)])
                : const EmptyNote('Nothing on this shop\'s shelf online yet — ask at the counter.', icon: Ph.storefront),
          );
        }
        return ShelfView(slug: slug, shelf: shelf);
      },
    );
  }
}

class ShelfView extends StatefulWidget {
  final String slug;
  final Shelf shelf;
  const ShelfView({super.key, required this.slug, required this.shelf});
  @override
  State<ShelfView> createState() => _ShelfViewState();
}

class _ShelfViewState extends State<ShelfView> {
  late Map<String, int> _list = savedList(widget.slug);
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _set(ShelfItem it, int qty) {
    Haptics.tick();
    setState(() {
      final q = qty.clamp(0, 99);
      _list = {..._list}..removeWhere((k, _) => k == it.id);
      if (q > 0) _list[it.id] = q;
    });
    saveList(widget.slug, _list);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final shelf = widget.shelf;
    final byId = {for (final i in shelf.items) i.id: i};
    // Something sold out since it went on the list just drops off it.
    final onList = [for (final e in _list.entries) if (byId[e.key] != null) (item: byId[e.key]!, qty: e.value)];
    final total = onList.fold<double>(0, (s, l) => s + l.item.price * l.qty);
    final q = _q.text.trim().toLowerCase();
    final shown = shelf.items.where((i) => q.isEmpty || i.title.toLowerCase().contains(q)).toList();
    final cats = <String>{for (final i in shown) i.category}.toList()..sort((a, b) => _categoryWords.keys.toList().indexOf(a) - _categoryWords.keys.toList().indexOf(b));
    final alcohol = onList.any((l) => l.item.alcohol);

    Widget row(ShelfItem it) {
      final n = _list[it.id] ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.title, style: T.row(bd)),
              Text(
                [if (it.pack.isNotEmpty) it.pack, formatMoney(it.price, shelf.currency) + (it.byWeight ? ' a kg' : ''), if (it.mrp != null && it.mrp! > it.price) 'MRP ${formatMoney(it.mrp!, shelf.currency)}'].join(' · '),
                style: T.caption(bd).copyWith(fontFeatures: T.tnum),
              ),
            ]),
          ),
          if (it.byWeight)
            Text('weighed\nat the counter', textAlign: TextAlign.right, style: T.caption(bd))
          else ...[
            if (n > 0) ...[
              IconBtn(Ph.minus, tooltip: 'One fewer ${it.title}', onTap: () => _set(it, n - 1)),
              SizedBox(width: 22, child: RollingNumber(n, textAlign: TextAlign.center, style: T.row(bd))),
            ],
            IconBtn(Ph.plus, tooltip: 'Add ${it.title} to the list', onTap: () => _set(it, n + 1)),
          ],
        ]),
      );
    }

    return SubPage(
      title: shelf.venueName,
      subtitle: 'The shelf · make a list for the till',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (onList.isNotEmpty) ...[
          Glass(
            padding: const EdgeInsets.all(S.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('YOUR LIST', style: T.label(bd, color: bd.accentText)),
              const SizedBox(height: S.s),
              for (final l in onList) Text('${l.qty} × ${l.item.title}', style: T.body(bd)),
              const SizedBox(height: S.s),
              Text('About ${formatMoney(total, shelf.currency)} — the till has the final word.', style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
              const SizedBox(height: S.m),
              BdButton('Show it at the till', icon: Ph.qrCode, kind: BtnKind.accent, onTap: () => _showQr(context, onList)),
              const SizedBox(height: S.xs),
              TextAction('Clear the list', faint: true, size: 13, onTap: () {
                setState(() => _list = {});
                saveList(widget.slug, _list);
              }),
            ]),
          ),
          const SizedBox(height: S.l),
        ],
        GlassField(controller: _q, hint: 'Find something', icon: Ph.magnifyingGlass, onChanged: (_) => setState(() {})),
        for (final c in cats) ...[
          SectionHeader(_categoryWords[c] ?? c),
          Group(children: [for (final it in shown.where((i) => i.category == c)) row(it)]),
        ],
        if (shown.isEmpty) Padding(padding: const EdgeInsets.only(top: S.l), child: Text('Nothing matches.', style: T.caption(bd))),
        const SizedBox(height: S.xl),
        Text(
          alcohol
              ? 'Bottles are sold at the counter, where the law asks for an ID check. A list only saves you the hunt — nothing is ordered or paid here.'
              : 'A list only saves you the hunt — nothing is ordered or paid here. Opening the shelf tells the shop nothing about you.',
          style: T.caption(bd),
        ),
      ]),
    );
  }

  Future<void> _showQr(BuildContext context, List<({ShelfItem item, int qty})> onList) async {
    final data = shopListQr(widget.slug, [for (final l in onList) (productId: l.item.id, qty: l.qty)]);
    await showBdSheet<void>(context, title: 'Your list', builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Show this at the till. They scan it, and it\'s in their basket.', textAlign: TextAlign.center, style: T.body(bd, color: bd.muted)),
        const SizedBox(height: S.l),
        Center(
          child: Container(
            padding: const EdgeInsets.all(S.m),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(rTile)),
            child: Semantics(
              label: 'Your list as a code for the till',
              child: QrImageView(key: ValueKey(data), data: data, size: 240, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
            ),
          ),
        ),
        const SizedBox(height: S.l),
        for (final l in onList) Text('${l.qty} × ${l.item.title}', textAlign: TextAlign.center, style: T.body(bd)),
      ]);
    });
  }
}
