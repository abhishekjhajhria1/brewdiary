// Plans — a port of src/components/together/Plans.tsx. Two halves: COMING UP (plans
// I may see and ask to join) and MINE (plans I host, where I approve who comes).
// Only ever friends or friends-of-friends — no public/stranger option, enforced by
// the database. Safety is first-class: every person carries block/report, join is a
// request the host approves, and "fit" is soft facts — never a rating.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/friends.dart';
import '../../data/plans.dart';
import '../../data/safety.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';
import '../widgets/social.dart';

const _policyHint = {
  JoinPolicy.private: 'A private note on your calendar — no one else sees it.',
  JoinPolicy.invite: 'Only the friends you pick can see it and ask to join.',
  JoinPolicy.friends: 'Any of your friends can see it and ask to join.',
  JoinPolicy.fof: 'Friends, and their friends, can ask to join.',
};
const _policyShort = {JoinPolicy.private: 'Just me', JoinPolicy.invite: 'Invite only', JoinPolicy.friends: 'Friends', JoinPolicy.fof: 'Friends of friends'};
const _policyIcon = {JoinPolicy.private: Ph.lock, JoinPolicy.invite: Ph.userCheck, JoinPolicy.friends: Ph.users, JoinPolicy.fof: Ph.usersThree};

String _prettyDate(String key) {
  final d = parseKey(key);
  if (key == todayKey()) return 'Tonight';
  return '${weekdays[mondayIndex(d)]} ${d.day} ${monthNames[d.month - 1].substring(0, 3)}';
}

/// "18:30" → "6:30 pm".
String? _prettyTime(String? t) {
  if (t == null || t.isEmpty) return null;
  final p = t.split(':');
  final hr = int.tryParse(p[0]);
  if (hr == null) return null;
  final h12 = hr % 12 == 0 ? 12 : hr % 12;
  return '$h12:${p.length > 1 ? p[1] : '00'} ${hr < 12 ? 'am' : 'pm'}';
}

class PlansSection extends StatefulWidget {
  const PlansSection({super.key});
  @override
  State<PlansSection> createState() => _PlansSectionState();
}

class _PlansSectionState extends State<PlansSection> {
  bool _mine = false;

  @override
  Widget build(BuildContext context) {
    return Loader<({bool banned, String? suspendedUntil})?>(
      refresh: safetyRev,
      load: SafetyApi.mySanction,
      builder: (context, sanction, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: S.l),
          if (sanction != null) _SanctionBanner(banned: sanction.banned, until: sanction.suspendedUntil),
          Row(children: [
            Expanded(child: Segmented<bool>(options: const [(false, 'Coming up'), (true, 'Mine')], value: _mine, onChanged: (v) => setState(() => _mine = v))),
            if (sanction == null) ...[
              const SizedBox(width: S.s),
              BdButton('Plan a night', expand: false, height: 40, icon: Ph.calendarPlus, onTap: () => showBdSheet(context, title: 'Plan a night', builder: (_) => const _CreatePlan())),
            ],
          ]),
          const SizedBox(height: S.m),
          if (_mine) const _Mine() else const _ComingUp(),
        ]);
      },
    );
  }
}

