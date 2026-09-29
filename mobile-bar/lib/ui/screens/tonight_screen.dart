// Tonight — what service needs from the room: open it, put its code on the tables, see
// who joined, record a tab, hand out (positive-only) vibe, and hand over a reward that
// was earned. Everything that touches a guest's standing is checked again by the
// database: a verified venue, the right role, the guest really in the room.
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
import 'guests_screen.dart';
import 'host_screen.dart';

/// The four things staff can praise a guest for — fixed, positive, never a rating.
const staffVibeReasons = ['great vibe', 'kept it classy', 'a pleasure to serve', 'looked after the table'];

class TonightScreen extends StatefulWidget {
  final Venue venue;
  const TonightScreen({super.key, required this.venue});
  @override
  State<TonightScreen> createState() => _TonightScreenState();
}

class _TonightScreenState extends State<TonightScreen> {
  int _boardHours = 6;
  bool _opening = false;

  Venue get v => widget.venue;

  Future<void> _open() async {
    setState(() => _opening = true);
    await runAction(context, () => Backend.i.openRoom(v, boardHours: _boardHours), done: 'Room open — put the code on the tables.');
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return ScrollPage(
      title: 'Tonight',
      subtitle: v.name,
      onRefresh: () async => roomsRev.bump(),
      children: [
        const DemoNote(),
        ShiftCard(venue: v),
        if (!v.verified)
          Padding(
            padding: const EdgeInsets.only(bottom: S.l),
            child: Text('Not verified yet — rooms work, but tabs, vibe and rewards wait until brewdiary verifies you (More › Setup).', style: T.caption(bd)),
          ),
        if (s.can(Cap.openRoom)) ...[
          Glass(
            padding: const EdgeInsets.all(S.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Open tonight\'s room', style: T.row(bd)),
              const SizedBox(height: 4),
              Text('Guests join with the code. The wall screen runs for as long as you choose — then everyone drops off it.', style: T.caption(bd)),
              const SizedBox(height: S.m),
              Segmented<int>(options: const [(4, '4 hours'), (6, '6 hours'), (8, '8 hours')], value: _boardHours, onChanged: (h) => setState(() => _boardHours = h)),
              const SizedBox(height: S.s),
              BdButton('Open a room', icon: Ph.doorOpen, busy: _opening, onTap: _open),
            ]),
          ),
        ],
        const SectionHeader('Rooms'),
        Loader<List<Room>>(
          load: () => Backend.i.rooms(v.id),
          refresh: roomsRev,
          retry: true,
          builder: (context, rooms, loading) {
            if (rooms == null) return const Skeleton(height: 120);
            if (rooms.isEmpty) return const EmptyNote('No rooms yet. Open one and put the code on the tables.');
            return Column(children: [for (final r in rooms) Padding(padding: const EdgeInsets.only(bottom: S.m), child: _RoomCard(venue: v, room: r))]);
          },
        ),
      ],
    );
  }
}

class _RoomCard extends StatefulWidget {
  final Venue venue;
  final Room room;
  const _RoomCard({required this.venue, required this.room});
  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  bool _open = false;

  String get _joinUrl => '${Config.siteUrl}/p/${widget.room.inviteCode}';
  String get _kioskUrl => '${Config.siteUrl}/kiosk/${widget.room.inviteCode}';

  @override
  void initState() {
    super.initState();
    _open = widget.room.boardLive;
  }

  void _showQr() {
    showBdSheet<void>(context, title: 'Room code', builder: (ctx) {
      final bd = ctx.bd;
      return Column(children: [
        QrBox(_joinUrl),
        const SizedBox(height: S.l),
        Text(widget.room.inviteCode, style: T.serif(bd, size: 34).copyWith(letterSpacing: 4)),
        const SizedBox(height: S.s),
        Text('Scan to join tonight, or type the code at bwdy.site.', textAlign: TextAlign.center, style: T.caption(bd)),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final r = widget.room;
    return Glass(
      padding: const EdgeInsets.fromLTRB(S.l, S.m, S.s, S.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: T.row(bd), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                Text('code ${r.inviteCode}', style: T.caption(bd).copyWith(fontFeatures: T.tnum)),
                const SizedBox(width: S.s),
                ToneTag(r.boardLive ? 'live' : 'ended', r.boardLive ? Tone.good : Tone.calm),
              ]),
            ]),
          ),
          IconBtn(Ph.qrCode, tooltip: 'Show the code', onTap: _showQr),
          IconBtn(Ph.shareNetwork, tooltip: 'Share the link', onTap: () => SharePlus.instance.share(ShareParams(text: 'Join us tonight: $_joinUrl'))),
          IconBtn(Ph.monitor, tooltip: 'Wall screen link', onTap: () => SharePlus.instance.share(ShareParams(text: _kioskUrl))),
        ]),
        TextAction(_open ? 'Hide guests' : 'Guests', accent: !_open, icon: Ph.users, onTap: () => setState(() => _open = !_open)),
        if (_open) _RoomGuests(venue: widget.venue, room: r),
      ]),
    );
  }
}

class _RoomGuests extends StatelessWidget {
  final Venue venue;
  final Room room;
  const _RoomGuests({required this.venue, required this.room});

