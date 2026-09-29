// Stock — a counter's shelf and what's on it (050). On hand is always the ledger's sum:
// deliveries in, sales out, breakages and counts noted with a reason. Who may do what
// follows the role: bartenders and kitchen receive deliveries, managers adjust and edit
// the shelf. A price can never be saved above the printed MRP, and a shop that sells no
// alcohol can't list any.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

const _categories = [
  ('spirit', 'Spirits'),
  ('beer', 'Beer'),
  ('wine', 'Wine'),
  ('other_alcohol', 'Other alcohol'),
  ('soft', 'Soft drinks'),
  ('food', 'Food'),
  ('sweet', 'Sweets'),
  ('other', 'Other'),
];

class StockScreen extends StatelessWidget {
  final Venue venue;
  const StockScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Stock',
          subtitle: venue.name,
          back: true,
          tabBar: false,
          maxWidth: kWideMaxWidth,
          onRefresh: () async => stockRev.bump(),
          children: [
            if (s.can(Cap.editMenu)) ...[
              BdButton('Add a product', icon: Ph.plus, kind: BtnKind.secondary, onTap: () => _edit(context, null)),
              const SizedBox(height: S.l),
            ],
            Loader<(List<ShopProduct>, Map<String, int>)>(
              load: () async => (await Backend.i.products(venue.id), await Backend.i.stock(venue.id)),
              refresh: stockRev,
              retry: true,
              builder: (context, data, loading) {
                if (data == null) return const Skeleton(height: 240);
                final (products, stock) = data;
                if (products.isEmpty) return const EmptyNote('No products yet. Add what you sell — the till and the stock count follow.');
                return Group(children: [
                  for (final p in products)
                    GroupTile(
                      title: p.brand == null ? p.name : '${p.brand} ${p.name}',
                      subtitle: [if (p.pack.isNotEmpty) p.pack, money(p.price, venue.currency), if (!p.active) 'off the till'].join(' · '),
                      trailing: _OnHand(n: stock[p.id] ?? 0, grams: p.byWeight),
                      onTap: () => _actions(context, p),
                    ),
                ]);
              },
            ),
            const SectionHeader('Suppliers'),
            Loader<List<ShopSupplier>>(
              load: () => Backend.i.suppliers(venue.id),
              refresh: stockRev,
              builder: (context, list, loading) {
                if (list == null) return const Skeleton(height: 60);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (list.isEmpty) Text('None yet. Add the businesses you buy from — a name and a licence number.', style: T.caption(bd)),
                  if (list.isNotEmpty) Group(children: [for (final x in list) GroupTile(icon: Ph.truck, title: x.name, subtitle: x.licence == null ? null : 'Licence ${x.licence}')]),
                  if (s.can(Cap.receiveStock)) ...[
                    const SizedBox(height: S.m),
                    BdButton('Add a supplier', kind: BtnKind.quiet, onTap: () => _addSupplier(context)),
                  ],
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, ShopProduct p) async {
    final s = Session.instance;
    await showActions(context, title: p.name, actions: [
      if (s.can(Cap.receiveStock)) SheetAction('Receive a delivery', icon: Ph.package, onTap: () => _receive(context, p)),
      if (s.can(Cap.adjustStock)) SheetAction('Adjust (count, breakage, return)', icon: Ph.slidersHorizontal, onTap: () => _adjust(context, p)),
      if (s.can(Cap.editMenu)) SheetAction('Edit', icon: Ph.pencilSimple, onTap: () => _edit(context, p)),
    ]);
  }

  Future<void> _receive(BuildContext context, ShopProduct p) async {
    final qty = TextEditingController();
    final invoice = TextEditingController();
    String? supplier;
    final suppliers = await Backend.i.suppliers(venue.id).catchError((_) => const <ShopSupplier>[]);
    if (!context.mounted) return;
    await showBdSheet<void>(context, title: 'Receive ${p.name}', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LineField(controller: qty, label: p.byWeight ? 'Grams received' : 'How many', keyboard: TextInputType.number, autofocus: true),
          if (suppliers.isNotEmpty) ...[
            const SizedBox(height: S.l),
            Wrap(spacing: S.s, runSpacing: S.s, children: [for (final x in suppliers) BdChip(x.name, active: supplier == x.id, onTap: () => set(() => supplier = supplier == x.id ? null : x.id))]),
          ],
          const SizedBox(height: S.l),
          LineField(controller: invoice, label: 'Invoice / challan no. (optional)'),
          const SizedBox(height: S.xl),
          BdButton('Receive', onTap: () async {
            final n = int.tryParse(qty.text.trim()) ?? 0;
            final ok = await runAction(ctx, () => Backend.i.receiveStock(p.id, n, supplierId: supplier, invoice: invoice.text), done: 'Received.');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
        ]);
      });
    });
    qty.dispose();
    invoice.dispose();
  }

  Future<void> _adjust(BuildContext context, ShopProduct p) async {
    final qty = TextEditingController();
    final note = TextEditingController();
    var why = 'adjust';
    var sign = -1;
    await showBdSheet<void>(context, title: 'Adjust ${p.name}', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Segmented<String>(options: const [('adjust', 'Count'), ('waste', 'Breakage'), ('return', 'Return')], value: why, onChanged: (x) => set(() => why = x)),
          const SizedBox(height: S.l),
          Segmented<int>(options: const [(-1, 'Fewer'), (1, 'More')], value: sign, onChanged: (x) => set(() => sign = x)),
          const SizedBox(height: S.l),
          LineField(controller: qty, label: p.byWeight ? 'Grams' : 'How many', keyboard: TextInputType.number),
          const SizedBox(height: S.l),
          LineField(controller: note, label: why == 'adjust' ? 'Why (required)' : 'Note (optional)'),
          const SizedBox(height: S.s),
          Text('Every adjustment is kept in the ledger with who made it.', style: T.caption(bd)),
          const SizedBox(height: S.xl),
          BdButton('Save', onTap: () async {
            final n = (int.tryParse(qty.text.trim()) ?? 0) * sign;
            final ok = await runAction(ctx, () => Backend.i.adjustStock(p.id, n, why, note: note.text), done: 'Saved.');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
        ]);
      });
    });
    qty.dispose();
    note.dispose();
  }

  Future<void> _edit(BuildContext context, ShopProduct? p) async {
    final name = TextEditingController(text: p?.name ?? '');
    final brand = TextEditingController(text: p?.brand ?? '');
    final size = TextEditingController(text: p?.size?.toStringAsFixed(0) ?? '');
    final price = TextEditingController(text: p?.price.toStringAsFixed(0) ?? '');
    final mrp = TextEditingController(text: p?.mrp?.toStringAsFixed(0) ?? '');
    final barcode = TextEditingController(text: p?.barcode ?? '');
    var category = p?.category ?? (venue.sellsAlcohol ? 'spirit' : 'sweet');
    var byWeight = p?.byWeight ?? false;
    var active = p?.active ?? true;
    final cats = [for (final c in _categories) if (venue.sellsAlcohol || !alcoholCategories.contains(c.$1)) c];
    await showBdSheet<void>(context, title: p == null ? 'A new product' : 'Edit ${p.name}', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        final alcohol = alcoholCategories.contains(category);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LineField(controller: name, label: 'Name', caps: TextCapitalization.words, maxLength: 120),
          const SizedBox(height: S.m),
          LineField(controller: brand, label: 'Brand (optional)', caps: TextCapitalization.words),
          const SizedBox(height: S.l),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final c in cats) BdChip(c.$2, active: category == c.$1, onTap: () => set(() {
                  category = c.$1;
                  if (alcoholCategories.contains(c.$1)) byWeight = false;
                })),
          ]),
          if (!alcohol) ...[
            const SizedBox(height: S.m),
            SettingRow(title: 'Sold by weight', hint: 'Price per kg; the till asks for grams.', trailing: BdToggle(on: byWeight, label: 'Sold by weight', onChanged: (x) => set(() => byWeight = x))),
          ],
          if (!byWeight) ...[
            const SizedBox(height: S.m),
            LineField(controller: size, label: alcohol ? 'Bottle / can size (ml)' : 'Size (optional)', keyboard: TextInputType.number),
          ],
          const SizedBox(height: S.m),
          LineField(controller: price, label: byWeight ? 'Price per kg (${venue.currency})' : 'Price (${venue.currency})', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: S.m),
          LineField(controller: mrp, label: 'MRP — printed maximum price (optional)', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: S.m),
          LineField(controller: barcode, label: 'Barcode (optional)', caps: TextCapitalization.none),
          if (p != null)
            SettingRow(title: 'On the till', trailing: BdToggle(on: active, label: 'On the till', onChanged: (x) => set(() => active = x))),
          const SizedBox(height: S.s),
          Text(alcohol ? 'Alcohol is sold only where the state\'s retail rules are researched, with an ID check.' : 'The price can never be above the MRP.', style: T.caption(bd)),
          const SizedBox(height: S.xl),
          BdButton('Save', onTap: () async {
            final item = ShopProduct(
              id: p?.id ?? newId(),
              name: name.text,
              brand: brand.text,
              category: category,
              size: byWeight ? null : double.tryParse(size.text.trim()),
              unit: byWeight ? 'g' : (alcohol ? 'ml' : 'piece'),
              byWeight: byWeight,
              price: double.tryParse(price.text.trim()) ?? -1,
              mrp: double.tryParse(mrp.text.trim()),
              barcode: barcode.text,
              active: active,
            );
            if (item.price < 0) return toast(ctx, 'Give it a price.');
            if (alcohol && item.size == null) return toast(ctx, 'Give the bottle size in ml.');
            final ok = await runAction(ctx, () => Backend.i.saveProduct(venue.id, item, isNew: p == null), done: 'Saved.');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
        ]);
      });
    });
    for (final c in [name, brand, size, price, mrp, barcode]) {
      c.dispose();
    }
  }

  Future<void> _addSupplier(BuildContext context) async {
    final name = TextEditingController();
    final licence = TextEditingController();
    await showBdSheet<void>(context, title: 'A new supplier', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LineField(controller: name, label: 'Business name', caps: TextCapitalization.words, autofocus: true),
        const SizedBox(height: S.m),
        LineField(controller: licence, label: 'Licence no. (optional)'),
        const SizedBox(height: S.xl),
        BdButton('Add', onTap: () async {
          final ok = await runAction(ctx, () => Backend.i.addSupplier(venue.id, name.text, licence: licence.text), done: 'Added.');
          if (ok && ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
    name.dispose();
    licence.dispose();
  }
}

class _OnHand extends StatelessWidget {
  final int n;
  final bool grams;
  const _OnHand({required this.n, required this.grams});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final text = grams ? (n >= 1000 ? '${(n / 1000).toStringAsFixed(1)} kg' : '$n g') : '$n';
    if (n <= 0) return ToneTag(n == 0 ? 'out' : text, Tone.late);
    return Text(text, style: T.sans(bd, size: 15, weight: FontWeight.w600).copyWith(fontFeatures: T.tnum));
  }
}
