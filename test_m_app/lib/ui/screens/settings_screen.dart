// Settings — the settings half of src/components/you/You.tsx, laid out as a phone
// settings page: grouped rows, each group with a sentence-case header and a quiet
// footer that says what the switch really does. Everything that needs more than a
// row (handle, public profile, standing, blocks, venue notes) opens in a sheet.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/handles.dart';
import 'package:brewdiary_core/jurisdiction.dart';
import 'package:brewdiary_core/misc.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import '../../data/auth.dart';
import '../../data/base.dart';
import '../../data/entries.dart';
import '../../data/friends.dart';
import '../../data/reminder.dart';
import '../../data/safety.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';
import 'landing_screen.dart' show showAuthSheet;
import 'profile_screen.dart';

/// Settings on a page of its own (kept for links); in the app they live inline at
/// the bottom of You, like the website — see [SettingsBody].
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const SubPage(title: 'Settings', child: SettingsBody());
}

/// Every setting, as one column: shown at the bottom of the You tab (no gear to find).
class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final profile = auth.profile;
        final cloud = profile != null && db != null;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _AccountCard(),
          const _Header('Appearance'),
          const _AppearanceGroup(),
          const _Header('Reminder'),
          const _ReminderGroup(),
          const _Header('Where you are'),
          const _PlaceGroup(),
          const _Header('Gentle limits'),
          const _LimitsGroup(),
          const _Header('Extras'),
          const _ExtrasGroup(),
          const _Header('Ninkasi'),
          const _NinkasiGroup(),
          if (cloud) ...[
            const _Header('Together and privacy'),
            const _PrivacyGroup(),
          ],
          const _Header('Your data'),
          _DataGroup(cloud: cloud),
          const _Header('About'),
          Group(children: [
            GroupTile(icon: Ph.shieldCheck, title: 'Privacy', trailing: Icon(Ph.arrowUpRight, size: 16, color: context.bd.faint), onTap: () => launchUrl(Config.api('/privacy'), mode: LaunchMode.externalApplication)),
            GroupTile(icon: Ph.fileText, title: 'Terms', trailing: Icon(Ph.arrowUpRight, size: 16, color: context.bd.faint), onTap: () => launchUrl(Config.api('/terms'), mode: LaunchMode.externalApplication)),
          ]),
          if (profile != null) ...[
            const SizedBox(height: S.x3),
            BdButton('Sign out', kind: BtnKind.secondary, icon: Ph.signOut, onTap: () async {
              if (await confirm(context, title: 'Sign out?', body: 'Your diary stays safe in your account — sign back in any time.', yes: 'Sign out', no: 'Stay signed in')) {
                await auth.signOut();
              }
            }),
          ],
        ]);
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header(this.title);
  @override
  Widget build(BuildContext context) => SectionHeader(title, padding: const EdgeInsets.only(top: S.x3, bottom: S.s, left: S.xs));
}

// ── account ──────────────────────────────────────────────────────────────────
class _AccountCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final profile = auth.profile;
    if (profile == null) {
      return Group(
        footer: 'Your diary lives on this phone until you make one — then it comes with you.',
        children: [GroupTile(icon: Ph.signIn, title: 'Sign in or create a diary', chevron: true, onTap: () => showAuthSheet(context, signup: true))],
      );
    }
    final cloud = db != null;
    return Group(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: S.m),
        child: Row(children: [
          Initial(profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(), size: 48),
          const SizedBox(width: S.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 18, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(profile.handle.isNotEmpty ? '@${profile.handle}' : (cloud ? 'Signed in' : 'A diary on this phone'), style: T.caption(bd)),
            ]),
          ),
        ]),
      ),
      if (cloud && profile.handle.isNotEmpty) GroupTile(icon: Ph.at, title: 'Your handle', subtitle: '@${profile.handle}', chevron: true, onTap: () => showBdSheet(context, title: 'Your handle', builder: (_) => _HandleSheet(handle: profile.handle))),
      if (cloud)
        Loader<ProfileSettings>(
          refresh: profileRev,
          load: ProfileApi.settings,
          builder: (context, s, _) => GroupTile(
            icon: Ph.globe,
            title: 'Public profile',
            subtitle: _visibilityLabel[s?.visibility ?? ProfileVisibility.friends],
            chevron: true,
            onTap: () => showBdSheet(context, title: 'Public profile', builder: (_) => _ProfilePrivacySheet(handle: profile.handle)),
          ),
        ),
      if (cloud) GroupTile(icon: Ph.sealCheck, title: 'Your standing', chevron: true, onTap: () => showBdSheet(context, title: 'Your standing', builder: (_) => const _TrustSheet())),
    ]);
  }
}

