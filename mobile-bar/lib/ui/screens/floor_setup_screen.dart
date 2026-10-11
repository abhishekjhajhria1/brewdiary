// Setting up the floor — once: areas (Bar, Floor, Patio), the tables in them, the
// PICKUP POINTS (a bar counter, a café's or a shop's counter — where an order gets a
// number to collect, 059), and each one's own link (bwdy.site/t/<code>) to print as a QR
// or write onto an NFC sticker from this phone. Scanning or tapping it opens the menu
// with the table known.
//
// And how phone orders come in: off, waiting for a staff OK, or straight onto the bar's
// and kitchen's screens and printers — for places where nobody on the floor carries a
// phone. A pause for the rush, and ordering without an account, sit with it. A new code
// retires every printed tag for that table.
import 'package:brewdiary_core/links.dart' show readyUrl;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../device/nfc_tags.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'ready_board_screen.dart';

String tableLink(VenueTable t) => '${Config.siteUrl}/t/${t.code}';
String readyLink(VenueTable t) => readyUrl(t.code, Config.siteUrl);

/// What each way of taking phone orders means, in a line.
String phoneOrdersHint(PhoneOrders p, {required bool counter}) => switch (p) {
      PhoneOrders.off => counter ? 'Your counter\'s QR shows what you sell. Customers order with you.' : 'Your QRs and tags show the menu. Guests order with staff.',
      PhoneOrders.confirm => 'A guest\'s order waits in the inbox for a staff member\'s OK, then goes to the bar and the kitchen.',
      PhoneOrders.direct => 'A guest\'s order goes straight onto the bar\'s and kitchen\'s screens — and their ticket printers. For places where nobody on the floor carries a phone.',
    };

class FloorSetupScreen extends StatelessWidget {
  final Venue venue;
  const FloorSetupScreen({super.key, required this.venue});

