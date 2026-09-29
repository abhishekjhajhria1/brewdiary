// The team: who's on, what each role may do, and — for an owner or manager — adding,
// promoting and removing people, or sending an invite code. The database decides who
// may grant what (can_grant_role, 045): a manager manages the floor, never another
// manager, and nobody is ever made an owner from an app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

class TeamScreen extends StatelessWidget {
  final Venue venue;
  const TeamScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final mine = venue.myRole;
    final manage = s.can(Cap.manageTeam);
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Team',
          back: true,
          tabBar: false,
          onRefresh: () async => staffRev.bump(),
          children: [
            Loader<List<StaffMember>>(
              load: () => Backend.i.staff(venue.id),
              refresh: staffRev,
              retry: true,
              builder: (context, team, loading) {
                if (team == null) return const Skeleton(height: 200);
                return Group(children: [
                  for (final m in team)
                    GroupTile(
                      title: m.id == s.user?.id ? '${m.name} (you)' : m.name,
                      subtitle: '${roleLabel(m.role, venue.kind)} · @${m.handle}',
                      trailing: manage && m.id != s.user?.id && canGrant(mine, m.role) ? Icon(Ph.dotsThree, color: bd.faint) : null,
                      onTap: manage && m.id != s.user?.id && canGrant(mine, m.role) ? () => _member(context, m) : null,
                    ),
                ]);
              },
            ),
            if (manage) ...[
              const SizedBox(height: S.xl),
              BdButton('Invite with a code', icon: Ph.key, onTap: () => _invite(context)),
              const SizedBox(height: S.s),
              BdButton('Add by name or @handle', icon: Ph.userPlus, kind: BtnKind.secondary, onTap: () => _add(context)),
            ],
            const SectionHeader('Who can do what'),
            for (final r in StaffRole.values)
              Padding(
                padding: const EdgeInsets.only(bottom: S.s),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${roleLabel(r, venue.kind)} — ', style: T.sans(bd, size: 14, weight: FontWeight.w600)),
                  TextSpan(text: roleBlurb(r), style: T.sans(bd, size: 14, color: bd.muted)),
                ])),
              ),
            if (!manage && s.venue?.myRole != StaffRole.owner) ...[
              const SizedBox(height: S.xl),
              BdButton('Leave this team', kind: BtnKind.quiet, onTap: () async {
                final yes = await confirm(context, title: 'Leave ${venue.name}?', body: 'You\'ll need a new invite to come back.', yes: 'Leave');
                if (!yes || !context.mounted) return;
                final ok = await runAction(context, () => Backend.i.removeStaff(venue.id, s.user!.id));
                if (ok) await s.refreshVenues();
              }),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _member(BuildContext context, StaffMember m) async {
    final mine = venue.myRole;
    await showActions(context, title: m.name, message: roleBlurb(m.role), actions: [
      for (final r in grantable(mine))
        if (r != m.role) SheetAction('Make ${roleLabel(r, venue.kind).toLowerCase()}', icon: Ph.userGear, onTap: () => runAction(context, () => Backend.i.setStaffRole(venue.id, m.id, r), done: '${m.name} is now ${roleLabel(r, venue.kind).toLowerCase()}.')),
      SheetAction('Remove from the team', icon: Ph.userMinus, destructive: true, onTap: () async {
        final yes = await confirm(context, title: 'Remove ${m.name}?', body: 'Their access ends at once. What they recorded stays.', yes: 'Remove');
        if (yes && context.mounted) await runAction(context, () => Backend.i.removeStaff(venue.id, m.id), done: '${m.name} is off the team.');
      }),
    ]);
  }

  Future<void> _invite(BuildContext context) async {
    final roles = grantable(venue.myRole);
    var role = roles.contains(StaffRole.server) ? StaffRole.server : roles.last;
    StaffInvite? invite;
    await showBdSheet<void>(context, title: 'Invite someone', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        if (invite != null) {
          final text = 'Join ${venue.name} on brewdiary bar as ${roleLabel(invite!.role, venue.kind).toLowerCase()}: open the app and use the code ${invite!.code}';
          return Column(children: [
            QrBox(invite!.code, size: 180),
            const SizedBox(height: S.l),
            SelectableText(invite!.code, style: T.serif(bd, size: 32).copyWith(letterSpacing: 3)),
            const SizedBox(height: S.s),
            Text('One use, for a ${roleLabel(invite!.role, venue.kind).toLowerCase()}. Good for 7 days.', style: T.caption(bd)),
            const SizedBox(height: S.l),
            BdButton('Share the code', icon: Ph.shareNetwork, onTap: () => SharePlus.instance.share(ShareParams(text: text))),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('They join with the role you pick. No need to know their @handle.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final r in roles) BdChip(roleLabel(r, venue.kind), active: role == r, onTap: () => set(() => role = r)),
          ]),
          const SizedBox(height: S.s),
          Text(roleBlurb(role), style: T.caption(bd)),
          const SizedBox(height: S.xl),
          BdButton('Make a code', onTap: () async {
            try {
              final i = await Backend.i.createInvite(venue.id, role);
              set(() => invite = i);
            } on BackendError catch (e) {
              if (ctx.mounted) toast(ctx, e.message);
            }
          }),
        ]);
      });
    });
  }

  Future<void> _add(BuildContext context) async {
    final q = TextEditingController();
    final roles = grantable(venue.myRole);
    var role = roles.contains(StaffRole.bartender) ? StaffRole.bartender : roles.last;
    List<ProfileHit> hits = const [];
    Timer? debounce;
    await showBdSheet<void>(context, title: 'Add to the team', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final r in roles) BdChip(roleLabel(r, venue.kind), active: role == r, onTap: () => set(() => role = r)),
          ]),
          const SizedBox(height: S.m),
          GlassField(
            controller: q,
            hint: 'Name or @handle',
            icon: Ph.magnifyingGlass,
            caps: TextCapitalization.none,
            autofocus: true,
            onChanged: (text) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), () async {
                try {
                  final r = await Backend.i.searchPeople(text);
                  set(() => hits = r);
                } catch (_) {}
              });
            },
          ),
          const SizedBox(height: S.s),
          for (final p in hits)
            GroupTile(
              title: p.name,
              subtitle: '@${p.handle}',
              trailing: AccentPill('Add', onTap: () async {
                final ok = await runAction(ctx, () => Backend.i.addStaff(venue.id, p.id, role), done: '${p.name} joined as ${roleLabel(role, venue.kind).toLowerCase()}.');
                if (ok && ctx.mounted) Navigator.pop(ctx);
              }),
            ),
          if (hits.isEmpty) Text('Tip: an invite code is easier — they don\'t need to tell you their handle.', style: T.caption(bd)),
        ]);
      });
    });
    debounce?.cancel();
    q.dispose();
  }
}