const _visibilityLabel = {ProfileVisibility.friends: 'Friends only', ProfileVisibility.fof: 'Friends of friends', ProfileVisibility.public: 'Public'};

/// Trade your handle for one we spin up — you never type it, so it stays clean.
class _HandleSheet extends StatefulWidget {
  final String handle;
  const _HandleSheet({required this.handle});
  @override
  State<_HandleSheet> createState() => _HandleSheetState();
}

class _HandleSheetState extends State<_HandleSheet> {
  late String _candidate = reroll(widget.handle);
  bool _busy = false;
  String? _note;
  int _taken = 0;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final res = await auth.updateHandle(_candidate);
    if (!mounted) return;
    if (res.ok) {
      Navigator.pop(context);
      toast(context, 'You are @$_candidate now.');
      return;
    }
    setState(() {
      _busy = false;
      if (res.error == 'taken') {
        _taken++;
        _candidate = reroll(_candidate, attempt: _taken);
        _note = "Someone just took that one — here's another.";
      } else {
        _note = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('How friends find you, and your address at /u/<handle>. Trade it whenever you like — you pick from ones we spin up, so it stays clean.', style: T.bodyMuted(bd)),
      const SizedBox(height: S.xxl),
      Glass(
        padding: const EdgeInsets.fromLTRB(S.l, S.l, S.s, S.l),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Now @${widget.handle}', style: T.caption(bd)),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: Motion.fast,
                child: Text('@$_candidate', key: ValueKey(_candidate), style: T.serif(bd, size: 24, color: bd.accentText)),
              ),
            ]),
          ),
          IconBtn(Ph.arrowsClockwise, tooltip: 'Another one', onTap: _busy ? null : () => setState(() => _candidate = reroll(_candidate, attempt: _taken))),
        ]),
      ),
      if (_note != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(_note!, style: T.sans(bd, size: 14, color: bd.accentText))),
      const SizedBox(height: S.xxl),
      BdButton('Use @$_candidate', busy: _busy, onTap: _save),
      const SizedBox(height: S.s),
      BdButton('Keep @${widget.handle}', kind: BtnKind.secondary, onTap: _busy ? null : () => Navigator.pop(context)),
    ]);
  }
}

class _ProfilePrivacySheet extends StatefulWidget {
  final String handle;
  const _ProfilePrivacySheet({required this.handle});
  @override
  State<_ProfilePrivacySheet> createState() => _ProfilePrivacySheetState();
}

