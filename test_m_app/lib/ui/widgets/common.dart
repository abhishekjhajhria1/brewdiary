// Shared building blocks — the Flutter equivalents of the web's `.glass`, `.label`,
// Chip, buttons, toggles, sheets and fetch-on-mount hooks.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The vibrant ambient layer — four soft drink-hued blobs over the base.
class Ambient extends StatelessWidget {
  final Widget child;
  const Ambient({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return CustomPaint(painter: _AmbientPainter(bd), child: child);
  }
}

class _AmbientPainter extends CustomPainter {
  final BD bd;
  _AmbientPainter(this.bd);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bd.base);
    // (x%, y%, radiusX%, radiusY%) from the CSS radial-gradients.
    const blobs = [(0.12, 0.08, 0.60, 0.50), (0.92, 0.14, 0.55, 0.45), (0.78, 0.92, 0.60, 0.55), (0.18, 0.88, 0.55, 0.50)];
    for (var i = 0; i < 4; i++) {
      final b = blobs[i];
      final center = Offset(size.width * b.$1, size.height * b.$2);
      final r = math.max(size.width * b.$3, size.height * b.$4 * .6);
      final paint = Paint()
        ..shader = RadialGradient(colors: [bd.ambient[i], bd.ambient[i].withValues(alpha: 0)], stops: const [0, .7])
            .createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.bd != bd;
}

/// The frosted-glass tile — the core material. `strong` is the more opaque sheet
/// variant; `blur` adds a real backdrop blur (kept for chrome, where it shows).
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool strong;
  final bool blur;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  const Glass({super.key, required this.child, this.padding, this.radius = rTile, this.strong = false, this.blur = false, this.onTap, this.margin});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? bd.glassStrong : bd.glass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: bd.glassBorder, width: 1),
        boxShadow: [BoxShadow(color: bd.shadow, blurRadius: 30, offset: const Offset(0, 8))],
      ),
      child: child,
    );
    if (blur) {
      box = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: strong ? 24 : 16, sigmaY: strong ? 24 : 16), child: box),
      );
    }
    if (onTap != null) box = Pressable(onTap: onTap!, child: box);
    return margin == null ? box : Padding(padding: margin!, child: box);
  }
}

/// Subtle interactive lift for tappable tiles (`.glass-press`).
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enabled;
  const Pressable({super.key, required this.child, required this.onTap, this.enabled = true});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap();
            }
          : null,
      child: AnimatedScale(scale: _down ? .985 : 1, duration: const Duration(milliseconds: 180), curve: Curves.easeOutCubic, child: widget.child),
    );
  }
}

class Label extends StatelessWidget {
  final String text;
  final Color? color;
  final TextAlign? align;
  const Label(this.text, {super.key, this.color, this.align});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: T.label(context.bd, color: color), textAlign: align);
}

/// A small quick-pick chip — tap to fill a field. Small radius, not a pill.
class BdChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const BdChip(this.text, {super.key, this.active = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? bd.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(rCtl),
          border: Border.all(color: active ? bd.ink : bd.lineStrong),
        ),
        child: Text(text, style: T.sans(bd, size: 14, color: active ? bd.base : bd.muted)),
      ),
    );
  }
}

/// Glass chip used for "vibe"/"thank" reasons and friend picks.
class GlassChip extends StatelessWidget {
  final String text;
  final bool done;
  final VoidCallback? onTap;
  const GlassChip(this.text, {super.key, this.done = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Glass(
      radius: rCtl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: done ? null : onTap,
      child: Text(done ? '$text ✓' : text, style: T.sans(bd, size: 12.5, color: done ? bd.faint : bd.muted)),
    );
  }
}

/// Solid ink button — the primary action (`bg-ink text-paper`).
class InkButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool busy;
  final double height;
  final bool uppercase;
  const InkButton(this.text, {super.key, this.onTap, this.busy = false, this.height = 48, this.uppercase = true});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final enabled = onTap != null && !busy;
    return Pressable(
      onTap: onTap ?? () {},
      enabled: enabled,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : .4,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bd.ink, borderRadius: BorderRadius.circular(rCtl)),
          child: Text(
            busy ? '…' : (uppercase ? text.toUpperCase() : text),
            style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.base, spacing: uppercase ? 14 * .12 : null),
          ),
        ),
      ),
    );
  }
}

