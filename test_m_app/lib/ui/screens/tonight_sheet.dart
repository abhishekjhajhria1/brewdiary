// Tonight — pace the night and get home safe. Opened from a party room, and from
// the calendar on an evening you've logged a drink.
//
// Pacing: a few water-break nudges for this one night (opt-in; it only ever says
// "slow down"). Getting home: a ride app, directions home, or send a friend where
// you are. Your location is read once, put in the message YOU send, and never
// stored or sent to brewdiary.
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import '../../data/entries.dart';
import '../../data/reminder.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showTonight(BuildContext context) => showBdSheet(context, title: 'Tonight', builder: (_) => const TonightSheet());

/// Evening, and you've logged a drink with alcohol today: offer the Tonight sheet.
bool tonightWorthOffering(DateTime now) {
  final evening = now.hour >= 18 || now.hour < 4;
  if (!evening) return false;
  final day = now.hour < 4 ? toKey(addDays(now, -1)) : toKey(now);
  return entryStore.entries.any((e) => e.date == day && isAlcoholic(e.drink, e.type));
}

/// The ride links for where you are. Plain https links: each opens its app when
/// installed, the website when not.
List<(String, Uri)> rideLinks(String? country) => [
      ('Book an Uber', Uri.parse('https://m.uber.com/ul/?action=setPickup&pickup=my_location')),
      if (country == 'IN') ...[
        ('Book an Ola', Uri.parse('https://book.olacabs.com/')),
        ('Book a Rapido', Uri.parse('https://www.rapido.bike/')),
      ],
      ('Find a taxi nearby', Uri.parse('https://www.google.com/maps/search/?api=1&query=taxi')),
    ];

class TonightSheet extends StatefulWidget {
  const TonightSheet({super.key});
  @override
  State<TonightSheet> createState() => _TonightSheetState();
}

class _TonightSheetState extends State<TonightSheet> {
  bool _locating = false;

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, "Couldn't open that — try from your home screen.");
  }

  Future<void> _togglePace(bool on) async {
    final r = ReminderStore.instance;
    if (!on) return r.stopPacing();
    final ok = await r.startPacing();
    if (!mounted) return;
    toast(context, ok ? "A water-break nudge every 45 minutes, five times. That's all." : 'Notifications are off for brewdiary — allow them in your phone settings.');
  }

  Future<void> _shareWhereIAm() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'Location is off for brewdiary — you can still share from your maps app.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      final link = 'https://maps.google.com/?q=${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
      await SharePlus.instance.share(ShareParams(text: 'Heading home. Here\'s where I am right now: $link'));
    } catch (_) {
      if (mounted) toast(context, "Couldn't get a location fix — try again outside, or share from your maps app.");
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final r = ReminderStore.instance;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Label('Pace yourself'),
        const SizedBox(height: S.s),
        Group(children: [
          SettingRow(
            title: 'Water-break nudges',
            hint: r.pacing ? 'On until ${TimeOfDay.fromDateTime(r.pacingUntil!).format(context)}.' : 'Every 45 minutes, five times, then it stops.',
            trailing: BdToggle(on: r.pacing, label: 'Water-break nudges', onChanged: _togglePace),
          ),
          SettingRow(
            title: 'Morning check-in',
            hint: r.morningAt != null ? 'Tomorrow at 9:30 — water first, and a few kind things.' : 'One note tomorrow morning, with what actually helps.',
            trailing: BdToggle(
              on: r.morningAt != null,
              label: 'Morning check-in',
              onChanged: (v) async {
                final ok = await r.setMorningCheck(v);
                if (!ok && context.mounted) toast(context, 'Notifications are off for brewdiary — allow them in your phone settings.');
              },
            ),
          ),
        ]),
        const SizedBox(height: S.xl),
        const Label('Getting home'),
        const SizedBox(height: S.s),
        Group(children: [
          for (final (name, uri) in rideLinks(PlaceStore.instance.country))
            GroupTile(icon: Ph.carProfile, title: name, chevron: true, onTap: () => _open(uri)),
          GroupTile(
            icon: Ph.house,
            title: 'Directions home',
            subtitle: 'Uses the Home you saved in Google Maps.',
            chevron: true,
            onTap: () => _open(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=Home')),
          ),
          GroupTile(
            icon: Ph.shareNetwork,
            title: _locating ? 'Finding you…' : 'Send a friend where I am',
            subtitle: 'A map link in a message you send. Not stored anywhere.',
            chevron: true,
            onTap: _locating ? null : _shareWhereIAm,
          ),
          GroupTile(icon: Ph.phone, title: 'Call someone', chevron: true, onTap: () => _open(Uri.parse('tel:'))),
        ]),
        const SizedBox(height: S.l),
        Text('Not sure you should drive? Then don\'t — the ride is cheaper than the morning after.', style: T.caption(bd)),
      ]),
    );
  }
}