class _SanctionBanner extends StatelessWidget {
  final bool banned;
  final String? until;
  const _SanctionBanner({required this.banned, this.until});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final u = until == null ? null : DateTime.tryParse(until!);
    final untilText = u == null ? null : '${monthNames[u.month - 1].substring(0, 3)} ${u.day}';
    return Glass(
      margin: const EdgeInsets.only(bottom: S.l),
      padding: const EdgeInsets.all(S.l),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Ph.warningCircle, size: 22, color: bd.accentText),
        const SizedBox(width: S.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(banned ? 'Your account is limited.' : 'Your account is paused for now.', style: T.row(bd)),
            const SizedBox(height: 4),
            Text(
              'You can still look around, but planning and joining are off${!banned && untilText != null ? ' until $untilText' : ''}. If you think this is a mistake, reach out through the help link.',
              style: T.caption(bd),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ComingUp extends StatelessWidget {
  const _ComingUp();
  @override
  Widget build(BuildContext context) {
    return Loader<List<Plan>>(
      refresh: plansRev,
      load: PlansApi.upcoming,
      builder: (context, plans, loading) {
        if (plans == null) return const Column(children: [Skeleton(height: 160), SizedBox(height: S.m), Skeleton(height: 160)]);
        if (plans.isEmpty) {
          return const EmptyNote('No plans from your circle yet. When a friend (or a friend of a friend) plans a night, it shows up here — or start one yourself.', icon: Ph.calendarBlank);
        }
        return Column(children: [
          for (var i = 0; i < plans.length; i++) ...[
            if (i > 0) const SizedBox(height: S.m),
            PlanCard(plan: plans[i]),
          ],
        ]);
      },
    );
  }
}

/// A plan from your circle: what, when, who's hosting, soft comfort cues, and the
/// one action that fits your state (ask, going, waiting, full…).
class PlanCard extends StatefulWidget {
  final Plan plan;
  const PlanCard({super.key, required this.plan});
  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  bool _busy = false;
  String? _err;

  Future<void> _run(Future<String?> Function() f) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await f();
    if (mounted) {
      setState(() {
        _busy = false;
        _err = e;
      });
    }
  }

  Widget _status(BD bd, String text, {bool accent = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.s),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (accent) ...[Icon(PhBold.check, size: 14, color: bd.accentText), const SizedBox(width: 4)],
          Text(text, style: T.sans(bd, size: 14, weight: FontWeight.w500, color: accent ? bd.accentText : bd.muted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = widget.plan;
    final me = auth.meId;
    final full = p.capacity != null && p.going >= p.capacity!;
    final isInvite = p.joinPolicy == JoinPolicy.invite;

    final List<Widget> actions;
    if (isInvite) {
      if (p.myStatus == JoinStatus.approved) {
        actions = [_status(bd, "You're going", accent: true), TextAction("Can't make it", onTap: _busy ? null : () => _run(() => PlansApi.respondInvite(p.id, false)))];
      } else if (p.myStatus == JoinStatus.declined) {
        actions = [_status(bd, 'Not going'), TextAction('Going after all', accent: true, onTap: _busy || full ? null : () => _run(() => PlansApi.respondInvite(p.id, true)))];
      } else if (full) {
        actions = [_status(bd, 'Full')];
      } else {
        actions = [
          TextAction("Can't make it", onTap: _busy ? null : () => _run(() => PlansApi.respondInvite(p.id, false))),
          BdButton('Going', expand: false, height: 40, busy: _busy, onTap: () => _run(() => PlansApi.respondInvite(p.id, true))),
        ];
      }
    } else if (p.myStatus == JoinStatus.approved) {
      actions = [_status(bd, "You're in", accent: true), TextAction('Leave', onTap: _busy ? null : () => _run(() => PlansApi.withdraw(p.id)))];
    } else if (p.myStatus == JoinStatus.requested) {
      actions = [_status(bd, 'Asked · waiting'), TextAction('Cancel', onTap: _busy ? null : () => _run(() => PlansApi.withdraw(p.id)))];
    } else if (p.myStatus == JoinStatus.declined) {
      actions = [_status(bd, 'Not this time')];
    } else if (full) {
      actions = [_status(bd, 'Full')];
    } else {
      actions = [BdButton('Ask to join', expand: false, height: 40, busy: _busy, onTap: () => _run(() => PlansApi.requestJoin(p.id)))];
    }

    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.l, S.xs, S.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, style: T.serif(bd, size: 22, height: 1.15)),
              const SizedBox(height: 4),
              Text([_prettyDate(p.date), _prettyTime(p.time), p.city].whereType<String>().join(' · '), style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.muted)),
              const SizedBox(height: 2),
              Text('Hosted by ${p.hostName} @${p.hostHandle}', style: T.caption(bd)),
            ]),
          ),
          if (p.hostId != me) IconBtn(Ph.dotsThree, tooltip: 'Options for ${p.hostName}', color: bd.muted, onTap: () => personActions(context, id: p.hostId, name: p.hostName, planId: p.id)),
        ]),
        if (p.note != null) Padding(padding: const EdgeInsets.only(top: S.m, right: S.m), child: Text(p.note!, style: T.body(bd, color: bd.muted))),
        if (p.drinks.isNotEmpty || p.vibeTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.m, right: S.m),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in p.drinks) _Tag(d),
              for (final t in p.vibeTags) _Tag(t, quiet: true),
            ]),
          ),
        Loader<PlanSignals?>(
          load: () => PlansApi.signals(p.id),
          builder: (context, s, _) => _SoftSignals(signals: s),
        ),
        Padding(padding: const EdgeInsets.only(top: S.m, right: S.m), child: Divider(height: 1, thickness: .8, color: bd.line)),
        const SizedBox(height: S.xs),
        Row(children: [
          Expanded(child: Text('${p.going} going${p.capacity != null ? ' · ${(p.capacity! - p.going).clamp(0, 999)} spots left' : ''}', style: T.caption(bd))),
          ...actions,
          const SizedBox(width: S.xs),
        ]),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(_err!, style: T.caption(bd, color: bd.accentText))),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool quiet;
  const _Tag(this.text, {this.quiet = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: quiet ? Colors.transparent : bd.glass, borderRadius: BorderRadius.circular(rCtl - 4), border: Border.all(color: quiet ? bd.line : bd.glassBorder, width: .8)),
      child: Text(text, style: T.sans(bd, size: 13, color: quiet ? bd.faint : bd.muted)),
    );
  }
}

