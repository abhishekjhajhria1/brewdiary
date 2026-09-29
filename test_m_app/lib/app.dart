// The root: themes, the age gate, and the tabbed shell.
//
// Shell: each tab is its own scrolling page (pinned frosted top bar + large title,
// see ui/widgets/page.dart) kept alive in an IndexedStack, and a floating glass tab
// bar with icon + label that slides away while the keyboard is up. Together is
// always in the bar; until you're signed in to the cloud it's the introduction.
import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/menus.dart';
import 'data/auth.dart';
import 'data/base.dart';
import 'data/entries.dart';
import 'data/reminder.dart';
import 'data/settings.dart';
import 'ui/screens/bartender_screen.dart';
import 'ui/screens/calendar_screen.dart';
import 'ui/screens/discover_screen.dart';
import 'ui/screens/landing_screen.dart';
import 'ui/screens/menu_screen.dart';
import 'ui/screens/morning_after.dart';
import 'ui/screens/party_screens.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/screens/split_screen.dart';
import 'ui/screens/together_intro.dart';
import 'ui/screens/together_screen.dart';
import 'ui/screens/you_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/common.dart';
import 'ui/widgets/moments.dart';
import 'ui/widgets/page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class BrewdiaryApp extends StatelessWidget {
  const BrewdiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => MaterialApp(
        title: 'brewdiary',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildTheme(BD.light),
        darkTheme: buildTheme(BD.darkTokens),
        themeMode: ThemeStore.instance.mode,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
            // Honour the person's text size, within the range the layouts are built for.
            child: MediaQuery(
              data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: .9, maxScaleFactor: 1.3)),
              child: KeyboardScope(inset: mq.viewInsets.bottom, child: child!),
            ),
          );
        },
        home: const _Root(),
      ),
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
        // The scaffold resizes for the keyboard (so a focused field scrolls into
        // view); the ambient layer stays outside it so the background never jumps.
        return Ambient(child: Scaffold(backgroundColor: Colors.transparent, body: body));
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
  final Set<Tab> _visited = {Tab.calendar};
  final Map<String, ScrollController> _scrollers = {};
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    // Every tab's header carries the website's DISCOVER pill and theme dot.
    siteHeaderActions = (context) => [
          AccentPill('Discover', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiscoverScreen()))),
          ThemeDot(dark: ThemeStore.instance.isDark, onTap: ThemeStore.instance.toggle),
        ];
    if (Shell.deepLinks) _listenForLinks();
    ReminderStore.instance.openToday.addListener(_openToday);
    ReminderStore.instance.openMorning.addListener(_openMorning);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openMorning());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openToday());
  }

  @override
  void dispose() {
    ReminderStore.instance.openToday.removeListener(_openToday);
    ReminderStore.instance.openMorning.removeListener(_openMorning);
    _links?.cancel();
    for (final c in _scrollers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Invite links (`bwdy.site/p/<code>`), public profiles (`/u/<handle>`), party
  /// pages (`/party/<id>`) and table menus (`/m/<slug>`, from an NFC tag or QR)
  /// open straight into the app when installed.
  void _listenForLinks() {
    final links = AppLinks();
    links.getInitialLink().then((u) {
      if (u != null) _route(u);
    }).catchError((_) {});
    _links = links.uriLinkStream.listen(_route, onError: (_) {});
  }

  /// The nightly reminder was tapped: straight to today's log sheet — one tap, done.
  void _openToday() {
    final pending = ReminderStore.instance.openToday;
    final ctx = navigatorKey.currentContext;
    if (!pending.value || ctx == null || !mounted) return;
    pending.value = false;
    _select(Tab.calendar);
    openLog(ctx, todayKey(), cheer: auth.isAuthed);
  }

  /// The morning check-in was tapped: the morning-after page.
  void _openMorning() {
    final pending = ReminderStore.instance.openMorning;
    if (!pending.value || navigatorKey.currentState == null || !mounted) return;
    pending.value = false;
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const MorningAfterScreen()));
  }

  void _route(Uri uri) {
    // Home-screen widgets open brewdiary://quick/<water|cigarette> and brewdiary://split.
    if (uri.scheme == 'brewdiary') return _widgetLink(uri);
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
      case 'm':
        // A table's NFC tag or QR (bwdy.site/m/<slug>) — the venue's menu.
        final slug = menuSlugFrom(uri);
        if (slug != null) nav.push(MaterialPageRoute(builder: (_) => MenuScreen(slug: slug)));
    }
  }

  void _widgetLink(Uri uri) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    if (uri.host == 'quick') {
      final what = uri.pathSegments.firstOrNull;
      final def = extras.where((d) => d.entryDrink.toLowerCase() == what).firstOrNull;
      if (def == null) return;
      entryStore.addEntry(date: todayKey(), drink: def.entryDrink, type: def.entryType);
      toast(ctx, 'Logged one ${def.unit} for today.');
    } else if (uri.host == 'split') {
      if (auth.isAuthed && db != null) {
        navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const SplitScreen()));
      } else {
        toast(ctx, 'Split needs you signed in to the brewdiary cloud.');
      }
    }
  }

  /// Together needs an account on the brewdiary cloud; without one its tab still
  /// shows — as the introduction to the room rather than the room itself.
  bool get _togetherLive => auth.isAuthed && db != null;

  String _slot(Tab t, bool guest) => switch (t) {
        Tab.calendar when guest => 'landing',
        Tab.together when !_togetherLive => 'together-intro',
        _ => t.name,
      };

  ScrollController _scroller(String slot) => _scrollers.putIfAbsent(slot, ScrollController.new);

  /// Switch tabs; tapping the tab you're on scrolls it back to the top.
  void _select(Tab t) {
    if (t == _tab) {
      final c = _scrollers[_slot(t, !auth.isAuthed)];
      if (c != null && c.hasClients && c.positions.length == 1 && c.offset > 0) c.animateTo(0, duration: Motion.slow, curve: Motion.curve);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = t;
      _visited.add(t);
    });
  }

  Widget _screen(Tab t, bool guest) => switch (t) {
        Tab.calendar => guest ? const LandingScreen() : CalendarScreen(onOpenNinkasi: () => _select(Tab.ninkasi)),
        Tab.together => _togetherLive ? const TogetherScreen() : const TogetherIntro(),
        Tab.ninkasi => const BartenderScreen(),
        Tab.you => const YouScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final signedIn = auth.isAuthed;
        final guest = !signedIn;
        // Together is always in the bar — for guests it's the introduction.
        const tabs = Tab.values;

        // Every visited tab stays alive (scroll position, a half-typed message,
        // the Ninkasi chat); only the current one animates. A different person
        // signing in starts from a clean slate.
        return Stack(children: [
          Positioned.fill(
            child: IndexedStack(
              key: ValueKey(auth.meId ?? 'guest'),
              index: tabs.indexOf(_tab),
              children: [
                for (final t in tabs)
                  KeyedSubtree(
                    key: ValueKey(_slot(t, guest)),
                    child: TickerMode(
                      enabled: t == _tab,
                      child: _visited.contains(t) ? PrimaryScrollController(controller: _scroller(_slot(t, guest)), child: _screen(t, guest)) : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _TabBarHost(tabs: tabs, current: _tab, onSelect: _select)),
        ]);
      },
    );
  }
}

/// Hides the tab bar while the keyboard is up, so it never covers a field. Kept
/// apart from the shell so the pages don't rebuild when the keyboard moves.
class _TabBarHost extends StatelessWidget {
  final List<Tab> tabs;
  final Tab current;
  final ValueChanged<Tab> onSelect;
  const _TabBarHost({required this.tabs, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final keyboard = KeyboardScope.isUp(context);
    return IgnorePointer(
      ignoring: keyboard,
      child: AnimatedOpacity(
        opacity: keyboard ? 0 : 1,
        duration: Motion.fast,
        child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
          // A soft fade under the floating bar, so content scrolling beneath it
          // recedes instead of competing with the tabs.
          Positioned.fill(
            top: -28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bd.base.withValues(alpha: 0), bd.base.withValues(alpha: bd.dark ? .72 : .6)],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSlide(
            offset: keyboard ? const Offset(0, 1.4) : Offset.zero,
            duration: Motion.med,
            curve: Motion.curve,
            child: _TabBar(tabs: tabs, current: current, onSelect: onSelect),
          ),
        ]),
      ),
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
      padding: EdgeInsets.fromLTRB(S.l, 0, S.l, bottom > 0 ? bottom : S.m),
      // On a foldable or tablet the bar stays phone-width, centred.
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rTile + 4),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: bd.dark ? const Color(0xB31A1B22) : const Color(0xCCF7F4FA),
                  borderRadius: BorderRadius.circular(rTile + 4),
                  border: Border.all(color: bd.glassBorder, width: .8),
                ),
                child: Row(children: [
                  for (final t in tabs)
                    Expanded(
                      child: Semantics(
                        key: ValueKey('tab-${t.name}'),
                        selected: t == current,
                        button: true,
                        label: _labels[t],
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (t != current) HapticFeedback.selectionClick();
                            onSelect(t);
                          },
                          child: Stack(alignment: Alignment.topCenter, children: [
                            // The website's amber marker over the current tab.
                            Positioned(
                              top: 4,
                              child: AnimatedContainer(
                                duration: Motion.med,
                                curve: Motion.curve,
                                width: t == current ? 22 : 0,
                                height: 3,
                                decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(99)),
                              ),
                            ),
                            Positioned.fill(
                              // Text-only, in the website's spaced capitals: the amber mark says where you are.
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: Motion.fast,
                                  style: T.sans(bd, size: 11.5, spacing: 11.5 * .16, weight: t == current ? FontWeight.w600 : FontWeight.w500, color: t == current ? bd.ink : bd.faint),
                                  child: Text(_labels[t]!.toUpperCase(), maxLines: 1),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