  @override
  Widget build(BuildContext context) {
    return Loader<List<RoomGuest>>(
      load: () => Backend.i.roomGuests(room.id),
      refresh: guestsRev,
      retry: true,
      builder: (context, guests, loading) {
        if (guests == null) return const Skeleton(height: 60);
        if (guests.isEmpty) return const EmptyNote('No one has joined this room yet.');
        return Hairlines(children: [for (final g in guests) _GuestRow(venue: venue, room: room, guest: g)]);
      },
    );
  }
}

class _GuestRow extends StatelessWidget {
  final Venue venue;
  final Room room;
  final RoomGuest guest;
  const _GuestRow({required this.venue, required this.room, required this.guest});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    final live = venue.verified;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(children: [
        Initial(guest.name.isEmpty ? '?' : guest.name[0].toUpperCase(), size: 34),
        const SizedBox(width: S.m),
        Expanded(child: Text(guest.name, style: T.row(bd), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (live && s.can(Cap.recordSpend)) IconBtn(Ph.receipt, tooltip: 'Record ${guest.name}\'s tab', onTap: () => _tab(context)),
        if (live && s.can(Cap.giveVibe)) IconBtn(Ph.handsClapping, tooltip: 'Give ${guest.name} vibe', onTap: () => _vibe(context)),
        if (live && s.can(Cap.redeemPerk)) IconBtn(Ph.gift, tooltip: '${guest.name}\'s rewards', onTap: () => showPerksSheet(context, venue, guest.id, guest.name)),
        if (s.can(Cap.guestCard))
          IconBtn(Ph.caretRight, tooltip: 'Open ${guest.name}\'s card', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GuestDetailScreen(venue: venue, guestId: guest.id, name: guest.name)))),
      ]),
    );
  }

  Future<void> _tab(BuildContext context) async {
    final amount = TextEditingController();
    await showBdSheet<void>(context, title: 'Record a tab', builder: (ctx) {
      final bd = ctx.bd;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${guest.name}\'s tab tonight, in ${venue.currency}. Only staff can record this — a guest can never write their own.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.l),
        LineField(controller: amount, label: 'Amount', hint: '2400', keyboard: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
        const SizedBox(height: S.xl),
        BdButton('Record', onTap: () async {
          final n = double.tryParse(amount.text.replaceAll(',', '').trim());
          if (n == null || n <= 0) return toast(ctx, 'Type the amount.');
          final ok = await runAction(ctx, () => Backend.i.recordSpend(room.id, guest.id, n), done: 'Recorded ${money(n, venue.currency, round: false)}.');
          if (ok && ctx.mounted) Navigator.pop(ctx);
        }),
      ]);
    });
    amount.dispose();
  }

  Future<void> _vibe(BuildContext context) async {
    await showBdSheet<void>(context, title: 'Give vibe', builder: (ctx) {
      final bd = ctx.bd;
      final given = <String>{};
      return StatefulBuilder(builder: (ctx, set) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Positive only — there is no other kind. Each reason once per night.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final r in staffVibeReasons)
              GlassChip(r, done: given.contains(r), onTap: () async {
                final ok = await runAction(ctx, () => Backend.i.giveVibe(room.id, guest.id, r));
                if (ok) set(() => given.add(r));
              }),
          ]),
        ]);
      });
    });
  }
}

/// A guest's standing on every reward tier here, with the button that hands one over.
/// The server re-checks that it was earned — a stale screen can't give one away.
Future<void> showPerksSheet(BuildContext context, Venue venue, String guestId, String name) {
  return showBdSheet<void>(context, title: '$name\'s rewards', builder: (ctx) {
    final bd = ctx.bd;
    return Loader<List<PerkStanding>>(
      load: () => Backend.i.perkStatus(venue.id, guestId),
      refresh: guestsRev,
      retry: true,
      builder: (ctx, tiers, loading) {
        if (tiers == null) return const Skeleton(height: 80);
        if (tiers.isEmpty) return const EmptyNote('No loyalty card here yet — set one up under More › Perks.');
        return Column(children: [
          for (final t in tiers)
            Padding(
              padding: const EdgeInsets.only(bottom: S.m),
              child: Glass(
                padding: const EdgeInsets.all(S.l),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.reward, style: T.row(bd)),
                      const SizedBox(height: 4),
                      Text(
                        t.kind == PerkKind.spend
                            ? '${money(t.progress, t.currency)} of ${money(t.threshold, t.currency)}'
                            : '${t.progress.toStringAsFixed(t.progress % 1 == 0 ? 0 : 1)} of ${t.threshold.toStringAsFixed(0)} visits',
                        style: T.caption(bd).copyWith(fontFeatures: T.tnum),
                      ),
                    ]),
                  ),
                  if (t.earned)
                    AccentPill('Hand over', icon: Ph.gift, onTap: () async {
                      await runAction(ctx, () => Backend.i.redeemPerk(t.perkId, guestId), done: 'Enjoy — ${t.reward.toLowerCase()}.');
                    })
                  else
                    const ToneTag('in progress', Tone.calm),
                ]),
              ),
            ),
        ]);
      },
    );
  });
}