/// Outlined quiet button (`border border-line`).
class LineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final double height;
  const LineButton(this.text, {super.key, this.onTap, this.height = 44});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Pressable(
      onTap: onTap ?? () {},
      enabled: onTap != null,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.line)),
        child: Text(text, style: T.sans(bd, size: 14, color: onTap == null ? bd.faint : bd.muted)),
      ),
    );
  }
}

/// Amber pill — the Discover call-to-action shape.
class AccentPill extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const AccentPill(this.text, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: bd.accent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: bd.accent.withValues(alpha: .5), blurRadius: 18, offset: const Offset(0, 3), spreadRadius: -5)],
        ),
        child: Text(text.toUpperCase(), style: T.sans(bd, size: 12, weight: FontWeight.w500, color: bd.accentContrast, spacing: 12 * .14)),
      ),
    );
  }
}

/// A text-only action ("Accept", "Remove", …).
class TextAction extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool accent;
  final bool faint;
  final double size;
  const TextAction(this.text, {super.key, this.onTap, this.accent = false, this.faint = false, this.size = 14});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final color = onTap == null ? bd.faint : (accent ? bd.accent : (faint ? bd.faint : bd.muted));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(text, style: T.sans(bd, size: size, color: color, weight: accent ? FontWeight.w500 : FontWeight.w400)),
      ),
    );
  }
}

/// The calm on/off switch used in settings.
class BdToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const BdToggle({super.key, required this.on, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      toggled: on,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!on);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: on ? bd.accent : bd.lineStrong, borderRadius: BorderRadius.circular(999)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(width: 20, height: 20, decoration: BoxDecoration(color: on ? bd.accentContrast : bd.base, shape: BoxShape.circle)),
          ),
        ),
      ),
    );
  }
}

/// A settings row: title + hint on the left, a control on the right.
class SettingRow extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget trailing;
  const SettingRow({super.key, required this.title, this.hint, required this.trailing});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.sans(bd, size: 14)),
              if (hint != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint!, style: T.sans(bd, size: 12, color: bd.faint, height: 1.4))),
            ]),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// Underlined text field (`border-b border-line-strong`), the web's form idiom.
class LineField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool italic;
  final double size;
  final bool autofocus;
  final bool obscure;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final int maxLines;
  final TextCapitalization caps;
  final int? maxLength;
  const LineField({
    super.key,
    required this.controller,
    this.hint,
    this.italic = false,
    this.size = 15,
    this.autofocus = false,
    this.obscure = false,
    this.keyboard,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.maxLines = 1,
    this.caps = TextCapitalization.sentences,
    this.maxLength,
  });
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboard,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: caps,
      style: T.sans(bd, size: size).copyWith(fontStyle: italic ? FontStyle.italic : FontStyle.normal),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: hint,
        hintStyle: T.sans(bd, size: size, color: bd.faint),
        contentPadding: const EdgeInsets.only(bottom: 8, top: 4),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: bd.lineStrong)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: bd.ink)),
      ),
    );
  }
}

/// Boxed glass input (`glass rounded-ctl px-4 py-2.5`).
class GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboard;
  final int maxLines;
  final bool autofocus;
  final TextCapitalization caps;
  final int? maxLength;
  const GlassField({super.key, required this.controller, this.hint, this.onChanged, this.onSubmitted, this.keyboard, this.maxLines = 1, this.autofocus = false, this.caps = TextCapitalization.sentences, this.maxLength});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      decoration: BoxDecoration(color: bd.glass, borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.glassBorder)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: keyboard,
        maxLines: maxLines,
        minLines: 1,
        autofocus: autofocus,
        textCapitalization: caps,
        maxLength: maxLength,
        style: T.sans(bd),
        decoration: InputDecoration(border: InputBorder.none, counterText: '', hintText: hint, hintStyle: T.sans(bd, color: bd.faint), contentPadding: const EdgeInsets.symmetric(vertical: 11)),
      ),
    );
  }
}