/// Soft, factual comfort cues — never a score on a person.
class _SoftSignals extends StatelessWidget {
  final PlanSignals? signals;
  const _SoftSignals({this.signals});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = signals;
    if (s == null) return const SizedBox.shrink();
    final bits = <String>[
      if (s.mutualFriends > 0) '${s.mutualFriends} mutual friend${s.mutualFriends == 1 ? '' : 's'}',
      if (s.hostVouches > 0) '${s.hostVouches} vouch${s.hostVouches == 1 ? '' : 'es'}',
      if (s.sharedDrinks > 0) '${s.sharedDrinks} shared taste${s.sharedDrinks == 1 ? '' : 's'}',
      if (s.hostSince != null && DateTime.tryParse(s.hostSince!) != null) 'on brewdiary since ${DateTime.parse(s.hostSince!).year}',
    ];
    if (bits.isEmpty && !s.hostVerified) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: S.m, right: S.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(s.hostVerified ? Ph.sealCheck : Ph.users, size: 15, color: s.hostVerified ? bd.accentText : bd.faint),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(TextSpan(children: [
            if (s.hostVerified) TextSpan(text: 'Verified${bits.isNotEmpty ? ' · ' : ''}', style: T.caption(bd, color: bd.accentText)),
            TextSpan(text: bits.join(' · '), style: T.caption(bd)),
          ])),
        ),
      ]),
    );
  }
}

class _Mine extends StatelessWidget {
  const _Mine();
  @override
  Widget build(BuildContext context) {
    return Loader<List<MyPlan>>(
      refresh: plansRev,
      load: PlansApi.mine,
      builder: (context, plans, loading) {
        if (plans == null) return const Column(children: [Skeleton(height: 140), SizedBox(height: S.m), Skeleton(height: 140)]);
        if (plans.isEmpty) {
          return const EmptyNote("You haven't planned a night yet. Pick a day, say what you fancy, and let friends (or friends of friends) ask to come.", icon: Ph.calendarPlus);
        }
        return Column(children: [
          for (var i = 0; i < plans.length; i++) ...[
            if (i > 0) const SizedBox(height: S.m),
            MyPlanCard(plan: plans[i]),
          ],
        ]);
      },
    );
  }
}

/// A plan I host: its state, who's asking, who's invited, and the host's controls.
class MyPlanCard extends StatefulWidget {
  final MyPlan plan;
  const MyPlanCard({super.key, required this.plan});
  @override
  State<MyPlanCard> createState() => _MyPlanCardState();
}

class _MyPlanCardState extends State<MyPlanCard> {
  bool _openReqs = false;
  bool _openGuests = false;

