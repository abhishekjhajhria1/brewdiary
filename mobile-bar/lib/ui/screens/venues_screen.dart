// Your venues: pick the one you're working tonight, create one, or join a team with an
// invite code a manager shared.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import '../../data/settings.dart';
import '../../logic/venue_kinds.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'create_venue_screen.dart';

IconData kindIcon(VenueKind k) => switch (k) {
      VenueKind.bar => Ph.beerStein,
      VenueKind.club => Ph.musicNotes,
      VenueKind.restaurant => Ph.forkKnife,
      VenueKind.cafe => Ph.coffee,
      VenueKind.store => Ph.wine,
      VenueKind.sweetShop => Ph.cookie,
      VenueKind.bakery => Ph.bread,
      VenueKind.shop => Ph.storefront,
    };

class VenuesScreen extends StatelessWidget {
  const VenuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Your venues',
          tabBar: false,
          actions: [
            ThemeDot(dark: ThemeStore.instance.isDark, onTap: ThemeStore.instance.toggle),
            IconBtn(Ph.signOut, tooltip: 'Sign out', onTap: () => s.signOut()),
          ],
          onRefresh: () => s.refreshVenues(),
          children: [
            const DemoNote(),
            if (s.error != null) Padding(padding: const EdgeInsets.only(bottom: S.l), child: Text(s.error!, style: T.sans(bd, size: 14, color: bd.accentText))),
            if (s.venues.isEmpty)
              Glass(
                padding: const EdgeInsets.all(S.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nothing here yet', style: T.title(bd)),
                  const SizedBox(height: S.s),
                  Text('Create your venue — a bar, a restaurant, a café, a sweet shop, any shop — or join your team with the code your manager sent you.', style: T.bodyMuted(bd)),
                ]),
              )
            else
              Group(children: [
                for (final v in s.venues)
                  GroupTile(
                    icon: kindIcon(v.kind),
                    title: v.name,
                    subtitle: [
                      roleLabel(v.myRole, v.kind),
                      v.kind.label,
                      if (v.city != null && v.city!.isNotEmpty) v.city!,
                      if (!v.verified) 'not verified yet',
                    ].join(' · '),
                    chevron: true,
                    onTap: () => s.select(v),
                  ),
              ]),
            const SizedBox(height: S.xl),
            BdButton('Create a venue', icon: Ph.plus, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateVenueScreen()))),
            const SizedBox(height: S.s),
            BdButton('Join with an invite code', kind: BtnKind.secondary, icon: Ph.key, onTap: () => _join(context)),
            const SizedBox(height: S.xl),
            Text('Signed in as ${s.user?.name ?? ''}${(s.user?.handle.isNotEmpty ?? false) ? ' · @${s.user!.handle}' : ''}', style: T.caption(bd)),
          ],
        ),
      ),
    );
  }

  Future<void> _join(BuildContext context) async {
    final code = TextEditingController();
    await showBdSheet<void>(context, title: 'Join a team', builder: (ctx) {
      final bd = ctx.bd;
      var busy = false;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Type the 10-letter code your manager shared. You join with the role they chose.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          LineField(controller: code, label: 'Invite code', hint: 'abcd2345xy', caps: TextCapitalization.none, autofocus: true),
          const SizedBox(height: S.xl),
          BdButton('Join', busy: busy, onTap: () async {
            set(() => busy = true);
            try {
              final name = await Backend.i.acceptInvite(code.text);
              await Session.instance.refreshVenues();
              if (ctx.mounted) {
                Navigator.pop(ctx);
                toast(context, 'Welcome to $name.');
              }
            } on BackendError catch (e) {
              if (ctx.mounted) toast(ctx, e.message);
            } finally {
              if (ctx.mounted) set(() => busy = false);
            }
          }),
        ]);
      });
    });
    code.dispose();
  }
}

/// Where a venue's features stand, in one line — used by the create and setup screens.
String legalLine(Venue v) => switch (v.legal) {
      LegalClass.noAlcohol => 'No alcohol sold here, so alcohol-promotion law doesn\'t shape your loyalty card.',
      LegalClass.offTrade => 'A liquor store: its card counts visits and its reward is never alcohol.',
      LegalClass.onTrade => 'Serves alcohol: the loyalty card follows the rules where you are.',
    };