class _ProfilePrivacySheetState extends State<_ProfilePrivacySheet> {
  final _link = TextEditingController();
  bool _loadedLink = false;
  bool _saving = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<ProfileSettings>(
      refresh: profileRev,
      load: ProfileApi.settings,
      builder: (context, s, loading) {
        final vis = s?.visibility ?? ProfileVisibility.friends;
        if (s != null && !_loadedLink) {
          _loadedLink = true;
          _link.text = s.socialHandle;
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Who can open your profile at /u/${widget.handle}. It shows a streak mosaic and totals — never your notes, never your spend, never where you were.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.xl),
          Group(children: [
            for (final v in ProfileVisibility.values)
              GroupTile(
                title: _visibilityLabel[v]!,
                trailing: vis == v ? Icon(PhBold.check, size: 18, color: bd.accentText) : null,
                onTap: () => ProfileApi.setVisibility(v),
              ),
          ]),
          if (vis != ProfileVisibility.friends) ...[
            const SizedBox(height: S.s),
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction('See your profile as others do', accent: true, icon: Ph.eye, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicProfileScreen(handle: widget.handle)))),
            ),
          ],
          const SizedBox(height: S.xl),
          const Label('One social link'),
          const SizedBox(height: S.s),
          GlassField(controller: _link, hint: '@you or https://…', caps: TextCapitalization.none, icon: Ph.linkSimple, keyboard: TextInputType.url),
          const SizedBox(height: S.s),
          Text("Anyone who can see your profile sees this. Add only a handle you're fine with strangers finding — never your phone, email, or address.", style: T.caption(bd)),
          const SizedBox(height: S.xl),
          BdButton('Save link', busy: _saving, onTap: () async {
            setState(() => _saving = true);
            await ProfileApi.setSocialHandle(_link.text);
            if (!context.mounted) return;
            setState(() => _saving = false);
            toast(context, 'Saved.');
          }),
        ]);
      },
    );
  }
}

/// Your standing — a quiet, coarse trust signal, never a score of you as a person.
class _TrustSheet extends StatelessWidget {
  const _TrustSheet();
  static const _nextAt = {TrustLevel.fresh: 4.0, TrustLevel.active: 14.0, TrustLevel.established: 34.0};
  static const _nextLevel = {TrustLevel.fresh: TrustLevel.active, TrustLevel.active: TrustLevel.established, TrustLevel.established: TrustLevel.trusted};

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final profile = auth.profile!;
    return Loader<(int, int)>(
      refresh: Listenable.merge([vouchRev, friendsRev]),
      load: () async => ((await FriendsApi.friends()).length, await VouchApi.myCount()),
      builder: (context, data, _) {
        final created = DateTime.tryParse(profile.createdAt) ?? appNow();
        final signals = TrustSignals(
          tenureDays: math.max(0, appNow().difference(created).inDays),
          activeDays: entryStore.entries.map((e) => e.date).toSet().length,
          friends: data?.$1 ?? 0,
          presenceChecked: profile.presenceChecked,
          vouches: data?.$2 ?? 0,
        );
        final level = trustLevelFrom(signals);
        final score = trustScore(signals);
        final nextAt = _nextAt[level];
        final pct = nextAt == null ? 1.0 : math.min(1.0, score / nextAt);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(trustLabel[level]!, style: T.serif(bd, size: 30, color: bd.accentText)),
          const SizedBox(height: S.s),
          Text("A quiet signal that you're a real, settled person — it grows as you use brewdiary and connect with friends, and helps others feel comfortable meeting up. It's never a score of you as a person, and nobody sees a ranking.", style: T.bodyMuted(bd)),
          if (nextAt != null) ...[
            const SizedBox(height: S.xl),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(children: [
                Container(height: 6, color: bd.ink.withValues(alpha: .1)),
                FractionallySizedBox(widthFactor: pct, child: Container(height: 6, color: bd.accent)),
              ]),
            ),
            const SizedBox(height: S.s),
            Text('Keep logging and connecting to reach ${trustLabel[_nextLevel[level]]}.', style: T.caption(bd)),
          ],
          const SizedBox(height: S.xl),
          Group(children: [
            GroupTile(title: 'Days here', trailing: Text('${signals.tenureDays}', style: T.row(bd, color: bd.muted))),
            GroupTile(title: 'Days logged', trailing: Text('${signals.activeDays}', style: T.row(bd, color: bd.muted))),
            GroupTile(title: 'Friends', trailing: Text('${signals.friends}', style: T.row(bd, color: bd.muted))),
            GroupTile(title: 'Friends who vouch for you', trailing: Text('${signals.vouches}', style: T.row(bd, color: bd.muted))),
            GroupTile(title: 'Photo-ID verification', trailing: Text('Coming soon', style: T.caption(bd))),
          ]),
        ]);
      },
    );
  }
}

