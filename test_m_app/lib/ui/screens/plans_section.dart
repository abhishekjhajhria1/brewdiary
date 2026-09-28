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
import 'together_screen.dart' show DateField, showReportSheet;

const _policyHint = {
  JoinPolicy.private: 'A private note on your calendar — no one else sees it.',
  JoinPolicy.invite: 'Only the friends you pick can see it and ask to join.',
  JoinPolicy.friends: 'Any of your friends can see it and ask to join.',
  JoinPolicy.fof: 'Friends, and their friends, can ask to join.',
};
const _policyShort = {JoinPolicy.private: 'just me', JoinPolicy.invite: 'invite only', JoinPolicy.friends: 'friends', JoinPolicy.fof: 'friends of friends'};

String _prettyDate(String key) {
  final d = parseKey(key);
  return '${weekdays[mondayIndex(d)]} ${d.day} ${monthNames[d.month - 1]}';
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
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Loader<({bool banned, String? suspendedUntil})?>(
        refresh: safetyRev,
        load: SafetyApi.mySanction,
        builder: (context, sanction, _) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (sanction != null) _SanctionBanner(banned: sanction.banned, until: sanction.suspendedUntil),
            Row(children: [
              Glass(
                radius: rCtl,
                padding: const EdgeInsets.all(4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final m in [false, true])
                    GestureDetector(
                      onTap: () => setState(() => _mine = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(color: _mine == m ? bd.ink : Colors.transparent, borderRadius: BorderRadius.circular(7)),
                        child: Text((m ? 'Mine' : 'Coming up').toUpperCase(), style: T.sans(bd, size: 11, weight: FontWeight.w500, spacing: 1.3, color: _mine == m ? bd.base : bd.faint)),
                      ),
                    ),
                ]),
              ),
              const Spacer(),
              if (sanction == null) SizedBox(width: 130, child: InkButton(_creating ? 'Close' : 'Plan a night', height: 40, uppercase: false, onTap: () => setState(() => _creating = !_creating))),
            ]),
            const SizedBox(height: 16),
            if (_creating && sanction == null) _CreatePlan(onDone: () => setState(() => _creating = false)),
            if (_mine) const _Mine() else const _ComingUp(),
          ]);
        },
      ),
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(banned ? 'Your account is limited.' : 'Your account is paused for now.', style: T.sans(bd)),
        const SizedBox(height: 4),
        Text(
          'You can still look around, but planning and joining are off${!banned && untilText != null ? ' until $untilText' : ''}. If you think this is a mistake, reach out through the help link.',
          style: T.sans(bd, size: 14, color: bd.faint, height: 1.5),
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
        if (plans == null) return const Column(children: [Skeleton(height: 140), SizedBox(height: 12), Skeleton(height: 140)]);
        if (plans.isEmpty) {
          return const EmptyNote('No plans from your circle yet. When a friend (or a friend of a friend) plans a night, it shows up here — or start one yourself with “Plan a night”.');
        }
        return Column(children: [for (final p in plans) Padding(padding: const EdgeInsets.only(bottom: 12), child: _DiscoverCard(plan: p))]);
      },
    );
  }
}

class _DiscoverCard extends StatefulWidget {
  final Plan plan;
  const _DiscoverCard({required this.plan});
  @override
  State<_DiscoverCard> createState() => _DiscoverCardState();
}

class _DiscoverCardState extends State<_DiscoverCard> {
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

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = widget.plan;
    final me = auth.meId;
    final full = p.capacity != null && p.going >= p.capacity!;
    final isInvite = p.joinPolicy == JoinPolicy.invite;