/// Section header: big serif title with a quiet label on the right, over a hairline.
class PageHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final double size;
  const PageHeader(this.title, {super.key, this.trailing, this.size = 48});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text(title, style: T.serif(bd, size: size))),
        if (trailing != null) Label(trailing!, color: bd.faint),
      ]),
    );
  }
}

/// A pulsing placeholder tile while data loads.
class Skeleton extends StatefulWidget {
  final double height;
  final double radius;
  const Skeleton({super.key, this.height = 80, this.radius = rTile});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: .45, end: 1.0).animate(_c),
      child: Glass(radius: widget.radius, child: SizedBox(height: widget.height, width: double.infinity)),
    );
  }
}

/// Faint centred copy for empty states.
class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
        child: Text(text, textAlign: TextAlign.center, style: T.sans(context.bd, size: 14, color: context.bd.faint, height: 1.5)),
      );
}

/// A hairline-divided list (`divide-y divide-line border-y border-line`).
class Hairlines extends StatelessWidget {
  final List<Widget> children;
  const Hairlines({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: bd.line))),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: bd.line),
          children[i],
        ],
      ]),
    );
  }
}

/// Round initial avatar (the friend rail).
class Initial extends StatelessWidget {
  final String letter;
  final double size;
  final Color? color;
  const Initial(this.letter, {super.key, this.size = 48, this.color});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bd.glass, shape: BoxShape.circle, border: Border.all(color: bd.glassBorder)),
      child: Text(letter, style: T.serif(bd, size: size * .38, color: color)),
    );
  }
}

/// Bottom sheet in the house style: strong glass, rounded top, grab handle.
Future<R?> showBdSheet<R>(BuildContext context, {required WidgetBuilder builder, bool scroll = true}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .5),
    builder: (ctx) {
      final bd = ctx.bd;
      final body = Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: builder(ctx));
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .9),
            decoration: BoxDecoration(
              color: Color.alphaBlend(bd.glassStrong, bd.base.withValues(alpha: .9)),
              border: Border(top: BorderSide(color: bd.glassBorder)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: bd.lineStrong, borderRadius: BorderRadius.circular(99))),
              ),
              Flexible(child: scroll ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), child: body) : body),
            ]),
          ),
        ),
      );
    },
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}

Future<bool> confirm(BuildContext context, {required String title, required String body, String yes = 'Yes', String no = 'Keep'}) async {
  final bd = context.bd;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Color.alphaBlend(bd.glassStrong, bd.base),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rTile)),
      title: Text(title, style: T.serif(bd, size: 24)),
      content: Text(body, style: T.sans(bd, color: bd.muted, height: 1.5)),
      actions: [
        TextAction(no, onTap: () => Navigator.pop(ctx, false), faint: true),
        const SizedBox(width: 8),
        TextAction(yes, onTap: () => Navigator.pop(ctx, true), accent: true),
      ],
    ),
  );
  return r == true;
}

/// Fetch-on-mount + refresh-on-signal: the Flutter mirror of the web hooks that
/// re-run when a module's `version` bumps. Keeps showing the last data while it
/// reloads so lists never flash empty.
class Loader<D> extends StatefulWidget {
  final Future<D> Function() load;
  final Listenable? refresh;
  final Object? deps;
  final Widget Function(BuildContext context, D? data, bool loading) builder;
  const Loader({super.key, required this.load, required this.builder, this.refresh, this.deps});
  @override
  State<Loader<D>> createState() => _LoaderState<D>();
}

class _LoaderState<D> extends State<Loader<D>> {
  D? _data;
  bool _loading = true;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant Loader<D> old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) {
      old.refresh?.removeListener(_reload);
      widget.refresh?.addListener(_reload);
    }
    if (old.deps != widget.deps) _reload();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    if (mounted) setState(() => _loading = true);
    try {
      final d = await widget.load();
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[brewdiary] load failed: $e');
      if (!mounted || gen != _gen) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _data, _loading);
}

/// Listen to any number of ChangeNotifiers and rebuild.
class Watch extends StatelessWidget {
  final List<Listenable> to;
  final WidgetBuilder builder;
  const Watch({super.key, required this.to, required this.builder});
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge(to), builder: (c, _) => builder(c));
}