// ── appearance ───────────────────────────────────────────────────────────────
class _AppearanceGroup extends StatelessWidget {
  const _AppearanceGroup();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => Group(
        footer: 'System follows your phone’s light or dark setting.',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.s),
            child: Segmented<ThemeMode>(
              options: const [(ThemeMode.dark, 'Dark'), (ThemeMode.light, 'Light'), (ThemeMode.system, 'System')],
              value: ThemeStore.instance.mode,
              onChanged: ThemeStore.instance.set,
            ),
          ),
        ],
      ),
    );
  }
}

// ── reminder ─────────────────────────────────────────────────────────────────
/// The nightly reminder — a real scheduled notification on the phone.
class _ReminderGroup extends StatelessWidget {
  const _ReminderGroup();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final r = ReminderStore.instance;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) => Group(children: [
        SettingRow(
          title: 'Nightly reminder',
          hint: "One quiet nudge in the evening, skipped on days you've already written in.",
          trailing: BdToggle(
            on: r.on,
            label: 'Nightly reminder',
            onChanged: (v) async {
              final ok = await r.setOn(v);
              if (!ok && context.mounted) toast(context, 'Notifications are off for brewdiary — allow them in your phone settings.');
            },
          ),
        ),
        if (r.on)
          GroupTile(
            title: 'Remind me at',
            trailing: Text(r.time.format(context), style: T.row(bd, color: bd.accentText)),
            onTap: () async {
              final t = await pickTime(context, title: 'Remind me at', initial: r.time);
              if (t != null) r.setTime(t);
            },
          ),
      ]),
    );
  }
}

// ── where you are ────────────────────────────────────────────────────────────
/// The traveller's switch — what YOU can do follows where you ARE.
class _PlaceGroup extends StatelessWidget {
  const _PlaceGroup();

  Future<void> _changeCountry(BuildContext context) async {
    final place = PlaceStore.instance;
    final current = place.country ?? 'IN';
    final known = knownCountries.any((c) => c.$1 == current);
    final next = await pickCountry(context, current: known ? current : 'ZZ');
    if (next == null || next == current || !context.mounted) return;
    final needs = place.moveTo(next);
    if (needs == null) {
      toast(context, 'Now set to ${next == 'ZZ' ? 'somewhere else' : countryLabel(next)}.');
      return;
    }
    await showBdSheet(context, title: 'One more check', builder: (_) => _ReconfirmAge(country: next, age: needs));
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: PlaceStore.instance,
      builder: (context, _) {
        final place = PlaceStore.instance;
        final code = place.country;
        final known = knownCountries.any((c) => c.$1 == code);
        return Group(
          footer: "Travelling? Set this to the country you're in. It sets your currency and the legal drinking age we hold you to — that follows where you are, not where you're from.",
          children: [
            GroupTile(
              icon: Ph.globe,
              title: 'Country',
              trailing: Text(known ? countryLabel(code) : 'Somewhere else', style: T.row(bd, color: bd.muted)),
              chevron: true,
              onTap: () => _changeCountry(context),
            ),
            GroupTile(
              icon: Ph.money,
              title: 'Currency for Split',
              trailing: Text('${place.currency}  ${currencySymbol(place.currency)}', style: T.row(bd, color: bd.muted)),
              chevron: true,
              onTap: () async {
                final c = await pickCurrency(context, current: place.currency);
                if (c != null) place.saveCurrency(c);
              },
            ),
          ],
        );
      },
    );
  }
}

/// Moving somewhere with a higher legal age means confirming it again.
class _ReconfirmAge extends StatefulWidget {
  final String country;
  final int age;
  const _ReconfirmAge({required this.country, required this.age});
  @override
  State<_ReconfirmAge> createState() => _ReconfirmAgeState();
}