    Widget action;
    if (isInvite) {
      if (p.myStatus == JoinStatus.approved) {
        action = Row(mainAxisSize: MainAxisSize.min, children: [
          Text("You're going", style: T.sans(bd, size: 14, color: bd.accent)),
          const SizedBox(width: 12),
          TextAction("Can't make it", faint: true, onTap: _busy ? null : () => _run(() => PlansApi.respondInvite(p.id, false))),
        ]);
      } else if (p.myStatus == JoinStatus.declined) {
        action = Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Not going', style: T.sans(bd, size: 14, color: bd.faint)),
          const SizedBox(width: 12),
          TextAction('Going', accent: true, onTap: _busy || full ? null : () => _run(() => PlansApi.respondInvite(p.id, true))),
        ]);
      } else if (full) {
        action = Text('Full', style: T.sans(bd, size: 14, color: bd.faint));
      } else {
        action = Row(mainAxisSize: MainAxisSize.min, children: [
          TextAction("Can't make it", faint: true, onTap: _busy ? null : () => _run(() => PlansApi.respondInvite(p.id, false))),
          const SizedBox(width: 10),
          SizedBox(width: 84, child: InkButton('Going', height: 38, uppercase: false, busy: _busy, onTap: () => _run(() => PlansApi.respondInvite(p.id, true)))),
        ]);
      }
    } else if (p.myStatus == JoinStatus.approved) {
      action = Row(mainAxisSize: MainAxisSize.min, children: [
        Text("You're in", style: T.sans(bd, size: 14, color: bd.accent)),
        const SizedBox(width: 12),
        TextAction('Leave', faint: true, onTap: _busy ? null : () => _run(() => PlansApi.withdraw(p.id))),
      ]);
    } else if (p.myStatus == JoinStatus.requested) {
      action = Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Asked · waiting', style: T.sans(bd, size: 14, color: bd.muted)),
        const SizedBox(width: 12),
        TextAction('Cancel', faint: true, onTap: _busy ? null : () => _run(() => PlansApi.withdraw(p.id))),
      ]);
    } else if (p.myStatus == JoinStatus.declined) {
      action = Text('Not this time', style: T.sans(bd, size: 14, color: bd.faint));
    } else if (full) {
      action = Text('Full', style: T.sans(bd, size: 14, color: bd.faint));
    } else {
      action = SizedBox(width: 116, child: InkButton('Ask to join', height: 38, uppercase: false, busy: _busy, onTap: () => _run(() => PlansApi.requestJoin(p.id))));
    }

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, style: T.serif(bd, size: 21, height: 1.15)),
              const SizedBox(height: 3),
              Text(
                [_prettyDate(p.date), _prettyTime(p.time), p.city, '${p.hostName} @${p.hostHandle}'].whereType<String>().join(' · '),
                style: T.sans(bd, size: 12, color: bd.faint),
              ),
            ]),
          ),
          if (p.hostId != me) _PersonMenu(subjectId: p.hostId, subjectName: p.hostName, planId: p.id),
        ]),
        if (p.note != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(p.note!, style: T.sans(bd, color: bd.muted, height: 1.55))),
        if (p.drinks.isNotEmpty || p.vibeTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final d in p.drinks) Glass(radius: rCtl, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text(d, style: T.sans(bd, size: 12, color: bd.muted))),
              for (final t in p.vibeTags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.line)),
                  child: Text(t, style: T.sans(bd, size: 12, color: bd.faint)),
                ),
            ]),
          ),
        Loader<PlanSignals?>(
          load: () => PlansApi.signals(p.id),
          builder: (context, s, _) => _SoftSignals(signals: s),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('${p.going} going${p.capacity != null ? ' · ${(p.capacity! - p.going).clamp(0, 999)} spots left' : ''}', style: T.sans(bd, size: 12, color: bd.faint))),
          action,
        ]),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: T.sans(bd, size: 12, color: bd.accent))),
      ]),
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
      padding: const EdgeInsets.only(top: 12),
      child: Text.rich(TextSpan(children: [
        if (s.hostVerified) TextSpan(text: '✓ verified${bits.isNotEmpty ? ' · ' : ''}', style: T.sans(bd, size: 12, color: bd.accent)),
        TextSpan(text: bits.join(' · '), style: T.sans(bd, size: 12, color: bd.faint)),
      ])),
    );
  }
}

/// The quiet safety affordance on every person.
class _PersonMenu extends StatelessWidget {
  final String subjectId;
  final String subjectName;
  final String? planId;
  const _PersonMenu({required this.subjectId, required this.subjectName, this.planId});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return PopupMenuButton<String>(
      tooltip: 'Options for $subjectName',
      color: Color.alphaBlend(bd.glassStrong, bd.base),
      icon: Icon(Icons.more_horiz, size: 20, color: bd.faint),
      onSelected: (v) async {
        if (v == 'report') {
          showReportSheet(context, subjectId, subjectName, planId: planId);
        } else if (v == 'block') {
          if (await confirm(context, title: 'Block $subjectName?', body: "You won't see each other, and any live join between you is withdrawn.", yes: 'Block')) {
            await SafetyApi.block(subjectId);
            plansRev.bump();
            if (context.mounted) toast(context, "Blocked. You won't see each other.");
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'report', child: Text('Report', style: T.sans(bd, size: 14, color: bd.muted))),
        PopupMenuItem(value: 'block', child: Text('Block $subjectName', style: T.sans(bd, size: 14, color: bd.muted))),
      ],
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
        if (plans == null) return const Column(children: [Skeleton(height: 130), SizedBox(height: 12), Skeleton(height: 130)]);
        if (plans.isEmpty) {
          return const EmptyNote("You haven't planned a night yet. “Plan a night” up top — pick a day, say what you fancy, and let friends (or friends of friends) ask to come.");
        }
        return Column(children: [for (final p in plans) Padding(padding: const EdgeInsets.only(bottom: 12), child: _MyPlanCard(plan: p))]);
      },
    );
  }
}