  Venue get v => Session.instance.venue?.id == venue.id ? Session.instance.venue! : venue;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final can = s.can(Cap.editSettings);
    final canPause = s.can(Cap.takeOrders) || s.can(Cap.barStation) || s.can(Cap.kitchenStation);
    final counter = v.kind.isCounter;
    void managers() => toast(context, 'An owner or manager can change this.');
    return Scaffold(
      body: Ambient(
        child: ListenableBuilder(
          listenable: Session.instance,
          builder: (context, _) => ScrollPage(
            title: counter ? 'Phone orders' : 'Floor',
            subtitle: counter ? 'your counter\'s QR, pickup numbers' : 'tables, pickup points, phone orders',
            back: true,
            tabBar: false,
            maxWidth: kWideMaxWidth,
            children: [
              const SectionHeader('Phone orders'),
              Segmented<PhoneOrders>(
                options: const [(PhoneOrders.off, 'Off'), (PhoneOrders.confirm, 'Staff OK first'), (PhoneOrders.direct, 'Straight in')],
                value: v.phoneOrders,
                onChanged: (p) => can
                    ? runAction(context, () => Backend.i.updateVenue(v.id, tableService: p != PhoneOrders.off, ordersDirect: p == PhoneOrders.direct))
                    : managers(),
              ),
              const SizedBox(height: S.s),
              Text(phoneOrdersHint(v.phoneOrders, counter: counter), style: T.caption(bd)),
              if (v.phoneOrders != PhoneOrders.off) ...[
                SettingRow(
                  title: 'Paused for the rush',
                  hint: v.ordersPaused ? 'Guests are asked to order at the bar until you switch this off.' : 'Hold phone orders for a while — the bar and the kitchen can flip this too.',
                  trailing: BdToggle(
                    on: v.ordersPaused,
                    label: 'Phone orders paused',
                    onChanged: (x) => canPause ? runAction(context, () => Backend.i.pausePhoneOrders(v.id, x)) : managers(),
                  ),
                ),
                SettingRow(
                  title: 'Without an account',
                  hint: 'Guests order without signing up. Being at the table (its code) is the proof; a new code retires a leaked one. Staff never see who asked either way.',
                  trailing: BdToggle(on: v.ordersAnon, label: 'Ordering without an account', onChanged: (x) => can ? runAction(context, () => Backend.i.updateVenue(v.id, ordersAnon: x)) : managers()),
                ),
              ],
              if (!v.verified) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('Your QRs and tags open the menu once you\'re verified.', style: T.caption(bd))),
              if (!counter)
                SettingRow(
                  title: 'Capacity',
                  hint: v.capacity == null
                      ? 'How many people your licence allows inside at once. The door counter turns amber at 90% and red at full.'
                      : '${v.capacity} people. The door counter turns amber at 90% and red at full.',
                  trailing: AccentPill(v.capacity == null ? 'Set' : 'Change', onTap: () => can ? _capacity(context) : managers()),
                ),
              const SizedBox(height: S.l),
              Loader<(List<VenueArea>, List<VenueTable>)>(
                load: () async => (await Backend.i.areas(v.id), await Backend.i.tables(v.id)),
                refresh: floorRev,
                retry: true,
                builder: (context, data, loading) {
                  if (data == null) return const Skeleton(height: 200);
                  final (areas, all) = data;
                  final tables = all.where((t) => !t.isPickup).toList();
                  final points = all.where((t) => t.isPickup).toList();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (!counter)
                      for (final a in [...areas, null]) ...[
                        if (a != null || tables.any((t) => t.areaId == null)) SectionHeader(a?.name ?? 'No area'),
                        Group(children: [
                          for (final t in tables.where((t) => t.areaId == a?.id))
                            GroupTile(
                              icon: Ph.qrCode,
                              title: t.label + (t.active ? '' : ' (retired)'),
                              subtitle: '${t.seats} seats · bwdy.site/t/${t.code}',
                              chevron: true,
                              onTap: () => _table(context, t, areas),
                            ),
                        ]),
                      ],
                    const SectionHeader('Pickup points'),
                    if (points.isEmpty)
                      Text(
                        counter
                            ? 'Your counter\'s QR: customers see what you sell and — with phone orders on — order and collect by number.'
                            : 'A bar counter or a window where people order standing up: an order there gets a number to collect, shown on a ready board.',
                        style: T.caption(bd),
                      )
                    else
                      Group(children: [
                        for (final t in points)
                          GroupTile(
                            icon: Ph.storefront,
                            title: t.label + (t.active ? '' : ' (retired)'),
                            subtitle: 'pickup point · bwdy.site/t/${t.code}',
                            chevron: true,
                            onTap: () => _table(context, t, areas),
                          ),
                      ]),
                    if (can) ...[
                      const SizedBox(height: S.l),
                      if (!counter) ...[
                        BdButton('Add a table', icon: Ph.plus, onTap: () => _editTable(context, null, areas, all.length)),
                        const SizedBox(height: S.s),
                      ],
                      BdButton('Add a pickup point', icon: Ph.storefront, kind: counter ? BtnKind.primary : BtnKind.secondary, onTap: () => _editTable(context, null, areas, all.length, pickup: true)),
                      if (!counter) ...[
                        const SizedBox(height: S.s),
                        BdButton('Add an area', icon: Ph.squaresFour, kind: BtnKind.secondary, onTap: () => _addArea(context, areas.length)),
                      ],
                    ],
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _capacity(BuildContext context) async {
    final ctl = TextEditingController(text: v.capacity?.toString() ?? '');
    await showBdSheet<void>(context, title: 'Capacity', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LineField(controller: ctl, label: 'People allowed inside at once', keyboard: TextInputType.number, autofocus: true, maxLength: 5),
        const SizedBox(height: S.s),
        Text('The number on your licence or fire certificate. Leave it empty to count without a limit.', style: T.caption(ctx.bd)),
        const SizedBox(height: S.xl),
        BdButton('Save', onTap: () async {
          final raw = ctl.text.trim();
          final n = raw.isEmpty ? 0 : int.tryParse(raw);
          if (n == null || n < 0 || n > 20000) return toast(ctx, 'A number from 1 to 20,000, or leave it empty.', tone: ToastTone.error);
          final ok = await runAction(ctx, () => Backend.i.updateVenue(v.id, capacity: n));
          if (ok && ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
    ctl.dispose();
  }

  Future<void> _table(BuildContext context, VenueTable t, List<VenueArea> areas) async {
    final can = Session.instance.can(Cap.editSettings);
    await showBdSheet<void>(context, title: t.label, builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: QrBox(tableLink(t), size: 180)),
        const SizedBox(height: S.m),
        SelectableText(tableLink(t), textAlign: TextAlign.center, style: T.sans(bd, size: 14)),
        const SizedBox(height: S.s),
        Text(
          t.isPickup
              ? 'Put it on the counter. Orders here get a number; the ready board shows it when it\'s ready.'
              : 'Print it for the table, or write it to an NFC sticker. It opens your menu with the table known.',
          textAlign: TextAlign.center,
          style: T.caption(bd),
        ),
        const SizedBox(height: S.l),
        BdButton('Write an NFC sticker', icon: Ph.handTap, onTap: () => writeTagSheet(ctx, url: tableLink(t), what: t.label)),
        const SizedBox(height: S.s),
        BdButton('Share the link', icon: Ph.shareNetwork, kind: BtnKind.secondary, onTap: () => SharePlus.instance.share(ShareParams(text: '${v.name} · ${t.label}: ${tableLink(t)}'))),
        if (t.isPickup) ...[
          const SizedBox(height: S.s),
          BdButton('Ready board on this screen', icon: Ph.television, kind: BtnKind.secondary, onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReadyBoardScreen(venueName: v.name, code: t.code)));
          }),
          const SizedBox(height: S.s),
          TextAction('Share the ready board\'s link (for a TV\'s browser)', icon: Ph.monitor, onTap: () => SharePlus.instance.share(ShareParams(text: '${v.name} · ready board: ${readyLink(t)}'))),
        ],
        if (can) ...[
          const SizedBox(height: S.s),
          BdButton('Edit', kind: BtnKind.secondary, onTap: () {
            Navigator.pop(ctx);
            _editTable(context, t, areas, t.position);
          }),
          const SizedBox(height: S.s),
          BdButton('New code (retires the printed one)', kind: BtnKind.quiet, onTap: () async {
            final yes = await confirm(ctx, title: 'Retire ${t.label}\'s QR?', body: 'Every printed tag for this table stops working. Print the new one.', yes: 'New code');
            if (yes && ctx.mounted) {
              await runAction(ctx, () => Backend.i.rotateTableCode(t.id), done: 'New code — print it.');
              if (ctx.mounted) Navigator.pop(ctx);
            }
          }),
        ],
      ]);
    });
  }

  Future<void> _addArea(BuildContext context, int position) async {
    final name = TextEditingController();
    await showBdSheet<void>(context, title: 'A new area', builder: (ctx) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LineField(controller: name, label: 'Name', hint: 'Patio, Upstairs, Bar', autofocus: true, caps: TextCapitalization.words, maxLength: 40),
        const SizedBox(height: S.l),
        BdButton('Add', onTap: () async {
          final ok = await runAction(ctx, () => Backend.i.saveArea(v.id, VenueArea(id: newId(), name: name.text, position: position), isNew: true));
          if (ok && ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
    name.dispose();
  }

  Future<void> _editTable(BuildContext context, VenueTable? t, List<VenueArea> areas, int position, {bool pickup = false}) async {
    final isPickup = t?.isPickup ?? pickup;
    final label = TextEditingController(text: t?.label ?? (isPickup && v.kind.isCounter ? 'Counter' : ''));
    var seats = t?.seats ?? 4;
    String? area = t?.areaId ?? (areas.isEmpty || isPickup ? null : areas.first.id);
    var active = t?.active ?? true;
    await showBdSheet<void>(context, title: t == null ? (isPickup ? 'A new pickup point' : 'A new table') : 'Edit ${t.label}', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final bd = ctx.bd;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LineField(controller: label, label: 'Label', hint: isPickup ? 'Bar counter, Counter, Window' : 'T1, B4, Window', autofocus: t == null, maxLength: 20),
          if (!isPickup) ...[
            const SizedBox(height: S.m),
            Text('Seats', style: T.label(bd)),
            const SizedBox(height: S.s),
            Wrap(spacing: S.s, runSpacing: S.s, children: [for (final n in const [1, 2, 4, 6, 8, 10, 12]) BdChip('$n', active: seats == n, onTap: () => set(() => seats = n))]),
          ],
          if (areas.isNotEmpty && !v.kind.isCounter) ...[
            const SizedBox(height: S.m),
            Text('Area', style: T.label(bd)),
            const SizedBox(height: S.s),
            Wrap(spacing: S.s, runSpacing: S.s, children: [for (final a in areas) BdChip(a.name, active: area == a.id, onTap: () => set(() => area = a.id))]),
          ],
          if (t != null)
            SettingRow(title: 'In use', hint: 'Retire a table you no longer have; its history stays.', trailing: BdToggle(on: active, label: 'In use', onChanged: (x) => set(() => active = x))),
          const SizedBox(height: S.xl),
          BdButton('Save', onTap: () async {
            final table = VenueTable(id: t?.id ?? newId(), areaId: area, label: label.text.trim(), seats: isPickup ? 1 : seats, code: t?.code ?? '', active: active, position: position, kind: isPickup ? 'pickup' : 'table');
            final ok = await runAction(ctx, () => Backend.i.saveTable(v.id, table, isNew: t == null));
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
        ]);
      });
    });
    label.dispose();
  }
}