class _ReconfirmAgeState extends State<_ReconfirmAge> {
  DateTime? _dob;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final where = widget.country == 'ZZ' ? 'there' : 'in ${countryLabel(widget.country)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("The legal drinking age $where is ${widget.age}+, higher than the one you confirmed. Confirm your date of birth again and we'll move you — it's checked, never saved.", style: T.bodyMuted(bd)),
      const SizedBox(height: S.xl),
      PickerField(
        label: 'Date of birth',
        value: _dob == null ? 'Choose a date' : writtenDate(_dob!),
        placeholder: _dob == null,
        icon: Ph.calendarBlank,
        onTap: () async {
          final now = appNow();
          final d = await pickDate(context, title: 'Date of birth', initial: _dob ?? DateTime(now.year - 25, now.month, now.day), first: DateTime(now.year - 110), last: now);
          if (d != null) {
            setState(() {
              _dob = d;
              _error = null;
            });
          }
        },
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
      const SizedBox(height: S.xxl),
      BdButton('Confirm and move', onTap: _dob == null
          ? null
          : () {
              if (PlaceStore.instance.confirmAge(_dob!, widget.country == 'ZZ' ? null : widget.country)) {
                Navigator.pop(context);
                toast(context, 'Now set to ${widget.country == 'ZZ' ? 'somewhere else' : countryLabel(widget.country)}.');
              } else {
                setState(() => _error = 'You need to be ${widget.age}+ there — your country stays as it was.');
              }
            }),
    ]);
  }
}

// ── gentle limits ────────────────────────────────────────────────────────────
/// Gentle limits — both OFF by default, both on-device only.
class _LimitsGroup extends StatelessWidget {
  const _LimitsGroup();
  @override
  Widget build(BuildContext context) {
    final g = GoalsStore.instance;
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) => Group(
        footer: 'Optional, and off unless you set one. They stay on this phone — a private intention never leaves it.',
        children: [
          _StepperRow(title: 'Weekly limit', hint: 'Alcoholic drinks in a rolling 7 days.', value: g.weeklyLimit, start: 7, max: goalMax[GoalKey.weeklyLimit]!, onChanged: (v) => g.set(GoalKey.weeklyLimit, v)),
          _StepperRow(title: 'Dry days', hint: 'Days with nothing alcoholic, per week.', value: g.dryDays, start: 2, max: goalMax[GoalKey.dryDays]!, onChanged: (v) => g.set(GoalKey.dryDays, v)),
        ],
      ),
    );
  }
}

/// − value + ; stepping below 1 switches it off.
class _StepperRow extends StatelessWidget {
  final String title;
  final String hint;
  final int? value;
  final int start;
  final int max;
  final ValueChanged<int?> onChanged;
  const _StepperRow({required this.title, required this.hint, required this.value, required this.start, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final v = value;
    return SettingRow(
      title: title,
      hint: hint,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconBtn(Ph.minus, glass: true, size: 18, tooltip: 'Lower $title', onTap: v == null ? null : () => onChanged(v - 1 <= 0 ? null : v - 1)),
        SizedBox(
          width: 40,
          child: Semantics(
            liveRegion: true,
            child: Text(v == null ? 'Off' : '$v', textAlign: TextAlign.center, style: T.sans(bd, size: 16, weight: FontWeight.w600, color: v == null ? bd.faint : bd.ink).copyWith(fontFeatures: T.tnum)),
          ),
        ),
        IconBtn(Ph.plus, glass: true, size: 18, tooltip: 'Raise $title', onTap: v != null && v >= max ? null : () => onChanged(v == null ? start : v + 1)),
      ]),
    );
  }
}