class _MyPlanCard extends StatefulWidget {
  final MyPlan plan;
  const _MyPlanCard({required this.plan});
  @override
  State<_MyPlanCard> createState() => _MyPlanCardState();
}

class _MyPlanCardState extends State<_MyPlanCard> {
  bool _openReqs = false;
  bool _openGuests = false;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final p = widget.plan;
    final cancelled = p.status == PlanStatus.cancelled;
    final isPrivate = p.joinPolicy == JoinPolicy.private;
    final isInvite = p.joinPolicy == JoinPolicy.invite;
    return Opacity(
      opacity: cancelled ? .6 : 1,
      child: Glass(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: T.serif(bd, size: 21, height: 1.15)),
                const SizedBox(height: 3),
                Text([_prettyDate(p.date), _prettyTime(p.time), p.city, _policyShort[p.joinPolicy]].whereType<String>().join(' · '), style: T.sans(bd, size: 12, color: bd.faint)),
              ]),
            ),
            Text(
              cancelled ? 'cancelled' : (isPrivate ? 'private' : (p.status == PlanStatus.closed ? 'closed' : '${p.going} going')),
              style: T.sans(bd, size: 12, color: cancelled ? bd.faint : bd.muted),
            ),
          ]),
          if (p.note != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(p.note!, style: T.sans(bd, color: bd.muted, height: 1.55))),
          if (isPrivate && !cancelled) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Only you can see this — a quiet note on your calendar.', style: T.sans(bd, size: 14, color: bd.faint))),
          if (isInvite && !cancelled) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: TextAction('Guests ${_openGuests ? '▴' : '▾'}', accent: true, onTap: () => setState(() => _openGuests = !_openGuests))),
            if (_openGuests) _Guests(planId: p.id),
          ],
          if (!cancelled && !isPrivate) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction('${p.pending > 0 ? '${p.pending} waiting to join' : 'Requests'} ${_openReqs ? '▴' : '▾'}', accent: true, onTap: () => setState(() => _openReqs = !_openReqs)),
            ),
            if (_openReqs) _Requests(planId: p.id),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: bd.line),
          const SizedBox(height: 6),
          Wrap(spacing: 16, children: [
            if (p.status == PlanStatus.open) TextAction('Stop taking people', faint: true, onTap: () => PlansApi.setStatus(p.id, PlanStatus.closed)),
            if (p.status == PlanStatus.closed) TextAction('Reopen', faint: true, onTap: () => PlansApi.setStatus(p.id, PlanStatus.open)),
            if (!cancelled) TextAction('Call it off', faint: true, onTap: () => PlansApi.setStatus(p.id, PlanStatus.cancelled)),
            TextAction('Delete', faint: true, onTap: () async {
              if (await confirm(context, title: 'Delete for good?', body: 'The plan and its requests are removed.', yes: 'Delete')) {
                await PlansApi.delete(p.id);
              }
            }),
          ]),
        ]),
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
        if (reqs == null) return Text('Loading…', style: T.sans(bd, size: 12, color: bd.faint));
        if (reqs.isEmpty) return Text('No one has asked yet.', style: T.sans(bd, size: 12, color: bd.faint));
        final live = reqs.where((r) => r.status == JoinStatus.requested).toList();
        final approved = reqs.where((r) => r.status == JoinStatus.approved).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in live)
            Glass(
              radius: rCtl,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${r.name} ', style: T.sans(bd)),
                      TextSpan(text: '@${r.handle}', style: T.sans(bd, size: 12, color: bd.faint)),
                    ])),
                    if (r.message != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${r.message}”', style: T.sans(bd, size: 14, color: bd.muted))),
                  ]),
                ),
                TextAction('Approve', accent: true, onTap: () async {
                  final e = await PlansApi.respondJoin(r.joinId, true);
                  if (e != null && context.mounted) toast(context, e);
                }),
                const SizedBox(width: 10),
                TextAction('Decline', faint: true, onTap: () => PlansApi.respondJoin(r.joinId, false)),
              ]),
            ),
          if (approved.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Going: ${approved.map((r) => r.name).join(', ')}', style: T.sans(bd, size: 12, color: bd.faint))),
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
            Text('No one invited yet.', style: T.sans(bd, size: 12, color: bd.faint))
          else
            for (final g in list)
              Row(children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${g.name} ', style: T.sans(bd, size: 14)),
                    TextSpan(text: '@${g.handle}', style: T.sans(bd, size: 12, color: bd.faint)),
                  ])),
                ),
                TextAction('Remove', faint: true, onTap: () => PlansApi.uninvite(planId, g.userId)),
              ]),
          const SizedBox(height: 8),
          Text('Invite someone by name or @handle', style: T.sans(bd, size: 12, color: bd.faint)),
          const SizedBox(height: 6),
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
      GlassField(controller: _q, hint: 'Type a name or @handle', onChanged: _search, caps: TextCapitalization.none),
      if (shown.isNotEmpty)
        Glass(
          radius: rCtl,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            for (final u in shown)
              InkWell(
                onTap: () {
                  widget.onPick(u);
                  _q.clear();
                  setState(() => _results = []);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(children: [
                    Expanded(child: Text(u.name, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 14, color: bd.muted))),
                    Text('@${u.handle}', style: T.sans(bd, size: 12, color: bd.faint)),
                  ]),
                ),
              ),
          ]),
        ),
    ]);
  }
}