  Future<void> _manage() {
    final p = widget.plan;
    final cancelled = p.status == PlanStatus.cancelled;
    return showActions(context, title: p.title, actions: [
      if (p.status == PlanStatus.open) SheetAction('Stop taking people', icon: Ph.lock, onTap: () => PlansApi.setStatus(p.id, PlanStatus.closed)),
      if (p.status == PlanStatus.closed) SheetAction('Reopen', icon: Ph.arrowCounterClockwise, onTap: () => PlansApi.setStatus(p.id, PlanStatus.open)),
      if (!cancelled) SheetAction('Call it off', icon: Ph.prohibit, onTap: () => PlansApi.setStatus(p.id, PlanStatus.cancelled)),
      SheetAction('Delete', icon: Ph.trash, destructive: true, onTap: () async {
        if (await confirm(context, title: 'Delete for good?', body: 'The plan and its requests are removed.', yes: 'Delete')) await PlansApi.delete(p.id);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = widget.plan;
    final cancelled = p.status == PlanStatus.cancelled;
    final isPrivate = p.joinPolicy == JoinPolicy.private;
    final isInvite = p.joinPolicy == JoinPolicy.invite;
    final badge = cancelled ? 'Called off' : (isPrivate ? 'Private' : (p.status == PlanStatus.closed ? 'Closed' : '${p.going} going'));
    return Opacity(
      opacity: cancelled ? .6 : 1,
      child: Glass(
        padding: const EdgeInsets.fromLTRB(S.l, S.l, S.xs, S.s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: T.serif(bd, size: 22, height: 1.15)),
                const SizedBox(height: 4),
                Text([_prettyDate(p.date), _prettyTime(p.time), p.city].whereType<String>().join(' · '), style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.muted)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(_policyIcon[p.joinPolicy], size: 14, color: bd.faint),
                  const SizedBox(width: 4),
                  Text('${_policyShort[p.joinPolicy]} · $badge', style: T.caption(bd)),
                ]),
              ]),
            ),
            IconBtn(Ph.dotsThree, tooltip: 'Manage ${p.title}', color: bd.muted, onTap: _manage),
          ]),
          if (p.note != null) Padding(padding: const EdgeInsets.only(top: S.m, right: S.m), child: Text(p.note!, style: T.body(bd, color: bd.muted))),
          if (isPrivate && !cancelled) Padding(padding: const EdgeInsets.only(top: S.m, right: S.m), child: Text('Only you can see this — a quiet note on your calendar.', style: T.caption(bd))),
          if (isInvite && !cancelled) ...[
            const SizedBox(height: S.xs),
            _Disclosure(label: 'Guests', open: _openGuests, onTap: () => setState(() => _openGuests = !_openGuests)),
            if (_openGuests) Padding(padding: const EdgeInsets.only(right: S.m, bottom: S.s), child: _Guests(planId: p.id)),
          ],
          if (!cancelled && !isPrivate) ...[
            _Disclosure(label: p.pending > 0 ? '${p.pending} asking to join' : 'Requests', accent: p.pending > 0, open: _openReqs, onTap: () => setState(() => _openReqs = !_openReqs)),
            if (_openReqs) Padding(padding: const EdgeInsets.only(right: S.m, bottom: S.s), child: _Requests(planId: p.id)),
          ],
        ]),
      ),
    );
  }
}

/// A "show more" row with a turning caret.
class _Disclosure extends StatelessWidget {
  final String label;
  final bool open;
  final bool accent;
  final VoidCallback onTap;
  const _Disclosure({required this.label, required this.open, required this.onTap, this.accent = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      button: true,
      expanded: open,
      child: Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: S.tap),
          child: Row(children: [
            Text(label, style: T.sans(bd, size: 14, weight: FontWeight.w600, color: accent ? bd.accentText : bd.ink)),
            const SizedBox(width: 4),
            AnimatedRotation(turns: open ? .5 : 0, duration: Motion.fast, child: Icon(Ph.caretDown, size: 14, color: bd.faint)),
          ]),
        ),
      ),
    );
  }
}

