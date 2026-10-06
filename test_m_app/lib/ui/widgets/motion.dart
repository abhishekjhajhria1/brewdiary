// Motion and touch: how brewdiary moves, and how it answers a finger.
//
// Twinned: test_m_app/lib/ui/widgets/motion.dart and mobile-bar/lib/ui/widgets/
// motion.dart are the same file (test_m_app/test/motion_test.dart checks), so the
// diary and the venue app feel like one product. Change both together.
//
// The rules, from Apple's guidance on haptics and Material 3's motion system:
//   • Motion explains a change: where a thing came from, where it went. It is short
//     (150–400 ms), eases out on the way in, and never makes anyone wait to tap.
//   • A haptic means one thing, every time, and is spent sparingly: on a choice, a
//     commit, a success or a failure, not on every touch of glass. People can turn
//     haptics off in Settings, and the app reads the same without them.
//   • When the phone asks for reduced motion, everything here holds still: things
//     appear in place, numbers change without rolling, nothing pulses or shakes.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

// ── reduced motion ───────────────────────────────────────────────────────────
extension MotionPrefs on BuildContext {
  /// The phone asked for less motion (Accessibility settings), or a test did.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

// ── haptics ──────────────────────────────────────────────────────────────────
/// The haptic vocabulary. Each kind means one thing, everywhere in both apps.
abstract final class Haptics {
  /// False once the person switches haptics off in Settings (each app restores the
  /// choice from its own preferences at startup).
  static bool enabled = true;

  /// A tick: a choice among options (a chip, a tab, a segment, a stepper's step).
  static void tick() => _play(HapticFeedback.selectionClick);

  /// A light tap: something landed or took hold (a swipe passed its point, a long
  /// press caught, a pull-to-refresh let go).
  static void tap() => _play(HapticFeedback.lightImpact);

  /// A firmer knock, kept for the rare big moment (a milestone, a new rank).
  static void knock() => _play(HapticFeedback.mediumImpact);

  /// It worked: a drink logged, an order sent, a sale rung up.
  static void success() => _play(HapticFeedback.successNotification);

  /// Look up: something new needs you (a table asking, a ticket running late).
  static void warning() => _play(HapticFeedback.warningNotification);

  /// It didn't work: a wrong code, a refused action, a lost connection.
  static void error() => _play(HapticFeedback.errorNotification);

  static void _play(Future<void> Function() play) {
    if (!enabled) return;
    play().catchError((Object _) {});
  }
}

// ── press ────────────────────────────────────────────────────────────────────
/// Press feedback for anything tappable: it sinks a touch and dims under the finger,
/// then springs back, visibly even for the quickest tap, with a [Haptics.tick] unless
/// [haptic] is off. [onLongPress] catches with a [Haptics.tap].
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final bool haptic;

  /// How far it sinks: .97 for a control; a big surface passes something nearer 1.
  final double scale;
  const Pressable({super.key, required this.child, required this.onTap, this.onLongPress, this.enabled = true, this.haptic = true, this.scale = .97});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  // 0 at rest, 1 pressed. The release spring overshoots a hair past 0, so the
  // surface rises a touch above rest before it settles.
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  static final _release = SpringDescription.withDampingRatio(mass: 1, stiffness: 520, ratio: .62);
  bool _held = false;

