// Parties — the list half of src/components/together/Parties.tsx. One night, one
// room: host one or join with a code; upcoming nights first, then the recaps.
import 'package:flutter/material.dart';

import 'package:brewdiary_core/date.dart';
import '../../data/base.dart';
import '../../data/parties.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';
import 'party_screens.dart';

class PartiesSection extends StatelessWidget {
  const PartiesSection({super.key});

  void _open(BuildContext context, String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: id)));

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: S.l),
      RoomIntro('One night, one room — everything guests share lands here.', actions: [
        RoomAction('Host one', icon: Ph.confetti, primary: true, onTap: () => showBdSheet(context, title: 'Host a night', builder: (_) => _HostParty(onHosted: (id) => _open(context, id)))),
        RoomAction('Join with code', icon: Ph.ticket, onTap: () => showBdSheet(context, title: 'Join a party', builder: (_) => _JoinParty(onJoined: (id) => _open(context, id)))),
      ]),
      const SizedBox(height: S.xl),
      Loader<List<Party>>(
        retry: true,
        refresh: partiesRev,
        load: PartiesApi.mine,
        builder: (context, parties, loading) {
          if (parties == null) return const Skeleton(height: 112);
          if (parties.isEmpty) {
            return const EmptyNote('No nights yet. Host one, or join a friend\'s with their code — everyone logs, and the party page becomes the recap.', icon: Ph.confetti);
          }
          final today = todayKey();
          final upcoming = parties.where((p) => p.date.compareTo(today) >= 0).toList();
          final past = parties.where((p) => p.date.compareTo(today) < 0).toList();
          GroupTile tile(Party p) => GroupTile(
                icon: p.date == today ? PhFill.confetti : Ph.confetti,
                title: p.name,
                subtitle: '${p.date == today ? 'Tonight' : shortDay(p.date)}${p.venue != null ? ' · ${p.venue}' : ''} · ${p.going} going',
                chevron: true,
                onTap: () => _open(context, p.id),
              );
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (upcoming.isNotEmpty) Group(children: [for (final p in upcoming) tile(p)]),
            if (past.isNotEmpty) ...[
              if (upcoming.isNotEmpty) const SectionHeader('Recaps'),
              Group(children: [for (final p in past) tile(p)]),
            ],
          ]);
        },
      ),
    ]);
  }
}

class _HostParty extends StatefulWidget {
  final ValueChanged<String> onHosted;
  const _HostParty({required this.onHosted});
  @override
  State<_HostParty> createState() => _HostPartyState();
}

class _HostPartyState extends State<_HostParty> {
  final _name = TextEditingController();
  final _venue = TextEditingController();
  DateTime _date = appNow();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await PartiesApi.create(name: _name.text, date: toKey(_date), venue: _venue.text);
    if (!mounted) return;
    if (r.error != null) {
      setState(() {
        _busy = false;
        _error = r.error;
      });
      return;
    }
    Navigator.pop(context);
    if (r.id != null) widget.onHosted(r.id!);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final now = appNow();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LineField(controller: _name, autofocus: true, label: "What's the occasion?", hint: 'Housewarming, friday tasting…', onChanged: (_) => setState(() {})),
      const SizedBox(height: S.xl),
      DateField(label: 'When', value: _date, first: DateTime(now.year, now.month, now.day), last: DateTime(now.year + 2, 12, 31), onChanged: (d) => setState(() => _date = d)),
      const SizedBox(height: S.xl),
      LineField(controller: _venue, label: 'Where (optional)', hint: 'A bar, a flat…', caps: TextCapitalization.words),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: S.m), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
      const SizedBox(height: S.xxl),
      BdButton('Host it', busy: _busy, onTap: _name.text.trim().isEmpty ? null : _submit),
      const SizedBox(height: S.s),
      Text('Guests ask to join with the code; you let them in.', textAlign: TextAlign.center, style: T.caption(bd)),
    ]);
  }
}

class _JoinParty extends StatefulWidget {
  final ValueChanged<String> onJoined;
  const _JoinParty({required this.onJoined});
  @override
  State<_JoinParty> createState() => _JoinPartyState();
}

class _JoinPartyState extends State<_JoinParty> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await PartiesApi.join(_code.text);
    if (!mounted) return;
    if (r.error != null || r.id == null) {
      setState(() {
        _busy = false;
        _error = r.error ?? "Couldn't find that party.";
      });
      return;
    }
    Navigator.pop(context);
    if (r.pending) toast(context, 'Request sent to ${r.name} — the host will let you in.');
    widget.onJoined(r.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LineField(
        controller: _code,
        autofocus: true,
        label: 'Party code',
        hint: 'Paste the code from the invite',
        caps: TextCapitalization.none,
        error: _error,
        action: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: S.xxl),
      BdButton('Ask to join', busy: _busy, onTap: _code.text.trim().isEmpty ? null : _submit),
    ]);
  }
}
