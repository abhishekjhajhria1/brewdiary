// Setting up the floor — once: areas (Bar, Floor, Patio), the tables in them, and each
// table's own QR (bwdy.site/t/<code>) to print or write to an NFC tag. Scanning it opens
// the menu with the table already known; if the venue switches it on, guests can order
// and call staff from it. A new code retires every printed tag for that table.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart';
import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

String tableLink(VenueTable t) => '${Config.siteUrl}/t/${t.code}';

class FloorSetupScreen extends StatelessWidget {
  final Venue venue;
  const FloorSetupScreen({super.key, required this.venue});

  Venue get v => Session.instance.venue?.id == venue.id ? Session.instance.venue! : venue;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final can = Session.instance.can(Cap.editSettings);
    return Scaffold(
      body: Ambient(
        child: ListenableBuilder(
          listenable: Session.instance,
          builder: (context, _) => ScrollPage(
            title: 'Floor',
            subtitle: 'areas, tables, table QRs',
            back: true,
            tabBar: false,
            maxWidth: kWideMaxWidth,
            children: [
              SettingRow(
                title: 'Guests can order from the table',
                hint: 'Scanning a table\'s QR lets a signed-in guest send an order or call staff. Every order waits for your OK; staff never see who asked.',
                trailing: BdToggle(
                  on: v.tableService,
                  label: 'Ordering from the table',
                  onChanged: (x) => can ? runAction(context, () => Backend.i.updateVenue(v.id, tableService: x)) : toast(context, 'An owner or manager can change this.'),
                ),
              ),
              if (!v.verified) Text('The table QRs open the menu once you\'re verified.', style: T.caption(bd)),
              SettingRow(
                title: 'Capacity',
                hint: v.capacity == null
                    ? 'How many people your licence allows inside at once. The door counter turns amber at 90% and red at full.'
                    : '${v.capacity} people. The door counter turns amber at 90% and red at full.',
                trailing: AccentPill(v.capacity == null ? 'Set' : 'Change', onTap: () => can ? _capacity(context) : toast(context, 'An owner or manager can change this.')),
              ),
              const SizedBox(height: S.l),
              Loader<(List<VenueArea>, List<VenueTable>)>(
                load: () async => (await Backend.i.areas(v.id), await Backend.i.tables(v.id)),
                refresh: floorRev,
                retry: true,
                builder: (context, data, loading) {
                  if (data == null) return const Skeleton(height: 200);
                  final (areas, tables) = data;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                    if (can) ...[
                      const SizedBox(height: S.l),
                      BdButton('Add a table', icon: Ph.plus, onTap: () => _editTable(context, null, areas, tables.length)),
                      const SizedBox(height: S.s),
                      BdButton('Add an area', icon: Ph.squaresFour, kind: BtnKind.secondary, onTap: () => _addArea(context, areas.length)),
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
          if (n == null || n < 0 || n > 20000) return toast(ctx, 'A number from 1 to 20,000, or leave it empty.');
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
        Text('Print it for the table, or write it to an NFC tag. It opens your menu with the table known.', textAlign: TextAlign.center, style: T.caption(bd)),
        const SizedBox(height: S.l),
        BdButton('Share the link', icon: Ph.shareNetwork, onTap: () => SharePlus.instance.share(ShareParams(text: '${v.name} · ${t.label}: ${tableLink(t)}'))),
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

  Future<void> _editTable(BuildContext context, VenueTable? t, List<VenueArea> areas, int position) async {
    final label = TextEditingController(text: t?.label ?? '');
    var seats = t?.seats ?? 4;
    String? area = t?.areaId ?? (areas.isEmpty ? null : areas.first.id);
    var active = t?.active ?? true;
    await showBdSheet<void>(context, title: t == null ? 'A new table' : 'Edit ${t.label}', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final bd = ctx.bd;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LineField(controller: label, label: 'Label', hint: 'T1, B4, Window', autofocus: t == null, maxLength: 20),
          const SizedBox(height: S.m),
          Text('Seats', style: T.label(bd)),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [for (final n in const [1, 2, 4, 6, 8, 10, 12]) BdChip('$n', active: seats == n, onTap: () => set(() => seats = n))]),
          if (areas.isNotEmpty) ...[
            const SizedBox(height: S.m),
            Text('Area', style: T.label(bd)),
            const SizedBox(height: S.s),
            Wrap(spacing: S.s, runSpacing: S.s, children: [for (final a in areas) BdChip(a.name, active: area == a.id, onTap: () => set(() => area = a.id))]),
          ],
          if (t != null)
            SettingRow(title: 'In use', hint: 'Retire a table you no longer have; its history stays.', trailing: BdToggle(on: active, label: 'In use', onChanged: (x) => set(() => active = x))),
          const SizedBox(height: S.xl),
          BdButton('Save', onTap: () async {
            final table = VenueTable(id: t?.id ?? newId(), areaId: area, label: label.text.trim(), seats: seats, code: t?.code ?? '', active: active, position: position);
            final ok = await runAction(ctx, () => Backend.i.saveTable(v.id, table, isNew: t == null));
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
        ]);
      });
    });
    label.dispose();
  }
}
