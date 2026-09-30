// Your venues: pick the one you're working tonight, type the code a venue's owner gave
// you (053: they added your email; the code is the owner vouching for you), see where
// you're waiting for a yes or paused, create a venue, or ask to join with an invite code.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import '../../data/settings.dart';
import '../../logic/staff.dart';
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
            if (s.enrolments.isNotEmpty) ...[
              Text('A code to type'.toUpperCase(), style: T.section(bd)),
              const SizedBox(height: S.m),
              Group(children: [
                for (final e in s.enrolments)
                  GroupTile(
                    icon: Ph.key,
                    title: e.venueName,
                    subtitle: '${e.addedBy ?? 'A manager'} added you as ${_a(roleLabel(e.role, e.venueKind))} · type their code',
                    chevron: true,
                    onTap: () => claimCodeSheet(context, e),
                  ),
              ]),
              const SizedBox(height: S.xl),
            ],
            if (s.venues.isEmpty && s.enrolments.isEmpty && s.access.isEmpty)
              Glass(
                padding: const EdgeInsets.all(S.xl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nothing here yet', style: T.title(bd)),
                  const SizedBox(height: S.s),
                  Text('Create your venue — a bar, a restaurant, a café, a sweet shop, any shop. Or, if your manager added you, their code for you shows up here once you\'re signed in with the email they used.', style: T.bodyMuted(bd)),
                ]),
              )
            else if (s.venues.isNotEmpty)
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
            if (s.access.isNotEmpty) ...[
              const SectionHeader('Waiting and paused'),
              Group(children: [
                for (final a in s.access)
                  GroupTile(
                    icon: a.locked ? Ph.lock : Ph.hourglass,
                    title: a.venueName,
                    subtitle: a.locked ? reportLine(a.reportTo, a.reportToRole) : 'You asked to join as ${_a(roleLabel(a.role, a.venueKind))} — a manager says yes first.',
                    trailing: ToneTag(a.locked ? 'paused' : 'waiting', a.locked ? Tone.late : Tone.wait),
                    onTap: a.locked ? () => s.showLock(a) : null,
                  ),
              ]),
            ],
            const SizedBox(height: S.xl),
            BdButton('Create a venue', icon: Ph.plus, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateVenueScreen()))),
            const SizedBox(height: S.s),
            BdButton('Join with an invite code', kind: BtnKind.secondary, icon: Ph.ticket, onTap: () => _join(context)),
            const SizedBox(height: S.xl),
            Text(
              'Signed in as ${s.user?.name ?? ''}${(s.user?.handle.isNotEmpty ?? false) ? ' · @${s.user!.handle}' : ''}${(s.user?.email?.isNotEmpty ?? false) ? ' · ${s.user!.email}' : ''}. '
              'A manager who adds you uses this email — their code for you shows up here.',
              style: T.caption(bd),
            ),
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
          Text('Type the 10-letter code your manager shared. You join with the role they chose, once a manager says yes.', style: T.bodyMuted(bd)),
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
                toast(context, 'Asked to join $name — a manager will say yes.');
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

String _a(String roleWord) => roleWithArticle(roleWord);

/// The owner's code: the second step of joining a team someone added you to (053). The
/// emailed sign-in code proved the address is yours; this proves the owner meant you.
Future<void> claimCodeSheet(BuildContext context, MyEnrolment e) async {
  final code = TextEditingController();
  String? error;
  var busy = false;
  var left = e.triesLeft;
  await showBdSheet<void>(context, title: e.venueName, builder: (ctx) {
    final bd = ctx.bd;
    return StatefulBuilder(builder: (ctx, set) {
      Future<void> go() async {
        final typed = codeDigits(code.text);
        if (typed.length != 6) {
          set(() => error = 'The code is 6 digits.');
          return;
        }
        set(() {
          busy = true;
          error = null;
        });
        try {
          final r = await Backend.i.claimEnrolment(e.id, typed);
          if (r.ok) {
            await Session.instance.refreshVenues();
            final v = Session.instance.venues.where((x) => x.id == r.venueId).firstOrNull;
            if (ctx.mounted) Navigator.pop(ctx);
            if (v != null) Session.instance.select(v);
            if (context.mounted) toast(context, 'Welcome to ${r.venueName ?? e.venueName} — you\'re ${_a(roleLabel(r.role ?? e.role, e.venueKind))}.');
            return;
          }
          set(() {
            if (r.left != null) left = r.left!;
            error = claimMessage(r.error ?? ClaimError.notFound, left: r.left, addedBy: e.addedBy);
          });
          if (r.error == ClaimError.tooMany || r.error == ClaimError.expired || r.error == ClaimError.closed) {
            await Session.instance.refreshVenues(); // this code is done: take it off the list
          }
        } on BackendError catch (x) {
          set(() => error = x.message);
        } finally {
          if (ctx.mounted) set(() => busy = false);
        }
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${e.addedBy ?? 'A manager'} added you as ${_a(roleLabel(e.role, e.venueKind))}. Type the 6-digit code they gave you.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.l),
        LineField(
          controller: code,
          label: 'The owner\'s code',
          hint: '6 digits',
          keyboard: TextInputType.number,
          maxLength: 7, // room for a pasted "482 913"
          size: 24,
          autofocus: true,
          error: error,
          action: TextInputAction.done,
          onSubmitted: (_) => go(),
        ),
        const SizedBox(height: S.xl),
        BdButton('Join ${e.venueName}', busy: busy, onTap: busy ? null : go),
        const SizedBox(height: S.m),
        Text('${left == 1 ? '1 try' : '$left tries'} left · the code ${codeLifeLeft(e.expiresAt, DateTime.now())} · it only works for the email you\'re signed in with.', style: T.caption(bd)),
      ]);
    });
  });
  code.dispose();
}

/// Where a venue's features stand, in one line — used by the create and setup screens.
String legalLine(Venue v) => switch (v.legal) {
      LegalClass.noAlcohol => 'No alcohol sold here, so alcohol-promotion law doesn\'t shape your loyalty card.',
      LegalClass.offTrade => 'A liquor store: its card counts visits and its reward is never alcohol.',
      LegalClass.onTrade => 'Serves alcohol: the loyalty card follows the rules where you are.',
    };
