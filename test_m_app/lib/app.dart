// The root: theme, the age gate, and the tabbed shell. Mirrors the web layout —
// TopBar (brand · Discover · view toggle · theme) over the page, a glass TabBar at
// the bottom. Together is sign-in only; guests still get the local diary.
import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/auth.dart';
import 'data/base.dart';
import 'data/settings.dart';
import 'ui/screens/bartender_screen.dart';
import 'ui/screens/calendar_screen.dart';
import 'ui/screens/discover_screen.dart';
import 'ui/screens/landing_screen.dart';
import 'ui/screens/party_screens.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/screens/together_screen.dart';
import 'ui/screens/you_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class BrewdiaryApp extends StatelessWidget {
  const BrewdiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) {
        final dark = ThemeStore.instance.isDark;
        final bd = dark ? BD.darkTokens : BD.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
          child: MaterialApp(
            title: 'brewdiary',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: buildTheme(bd),
            home: const _Root(),
          ),
        );
      },
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([PlaceStore.instance, auth]),
      builder: (context, _) {
        Widget body;
        if (!PlaceStore.instance.ageConfirmed) {
          body = const AgeGateScreen();
        } else if (auth.status == AuthStatus.loading) {
          body = const SizedBox.shrink();
        } else {
          body = const Shell();
        }
        return Scaffold(backgroundColor: context.bd.base, body: Ambient(child: body));
      },
    );
  }
}

enum Tab { calendar, together, ninkasi, you }

class Shell extends StatefulWidget {
  /// Off in widget tests, where the native link plugin doesn't exist.
  static bool deepLinks = true;
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Tab _tab = Tab.calendar;
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    if (Shell.deepLinks) _listenForLinks();
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  /// Invite links (`bwdy.site/p/<code>`), public profiles (`/u/<handle>`) and
  /// party pages (`/party/<id>`) open straight into the app when installed.
  void _listenForLinks() {
    final links = AppLinks();
    links.getInitialLink().then((u) {
      if (u != null) _route(u);
    }).catchError((_) {});
    _links = links.uriLinkStream.listen(_route, onError: (_) {});
  }

  void _route(Uri uri) {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.length < 2) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    switch (seg[0]) {
      case 'p':
        nav.push(MaterialPageRoute(builder: (_) => PartyInviteScreen(code: seg[1])));
      case 'u':
        nav.push(MaterialPageRoute(builder: (_) => PublicProfileScreen(handle: seg[1])));
      case 'party':
        nav.push(MaterialPageRoute(builder: (_) => PartyRoomScreen(partyId: seg[1])));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final signedIn = auth.isAuthed;
        final tabs = [Tab.calendar, if (signedIn && db != null) Tab.together, Tab.ninkasi, Tab.you];
        if (!tabs.contains(_tab)) _tab = Tab.calendar;
        final guestHome = !signedIn && _tab == Tab.calendar;

        return Stack(children: [
          Positioned.fill(
            child: guestHome
                ? const LandingScreen()
                : _TabPage(
                    key: ValueKey(_tab),
                    tab: _tab,
                    child: switch (_tab) {
                      Tab.calendar => CalendarScreen(onOpenNinkasi: () => setState(() => _tab = Tab.ninkasi)),
                      Tab.together => const TogetherScreen(),
                      Tab.ninkasi => const BartenderScreen(),
                      Tab.you => const YouScreen(),
                    },
                  ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _TabBar(tabs: tabs, current: _tab, onSelect: (t) => setState(() => _tab = t))),
        ]);
      },
    );
  }
}

/// A scrolling page with the TopBar above it (the Ninkasi chat manages its own scroll).
class _TabPage extends StatelessWidget {
  final Tab tab;
  final Widget child;
  const _TabPage({super.key, required this.tab, required this.child});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    final bar = TopBar(onCalendar: tab == Tab.calendar);
    if (tab == Tab.ninkasi) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
        child: Column(children: [bar, const SizedBox(height: 24), Expanded(child: child)]),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, bottom + 110),
      children: [bar, const SizedBox(height: 24), child],
    );
  }
}

class TopBar extends StatelessWidget {
  final bool onCalendar;
  const TopBar({super.key, this.onCalendar = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Text('brewdiary', style: T.serif(bd, size: 20, italic: true, color: bd.muted)),
        const Spacer(),
        AccentPill('Discover', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiscoverScreen()))),
        if (onCalendar) ...[const SizedBox(width: 6), const _ViewToggle()],
        const SizedBox(width: 2),
        const ThemeToggleButton(),
      ]),
    );
  }
}

/// Month ↔ year squircle.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle();
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: CalendarViewStore.instance,
      builder: (context, _) {
        final year = CalendarViewStore.instance.view == CalendarView.year;
        return Semantics(
          label: year ? 'Show the month' : 'Show the whole year',
          button: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              CalendarViewStore.instance.toggle();
            },
            child: Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: bd.glass, borderRadius: BorderRadius.circular(11), border: Border.all(color: bd.glassBorder)),
              child: GridView.count(
                crossAxisCount: year ? 4 : 2,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                physics: const NeverScrollableScrollPhysics(),
                children: List.generate(year ? 16 : 4, (i) => Container(decoration: BoxDecoration(color: bd.ycell(1 + (i * 3) % 4), borderRadius: BorderRadius.circular(1.5)))),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  final List<Tab> tabs;
  final Tab current;
  final ValueChanged<Tab> onSelect;
  const _TabBar({required this.tabs, required this.current, required this.onSelect});

  static const _labels = {Tab.calendar: 'Calendar', Tab.together: 'Together', Tab.ninkasi: 'Ninkasi', Tab.you: 'You'};

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom > 0 ? bottom : 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rTile),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(color: bd.glassStrong, borderRadius: BorderRadius.circular(rTile), border: Border.all(color: bd.glassBorder)),
            child: Row(children: [
              for (final t in tabs)
                Expanded(
                  child: Semantics(
                    selected: t == current,
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelect(t);
                      },
                      child: SizedBox(
                        height: 52,
                        child: Stack(alignment: Alignment.center, children: [
                          if (t == current) Positioned(top: 4, child: Container(width: 32, height: 4, decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(99)))),
                          Text(
                            _labels[t]!.toUpperCase(),
                            style: T.sans(bd, size: 11, spacing: 11 * .14, weight: t == current ? FontWeight.w500 : FontWeight.w400, color: t == current ? bd.ink : bd.faint),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
