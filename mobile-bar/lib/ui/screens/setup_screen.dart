// Setup: the venue's details, its location (for area trends and the area map), verification, and
// — for the owner — deleting it. Once verified, where the venue is, what kind of place
// it is and its web address are fixed (the database refuses a change): the country
// decides which perks are lawful, and the address is printed on every table.
import 'package:brewdiary_core/jurisdiction.dart';
import 'package:brewdiary_core/geo.dart' show venueCell;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import 'venues_screen.dart';

class SetupScreen extends StatefulWidget {
  final Venue venue;
  const SetupScreen({super.key, required this.venue});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _name = TextEditingController(text: widget.venue.name);
  late final _city = TextEditingController(text: widget.venue.city ?? '');
  bool _locating = false;

  Venue get v => Session.instance.venue?.id == widget.venue.id ? Session.instance.venue! : widget.venue;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'Location is off for this app — you can allow it in Settings.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
      // Only a ~1 km cell leaves the phone, never the coordinates. A venue's address is
      // public; people are only ever kept at ~40 km (their own choice, in their diary).
      final cell = venueCell(pos.latitude, pos.longitude);
      if (mounted) await runAction(context, () => Backend.i.updateVenue(v.id, geohash: cell), done: 'Location set.');
    } catch (_) {
      if (mounted) toast(context, 'Couldn\'t get a location — try again outside or near a window.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final s = Session.instance;
    return Scaffold(
      body: Ambient(
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => ScrollPage(
            title: 'Setup',
            back: true,
            tabBar: false,
            children: [
              if (s.can(Cap.editSettings)) ...[
                LineField(controller: _name, label: 'Name', caps: TextCapitalization.words, maxLength: 80),
                const SizedBox(height: S.l),
                LineField(controller: _city, label: 'City', caps: TextCapitalization.words),
                const SizedBox(height: S.l),
                BdButton('Save details', kind: BtnKind.secondary, onTap: () => runAction(context, () => Backend.i.updateVenue(v.id, name: _name.text, city: _city.text), done: 'Saved.')),
              ],
              const SectionHeader('What and where'),
              Group(children: [
                GroupTile(icon: kindIcon(v.kind), title: v.kind.label, subtitle: legalLine(v)),
                GroupTile(icon: Ph.globe, title: countryLabel(v.country) + (v.region == null ? '' : ' · ${v.region}'), subtitle: 'Money in ${v.currency}'),
                GroupTile(icon: Ph.link, title: 'bwdy.site/m/${v.slug}', subtitle: v.verified ? 'Fixed now you\'re verified — it\'s on your tables.' : 'Fixed once you\'re verified.'),
                if (v.kind.alcoholIsChoice)
                  SettingRow(
                    title: 'We serve alcohol',
                    hint: v.verified ? 'Fixed once verified — ask brewdiary to change it.' : 'Changes which loyalty rewards are lawful.',
                    trailing: BdToggle(
                      on: v.servesAlcohol,
                      label: 'Serves alcohol',
                      onChanged: (x) => v.verified ? toast(context, 'Ask brewdiary to change this now you\'re verified.') : runAction(context, () => Backend.i.updateVenue(v.id, servesAlcohol: x)),
                    ),
                  ),
              ]),
              const SectionHeader('Your area'),
              Text(
                v.geohash == null || v.geohash!.isEmpty
                    ? 'Set it once, standing in your venue. We keep a ~1 km cell (never a pin) to show what your area is into and to place you on the area map.'
                    : (v.geohash!.length < 5
                        ? 'Set as a rough ~40 km area. Set it again, standing in the venue, to open the area map.'
                        : 'Set (a ~1 km cell).${v.verified ? ' You can refine it within your area; to move, ask brewdiary.' : ''}'),
                style: T.caption(bd),
              ),
              const SizedBox(height: S.m),
              BdButton(v.geohash == null ? 'Use my location' : 'Set it again', icon: Ph.crosshair, kind: BtnKind.secondary, busy: _locating, onTap: s.can(Cap.editSettings) ? _locate : null),
              const SizedBox(height: S.m),
              SettingRow(
                title: 'Share our totals with the area map',
                hint: 'Counts and bands only, from guests who said yes, in groups of 5+ across 3+ venues. Venues that share see the typical night\'s spend around them.',
                trailing: BdToggle(
                  on: v.areaShare,
                  label: 'Share with the area map',
                  onChanged: (x) => s.can(Cap.editSettings) ? runAction(context, () => Backend.i.updateVenue(v.id, areaShare: x)) : toast(context, 'An owner or manager can change this.'),
                ),
              ),
              if (s.can(Cap.requestVerification)) ...[
                const SectionHeader('Verification'),
                _Verification(venue: v),
              ],
              if (s.can(Cap.deleteVenue)) ...[
                const SectionHeader('Danger zone'),
                BdButton('Delete this venue', kind: BtnKind.quiet, onTap: () async {
                  final yes = await confirm(context, title: 'Delete ${v.name}?', body: 'Its menu, card, rooms and guest book go with it. This can\'t be undone.', yes: 'Delete');
                  if (!yes || !context.mounted) return;
                  final ok = await runAction(context, () => Backend.i.deleteVenue(v.id), done: 'Deleted.');
                  if (ok) {
                    s.leaveVenue();
                    await s.refreshVenues();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Verification extends StatelessWidget {
  final Venue venue;
  const _Verification({required this.venue});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (venue.verified) {
      return const Row(children: [ToneTag('verified', Tone.good)]);
    }
    return Loader<VerificationRequest?>(
      load: () => Backend.i.verification(venue.id),
      refresh: venueRev,
      builder: (context, req, loading) {
        if (loading && req == null) return const Skeleton(height: 80);
        if (req != null) {
          return Glass(
            padding: const EdgeInsets.all(S.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                ToneTag(req.status.name, req.status == VerificationStatus.rejected ? Tone.late : Tone.wait),
              ]),
              const SizedBox(height: S.s),
              Text(
                req.status == VerificationStatus.rejected
                    ? 'We couldn\'t verify this one. Withdraw it and send a new request with better contact details.'
                    : 'We\'ll reach you on ${req.contact} to check this is really your venue. Until then, tabs, vibe and rewards wait.',
                style: T.bodyMuted(bd),
              ),
              TextAction('Withdraw the request', onTap: () => runAction(context, () => Backend.i.withdrawVerification(venue.id))),
            ]),
          );
        }
        return _RequestForm(venue: venue);
      },
    );
  }
}

class _RequestForm extends StatefulWidget {
  final Venue venue;
  const _RequestForm({required this.venue});
  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _contact = TextEditingController();
  final _note = TextEditingController();
  @override
  void dispose() {
    _contact.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('A real person at brewdiary checks every venue before its rewards, tabs and menu go live — a venue can never approve itself.', style: T.caption(bd)),
      const SizedBox(height: S.m),
      LineField(controller: _contact, label: 'How we reach you', hint: 'Phone or email', caps: TextCapitalization.none),
      const SizedBox(height: S.l),
      LineField(controller: _note, label: 'Anything we should know (optional)', maxLength: 500),
      const SizedBox(height: S.l),
      BdButton('Ask to be verified', onTap: () => runAction(context, () => Backend.i.requestVerification(widget.venue.id, _contact.text, note: _note.text), done: 'Sent — we\'ll be in touch.')),
    ]);
  }
}
