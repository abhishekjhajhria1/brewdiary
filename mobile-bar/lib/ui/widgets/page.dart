// Page scaffolding shared by every screen.
//
// The pattern is the platform-native large title: a pinned top bar that is clear at
// rest and frosts (blur + hairline) once content scrolls beneath it, with the page's
// large serif title in the content. When the large title scrolls away, its compact
// twin fades into the bar. Pull-to-refresh is built in for data pages.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Height of the pinned top bar, excluding the status bar.
const kTopBarHeight = 64.0; // the floating header pill (52) and the space around it

/// The widest a page's content grows (foldables, tablets); beyond it, it centres.
const kContentMaxWidth = 640.0;

/// A page that earns a tablet's width (a map, a station) opts into this instead.
const kWideMaxWidth = 1100.0;

/// Side padding that keeps content at most [maxWidth] wide, centred.
double sideGutter(BuildContext context, [double maxWidth = kContentMaxWidth]) {
  final w = MediaQuery.sizeOf(context).width;
  return w - 2 * S.gutter > maxWidth ? (w - maxWidth) / 2 : S.gutter;
}

/// Bottom padding that keeps the last item clear of the tab bar (or the home
/// indicator on pushed pages).
double bottomClearance(BuildContext context, {required bool tabBar}) {
  // With the keyboard up the page has already been resized to end at its top edge.
  if (KeyboardScope.isUp(context)) return S.xl;
  return (tabBar ? kTabBarSpace : 0) + MediaQuery.paddingOf(context).bottom + S.xxl;
}

/// The website's header actions (DISCOVER + the theme dot), set once by the app
/// shell. Tab pages that bring no actions of their own show these.
List<Widget> Function(BuildContext context)? siteHeaderActions;

/// The theme switch as the website draws it: a small dot in the header.
class ThemeDot extends StatelessWidget {
  final bool dark;
  final VoidCallback onTap;
  const ThemeDot({super.key, required this.dark, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return IconBtnFrame(
      tooltip: dark ? 'Switch to light' : 'Switch to dark',
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.med,
        width: 11,
        height: 11,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bd.ink.withValues(alpha: .55)),
      ),
    );
  }
}

class ScrollPage extends StatefulWidget {
  /// Shown large in the content and compact in the bar once scrolled.
  final String? title;

  /// Replaces the compact title (e.g. the wordmark on the calendar).
  final Widget? barTitle;

  /// Optional line under the large title.
  final String? subtitle;

  /// A small note at the right of the large title ("3 FRIENDS", "14 NIGHT BEST"),
  /// with a hairline under the pair — the website's page header.
  final String? titleNote;
  final List<Widget> actions;
  final bool back;
  final bool tabBar;
  final Future<void> Function()? onRefresh;
  final List<Widget> children;
  final ScrollController? controller;

  /// How wide the content may grow on a tablet ([kWideMaxWidth] for maps and stations).
  final double maxWidth;

  const ScrollPage({
    super.key,
    this.title,
    this.barTitle,
    this.subtitle,
    this.titleNote,
    this.actions = const [],
    this.back = false,
    this.tabBar = true,
    this.onRefresh,
    required this.children,
    this.controller,
    this.maxWidth = kContentMaxWidth,
  });

  @override
  State<ScrollPage> createState() => _ScrollPageState();
}

class _ScrollPageState extends State<ScrollPage> {
  double _offset = 0;

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      final o = n.metrics.pixels;
      // Only rebuild when crossing the thresholds that change the bar.
      if ((o > 4) != (_offset > 4) || (o > 48) != (_offset > 48)) setState(() => _offset = o);
      _offset = o;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    final hasLarge = widget.title != null;
    final side = sideGutter(context, widget.maxWidth);