// ── extras ───────────────────────────────────────────────────────────────────
class _ExtrasGroup extends StatelessWidget {
  const _ExtrasGroup();
  static const _glassSizes = [200, 250, 300, 330, 500];

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final x = ExtrasStore.instance;
    return ListenableBuilder(
      listenable: x,
      builder: (context, _) => Group(
        footer: 'Optional trackers. Turn one on and a small counter shows up on your calendar for today.',
        children: [
          for (final e in extras) ...[
            SettingRow(title: e.label, hint: e.hint, trailing: BdToggle(on: x.isOn(e.key), label: e.label, onChanged: (v) => x.set(e.key, v))),
            if (e.key == ExtraKey.water && x.isOn(ExtraKey.water))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Glass size — optional, adds a volume', style: T.caption(bd)),
                  Wrap(spacing: S.s, children: [
                    BdChip('None', active: x.waterMl == null, onTap: () => x.setWaterMl(null)),
                    for (final ml in _glassSizes) BdChip('$ml ml', active: x.waterMl == ml, onTap: () => x.setWaterMl(ml)),
                  ]),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}

// ── ninkasi ──────────────────────────────────────────────────────────────────
class _NinkasiGroup extends StatelessWidget {
  const _NinkasiGroup();
  @override
  Widget build(BuildContext context) {
    final t = TrainingStore.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) => Group(children: [
        SettingRow(
          title: 'Help train Ninkasi',
          hint: 'Keep your chats with Ninkasi on this phone to teach her your taste${t.count > 0 ? ' · ${t.count} saved' : ''}.',
          trailing: BdToggle(on: t.collecting, label: 'Help train Ninkasi', onChanged: t.setCollecting),
        ),
        if (t.count > 0)
          GroupTile(
            icon: Ph.broom,
            title: 'Clear saved chats',
            destructive: true,
            onTap: () async {
              if (await confirm(context, title: 'Clear saved chats?', body: 'The ${t.count} chats kept on this phone for training are deleted.', yes: 'Clear')) t.clear();
            },
          ),
      ]),
    );
  }
}

// ── together & privacy (cloud) ───────────────────────────────────────────────
/// Anonymous trends (+ optional coarse area) and the leaderboard — both default OFF.
class _PrivacyGroup extends StatefulWidget {
  const _PrivacyGroup();
  @override
  State<_PrivacyGroup> createState() => _PrivacyGroupState();
}

class _PrivacyGroupState extends State<_PrivacyGroup> {
  bool _locating = false;

  Future<void> _setArea() async {
    setState(() => _locating = true);
    String? msg;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        msg = 'Location permission was declined — no worries, it stays off.';
      } else {
        final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)));
        await ProfileApi.setTrendsGeo(encodeGeohash(p.latitude, p.longitude));
      }
    } catch (_) {
      msg = "Couldn't read a location just now. Try again.";
    }
    if (!mounted) return;
    setState(() => _locating = false);
    if (msg != null) toast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Loader<ProfileSettings>(
        refresh: profileRev,
        load: ProfileApi.settings,
        builder: (context, s, loading) {
          final settings = s ?? const ProfileSettings();
          return Group(
            footer: "There's no always-on switch for venue screens: in a bar's room you choose, for that night only, whether to appear on its screen and whether your tab shows.",
            children: [
              SettingRow(
                title: 'Anonymous taste trends',
                hint: 'Count my logs in the “what’s pouring” trends — counts only, never my name or notes.',
                trailing: BdToggle(on: settings.shareTrends, label: 'Anonymous taste trends', onChanged: ProfileApi.setShareTrends),
              ),
              if (settings.shareTrends)
                settings.trendsGeo != null
                    ? GroupTile(
                        icon: Ph.mapPin,
                        title: 'Area set',
                        subtitle: 'A rough ~40 km cell — never your exact spot.',
                        trailing: TextAction('Clear', onTap: () => ProfileApi.setTrendsGeo(null)),
                      )
                    : GroupTile(
                        icon: Ph.navigationArrow,
                        title: _locating ? 'Locating…' : 'Set my area from location',
                        subtitle: 'So nearby bars can read the local taste — never your exact spot.',
                        trailing: _locating ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: bd.muted)) : null,
                        onTap: _locating ? null : _setArea,
                      ),
              if (settings.shareTrends)
                Loader<bool?>(
                  refresh: profileRev,
                  load: ProfileApi.shareNightsOut,
                  builder: (context, on, _) => on == null
                      ? const SizedBox.shrink()
                      : SettingRow(
                          title: 'Neighbourhood maps',
                          hint: 'Also count me where I go out (the venue rooms I join) — only in groups of 5+ people across 3+ venues. Never my name, never which venue.',
                          trailing: BdToggle(on: on, label: 'Neighbourhood maps', onChanged: ProfileApi.setShareNightsOut),
                        ),
                ),
              SettingRow(
                title: 'Leaderboard in Together',
                hint: 'Show the board — and put me on it, next to friends who also opted in. Never your spend.',
                trailing: BdToggle(on: settings.competeVisible, label: 'Leaderboard in Together', onChanged: _setCompete),
              ),
            ],
          );
        },
      ),
      const _SafetyRows(),
    ]);
  }

  static Future<void> _setCompete(bool v) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('profiles').update({'compete_visible': v}).eq('id', me);
    profileRev.bump();
    pointsRev.bump();
  }
}

