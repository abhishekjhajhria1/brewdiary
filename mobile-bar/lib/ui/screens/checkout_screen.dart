// Checkout — a counter's sale (050). Tap what's being bought, say how it was paid, ring
// it up. The server prices it again, moves the stock, and — for anything alcoholic —
// checks the law first: the state researched, not a dry day, inside legal hours, under
// the per-sale limit, and ID checked (a yes, never the ID itself). The screen shows the
// same rule before the tap so nobody learns it from an error.
//
// A sale has no customer attached: the till sells to "a customer". Punching a loyalty
// card is still its own step on the Till.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../logic/counter.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

const _categoryLabel = {
  'spirit': 'Spirits',
  'beer': 'Beer',
  'wine': 'Wine',
  'other_alcohol': 'Other alcohol',
  'soft': 'Soft drinks',
  'food': 'Food',
  'sweet': 'Sweets',
  'other': 'Other',
};

class CheckoutScreen extends StatefulWidget {
  final Venue venue;
  const CheckoutScreen({super.key, required this.venue});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _q = TextEditingController();
  Basket _basket = const Basket();
  String _paid = 'upi';
  bool _idChecked = false;
  bool _busy = false;
  String? _category;
  SaleStatus? _status;

  Venue get v => widget.venue;

  @override
  void initState() {
    super.initState();
    if (v.sellsAlcohol) {
      Backend.i.saleStatus(v.id).then((s) {
        if (mounted) setState(() => _status = s);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _add(ShopProduct p) async {
    if (!p.byWeight) return setState(() => _basket = _basket.add(p));
    final grams = await _askGrams(p);
    if (grams != null && grams > 0 && mounted) setState(() => _basket = _basket.add(p, grams));
  }

  Future<int?> _askGrams(ShopProduct p) async {
    final ctl = TextEditingController();
    final got = await showBdSheet<int>(context, title: p.name, builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${money(p.price, v.currency)} per kg', style: T.bodyMuted(bd)),
        const SizedBox(height: S.l),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final g in const [100, 250, 500, 1000]) BdChip(g >= 1000 ? '1 kg' : '$g g', onTap: () => Navigator.pop(ctx, g)),
        ]),
        const SizedBox(height: S.l),
        LineField(controller: ctl, label: 'Or grams', keyboard: TextInputType.number, onSubmitted: (t) => Navigator.pop(ctx, int.tryParse(t.trim()))),
        const SizedBox(height: S.m),
        BdButton('Add', onTap: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim()))),
      ]);
    });
    ctl.dispose();
    return got;
  }

  Future<void> _ring() async {
    final block = basketBlock(_basket, _status, idChecked: _idChecked);
    if (block != null) return toast(context, block, tone: ToastTone.error);
    setState(() => _busy = true);
    final total = _basket.total;
    final ok = await runAction(context, () => Backend.i.ringSale(v.id, newId(), _basket.toLines(), _paid, idChecked: _idChecked), done: 'Rung up ${money(total, v.currency)}.');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _basket = const Basket();
        _idChecked = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'New sale',
          subtitle: v.name,
          back: true,
          tabBar: false,
          maxWidth: kWideMaxWidth,
          children: [
            if (v.sellsAlcohol) _LawBanner(status: _status),
            Loader<(List<ShopProduct>, Map<String, int>)>(
              load: () async => (await Backend.i.products(v.id), await Backend.i.stock(v.id)),
              refresh: stockRev,
              retry: true,
              builder: (context, data, loading) {
                if (data == null) return const Skeleton(height: 240);
                final shelf = _shelf(context, data.$1.where((p) => p.active).toList(), data.$2);
                final basket = _basketPane(context);
                return LayoutBuilder(builder: (context, c) {
                  if (c.maxWidth >= 840) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: shelf),
                      const SizedBox(width: S.xl),
                      Expanded(flex: 2, child: basket),
                    ]);
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [basket, const SizedBox(height: S.l), shelf]);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _shelf(BuildContext context, List<ShopProduct> products, Map<String, int> stock) {
    final bd = context.bd;
    if (products.isEmpty) return const EmptyNote('Nothing on the shelf yet — add products in More › Stock.');
    final cats = {for (final p in products) p.category}.toList()..sort((a, b) => _categoryLabel.keys.toList().indexOf(a) - _categoryLabel.keys.toList().indexOf(b));
    final q = _q.text.trim().toLowerCase();
    final shown = products.where((p) => (_category == null || p.category == _category) && (q.isEmpty || '${p.name} ${p.brand ?? ''} ${p.barcode ?? ''}'.toLowerCase().contains(q))).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlassField(controller: _q, hint: 'Search or scan a barcode', icon: Ph.magnifyingGlass, caps: TextCapitalization.none, onChanged: (_) => setState(() {})),
      const SizedBox(height: S.s),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          Padding(padding: const EdgeInsets.only(right: S.s), child: BdChip('All', active: _category == null, onTap: () => setState(() => _category = null))),
          for (final c in cats) Padding(padding: const EdgeInsets.only(right: S.s), child: BdChip(_categoryLabel[c] ?? c, active: _category == c, onTap: () => setState(() => _category = c))),
        ]),
      ),
      const SizedBox(height: S.m),
      Group(children: [
        for (final p in shown)
          GroupTile(
            title: p.brand == null ? p.name : '${p.brand} ${p.name}',
            subtitle: [
              if (p.pack.isNotEmpty) p.pack,
              money(p.price, v.currency),
              if (p.mrp != null) 'MRP ${money(p.mrp!, v.currency)}',
              '${stock[p.id] ?? 0}${p.byWeight ? ' g' : ''} in stock',
            ].join(' · '),
            trailing: AccentPill('Add', onTap: () => _add(p)),
          ),
      ]),
      if (shown.isEmpty) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('Nothing matches.', style: T.caption(bd))),
    ]);
  }

  Widget _basketPane(BuildContext context) {
    final bd = context.bd;
    final block = basketBlock(_basket, _status, idChecked: _idChecked);
    return Glass(
      padding: const EdgeInsets.all(S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('THIS SALE', style: T.label(bd)),
        const SizedBox(height: S.s),
        if (_basket.isEmpty) Text('Tap Add on anything below.', style: T.bodyMuted(bd)),
        for (final l in _basket.lines)
          Reveal(
            key: ValueKey(l.product.id),
            child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text('${l.qtyLabel} ${l.product.name}', style: T.sans(bd, size: 15))),
              if (!l.product.byWeight) ...[
                IconBtn(Ph.minus, tooltip: 'One fewer ${l.product.name}', onTap: () => setState(() => _basket = _basket.set(l.product.id, l.qty - 1))),
                IconBtn(Ph.plus, tooltip: 'One more ${l.product.name}', onTap: () => setState(() => _basket = _basket.set(l.product.id, l.qty + 1))),
              ] else
                IconBtn(Ph.x, tooltip: 'Remove ${l.product.name}', onTap: () => setState(() => _basket = _basket.set(l.product.id, 0))),
              SizedBox(width: 90, child: RollingText(money(l.total, v.currency), textAlign: TextAlign.right, style: T.sans(bd, size: 15).copyWith(fontFeatures: T.tnum))),
            ]),
          ),
          ),
        if (!_basket.isEmpty) ...[
          const SizedBox(height: S.s),
          Container(height: .8, color: bd.line),
          const SizedBox(height: S.s),
          Row(children: [
            Expanded(child: Text('Total', style: T.sans(bd, size: 16, weight: FontWeight.w600))),
            RollingText(money(_basket.total, v.currency), style: T.serif(bd, size: 26).copyWith(fontFeatures: T.tnum)),
          ]),
          const SizedBox(height: S.m),
          Segmented<String>(options: const [('cash', 'Cash'), ('card', 'Card'), ('upi', 'UPI')], value: _paid, onChanged: (x) => setState(() => _paid = x)),
          if (_basket.hasAlcohol) ...[
            const SizedBox(height: S.s),
            SettingRow(
              title: 'ID checked — ${_status?.minAge ?? 21} or over',
              hint: 'Required for alcohol. Only the yes is kept, never the ID.',
              trailing: BdToggle(on: _idChecked, label: 'ID checked', onChanged: (x) => setState(() => _idChecked = x)),
            ),
          ],
          if (block != null)
            Padding(padding: const EdgeInsets.only(top: S.s), child: Text(block, style: T.sans(bd, size: 13.5, color: bd.accentText))),
          const SizedBox(height: S.m),
          BdButton('Ring up ${money(_basket.total, v.currency)}', busy: _busy, onTap: block == null ? _ring : null),
        ],
      ]),
    );
  }
}

/// What the law says about alcohol at this till right now.
class _LawBanner extends StatelessWidget {
  final SaleStatus? status;
  const _LawBanner({required this.status});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = status;
    if (s == null) return const SizedBox(height: S.s);
    final ok = s.researched && s.allowedNow;
    final text = ok
        ? 'Alcohol: on sale${s.saleEnd == null ? '' : ' until ${s.saleEnd}'} · ID ${s.minAge ?? 21}+${s.maxMl == null ? '' : ' · up to ${s.maxMl} ml a sale'}'
        : (s.reason ?? 'Alcohol can\'t be sold here right now.');
    return Padding(
      padding: const EdgeInsets.only(bottom: S.l),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ToneTag(ok ? 'open' : 'closed', ok ? Tone.good : Tone.late),
        const SizedBox(width: S.m),
        Expanded(child: Text(text, style: T.sans(bd, size: 14, color: bd.muted, height: 1.4))),
      ]),
    );
  }
}