  void _press() {
    _held = true;
    _c.animateTo(1, duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
  }

  void _spring() {
    // A spring stops within a hair of rest; land it exactly, so nothing stays dimmed
    // or scaled by a thousandth (and no layer is kept for an opacity of .9998).
    _c.animateWith(SpringSimulation(_release, _c.value, 0, 0)).then((_) {
      if (mounted && !_held) _c.value = 0;
    });
  }

  Future<void> _lift() async {
    _held = false;
    // A tap quicker than the press still shows one.
    if (_c.value < .6) {
      try {
        await _c.animateTo(1, duration: const Duration(milliseconds: 70), curve: Curves.easeOut).orCancel;
      } on TickerCanceled {
        return;
      }
      if (!mounted || _held) return;
    }
    _spring();
  }

  void _cancel() {
    _held = false;
    _spring();
  }

  void _tap() {
    if (widget.haptic) Haptics.tick();
    widget.onTap();
  }

  void _longPress() {
    Haptics.tap();
    _cancel();
    widget.onLongPress!();
  }

  @override
  void didUpdateWidget(covariant Pressable old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _c.value != 0) {
      _held = false;
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = context.reduceMotion;
    final on = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => _press() : null,
      onTapUp: on ? (_) => _lift() : null,
      onTapCancel: on ? _cancel : null,
      onTap: on ? _tap : null,
      onLongPress: on && widget.onLongPress != null ? _longPress : null,
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final v = _c.value;
          final dimmed = Opacity(opacity: 1 - .18 * v.clamp(0.0, 1.0), child: child);
          return still ? dimmed : Transform.scale(scale: 1 - (1 - widget.scale) * v, child: dimmed);
        },
      ),
    );
  }
}

// ── arrival ──────────────────────────────────────────────────────────────────
/// Content arriving on screen: it fades in and rises a few points, once, when first
/// built. [index] staggers a list, each item a beat after the one above and capped
/// so a long list never keeps anyone waiting. Key list items by their data, so that
/// only what is new arrives.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final double rise;
  const Reveal({super.key, required this.child, this.index = 0, this.delay = Duration.zero, this.rise = 10});
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _length = Duration(milliseconds: 380);
  static const _step = Duration(milliseconds: 45);
  late final AnimationController _c;
  late final Animation<double> _t;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // The wait lives inside the controller (an Interval), not in a timer, so a test's
    // pumpAndSettle sees it and nothing is left pending when a page closes.
    final wait = widget.delay + _step * math.min(widget.index, 8);
    final total = wait + _length;
    _c = AnimationController(vsync: this, duration: total);
    _t = CurvedAnimation(parent: _c, curve: Interval(wait.inMicroseconds / total.inMicroseconds, 1, curve: Easing.emphasizedDecelerate));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) {
          final v = _t.value;
          return Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, widget.rise * (1 - v)), child: child));
        },
      );
}

/// Shows or hides its child by growing or folding away while it fades: for a banner,
/// an undo row, a hint that comes and goes. Nothing pops in or out.
class Appear extends StatelessWidget {
  final bool visible;
  final Widget child;
  const Appear({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: context.reduceMotion ? Duration.zero : Motion.med,
        switchInCurve: Easing.emphasizedDecelerate,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: _stackTop,
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, alignment: Alignment.topCenter, fixedCrossAxisSizeFactor: 1, child: c)),
        child: visible ? KeyedSubtree(key: const ValueKey(true), child: child) : const SizedBox.shrink(key: ValueKey(false)),
      );
}

Widget _stackTop(Widget? current, List<Widget> previous) =>
    Stack(fit: StackFit.passthrough, alignment: Alignment.topCenter, children: [...previous, ?current]);

/// Swaps its child with a short slide in the direction of travel: [direction] +1
/// brings the new one in from the right (forward, next), -1 from the left, cross-
/// fading as it goes ([axis] vertical: from below, from above). Key the child by what
/// it shows; [size] lets the height follow when the new one is taller or shorter.
class SlideSwitcher extends StatelessWidget {
  final Widget child;
  final int direction;
  final Axis axis;

  /// How far it travels, as a fraction of its own size.
  final double shift;
  final bool size;
  final Duration duration;
  const SlideSwitcher({super.key, required this.child, this.direction = 1, this.axis = Axis.horizontal, this.shift = .12, this.size = false, this.duration = const Duration(milliseconds: 320)});