/// Blocked people and venue notes — shown only when there's something to show.
class _SafetyRows extends StatefulWidget {
  const _SafetyRows();
  @override
  State<_SafetyRows> createState() => _SafetyRowsState();
}

class _SafetyRowsState extends State<_SafetyRows> {
  final _booksRev = Rev();
  @override
  Widget build(BuildContext context) {
    return Loader<(List<BlockedPerson>, List<VenueBook>)>(
      refresh: Listenable.merge([safetyRev, _booksRev]),
      load: () async => (await SafetyApi.blocks(), await VenueBooksApi.mine()),
      builder: (context, data, _) {
        final blocked = data?.$1 ?? const <BlockedPerson>[];
        final books = data?.$2 ?? const <VenueBook>[];
        if (blocked.isEmpty && books.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: S.m),
          child: Group(children: [
            if (blocked.isNotEmpty)
              GroupTile(icon: Ph.prohibit, title: 'Blocked people', subtitle: '${blocked.length}', chevron: true, onTap: () => showBdSheet(context, title: 'Blocked people', builder: (_) => const _BlockedSheet())),
            if (books.isNotEmpty)
              GroupTile(
                icon: Ph.notebook,
                title: 'Notes venues keep on you',
                subtitle: '${books.length} ${books.length == 1 ? 'venue' : 'venues'}',
                chevron: true,
                onTap: () async {
                  await showBdSheet(context, title: 'Venue notes', builder: (_) => const _VenueBooksSheet());
                  _booksRev.bump();
                },
              ),
          ]),
        );
      },
    );
  }
}

class _BlockedSheet extends StatelessWidget {
  const _BlockedSheet();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<BlockedPerson>>(
      refresh: safetyRev,
      load: SafetyApi.blocks,
      builder: (context, list, _) {
        final people = list ?? const <BlockedPerson>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("You don't see each other's plans, and neither of you turns up in the other's search. Unblock to undo that.", style: T.bodyMuted(bd)),
          const SizedBox(height: S.xl),
          if (list == null)
            const Skeleton(height: 56)
          else if (people.isEmpty)
            const EmptyNote('Nobody is blocked.')
          else
            Group(children: [
              for (final p in people) GroupTile(title: p.name, subtitle: '@${p.handle}', trailing: TextAction('Unblock', onTap: () => SafetyApi.unblock(p.id))),
            ]),
        ]);
      },
    );
  }
}

/// Transparency: every venue that keeps a first-party note on you, and a Forget button.
class _VenueBooksSheet extends StatefulWidget {
  const _VenueBooksSheet();
  @override
  State<_VenueBooksSheet> createState() => _VenueBooksSheetState();
}