class _Requests extends StatelessWidget {
  final String planId;
  const _Requests({required this.planId});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<PlanRequest>>(
      refresh: plansRev,
      load: () => PlansApi.requests(planId),
      builder: (context, reqs, loading) {
        if (reqs == null) return const Skeleton(height: 56, radius: rCtl);
        if (reqs.isEmpty) return Text('No one has asked yet.', style: T.caption(bd));
        final live = reqs.where((r) => r.status == JoinStatus.requested).toList();
        final approved = reqs.where((r) => r.status == JoinStatus.approved).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (live.isNotEmpty)
            Hairlines(children: [
              for (final r in live)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.s),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name, style: T.row(bd)),
                        Text('@${r.handle}', style: T.caption(bd)),
                        if (r.message != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${r.message}”', style: T.body(bd, color: bd.muted))),
                      ]),
                    ),
                    TextAction('Approve', accent: true, onTap: () async {
                      final e = await PlansApi.respondJoin(r.joinId, true);
                      if (e != null && context.mounted) toast(context, e);
                    }),
                    IconBtn(Ph.x, tooltip: 'Decline ${r.name}', size: 18, color: bd.faint, onTap: () => PlansApi.respondJoin(r.joinId, false)),
                  ]),
                ),
            ]),
          if (approved.isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('Going: ${approved.map((r) => r.name).join(', ')}', style: T.caption(bd))),
        ]);
      },
    );
  }
}

class _Guests extends StatelessWidget {
  final String planId;
  const _Guests({required this.planId});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<({String userId, String name, String handle})>>(
      refresh: plansRev,
      load: () => PlansApi.invitees(planId),
      builder: (context, inv, loading) {
        final list = inv ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.isEmpty)
            Text('No one invited yet.', style: T.caption(bd))
          else
            Hairlines(children: [
              for (final g in list)
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.name, style: T.row(bd)),
                      Text('@${g.handle}', style: T.caption(bd)),
                    ]),
                  ),
                  IconBtn(Ph.x, tooltip: 'Uninvite ${g.name}', size: 18, color: bd.faint, onTap: () => PlansApi.uninvite(planId, g.userId)),
                ]),
            ]),
          const SizedBox(height: S.s),
          UserSearch(exclude: list.map((g) => g.userId).toSet(), onPick: (u) async {
            final e = await PlansApi.invite(planId, u.id);
            if (e != null && context.mounted) toast(context, e);
          }),
        ]);
      },
    );
  }
}

/// Type-a-name autocomplete over block/sanction-aware user search.
class UserSearch extends StatefulWidget {
  final ValueChanged<SocialProfile> onPick;
  final Set<String> exclude;
  const UserSearch({super.key, required this.onPick, this.exclude = const {}});
  @override
  State<UserSearch> createState() => _UserSearchState();
}