    Widget scroll = CustomScrollView(
      controller: widget.controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top + kTopBarHeight)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, hasLarge ? S.s : S.xs, side, bottomClearance(context, tabBar: widget.tabBar)),
          sliver: SliverList.list(children: [
            if (hasLarge) ...[
              if (widget.titleNote == null)
                Semantics(header: true, child: Text(widget.title!, style: T.largeTitle(bd), maxLines: 2, overflow: TextOverflow.ellipsis))
              else
                Container(
                  padding: const EdgeInsets.only(bottom: S.m),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.line, width: .8))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: Semantics(header: true, child: Text(widget.title!, style: T.largeTitle(bd), maxLines: 1, overflow: TextOverflow.ellipsis))),
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(widget.titleNote!.toUpperCase(), style: T.section(bd))),
                  ]),
                ),
              if (widget.subtitle != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(widget.subtitle!, style: T.bodyMuted(bd))),
              const SizedBox(height: S.xxl),
            ],
            ...widget.children,
          ]),
        ),
      ],
    );
    if (widget.onRefresh != null) {
      scroll = RefreshIndicator(
        // A light tap as the pull lets go: the refresh caught.
        onRefresh: () {
          Haptics.tap();
          return widget.onRefresh!();
        },
        edgeOffset: top + kTopBarHeight,
        color: bd.accent,
        backgroundColor: bd.sheet,
        child: scroll,
      );
    }

    return Stack(children: [
      NotificationListener<ScrollNotification>(onNotification: _onScroll, child: scroll),
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: TopBar(
          frosted: _offset > 4,
          maxWidth: widget.maxWidth,
          // Tab pages wear the website's header: the wordmark, handing over to the
          // page's own title once its large title has scrolled away.
          title: widget.barTitle ??
              (hasLarge
                  ? AnimatedSwitcher(
                      duration: Motion.fast,
                      child: _offset > 48 || !widget.tabBar
                          ? Opacity(key: const ValueKey('t'), opacity: _offset > 48 ? 1 : 0, child: Text(widget.title!, style: T.sans(bd, size: 17, weight: FontWeight.w600)))
                          : const Align(key: ValueKey('w'), alignment: Alignment.centerLeft, child: Wordmark()),
                    )
                  : null),
          back: widget.back,
          actions: widget.actions.isEmpty && widget.tabBar ? (siteHeaderActions?.call(context) ?? const []) : widget.actions,
        ),
      ),
    ]);
  }
}

/// The pinned bar: back button, a title, actions. Clear until `frosted`.
class TopBar extends StatelessWidget {
  final bool frosted;
  final Widget? title;
  final bool back;
  final List<Widget> actions;
  final double maxWidth;
  const TopBar({super.key, required this.frosted, this.title, this.back = false, this.actions = const [], this.maxWidth = kContentMaxWidth});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final top = MediaQuery.of(context).padding.top;
    final side = sideGutter(context, maxWidth);
    // The website's header: a glass pill floating over the page, a touch more
    // opaque once content scrolls beneath it.
    final pill = ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: AnimatedContainer(
          duration: Motion.med,
          height: 52,
          padding: EdgeInsets.only(left: back ? 2 : S.l, right: 4),
          decoration: BoxDecoration(
            // Quiet at rest (the page shows through), firmer once content scrolls under.
            color: frosted ? bd.glassStrong : bd.base.withValues(alpha: bd.dark ? .38 : .45),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: bd.glassBorder, width: .8),
          ),
          child: Row(children: [
            if (back) IconBtn(Ph.caretLeft, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()),
            if (title != null) Expanded(child: title!) else const Spacer(),
            ...actions,
          ]),
        ),
      ),
    );
    // Chrome grows with the text size only so far (as native bars do), so a
    // title and its actions always fit on one line.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Padding(padding: EdgeInsets.fromLTRB(side - 6, top + 6, side - 6, 6), child: pill),
    );
  }
}

/// The italic serif wordmark.
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        label: 'brewdiary',
        child: Text('brewdiary', maxLines: 1, style: T.serif(context.bd, size: size, italic: true, color: context.bd.ink)),
      );
}

/// A pushed page (Settings, Discover, a party, a profile, Split): back button and,
/// by default, a large title that condenses into the bar as you scroll. Pages
/// whose content carries its own heading pass `large: false` for a bar title only.
class SubPage extends StatelessWidget {
  final String? title;
  final Widget child;
  final bool scroll;
  final bool large;
  final String? subtitle;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  const SubPage({super.key, this.title, required this.child, this.scroll = true, this.large = true, this.subtitle, this.actions = const [], this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    // The ambient layer sits OUTSIDE the scaffold so it keeps the full screen
    // while the scaffold body shrinks for the keyboard.
    return Ambient(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: scroll
            ? (large && title != null
                ? ScrollPage(title: title, subtitle: subtitle, back: true, tabBar: false, actions: actions, onRefresh: onRefresh, children: [child])
                : ScrollPage(back: true, tabBar: false, actions: actions, onRefresh: onRefresh, barTitle: title == null ? null : _BarTitle(title!), children: [child]))
            : Stack(children: [
                Padding(padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kTopBarHeight), child: child),
                Positioned(left: 0, right: 0, top: 0, child: TopBar(frosted: false, back: true, actions: actions, title: title == null ? null : Text(title!, style: T.sans(bd, size: 17, weight: FontWeight.w600)))),
              ]),
      ),
    );
  }
}

class _BarTitle extends StatelessWidget {
  final String text;
  const _BarTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(context.bd, size: 17, weight: FontWeight.w600));
}