  @override
  Widget build(BuildContext context) {
    final still = context.reduceMotion;
    final d = direction.sign.toDouble();
    final along = axis == Axis.horizontal ? Offset(shift * d, 0) : Offset(0, shift * d);
    final switcher = AnimatedSwitcher(
      duration: still ? Duration.zero : duration,
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: _stackTop,
      transitionBuilder: (c, a) {
        final incoming = c.key == child.key;
        // Fade through, not across: the old one is gone before the new one shows,
        // so two months' numbers never sit on top of each other.
        return SlideTransition(
          position: Tween(begin: incoming ? along : -along, end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a.drive(CurveTween(curve: incoming ? const Interval(.4, 1) : const Interval(.55, 1))), child: c),
        );
      },
      child: child,
    );
    if (!size || still) return switcher;
    return AnimatedSize(duration: duration, curve: Easing.emphasizedDecelerate, alignment: Alignment.topCenter, child: switcher);
  }
}

// ── numbers ──────────────────────────────────────────────────────────────────
/// Text that rolls to its new value: the new one slides in from below as the old one
/// rises away (from above when the value falls), clipped to its own line. For counts
/// that change under a finger: a counter's +1, a cheers, a total.
class RollingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  /// +1 rolls up (the value grew), -1 rolls down; null reads it off the digits.
  final int? direction;
  const RollingText(this.text, {super.key, this.style, this.textAlign = TextAlign.start, this.direction});
  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  int _dir = 1;

  static num? _number(String s) => num.tryParse(s.replaceAll(RegExp(r'[^0-9.\-]'), ''));

  @override
  void didUpdateWidget(covariant RollingText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    final a = _number(old.text), b = _number(widget.text);
    _dir = widget.direction ?? (a != null && b != null && b < a ? -1 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final align = switch (widget.textAlign) {
      TextAlign.center => Alignment.center,
      TextAlign.right || TextAlign.end => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
    final text = Text(widget.text, key: ValueKey(widget.text), style: widget.style, textAlign: widget.textAlign, maxLines: 1, softWrap: false);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: context.reduceMotion ? Duration.zero : Motion.med,
        switchInCurve: Easing.emphasizedDecelerate,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(alignment: align, children: [...previous, ?current]),
        transitionBuilder: (c, a) {
          final incoming = c.key == ValueKey(widget.text);
          final from = Offset(0, (incoming ? .75 : -.75) * _dir);
          return SlideTransition(
            position: Tween(begin: from, end: Offset.zero).animate(a),
            child: FadeTransition(opacity: a, child: incoming ? c : ExcludeSemantics(child: c)),
          );
        },
        child: text,
      ),
    );
  }
}

/// An integer that rolls (see [RollingText]), in tabular figures so its neighbours
/// never jiggle.
class RollingNumber extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final TextAlign textAlign;
  final String Function(int value)? format;
  const RollingNumber(this.value, {super.key, this.style, this.textAlign = TextAlign.start, this.format});
  @override
  Widget build(BuildContext context) =>
      RollingText(format?.call(value) ?? '$value', style: (style ?? const TextStyle()).copyWith(fontFeatures: T.tnum), textAlign: textAlign);
}

/// A headline number that counts up to its value when it first appears, and on to
/// any new value after: for figures you look at, not counters you press.
class CountUp extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String Function(num value)? format;
  final Duration duration;
  const CountUp(this.value, {super.key, this.style, this.textAlign, this.format, this.duration = const Duration(milliseconds: 750)});

  String _show(num v) => format?.call(v) ?? '${v.round()}';

  @override
  Widget build(BuildContext context) {
    final style = (this.style ?? const TextStyle()).copyWith(fontFeatures: T.tnum);
    final target = value.toDouble();
    return Semantics(
      label: _show(value),
      excludeSemantics: true,
      child: context.reduceMotion
          ? Text(_show(value), style: style, textAlign: textAlign, maxLines: 1)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: duration,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(_show(value is int ? v.round() : v), style: style, textAlign: textAlign, maxLines: 1),
            ),
    );
  }
}

