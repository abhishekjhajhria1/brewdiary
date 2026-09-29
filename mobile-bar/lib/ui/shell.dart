// The venue shell. Tabs follow the role: a manager gets the numbers and the menu, a
// server gets tonight and the guests, the kitchen gets the 86 list. What a role can't
// do it doesn't see — and the database refuses it anyway.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/session.dart';
import '../logic/roles.dart';
import '../logic/venue_kinds.dart';
import 'screens/guests_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/more_screen.dart';
import 'screens/numbers_screen.dart';
import 'screens/tonight_screen.dart';
import 'screens/till_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

enum BarTab { service, guests, menu, numbers, more }

/// The tabs a role sees at a venue, in order.
List<BarTab> tabsFor(Venue v) {
  bool can(Cap c) => roleCan(v.myRole, c);
  return [
    if (can(Cap.floorView) || can(Cap.redeemPerk) || can(Cap.openRoom)) BarTab.service,
    if (can(Cap.guestCard)) BarTab.guests,
    if (can(Cap.editMenu) || can(Cap.mark86)) BarTab.menu,
    if (can(Cap.reports)) BarTab.numbers,
    BarTab.more,
  ];
}

String tabLabel(BarTab t, Venue v) => switch (t) {
      BarTab.service => serviceWord(v.kind),
      BarTab.guests => 'Guests',
      BarTab.menu => menuWord(v.kind),
      BarTab.numbers => 'Numbers',
      BarTab.more => 'More',
    };

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  BarTab _tab = BarTab.service;

  Widget _page(BarTab t, Venue v) => switch (t) {
        BarTab.service => v.kind.isCounter ? TillScreen(venue: v) : TonightScreen(venue: v),
        BarTab.guests => GuestsScreen(venue: v),
        BarTab.menu => MenuScreen(venue: v),
        BarTab.numbers => NumbersScreen(venue: v),
        BarTab.more => MoreScreen(venue: v),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final v = Session.instance.venue;
        if (v == null) return const SizedBox.shrink();
        final tabs = tabsFor(v);
        final current = tabs.contains(_tab) ? _tab : tabs.first;
        final keyboard = KeyboardScope.isUp(context);
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: Ambient(
            child: Stack(children: [
              Positioned.fill(
                child: IndexedStack(
                  index: tabs.indexOf(current),
                  children: [for (final t in tabs) KeyedSubtree(key: ValueKey('page-${t.name}-${v.id}'), child: _page(t, v))],
                ),
              ),
              if (!keyboard)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _TabBar(tabs: tabs, current: current, venue: v, onSelect: (t) => setState(() => _tab = t)),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  final List<BarTab> tabs;
  final BarTab current;
  final Venue venue;
  final ValueChanged<BarTab> onSelect;
  const _TabBar({required this.tabs, required this.current, required this.venue, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.l, 0, S.l, bottom > 0 ? bottom : S.m),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
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
                        label: tabLabel(t, venue),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (t != current) HapticFeedback.selectionClick();
                            onSelect(t);
                          },
                          child: Stack(alignment: Alignment.topCenter, children: [
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
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: AnimatedDefaultTextStyle(
                                    duration: Motion.fast,
                                    style: T.sans(bd, size: 11.5, spacing: 11.5 * .16, weight: t == current ? FontWeight.w600 : FontWeight.w500, color: t == current ? bd.ink : bd.faint),
                                    child: Text(tabLabel(t, venue).toUpperCase(), maxLines: 1),
                                  ),
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