class _UserSearchState extends State<UserSearch> {
  final _q = TextEditingController();
  List<SocialProfile> _results = [];
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _t?.cancel();
    if (q.trim().replaceFirst('@', '').length < 2) {
      setState(() => _results = []);
      return;
    }
    _t = Timer(const Duration(milliseconds: 250), () async {
      final r = await FriendsApi.search(q);
      if (mounted) setState(() => _results = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final shown = _results.where((u) => !widget.exclude.contains(u.id)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GlassField(controller: _q, hint: 'Invite by name or @handle', icon: Ph.userPlus, onChanged: _search, caps: TextCapitalization.none),
      if (shown.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: S.xs),
          child: Glass(
            radius: rCtl,
            padding: const EdgeInsets.symmetric(horizontal: S.l),
            child: Hairlines(children: [
              for (final u in shown)
                Pressable(
                  onTap: () {
                    widget.onPick(u);
                    _q.clear();
                    setState(() => _results = []);
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(children: [
                      Expanded(child: Text(u.name, overflow: TextOverflow.ellipsis, style: T.row(bd))),
                      Text('@${u.handle}', style: T.caption(bd)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
    ]);
  }
}

class _CreatePlan extends StatefulWidget {
  const _CreatePlan();
  @override
  State<_CreatePlan> createState() => _CreatePlanState();
}

class _CreatePlanState extends State<_CreatePlan> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _note = TextEditingController();
  final _drinks = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  int? _cap;
  JoinPolicy _policy = JoinPolicy.friends;
  final List<SocialProfile> _invited = [];
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    for (final c in [_title, _city, _note, _drinks]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_date == null || _title.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final isPrivate = _policy == JoinPolicy.private;
    final res = await PlansApi.create(NewPlan(
      title: _title.text,
      date: toKey(_date!),
      time: _time == null ? null : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
      city: _city.text,
      note: _note.text,
      drinks: _drinks.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      joinPolicy: _policy,
      capacity: isPrivate ? null : _cap,
    ));
    if (res.error != null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = res.error;
        });
      }
      return;
    }
    if (_policy == JoinPolicy.invite && _invited.isNotEmpty) {
      await Future.wait(_invited.map((u) => PlansApi.invite(res.id!, u.id)));
    }
    if (!mounted) return;
    Navigator.pop(context);
    toast(context, isPrivate ? 'Saved to your calendar.' : 'Plan made — friends can ask to join.');
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final isPrivate = _policy == JoinPolicy.private;
    final now = appNow();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LineField(controller: _title, autofocus: true, label: "What's the plan?", hint: 'Mezcal tasting, a quiet pint…', onChanged: (_) => setState(() {})),
      const SizedBox(height: S.xl),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: DateField(label: 'Day', value: _date, first: DateTime(now.year, now.month, now.day), last: DateTime(now.year + 2, 12, 31), onChanged: (d) => setState(() => _date = d))),
        const SizedBox(width: S.l),
        Expanded(child: TimeField(label: 'Time (optional)', value: _time, placeholder: 'Any time', onChanged: (t) => setState(() => _time = t))),
      ]),
      const SizedBox(height: S.xl),
      LineField(controller: _city, label: 'Where (optional)', hint: 'A city or an area', caps: TextCapitalization.words),
      const SizedBox(height: S.xl),
      const Label('What do you fancy? (optional)'),
      const SizedBox(height: S.s),
      GlassField(controller: _note, hint: 'A line for the people you invite', maxLines: 3),
      const SizedBox(height: S.m),
      GlassField(controller: _drinks, hint: 'Drinks, separated by commas', icon: Ph.martini),
      const SizedBox(height: S.xl),
      const Label('Who can see it'),
      const SizedBox(height: S.s),
      Group(
        footer: 'No public or stranger option — on purpose.',
        children: [
          for (final p in JoinPolicy.values)
            GroupTile(
              icon: _policyIcon[p],
              title: p == JoinPolicy.invite ? 'Specific friends' : joinPolicyLabel[p]!,
              subtitle: _policyHint[p],
              trailing: _policy == p ? Icon(PhBold.check, size: 18, color: bd.accentText) : null,
              onTap: () => setState(() => _policy = p),
            ),
        ],
      ),
      if (_policy == JoinPolicy.invite) ...[
        const SizedBox(height: S.l),
        UserSearch(exclude: _invited.map((u) => u.id).toSet(), onPick: (u) => setState(() => _invited.add(u))),
        if (_invited.isNotEmpty) ...[
          const SizedBox(height: S.xs),
          Wrap(spacing: S.s, children: [for (final u in _invited) BdChip(u.name, active: true, icon: PhBold.x, onTap: () => setState(() => _invited.remove(u)))]),
        ],
      ],
      if (!isPrivate) ...[
        const SizedBox(height: S.l),
        Group(children: [
          SettingRow(
            title: 'Max people',
            hint: 'Optional — leave it off for no limit.',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconBtn(Ph.minus, glass: true, size: 18, tooltip: 'Fewer people', onTap: _cap == null ? null : () => setState(() => _cap = _cap! <= 2 ? null : _cap! - 1)),
              SizedBox(width: 40, child: Text(_cap == null ? 'Off' : '$_cap', textAlign: TextAlign.center, style: T.sans(bd, size: 16, weight: FontWeight.w600, color: _cap == null ? bd.faint : bd.ink).copyWith(fontFeatures: T.tnum))),
              IconBtn(Ph.plus, glass: true, size: 18, tooltip: 'More people', onTap: (_cap ?? 0) >= 50 ? null : () => setState(() => _cap = _cap == null ? 4 : _cap! + 1)),
            ]),
          ),
        ]),
      ],
      if (_err != null) Padding(padding: const EdgeInsets.only(top: S.m), child: Text(_err!, style: T.sans(bd, size: 14, color: bd.accentText))),
      const SizedBox(height: S.xxl),
      BdButton(isPrivate ? 'Save to my calendar' : 'Make the plan', busy: _busy, onTap: _title.text.trim().isEmpty || _date == null ? null : _submit),
    ]);
  }
}
