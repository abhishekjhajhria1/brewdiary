// More — the rest of the venue: the team, the loyalty card, setup, your shift (clock in
// and out), your own thanks, switching venue, and the theme.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../data/settings.dart';
import '../../logic/roles.dart';
import '../../logic/venue_kinds.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'excise_screen.dart';
import 'floor_setup_screen.dart';
import 'perks_screen.dart';
import 'setup_screen.dart';
import 'staff_hours_screen.dart';
import 'stock_screen.dart';
import 'team_screen.dart';

class MoreScreen extends StatelessWidget {
  final Venue venue;
  const MoreScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ScrollPage(
      title: 'More',
      subtitle: '${venue.name} · ${roleLabel(venue.myRole, venue.kind)}',
      children: [
        const DemoNote(),
        Group(children: [
          GroupTile(
            icon: Ph.usersThree,
            title: 'Team',
            subtitle: s.can(Cap.manageTeam) ? 'Add employees, roles, pause access, hours, history' : 'Who you work with, your hours',
            chevron: true,
            onTap: () => push(TeamScreen(venue: venue)),
          ),
          if (!venue.kind.isCounter && (s.can(Cap.editSettings) || s.can(Cap.floorView)))
            GroupTile(icon: Ph.squaresFour, title: 'Floor setup', subtitle: 'Areas, tables, table QRs, ordering from the table', chevron: true, onTap: () => push(FloorSetupScreen(venue: venue))),
          if (venue.kind.isCounter && (s.can(Cap.countStock) || s.can(Cap.receiveStock) || s.can(Cap.editMenu)))
            GroupTile(icon: Ph.package, title: 'Stock', subtitle: 'What you sell, deliveries, suppliers', chevron: true, onTap: () => push(StockScreen(venue: venue))),
          if (venue.kind == VenueKind.store && s.can(Cap.reports))
            GroupTile(icon: Ph.receipt, title: 'Excise register', subtitle: 'Opening, in, sold, closing — as CSV', chevron: true, onTap: () => push(ExciseScreen(venue: venue))),
          if (s.can(Cap.editPerks)) GroupTile(icon: Ph.gift, title: 'Loyalty card', subtitle: 'Reward tiers and quiet nights', chevron: true, onTap: () => push(PerksScreen(venue: venue))),
          if (s.can(Cap.editSettings) || s.can(Cap.requestVerification))
            GroupTile(icon: Ph.slidersHorizontal, title: 'Setup', subtitle: venue.verified ? 'Details, location' : 'Details, location, verification', chevron: true, onTap: () => push(SetupScreen(venue: venue))),
        ]),
        if (s.can(Cap.ownShift)) ...[
          const SectionHeader('Your shift'),
          ShiftCard(venue: venue),
        ],
        const SectionHeader('Your thanks'),
        _MyThanks(venue: venue),
        const SectionHeader('This phone'),
        Group(children: [
          SettingRow(
            title: 'Dark theme',
            hint: 'Bars are dark — this is the default.',
            trailing: BdToggle(on: ThemeStore.instance.isDark, label: 'Dark theme', onChanged: (_) => ThemeStore.instance.toggle()),
          ),
          if (s.venues.length > 1 || true) GroupTile(icon: Ph.storefront, title: 'Switch venue', chevron: true, onTap: s.leaveVenue),
          GroupTile(icon: Ph.signOut, title: 'Sign out', onTap: () async {
            final yes = await confirm(context, title: 'Sign out?', body: 'You\'ll need your email to get back in.', yes: 'Sign out');
            if (yes) await s.signOut();
          }),
        ]),
        const SizedBox(height: S.l),
        Text('Signed in as ${s.user?.name ?? ''}${(s.user?.handle.isNotEmpty ?? false) ? ' · @${s.user!.handle}' : ''}', style: T.caption(bd)),
      ],
    );
  }
}

class _MyThanks extends StatelessWidget {
  final Venue venue;
  const _MyThanks({required this.venue});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final me = Session.instance.user?.id;
    return Loader<(List<KudosLine>, bool)>(
      load: () async {
        final lines = await Backend.i.myKudos(venue.id);
        final team = await Backend.i.staff(venue.id);
        final mine = team.where((m) => m.id == me).firstOrNull;
        return (lines, mine?.thankable ?? true);
      },
      refresh: staffRev,
      builder: (context, data, loading) {
        if (data == null) return const Skeleton(height: 90);
        final (lines, thankable) = data;
        final total = lines.fold<int>(0, (n, l) => n + l.n);
        return Glass(
          padding: const EdgeInsets.all(S.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(total == 0 ? 'No thanks yet — they\'ll show up here.' : 'Guests thanked you $total ${total == 1 ? 'time' : 'times'}.', style: T.row(bd)),
            for (final l in lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${l.reason} · ${l.n}', style: T.caption(bd))),
            const SizedBox(height: S.s),
            SettingRow(
              title: 'Guests can thank me',
              hint: 'Off means you vanish from the thank-you list. Only you see your thanks; your manager sees one number for the whole team.',
              trailing: BdToggle(on: thankable, label: 'Guests can thank me', onChanged: (v) => runAction(context, () => Backend.i.setThankable(venue.id, v))),
            ),
          ]),
        );
      },
    );
  }
}
