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
const kTopBarHeight = 52.0;

/// The widest a page's content grows (foldables, tablets); beyond it, it centres.
const kContentMaxWidth = 640.0;

/// Side padding that keeps content at most [kContentMaxWidth] wide, centred.
double sideGutter(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w - 2 * S.gutter > kContentMaxWidth ? (w - kContentMaxWidth) / 2 : S.gutter;
}

/// Bottom padding that keeps the last item clear of the tab bar (or the home
/// indicator on pushed pages).
double bottomClearance(BuildContext context, {required bool tabBar}) {
  // With the keyboard up the page has already been resized to end at its top edge.
  if (KeyboardScope.isUp(context)) return S.xl;
  return (tabBar ? kTabBarSpace : 0) + MediaQuery.paddingOf(context).bottom + S.xxl;
}

class ScrollPage extends StatefulWidget {
  /// Shown large in the content and compact in the bar once scrolled.
  final String? title;

  /// Replaces the compact title (e.g. the wordmark on the calendar).
  final Widget? barTitle;

  /// Optional line under the large title.
  final String? subtitle;
  final List<Widget> actions;
  final bool back;
  final bool tabBar;
  final Future<void> Function()? onRefresh;
  final List<Widget> children;
  final ScrollController? controller;

  const ScrollPage({
    super.key,
    this.title,
    this.barTitle,
    this.subtitle,
    this.actions = const [],
    this.back = false,
    this.tabBar = true,
    this.onRefresh,
    required this.children,
    this.controller,
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
    final side = sideGutter(context);

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
              Semantics(header: true, child: Text(widget.title!, style: T.largeTitle(bd), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
        onRefresh: widget.onRefresh!,
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
          title: widget.barTitle ?? (hasLarge ? AnimatedOpacity(opacity: _offset > 48 ? 1 : 0, duration: Motion.fast, child: Text(widget.title!, style: T.sans(bd, size: 17, weight: FontWeight.w600))) : null),
          back: widget.back,
          actions: widget.actions,
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
  const TopBar({super.key, required this.frosted, this.title, this.back = false, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final top = MediaQuery.of(context).padding.top;
    final side = sideGutter(context);
    final bar = AnimatedContainer(
      duration: Motion.med,
      height: top + kTopBarHeight,
      padding: EdgeInsets.only(top: top, left: back ? side - S.l : side, right: side - 14),
      decoration: BoxDecoration(
        color: frosted ? bd.base.withValues(alpha: bd.dark ? .72 : .70) : bd.base.withValues(alpha: 0),
        border: Border(bottom: BorderSide(color: frosted ? bd.line : Colors.transparent, width: .8)),
      ),
      child: Row(children: [
        if (back) IconBtn(Ph.caretLeft, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()),
        if (title != null) Expanded(child: title!) else const Spacer(),
        ...actions,
      ]),
    );
    // Chrome grows with the text size only so far (as native bars do), so a
    // title and its actions always fit on one line.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: frosted ? 20 : 0, sigmaY: frosted ? 20 : 0),
          child: bar,
        ),
      ),
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