class _VenueBooksSheetState extends State<_VenueBooksSheet> {
  final _rev = Rev();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Loader<List<VenueBook>>(
      refresh: _rev,
      load: VenueBooksApi.mine,
      builder: (context, books, _) {
        final list = books ?? const <VenueBook>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("A bar you've visited can keep its own notes on you — never your diary or what you do elsewhere. Here's every one, and you can erase any of them.", style: T.bodyMuted(bd)),
          const SizedBox(height: S.xl),
          if (books == null)
            const Skeleton(height: 72)
          else if (list.isEmpty)
            const EmptyNote('No venue keeps a note on you.')
          else
            Group(children: [
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.m),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.venueName, style: T.row(bd)),
                        if (b.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(b.body, style: T.body(bd, color: bd.muted))),
                        if (b.tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(b.tags.map((t) => '#$t').join(' '), style: T.caption(bd))),
                      ]),
                    ),
                    TextAction('Forget', onTap: () async {
                      await VenueBooksApi.forget(b.venueId);
                      _rev.bump();
                    }),
                  ]),
                ),
            ]),
        ]);
      },
    );
  }
}

// ── your data ────────────────────────────────────────────────────────────────
/// Export/import, the demo, and the rights: a copy of everything, or deletion.
class _DataGroup extends StatefulWidget {
  final bool cloud;
  const _DataGroup({required this.cloud});
  @override
  State<_DataGroup> createState() => _DataGroupState();
}

class _DataGroupState extends State<_DataGroup> {
  bool _busy = false;

  Future<void> _share(String json, String name) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name-${todayKey()}.json');
    await f.writeAsString(json);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')]));
  }

  Future<void> _exportDiary() => _share(const JsonEncoder.withIndent('  ').convert(entryStore.entries.map((e) => e.toJson()).toList()), 'brewdiary');

  Future<void> _import() async {
    try {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (r.isEmpty || r.first.path == null) return;
      final data = jsonDecode(utf8.decode(await File(r.first.path!).readAsBytes()));
      if (data is! List) throw const FormatException();
      final clean = data.map(Entry.tryParse).whereType<Entry>().toList();
      if (!mounted) return;
      if (await confirm(context, title: 'Replace your diary?', body: 'This swaps your diary for the ${clean.length} entries in that file.', yes: 'Replace')) {
        entryStore.replaceAll(clean);
      }
    } catch (_) {
      if (mounted) toast(context, "That file couldn't be read.");
    }
  }

  Future<void> _exportEverything() async {
    setState(() => _busy = true);
    final r = await AccountApi.exportEverything();
    if (r.json != null) await _share(r.json!, 'brewdiary-everything');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.error != null) toast(context, r.error!);
  }

  Future<void> _deleteAccount() async {
    final yes = await confirm(
      context,
      title: 'Delete everything?',
      body: "Every entry, photo, friendship and point is destroyed. This cannot be undone, and we can't get it back for you. Download your data first if you want to keep it.",
      yes: 'Yes, delete it all',
      no: 'Keep my account',
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    final err = await AccountApi.deleteAccount();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    return Group(
      footer: widget.cloud ? 'Deleting your account is immediate and permanent — the diary, the photos, the points, all of it.' : null,
      children: [
        GroupTile(icon: Ph.export, title: 'Export my diary', subtitle: 'A JSON file of every entry', onTap: _exportDiary),
        GroupTile(icon: Ph.fileArrowUp, title: 'Import a diary file', onTap: _import),
        if (widget.cloud) GroupTile(icon: Ph.downloadSimple, title: 'Download everything we hold', onTap: _busy ? null : _exportEverything),
        GroupTile(icon: Ph.arrowsClockwise, title: 'Reseed the demo month', onTap: () async {
          if (await confirm(context, title: 'Reseed the demo?', body: 'Your diary is replaced with a sample month.', yes: 'Reseed')) entryStore.reseed();
        }),
        GroupTile(icon: Ph.eraser, title: 'Reset diary', destructive: true, onTap: () async {
          if (await confirm(context, title: 'Reset your diary?', body: 'Every entry is removed. This cannot be undone.', yes: 'Reset')) entryStore.resetAll();
        }),
        if (widget.cloud) GroupTile(icon: Ph.trash, title: 'Delete my account', destructive: true, onTap: _busy ? null : _deleteAccount),
      ],
    );
  }
}
