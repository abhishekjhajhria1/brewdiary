// A venue's first days: a short list of what's left to set up — get verified, say
// where you are, put the menu up, add the tables, a reward, the team — each one
// gone once it's done. Nothing here blocks service on day one (PLAN M1.14).
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/models.dart';
import '../../data/prefs.dart';
import '../../data/session.dart';
import '../../logic/roles.dart';
import '../screens/floor_setup_screen.dart';
import '../screens/menu_screen.dart';
import '../screens/perks_screen.dart';
import '../screens/setup_screen.dart';
import '../screens/team_screen.dart';
import '../theme.dart';
import 'common.dart';

class _Step {
  final String key;
  final IconData icon;
  final String title;
  final String why;
  final Widget Function(Venue) screen;
  const _Step(this.key, this.icon, this.title, this.why, this.screen);
}

/// What's left to set up, worked out from the venue itself. Pure, for tests.
Future<List<String>> pendingSteps(Venue v, Session s) async {
  final b = Backend.i;
  Future<R?> safe<R>(Future<R> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  final out = <String>[];
  if (!v.verified && s.can(Cap.requestVerification)) {
    final req = await safe(() => b.verification(v.id));
    if (req == null || req.status == VerificationStatus.rejected) out.add('verify');
  }
  if (v.geohash == null && s.can(Cap.editSettings)) out.add('where');
  if (s.can(Cap.editMenu) && ((await safe(() => b.menu(v.id))) ?? const []).isEmpty) out.add('menu');
  if (!v.kind.isCounter && s.can(Cap.editSettings) && ((await safe(() => b.tables(v.id))) ?? const []).isEmpty) out.add('tables');
  if (v.verified && s.can(Cap.editPerks) && ((await safe(() => b.perks(v.id))) ?? const []).isEmpty) out.add('reward');
  if (s.can(Cap.manageTeam) && ((await safe(() => b.staff(v.id))) ?? const []).length <= 1) out.add('team');
  return out;
}

class NextSteps extends StatefulWidget {
  final Venue venue;
  const NextSteps({super.key, required this.venue});
  @override
  State<NextSteps> createState() => _NextStepsState();
}

class _NextStepsState extends State<NextSteps> {
  static final _steps = {
    for (final s in [
      _Step('verify', Ph.sealCheck, 'Get verified', 'Tabs, vibe and rewards start once brewdiary has checked you\'re real.', (v) => SetupScreen(venue: v)),
      _Step('where', Ph.mapPin, 'Say where you are', 'So the right rules apply and the area map can help.', (v) => SetupScreen(venue: v)),
      _Step('menu', Ph.notebook, 'Put your menu up', 'Guests open it from a table tag or QR — and order, if you switch that on.', (v) => MenuScreen(venue: v)),
      _Step('tables', Ph.squaresFour, 'Add your tables', 'Each gets its own tag: the menu with the table known.', (v) => FloorSetupScreen(venue: v)),
      _Step('reward', Ph.gift, 'Add a reward', 'A punch-card for visits — never for buying more.', (v) => PerksScreen(venue: v)),
      _Step('team', Ph.usersThree, 'Bring your team in', 'Each person signs in with their own email and the code you give them.', (v) => TeamScreen(venue: v)),
    ])
      s.key: s,
  };

  String get _hiddenKey => 'nextsteps.hidden.${widget.venue.id}';
  bool get _hidden => Prefs.getString(_hiddenKey) == 'yes';

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (_hidden) return const SizedBox.shrink();
    return Loader<List<String>>(
      load: () => pendingSteps(widget.venue, Session.instance),
      builder: (context, keys, loading) {
        if (keys == null || keys.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader('Getting set up', action: 'Hide', onAction: () async {
            await Prefs.setString(_hiddenKey, 'yes');
            if (mounted) setState(() {});
          }),
          Group(children: [
            for (final k in keys)
              if (_steps[k] != null)
                GroupTile(
                  icon: _steps[k]!.icon,
                  title: _steps[k]!.title,
                  subtitle: _steps[k]!.why,
                  chevron: true,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _steps[k]!.screen(widget.venue)));
                    if (mounted) setState(() {});
                  },
                ),
          ]),
          const SizedBox(height: S.s),
          Text('None of this is needed to serve tonight.', style: T.caption(bd)),
        ]);
      },
    );
  }
}
