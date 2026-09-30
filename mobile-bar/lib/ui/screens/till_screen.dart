// The till — a counter's service screen (a liquor store, a sweet shop, a bakery, a
// shop). Nobody hangs out at a counter, so there are no rooms: staff find the customer
// and punch their card, once a day however much they buy. At a liquor store that rule
// is the law's line, not just ours — there, a visit IS the purchase (030).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../../logic/venue_kinds.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'guests_screen.dart';
import 'tonight_screen.dart';
import 'checkout_screen.dart';
import 'host_screen.dart';

class TillScreen extends StatefulWidget {
  final Venue venue;
  const TillScreen({super.key, required this.venue});
  @override
  State<TillScreen> createState() => _TillScreenState();
}

class _TillScreenState extends State<TillScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<ProfileHit> _hits = const [];
  ProfileHit? _customer;
  bool _punched = false;

  Venue get v => widget.venue;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) return setState(() => _hits = const []);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await Backend.i.searchPeople(q);
        if (mounted) setState(() => _hits = r);
      } catch (_) {}
    });
  }

  Future<void> _punch(ProfileHit p) async {
    setState(() {
      _customer = p;
      _punched = false;
      _hits = const [];
      _q.clear();
    });
    final ok = await runAction(context, () => Backend.i.recordVisit(v.id, p.id), done: '${p.name}\'s card is punched for today.');
    if (mounted) setState(() => _punched = ok);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final store = v.kind == VenueKind.store;
    return ScrollPage(
      title: 'Till',
      subtitle: v.name,
      children: [
        const DemoNote(),
        ShiftCard(venue: v),
        if (s.can(Cap.takePayment)) ...[
          BdButton('New sale', icon: Ph.receipt, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckoutScreen(venue: v)))),
          const SizedBox(height: S.xl),
          const SectionHeader('Punch a card'),
        ],
        if (!v.verified)
          Glass(
            padding: const EdgeInsets.all(S.l),
            child: Text('Cards start once you\'re verified — until then nothing you punch would count, so we don\'t pretend. Ask for verification under More › Setup.', style: T.bodyMuted(bd)),
          )
        else if (!s.can(Cap.redeemPerk))
          const EmptyNote('Your role here doesn\'t run the till.')
        else ...[
          Text(store ? 'Once a day per customer — buying more never earns more, and a liquor store\'s reward is never alcohol.' : 'Once a day per customer — buying more doesn\'t earn more.', style: T.caption(bd)),
          const SizedBox(height: S.m),
          if (_customer == null) ...[
            GlassField(controller: _q, hint: 'Find a customer by name or @handle', icon: Ph.magnifyingGlass, onChanged: _search, caps: TextCapitalization.none),
            const SizedBox(height: S.s),
            if (_q.text.trim().length >= 2 && _hits.isEmpty) const EmptyNote('No one by that name or handle.'),
            if (_hits.isNotEmpty)
              Group(children: [
                for (final p in _hits)
                  GroupTile(title: p.name, subtitle: '@${p.handle}', trailing: AccentPill('Punch', onTap: () => _punch(p))),
              ]),
          ] else
            Glass(
              padding: const EdgeInsets.all(S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Initial(_customer!.name.isEmpty ? '?' : _customer!.name[0].toUpperCase(), size: 40),
                  const SizedBox(width: S.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_customer!.name, style: T.row(bd)),
                      Text('@${_customer!.handle}', style: T.caption(bd)),
                    ]),
                  ),
                  if (_punched) const ToneTag('punched', Tone.good),
                ]),
                const SizedBox(height: S.m),
                Wrap(spacing: S.s, runSpacing: S.s, children: [
                  BdChip('Rewards', icon: Ph.gift, onTap: () => showPerksSheet(context, v, _customer!.id, _customer!.name)),
                  if (s.can(Cap.guestCard))
                    BdChip('Their card', icon: Ph.addressBook, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuestDetailScreen(venue: v, guestId: _customer!.id, name: _customer!.name)))),
                ]),
                const SizedBox(height: S.s),
                TextAction('Next customer', icon: Ph.arrowRight, onTap: () => setState(() => _customer = null)),
              ]),
            ),
        ],
      ],
    );
  }
}
