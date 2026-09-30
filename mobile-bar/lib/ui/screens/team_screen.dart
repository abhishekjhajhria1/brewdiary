// The team: who's on and what each role may do — and, for an owner or manager, running
// it (053):
//   • ADD AN EMPLOYEE with their name, email, phone and role. brewdiary makes a 6-digit
//     code, shown here once; the employee signs in with that email and types it, and is
//     on the team with the role you chose. The code works only for that email.
//   • say yes (or no) to someone who used a shared invite code;
//   • PAUSE someone's access at any moment, with a reason and who they should report to.
//     Every screen and every call stops for them at once, and they're clocked out;
//   • their details (the name you use, a phone to call), the hours, the history.
// The database decides every one of these (venue_can, can_grant_role): a manager runs the
// floor, never another manager, and nobody is made an owner from an app.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/staff.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'locked_screen.dart' show staffWhen;
import 'payroll_screen.dart' show payRateSheet;
import 'staff_history_screen.dart';
import 'staff_hours_screen.dart';
import 'timesheet_screen.dart';

class TeamScreen extends StatelessWidget {
  final Venue venue;
  const TeamScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final manage = s.can(Cap.manageTeam);
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      body: Ambient(
        child: ScrollPage(
          title: 'Team',
          back: true,
          tabBar: false,
          onRefresh: () async => staffRev.bump(),
          children: [
            const DemoNote(),
            if (manage) ...[
              BdButton('Add an employee', icon: Ph.userPlus, onTap: () => addEmployeeSheet(context, venue)),
              const SizedBox(height: S.s),
              BdButton('Invite with a shared code', icon: Ph.ticket, kind: BtnKind.secondary, onTap: () => _invite(context)),
              const SizedBox(height: S.s),
            ],
            Loader<(List<StaffMember>, List<Enrolment>)>(
              load: () async {
                final team = await Backend.i.staff(venue.id);
                var codes = const <Enrolment>[];
                if (manage) {
                  try {
                    codes = await Backend.i.openEnrolments(venue.id);
                  } on BackendError catch (e) {
                    if (e.code != 'needs_update') rethrow; // a database before 053: no codes to show
                  }
                }
                return (team, codes);
              },
              refresh: staffRev,
              retry: true,
              builder: (context, data, loading) {
                if (data == null) return const Padding(padding: EdgeInsets.only(top: S.xl), child: Skeleton(height: 200));
                final (team, codes) = data;
                final waiting = team.where((m) => m.status == StaffStatus.pending).toList();
                final on = team.where((m) => m.status == StaffStatus.active).toList();
                final paused = team.where((m) => m.status == StaffStatus.locked).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (waiting.isNotEmpty) ...[
                    const SectionHeader('Waiting for your yes'),
                    Group(children: [for (final m in waiting) _waitingTile(context, m)]),
                  ],
                  if (codes.isNotEmpty) ...[
                    const SectionHeader('Added, not in yet'),
                    Group(children: [for (final e in codes) _codeTile(context, e)]),
                  ],
                  SectionHeader('On the team', trailing: Text('${on.length}', style: T.section(bd))),
                  Group(children: [for (final m in on) _memberTile(context, m, team)]),
                  if (paused.isNotEmpty) ...[
                    const SectionHeader('Paused'),
                    Group(children: [for (final m in paused) _memberTile(context, m, team)]),
                  ],
                ]);
              },
            ),
            if (s.can(Cap.editRota) || s.can(Cap.auditLog) || s.can(Cap.ownShift)) ...[
              const SectionHeader('Records'),
              Group(children: [
                if (s.can(Cap.editRota) || s.can(Cap.ownShift))
                  GroupTile(
                    icon: Ph.clock,
                    title: s.can(Cap.editRota) ? 'Hours' : 'My hours',
                    subtitle: s.can(Cap.editRota) ? 'Who\'s on now, and the week by name — for pay' : 'Your time on the clock here',
                    chevron: true,
                    onTap: () => push(StaffHoursScreen(venue: venue)),
                  ),
                if (s.can(Cap.auditLog))
                  GroupTile(
                    icon: Ph.clockCounterClockwise,
                    title: 'Team history',
                    subtitle: 'Who joined, was approved, paused, changed role — and by whom',
                    chevron: true,
                    onTap: () => push(StaffHistoryScreen(venue: venue)),
                  ),
              ]),
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
                final yes = await confirm(context, title: 'Leave ${venue.name}?', body: 'You\'ll need to be added again to come back.', yes: 'Leave');
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

  String _role(StaffRole r) => roleLabel(r, venue.kind);

  /// Someone who used a shared invite code. Saying yes is a security decision, so it's a
  /// deliberate tap: the sheet says who they are and how they asked before the button.
  Widget _waitingTile(BuildContext context, StaffMember m) {
    final bd = context.bd;
    final canAnswer = canGrant(venue.myRole, m.role);
    return GroupTile(
      icon: Ph.hourglass,
      title: m.name,
      subtitle: '${_role(m.role)} · @${m.handle}',
      trailing: canAnswer ? const ToneTag('asked to join', Tone.wait) : Text('a manager answers', style: T.caption(bd)),
      onTap: canAnswer
          ? () => showActions(
                context,
                title: m.name,
                message: '@${m.handle} asked to join as ${roleWithArticle(_role(m.role))}${m.joinedAt != null ? ' ${staffWhen(m.joinedAt!)}' : ''}, with a shared invite code. Say yes only if you know who this is.',
                actions: [
                  SheetAction('Approve as ${roleWithArticle(_role(m.role))}', icon: Ph.userCheck, onTap: () => runAction(context, () => Backend.i.approveStaff(venue.id, m.id), done: '${m.name} is on the team as ${roleWithArticle(_role(m.role))}.')),
                  SheetAction('Say no', icon: Ph.prohibit, destructive: true, onTap: () => runAction(context, () => Backend.i.declineStaff(venue.id, m.id), done: 'Said no to ${m.name}.')),
                ],
              )
          : null,
    );
  }

  Widget _codeTile(BuildContext context, Enrolment e) {
    final bd = context.bd;
    final state = e.usedUp
        ? '5 wrong tries — make a new code'
        : e.expired
            ? 'code ran out — make a new one'
            : 'code ${codeLifeLeft(e.expiresAt, DateTime.now())}';
    return GroupTile(
      icon: Ph.key,
      title: e.name,
      subtitle: '${_role(e.role)} · ${e.email} · $state',
      trailing: (e.usedUp || e.expired) ? const ToneTag('new code', Tone.wait) : Icon(Ph.dotsThree, color: bd.faint),
      onTap: () => showActions(context, title: e.name, message: '${_role(e.role)} · ${e.email}${e.addedBy != null ? ' · added by ${e.addedBy}' : ''}', actions: [
        SheetAction('Make a new code', icon: Ph.key, onTap: () async {
          try {
            final c = await Backend.i.reissueCode(e.id);
            if (context.mounted) await showCodeSheet(context, venue: venue, name: e.name, email: e.email, role: e.role, code: c);
          } on BackendError catch (x) {
            if (context.mounted) toast(context, x.message);
          }
        }),
        SheetAction('Cancel their code', icon: Ph.prohibit, destructive: true, onTap: () async {
          final yes = await confirm(context, title: 'Cancel ${e.name}\'s code?', body: 'It stops working at once. You can add them again later.', yes: 'Cancel code', no: 'Keep it');
          if (yes && context.mounted) await runAction(context, () => Backend.i.revokeEnrolment(e.id), done: '${e.name}\'s code is cancelled.');
        }),
      ]),
    );
  }

  Widget _memberTile(BuildContext context, StaffMember m, List<StaffMember> team) {
    final bd = context.bd;
    final s = Session.instance;
    final me = m.id == s.user?.id;
    final runs = s.can(Cap.manageTeam) && !me && canGrant(venue.myRole, m.role);
    final bits = <String>[
      _role(m.role),
      if (m.handle.isNotEmpty) '@${m.handle}',
      if (m.onShift && m.status == StaffStatus.active) 'on since ${_hm(m.onShiftSince!)}',
      if (m.status == StaffStatus.locked) reportLine(m.reportTo, null).replaceAll('Please report', 'reports').replaceAll('.', ''),
    ];
    return GroupTile(
      title: me ? youLabel(m.name) : m.name,
      subtitle: bits.join(' · '),
      trailing: m.status == StaffStatus.locked
          ? const ToneTag('paused', Tone.late)
          : m.onShift
              ? const ToneTag('on shift', Tone.good)
              : (runs || me)
                  ? Icon(Ph.dotsThree, color: bd.faint)
                  : null,
      onTap: runs
          ? () => _member(context, m, team)
          : me
              ? () => _self(context, m)
              : null,
    );
  }

  Future<void> _self(BuildContext context, StaffMember m) => showActions(context, title: m.name, message: roleBlurb(m.role), actions: [
        SheetAction('My details here', icon: Ph.identificationBadge, onTap: () => _details(context, m)),
        if (Session.instance.can(Cap.ownShift))
          SheetAction('My timesheet', icon: Ph.listChecks, onTap: () async => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimesheetScreen(venue: venue, userId: m.id, name: m.name)))),
        if (Session.instance.can(Cap.ownShift) || Session.instance.can(Cap.auditLog))
          SheetAction('My history here', icon: Ph.clockCounterClockwise, onTap: () async => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffHistoryScreen(venue: venue, userId: m.id, name: m.name)))),
      ]);

  Future<void> _member(BuildContext context, StaffMember m, List<StaffMember> team) async {
    final s = Session.instance;
    final mine = venue.myRole;
    final locked = m.status == StaffStatus.locked;
    await showActions(context, title: m.name, message: locked ? _lockNote(m) : roleBlurb(m.role), actions: [
      if (locked) ...[
        SheetAction('Give access again', icon: Ph.key, onTap: () => runAction(context, () => Backend.i.unlockStaff(venue.id, m.id), done: '${m.name} can use the app here again.')),
        SheetAction('Change the message', icon: Ph.notePencil, onTap: () => _lock(context, m, team)),
      ] else ...[
        for (final r in grantable(mine))
          if (r != m.role) SheetAction('Make ${_role(r).toLowerCase()}', icon: Ph.userGear, onTap: () => runAction(context, () => Backend.i.setStaffRole(venue.id, m.id, r), done: '${m.name} is now ${_role(r).toLowerCase()}.')),
        SheetAction('Pause their access', icon: Ph.lock, onTap: () => _lock(context, m, team)),
        if (m.onShift && s.can(Cap.editRota))
          SheetAction('Clock them out', icon: Ph.clock, onTap: () => runAction(context, () => Backend.i.endShift(venue.id, m.id), done: '${m.name} is clocked out.')),
      ],
      if (m.phone != null && m.phone!.isNotEmpty) SheetAction('Call ${m.phone}', icon: Ph.phone, onTap: () => _call(context, m.phone!)),
      SheetAction('Their details', icon: Ph.identificationBadge, onTap: () => _details(context, m)),
      if (s.can(Cap.editRota))
        SheetAction('Their timesheet', icon: Ph.listChecks, onTap: () async => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TimesheetScreen(venue: venue, userId: m.id, name: m.name)))),
      if (s.can(Cap.manageTeam) && m.role != StaffRole.owner && canGrant(mine, m.role))
        SheetAction('Their pay', icon: Ph.wallet, onTap: () => payRateSheet(context, venue, userId: m.id, name: m.name)),
      if (s.can(Cap.auditLog))
        SheetAction('Their history', icon: Ph.clockCounterClockwise, onTap: () async => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffHistoryScreen(venue: venue, userId: m.id, name: m.name)))),
      SheetAction('Remove from the team', icon: Ph.userMinus, destructive: true, onTap: () async {
        final yes = await confirm(context, title: 'Remove ${m.name}?', body: 'Their access ends at once. What they recorded stays. To bring them back you\'d add them again.', yes: 'Remove');
        if (yes && context.mounted) await runAction(context, () => Backend.i.removeStaff(venue.id, m.id), done: '${m.name} is off the team.');
      }),
    ]);
  }

  String _lockNote(StaffMember m) => [
        'Paused${m.lockedAt != null ? ' ${staffWhen(m.lockedAt!)}' : ''}.',
        if (m.lockReason != null && m.lockReason!.isNotEmpty) '"${m.lockReason}"',
        reportLine(m.reportTo, null).replaceAll('Please report', 'Reports'),
      ].join(' ');

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
    var ok = false;
    try {
      ok = await launchUrl(uri);
    } catch (_) {}
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (context.mounted) toast(context, 'Copied $phone.');
    }
  }

  /// Pause someone's access, or change what their paused screen says.
  Future<void> _lock(BuildContext context, StaffMember m, List<StaffMember> team) async {
    final me = Session.instance.user?.id;
    final why = TextEditingController(text: m.status == StaffStatus.locked ? (m.lockReason ?? '') : '');
    // Who they can be asked to report to: an owner or a manager here, working now.
    final bosses = team.where((x) => x.status == StaffStatus.active && x.role.isManagement).toList();
    var reportTo = bosses.where((x) => x.id == me).firstOrNull?.id ?? (bosses.isEmpty ? null : bosses.first.id);
    var busy = false;
    await showBdSheet<void>(context, title: m.status == StaffStatus.locked ? 'Change ${m.name}\'s message' : 'Pause ${m.name}\'s access', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (m.status != StaffStatus.locked) ...[
            Text('Everything here stops for them at once — the floor, tabs, the guest book — and they\'re clocked out. They see your message and who to report to. Nothing they recorded is lost.', style: T.bodyMuted(bd)),
            const SizedBox(height: S.l),
          ],
          LineField(controller: why, label: 'Why (they\'ll see this)', hint: 'Come and see me before your next shift', maxLength: 200, maxLines: 2),
          const SizedBox(height: S.l),
          const Label('Report to'),
          const SizedBox(height: S.s),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final b in bosses) BdChip(b.id == me ? 'Me' : b.name, active: reportTo == b.id, onTap: () => set(() => reportTo = b.id)),
          ]),
          const SizedBox(height: S.xl),
          BdButton(m.status == StaffStatus.locked ? 'Save the message' : 'Pause access', icon: Ph.lock, busy: busy, onTap: busy
              ? null
              : () async {
                  set(() => busy = true);
                  final ok = await runAction(ctx, () => Backend.i.lockStaff(venue.id, m.id, reason: why.text, reportTo: reportTo), done: m.status == StaffStatus.locked ? 'Message updated.' : '${m.name} is paused.');
                  if (ctx.mounted) {
                    set(() => busy = false);
                    if (ok) Navigator.pop(ctx);
                  }
                }),
        ]);
      });
    });
    why.dispose();
  }

  /// The name the venue uses for someone, and a phone number to reach them.
  Future<void> _details(BuildContext context, StaffMember m) async {
    final name = TextEditingController(text: m.name);
    final phone = TextEditingController(text: m.phone ?? '');
    String? phoneErr;
    await showBdSheet<void>(context, title: m.id == Session.instance.user?.id ? 'My details here' : '${m.name}\'s details', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Only owners, managers and ${m.id == Session.instance.user?.id ? 'you' : 'they'} see the phone number.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          LineField(controller: name, label: 'Name at work', caps: TextCapitalization.words, maxLength: 60),
          const SizedBox(height: S.l),
          LineField(controller: phone, label: 'Phone (optional)', hint: '+91 98765 43210', keyboard: TextInputType.phone, caps: TextCapitalization.none, error: phoneErr),
          const SizedBox(height: S.xl),
          BdButton('Save', onTap: () async {
            if (phone.text.trim().isNotEmpty && !validStaffPhone(phone.text)) {
              set(() => phoneErr = 'That phone number doesn\'t look right.');
              return;
            }
            final ok = await runAction(ctx, () => Backend.i.setStaffDetails(venue.id, m.id, name: name.text, phone: phone.text), done: 'Saved.');
            if (ok && ctx.mounted) Navigator.pop(ctx);
          }),
        ]);
      });
    });
    name.dispose();
    phone.dispose();
  }

  Future<void> _invite(BuildContext context) async {
    final roles = grantable(venue.myRole);
    var role = roles.contains(StaffRole.server) ? StaffRole.server : roles.last;
    StaffInvite? invite;
    await showBdSheet<void>(context, title: 'Invite with a shared code', builder: (ctx) {
      final bd = ctx.bd;
      return StatefulBuilder(builder: (ctx, set) {
        if (invite != null) {
          final text = 'Join ${venue.name} on brewdiary bar as ${roleLabel(invite!.role, venue.kind).toLowerCase()}: open the app and use the code ${invite!.code}';
          return Column(children: [
            QrBox(invite!.code, size: 180),
            const SizedBox(height: S.l),
            SelectableText(invite!.code, style: T.serif(bd, size: 32).copyWith(letterSpacing: 3)),
            const SizedBox(height: S.s),
            Text('One use, for a ${roleLabel(invite!.role, venue.kind).toLowerCase()}. Good for 7 days. They wait for your yes before they can do anything.', style: T.caption(bd), textAlign: TextAlign.center),
            const SizedBox(height: S.l),
            BdButton('Share the code', icon: Ph.shareNetwork, onTap: () => SharePlus.instance.share(ShareParams(text: text))),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('For a group chat or a notice: anyone with the code can ask to join, and you say yes or no. To add one person you know, "Add an employee" is safer.', style: T.bodyMuted(bd)),
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
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "Priya (you)" — without doubling a name that already says so ("You (demo)").
String youLabel(String name) => name.toLowerCase().startsWith('you') ? name : '$name (you)';

/// Add an employee: their details and the role, then their code — shown once.
Future<void> addEmployeeSheet(BuildContext context, Venue venue) async {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final roles = grantable(venue.myRole);
  var role = roles.contains(StaffRole.server) ? StaffRole.server : roles.last;
  String? nameErr, emailErr, phoneErr;
  var busy = false;
  StaffCode? made;
  await showBdSheet<void>(context, title: 'Add an employee', builder: (ctx) {
    final bd = ctx.bd;
    return StatefulBuilder(builder: (ctx, set) {
      if (made != null) {
        return _CodeView(venue: venue, name: name.text.trim(), email: email.text.trim().toLowerCase(), role: role, code: made!);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('They sign in to brewdiary bar with this email, then type the code you\'re about to get. Only then are they on the team — as the role you pick.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.l),
        LineField(controller: name, label: 'Their name', hint: 'Rahul Sharma', caps: TextCapitalization.words, maxLength: 60, error: nameErr, autofocus: true),
        const SizedBox(height: S.l),
        LineField(controller: email, label: 'Their email', hint: 'rahul@gmail.com', keyboard: TextInputType.emailAddress, caps: TextCapitalization.none, error: emailErr),
        const SizedBox(height: S.l),
        LineField(controller: phone, label: 'Phone (optional)', hint: '+91 98765 43210', keyboard: TextInputType.phone, caps: TextCapitalization.none, error: phoneErr),
        const SizedBox(height: S.l),
        const Label('Role'),
        const SizedBox(height: S.s),
        Wrap(spacing: S.s, runSpacing: S.s, children: [
          for (final r in roles) BdChip(roleLabel(r, venue.kind), active: role == r, onTap: () => set(() => role = r)),
        ]),
        const SizedBox(height: S.s),
        Text(roleBlurb(role), style: T.caption(bd)),
        const SizedBox(height: S.xl),
        BdButton('Make their code', icon: Ph.key, busy: busy, onTap: busy
            ? null
            : () async {
                set(() {
                  nameErr = name.text.trim().isEmpty ? 'Add their name.' : null;
                  emailErr = validStaffEmail(email.text) ? null : 'That email doesn\'t look right.';
                  phoneErr = phone.text.trim().isEmpty || validStaffPhone(phone.text) ? null : 'That phone number doesn\'t look right.';
                });
                if (nameErr != null || emailErr != null || phoneErr != null) return;
                set(() => busy = true);
                try {
                  final c = await Backend.i.enrolStaff(venue.id, name: name.text, email: email.text, phone: phone.text, role: role);
                  set(() => made = c);
                } on BackendError catch (e) {
                  if (ctx.mounted) toast(ctx, e.message);
                } finally {
                  if (ctx.mounted) set(() => busy = false);
                }
              }),
      ]);
    });
  });
  name.dispose();
  email.dispose();
  phone.dispose();
}

/// A code that was just made (or made again), in a sheet of its own.
Future<void> showCodeSheet(BuildContext context, {required Venue venue, required String name, required String email, required StaffRole role, required StaffCode code}) =>
    showBdSheet<void>(context, title: 'A new code for $name', builder: (ctx) => _CodeView(venue: venue, name: name, email: email, role: role, code: code));

class _CodeView extends StatelessWidget {
  final Venue venue;
  final String name;
  final String email;
  final StaffRole role;
  final StaffCode code;
  const _CodeView({required this.venue, required this.name, required this.email, required this.role, required this.code});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final spaced = code.code.length == 6 ? '${code.code.substring(0, 3)} ${code.code.substring(3)}' : code.code;
    final text = enrolShareText(venue: venue.name, roleWord: roleLabel(role, venue.kind), email: email, code: code.code);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('$name\'s code', style: T.bodyMuted(bd), textAlign: TextAlign.center),
      const SizedBox(height: S.m),
      Semantics(
        label: 'Code ${code.code.split('').join(' ')}',
        child: SelectableText(spaced, textAlign: TextAlign.center, style: T.serif(bd, size: 44).copyWith(letterSpacing: 6, fontFeatures: T.tnum)),
      ),
      const SizedBox(height: S.m),
      Text('Shown once — share it now, or tell them in person. It works only for $email, for 48 hours, with 5 tries.', style: T.caption(bd), textAlign: TextAlign.center),
      const SizedBox(height: S.xl),
      BdButton('Share the code', icon: Ph.shareNetwork, onTap: () => SharePlus.instance.share(ShareParams(text: text))),
      const SizedBox(height: S.s),
      BdButton('Done', kind: BtnKind.secondary, onTap: () => Navigator.pop(context)),
    ]);
  }
}