class _CreatePlan extends StatefulWidget {
  final VoidCallback onDone;
  const _CreatePlan({required this.onDone});
  @override
  State<_CreatePlan> createState() => _CreatePlanState();
}

class _CreatePlanState extends State<_CreatePlan> {
  final _title = TextEditingController();
  final _city = TextEditingController();
  final _note = TextEditingController();
  final _drinks = TextEditingController();
  final _cap = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  JoinPolicy _policy = JoinPolicy.friends;
  final List<SocialProfile> _invited = [];
  bool _busy = false;
  String? _err;

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
      capacity: isPrivate ? null : int.tryParse(_cap.text),
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
    if (mounted) setState(() => _busy = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final isPrivate = _policy == JoinPolicy.private;
    final now = appNow();
    return Glass(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Label('Plan a night', color: bd.faint),
        const SizedBox(height: 12),
        GlassField(controller: _title, hint: "What's the plan?", onChanged: (_) => setState(() {})),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _date == null
                ? GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 2));
                      if (d != null) setState(() => _date = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.lineStrong))),
                      child: Text('Pick a date', style: T.sans(bd, color: bd.faint)),
                    ),
                  )
                : DateField(value: _date!, first: DateTime(now.year, now.month, now.day), last: DateTime(now.year + 2), onChanged: (d) => setState(() => _date = d)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: GestureDetector(
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 20, minute: 0));
                if (t != null) setState(() => _time = t);
              },
              child: Container(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.lineStrong))),
                child: Text(_time == null ? 'Time (opt.)' : _time!.format(context), style: T.sans(bd, color: _time == null ? bd.faint : bd.ink)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        GlassField(controller: _city, hint: 'City or area (optional)'),
        const SizedBox(height: 10),
        GlassField(controller: _note, hint: 'What do you fancy doing? (optional)', maxLines: 3),
        const SizedBox(height: 10),
        GlassField(controller: _drinks, hint: 'Drinks, comma-separated (optional)'),
        const SizedBox(height: 14),
        Text('Who can see it', style: T.sans(bd, size: 12, color: bd.faint)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in JoinPolicy.values) BdChip(p == JoinPolicy.invite ? 'Specific friends' : joinPolicyLabel[p]!, active: _policy == p, onTap: () => setState(() => _policy = p)),
        ]),
        const SizedBox(height: 6),
        Text('${_policyHint[_policy]} No public or stranger option — on purpose.', style: T.sans(bd, size: 12, color: bd.faint, height: 1.4)),
        if (_policy == JoinPolicy.invite) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Invite people by name or @handle', style: T.sans(bd, size: 12, color: bd.faint)),
              const SizedBox(height: 6),
              UserSearch(exclude: _invited.map((u) => u.id).toSet(), onPick: (u) => setState(() => _invited.add(u))),
              if (_invited.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final u in _invited) BdChip('${u.name}  ×', active: true, onTap: () => setState(() => _invited.remove(u)))]),
              ],
            ]),
          ),
        ],
        if (!isPrivate) ...[
          const SizedBox(height: 10),
          GlassField(controller: _cap, hint: 'Max people (optional)', keyboard: TextInputType.number),
        ],
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: T.sans(bd, size: 14, color: bd.accent))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: InkButton(_busy ? 'Creating…' : (isPrivate ? 'Save to my calendar' : 'Create plan'), uppercase: false, busy: _busy, onTap: _title.text.trim().isEmpty || _date == null ? null : _submit)),
          const SizedBox(width: 12),
          TextAction('Cancel', faint: true, onTap: widget.onDone),
        ]),
      ]),
    );
  }
}