// ── tabs ─────────────────────────────────────────────────────────────────────
/// The tab body: every page stays alive underneath (an IndexedStack keeps your
/// place, a half-typed message, a scroll) and the page you switch to fades up into
/// place, Material's "fade through", over before a thumb can move again.
class FadeThroughStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const FadeThroughStack({super.key, required this.index, required this.children});
  @override
  State<FadeThroughStack> createState() => _FadeThroughStackState();
}

class _FadeThroughStackState extends State<FadeThroughStack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: const Interval(.1, 1, curve: Curves.easeOut));
  late final Animation<double> _scale = Tween(begin: .985, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Easing.emphasizedDecelerate));

  @override
  void didUpdateWidget(covariant FadeThroughStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !context.reduceMotion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: widget.index,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            // Same widgets in every slot, whichever is current, so no page is rebuilt
            // from scratch when it becomes (or stops being) the one on top.
            KeyedSubtree(
              key: widget.children[i].key ?? ValueKey(i),
              child: FadeTransition(
                opacity: i == widget.index ? _fade : kAlwaysCompleteAnimation,
                child: ScaleTransition(scale: i == widget.index ? _scale : kAlwaysCompleteAnimation, child: widget.children[i]),
              ),
            ),
        ],
      );
}

// ── attention ────────────────────────────────────────────────────────────────
/// Shakes its child sideways ("no") each time [trigger] changes: count wrong tries.
class Shake extends StatefulWidget {
  final int trigger;
  final Widget child;
  const Shake({super.key, required this.trigger, required this.child});
  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !context.reduceMotion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = _c.value;
          return Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * 9 * (1 - t), 0), child: child);
        },
      );
}

/// A sentence that says what went wrong, under a field or a form: it shakes once
/// as it appears (and again if it changes) with an error buzz, and is announced to
/// screen readers, so a failed try is felt and heard, not just printed.
class ErrorLine extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  const ErrorLine(this.text, {super.key, this.style, this.padding = EdgeInsets.zero});
  @override
  State<ErrorLine> createState() => _ErrorLineState();
}

class _ErrorLineState extends State<ErrorLine> {
  int _times = 0;

  @override
  void initState() {
    super.initState();
    Haptics.error();
    _times = 1;
  }

  @override
  void didUpdateWidget(covariant ErrorLine old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      Haptics.error();
      _times++;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: widget.padding,
        child: Shake(trigger: _times, child: Semantics(liveRegion: true, child: Text(widget.text, style: widget.style))),
      );
}

/// A few soft rings out from its child's edge when [active] turns on ("look here"),
/// then rest, so a busy screen never keeps flashing.
class Pulse extends StatefulWidget {
  final bool active;
  final Color color;
  final double radius;
  final int times;
  final Widget child;
  const Pulse({super.key, required this.active, required this.color, required this.child, this.radius = rTile, this.times = 3});
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  bool _started = false;

  void _go() {
    if (context.reduceMotion) return;
    _c.repeat(count: widget.times);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.active) _go();
  }

  @override
  void didUpdateWidget(covariant Pulse old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) _go();
    if (old.active && !widget.active) _c.reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _PulsePainter(_c, widget.color, widget.radius), child: widget.child);
}

class _PulsePainter extends CustomPainter {
  final Animation<double> t;
  final Color color;
  final double radius;
  _PulsePainter(this.t, this.color, this.radius) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v <= 0 || v >= 1) return;
    final e = Curves.easeOutCubic.transform(v);
    final grow = 10 * e;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 - e
      ..color = color.withValues(alpha: .7 * (1 - e));
    canvas.drawRRect(RRect.fromRectAndRadius((Offset.zero & size).inflate(grow), Radius.circular(radius + grow)), paint);
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.color != color || old.radius != radius;
}
