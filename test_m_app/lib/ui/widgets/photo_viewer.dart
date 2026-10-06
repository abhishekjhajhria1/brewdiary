// A photo, big. Tap a thumbnail and it grows out of its place to fill the screen;
// pinch or double-tap to look closer, swipe sideways through the night's photos,
// and pull down (or tap the cross) to put it back where it came from.
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// One photo to show: a local file path or an https URL, with words for a screen reader.
typedef ViewerPhoto = ({String url, String? label});

/// The image for a photo, from the phone or the network, with a soft fade-in once it
/// has loaded (never a pop) and a quiet mark if it can't be fetched.
class PhotoImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final String? semanticLabel;
  const PhotoImage(this.url, {super.key, this.fit = BoxFit.cover, this.semanticLabel});

  bool get _local => !url.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget fadeIn(BuildContext context, Widget child, int? frame, bool sync) {
      if (sync || context.reduceMotion) return child;
      return AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: Motion.med, curve: Curves.easeOut, child: child);
    }

    Widget broken(BuildContext context, Object error, StackTrace? stack) => ColoredBox(
          color: bd.glass,
          child: Center(child: Icon(Ph.image, size: 22, color: bd.faint)),
        );
    return _local
        ? Image.file(File(url), fit: fit, semanticLabel: semanticLabel, frameBuilder: fadeIn, errorBuilder: broken)
        : Image.network(url, fit: fit, semanticLabel: semanticLabel, frameBuilder: fadeIn, errorBuilder: broken);
  }
}

/// The Hero tag a thumbnail and the viewer share. [scope] keeps two places that show
/// the same photo (a sheet over a page) from claiming the same flight.
Object photoHeroTag(String url, [String scope = '']) => 'photo:$scope:$url';

/// Open [photos] full screen at [initial]. Thumbnails wrapped in a Hero with
/// [photoHeroTag] (same [scope]) fly into place. [action] puts one quiet button
/// under the photo ("Open that night"); it closes the viewer, then runs.
Future<void> showPhotoViewer(BuildContext context, List<ViewerPhoto> photos, {int initial = 0, String scope = '', ({String label, void Function(int index) onTap})? action}) {
  if (photos.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    transitionDuration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 340),
    reverseTransitionDuration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (context, animation, _) => _Viewer(photos: photos, initial: initial.clamp(0, photos.length - 1), scope: scope, route: animation, action: action),
  ));
}

class _Viewer extends StatefulWidget {
  final List<ViewerPhoto> photos;
  final int initial;
  final String scope;
  final Animation<double> route;
  final ({String label, void Function(int index) onTap})? action;
  const _Viewer({required this.photos, required this.initial, required this.scope, required this.route, this.action});
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  final _zoom = <int, TransformationController>{};
  // How far the photo has been pulled down to dismiss (points), and the spring back.
  late final AnimationController _pull = AnimationController.unbounded(vsync: this);
  bool _zoomed = false;
  bool _armed = false;
  Offset _lastTap = Offset.zero;

  TransformationController _zoomFor(int i) => _zoom.putIfAbsent(i, () {
        final c = TransformationController();
        c.addListener(() {
          final z = c.value.getMaxScaleOnAxis() > 1.01;
          if (z != _zoomed && i == _index) setState(() => _zoomed = z);
        });
        return c;
      });

  @override
  void dispose() {
    _pages.dispose();
    _pull.dispose();
    for (final c in _zoom.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  void _doubleTap() {
    final c = _zoomFor(_index);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      c.value = Matrix4.identity();
    } else {
      // Zoom 2.5× around where the finger was.
      final p = _lastTap;
      c.value = Matrix4.identity()
        ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
    Haptics.tick();
  }

  void _dragUpdate(DragUpdateDetails d) {
    _pull.value = (_pull.value + d.delta.dy).clamp(-400.0, 600.0);
    final armed = _pull.value.abs() > 110;
    if (armed != _armed) {
      _armed = armed;
      if (armed) Haptics.tap();
    }
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_armed || v.abs() > 900) {
      _close();
    } else {
      _pull.animateTo(0, duration: Motion.med, curve: Curves.easeOutCubic);
    }
    _armed = false;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final n = widget.photos.length;
    return AnimatedBuilder(
      animation: Listenable.merge([_pull, widget.route]),
      builder: (context, child) {
        final pulled = (_pull.value.abs() / 400).clamp(0.0, 1.0);
        final shade = (1 - pulled * .85) * widget.route.value;
        return Stack(children: [
          Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: .94 * shade))),
          Positioned.fill(child: Transform.translate(offset: Offset(0, _pull.value), child: Transform.scale(scale: 1 - pulled * .18, child: child))),
          // Chrome: the close button and "2 / 3", fading with the pull.
          Positioned(
            left: 8,
            right: 8,
            top: mq.padding.top + 6,
            child: Opacity(
              opacity: (shade).clamp(0.0, 1.0),
              child: Row(children: [
                IconBtn(Ph.x, tooltip: 'Close', color: Colors.white, onTap: _close),
                const Spacer(),
                if (n > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: S.m),
                    child: Text('${_index + 1} / $n', style: T.rawSans(14, Colors.white70, weight: FontWeight.w500).copyWith(fontFeatures: T.tnum)),
                  ),
              ]),
            ),
          ),
          if (widget.action != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: mq.padding.bottom + S.l,
              child: Opacity(
                opacity: shade.clamp(0.0, 1.0),
                child: Center(
                  child: Pressable(
                    onTap: () {
                      final i = _index;
                      Navigator.of(context).pop();
                      widget.action!.onTap(i);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: S.tap),
                      padding: const EdgeInsets.symmetric(horizontal: S.xl),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: Colors.white24, width: .8)),
                      child: Text(widget.action!.label, style: T.rawSans(15, Colors.white, weight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      },
      child: GestureDetector(
        // Pull down (or up) to put it back — not while zoomed in, where a drag pans.
        onVerticalDragUpdate: _zoomed ? null : _dragUpdate,
        onVerticalDragEnd: _zoomed ? null : _dragEnd,
        onDoubleTapDown: (d) => _lastTap = d.localPosition,
        onDoubleTap: _doubleTap,
        child: PageView.builder(
          controller: _pages,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
          itemCount: n,
          onPageChanged: (i) {
            _zoomFor(_index).value = Matrix4.identity();
            setState(() {
              _index = i;
              _zoomed = false;
            });
          },
          itemBuilder: (context, i) {
            final p = widget.photos[i];
            return InteractiveViewer(
              transformationController: _zoomFor(i),
              // At rest a drag is a page turn or a pull-to-close; panning starts once zoomed.
              panEnabled: _zoomed,
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Hero(
                  tag: photoHeroTag(p.url, widget.scope),
                  child: PhotoImage(p.url, fit: BoxFit.contain, semanticLabel: p.label ?? 'Photo ${i + 1} of $n'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
