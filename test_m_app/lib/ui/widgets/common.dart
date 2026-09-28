// Shared building blocks — the house components. Every interactive element here
// meets a 44pt minimum touch target, gives press feedback within a frame, and has
// a disabled state. Surfaces are glass WITHOUT drop shadows (see theme.dart).
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../theme.dart';

export '../icons.dart';


/// Height of the floating tab bar (bar + its margins), excluding the safe area.
const kTabBarSpace = 64.0 + S.m;

// ── keyboard ─────────────────────────────────────────────────────────────────
/// The on-screen keyboard's height, published once above the navigator. (Scaffolds
/// resize for the keyboard and so report zero viewInsets to their body; this keeps
/// the real value reachable.) Depend on [isUp] to rebuild only when it opens or
/// closes, [insetOf] for the height itself.
class KeyboardScope extends InheritedModel<bool> {
  final double inset;
  const KeyboardScope({super.key, required this.inset, required super.child});

  static bool isUp(BuildContext context) =>
      (InheritedModel.inheritFrom<KeyboardScope>(context, aspect: true)?.inset ?? MediaQuery.viewInsetsOf(context).bottom) > 0;

  static double insetOf(BuildContext context) =>
      InheritedModel.inheritFrom<KeyboardScope>(context, aspect: false)?.inset ?? MediaQuery.viewInsetsOf(context).bottom;

  @override
  bool updateShouldNotify(KeyboardScope oldWidget) => oldWidget.inset != inset;

  @override
  bool updateShouldNotifyDependent(KeyboardScope oldWidget, Set<bool> dependencies) =>
      (dependencies.contains(true) && (oldWidget.inset > 0) != (inset > 0)) || (dependencies.contains(false) && oldWidget.inset != inset);
}

// ── background ───────────────────────────────────────────────────────────────
/// The vibrant ambient layer — four soft drink-hued blobs over the base.
class Ambient extends StatelessWidget {
  final Widget child;
  const Ambient({super.key, required this.child});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _AmbientPainter(context.bd), child: child);
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

// ── surfaces ─────────────────────────────────────────────────────────────────
/// The glass surface. A soft top-lit fill + one hairline — no drop shadow (a
/// translucent card would show its own shadow through itself). `blur` adds a real
/// backdrop blur; reserve it for chrome that content scrolls under.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool strong;
  final bool blur;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final String? semanticLabel;
  const Glass({super.key, required this.child, this.padding, this.radius = rTile, this.strong = false, this.blur = false, this.onTap, this.margin, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? bd.glassStrong : null,
        gradient: strong ? null : LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [bd.glassTop, bd.glass], stops: const [0, .6]),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: bd.glassBorder, width: .8),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (blur) {
      box = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: box),
      );
    }
    if (onTap != null) {
      box = Semantics(button: true, label: semanticLabel, child: Pressable(onTap: onTap!, child: box));
    }
    return margin == null ? box : Padding(padding: margin!, child: box);
  }
}

/// Press feedback: a quick scale + dim, and a selection haptic.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enabled;
  final bool haptic;
  const Pressable({super.key, required this.child, required this.onTap, this.enabled = true, this.haptic = true});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (mounted && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => _set(true) : null,
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? .97 : 1,
        duration: Motion.fast,
        curve: Motion.curve,
        child: AnimatedOpacity(opacity: _down ? .8 : 1, duration: Motion.fast, child: widget.child),
      ),
    );
  }
}

// ── type ─────────────────────────────────────────────────────────────────────
/// Micro-caption (uppercase, tracked). For stat captions and field labels only.
class Label extends StatelessWidget {
  final String text;
  final Color? color;
  final TextAlign? align;
  const Label(this.text, {super.key, this.color, this.align});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: T.label(context.bd, color: color), textAlign: align);
}

/// A section title in sentence case, with an optional action on the right.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.trailing, this.padding = const EdgeInsets.only(top: S.section, bottom: S.m)});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: T.section(bd)))),
        ?trailing,
        if (action != null) TextAction(action!, accent: true, onTap: onAction),
      ]),
    );
  }
}

// ── controls ─────────────────────────────────────────────────────────────────
/// A quick-pick chip — tap to fill a field. 36pt tall, 44pt hit area.
class BdChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  const BdChip(this.text, {super.key, this.active = false, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      button: true,
      selected: active,
      child: Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: S.tap),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: Motion.fast,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? bd.ink : bd.glass,
                borderRadius: BorderRadius.circular(rCtl),
                border: Border.all(color: active ? bd.ink : bd.lineStrong, width: .8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 16, color: active ? bd.base : bd.muted), const SizedBox(width: 6)],
                Text(text, style: T.sans(bd, size: 14, color: active ? bd.base : bd.ink, weight: active ? FontWeight.w500 : FontWeight.w400)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A reason chip ("great vibe", "looked after us") — turns into a check once sent.
class GlassChip extends StatelessWidget {
  final String text;
  final bool done;
  final VoidCallback? onTap;
  const GlassChip(this.text, {super.key, this.done = false, this.onTap});
  @override
  Widget build(BuildContext context) => BdChip(text, active: done, icon: done ? Ph.check : null, onTap: done ? () {} : (onTap ?? () {}));
}

/// A segmented control: two to five mutually exclusive choices on one line.
/// `compact` (32pt, sized to its labels) fits a top bar; otherwise it fills the
/// width at 40pt. The hit area is always 44pt tall.
class Segmented<V> extends StatelessWidget {
  final List<(V, String)> options;
  final V value;
  final ValueChanged<V> onChanged;
  final bool compact;
  const Segmented({super.key, required this.options, required this.value, required this.onChanged, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    Widget segment((V, String) o) {
      final selected = o.$1 == value;
      return Semantics(
        button: true,
        selected: selected,
        label: o.$2,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            HapticFeedback.selectionClick();
            onChanged(o.$1);
          },
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? (bd.dark ? const Color(0x2EFFFFFF) : Colors.white) : Colors.transparent,
              borderRadius: BorderRadius.circular(rCtl - 3),
              border: Border.all(color: selected ? bd.glassBorder : Colors.transparent, width: .8),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(o.$2, maxLines: 1, style: T.sans(bd, size: 13.5, weight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? bd.ink : bd.muted)),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: S.tap,
      child: Center(
        child: Container(
          height: compact ? 32 : 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: bd.ink.withValues(alpha: bd.dark ? .07 : .06),
            borderRadius: BorderRadius.circular(rCtl),
            border: Border.all(color: bd.line, width: .8),
          ),
          child: Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
            for (final o in options) compact ? segment(o) : Expanded(child: segment(o)),
          ]),
        ),
      ),
    );
  }
}

enum BtnKind { primary, accent, secondary, quiet }

/// The one button. Primary = ink fill, accent = amber, secondary = glass, quiet = text.
class BdButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool busy;
  final double height;
  final IconData? icon;
  final bool expand;
  const BdButton(this.text, {super.key, this.onTap, this.kind = BtnKind.primary, this.busy = false, this.height = 52, this.icon, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final enabled = onTap != null && !busy;
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (bd.ink, bd.base, null),
      BtnKind.accent => (bd.accent, bd.accentContrast, null),
      BtnKind.secondary => (bd.glass, bd.ink, bd.lineStrong),
      BtnKind.quiet => (Colors.transparent, bd.muted, null),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: text,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap ?? () {},
        enabled: enabled,
        child: AnimatedOpacity(
          duration: Motion.fast,
          opacity: onTap == null ? .38 : 1,
          child: Container(
            height: math.max(height, S.tap),
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(rCtl),
              border: border == null ? null : Border.all(color: border, width: .8),
            ),
            child: busy
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
                    Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.sans(bd, size: 15, weight: FontWeight.w600, color: fg))),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Primary ink button (kept name for existing call sites). `uppercase` is ignored —
/// sentence-case labels read better on a phone.
class InkButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool busy;
  final double height;
  final bool uppercase;
  final IconData? icon;
  const InkButton(this.text, {super.key, this.onTap, this.busy = false, this.height = 52, this.uppercase = false, this.icon});
  @override
  Widget build(BuildContext context) => BdButton(text, onTap: onTap, busy: busy, height: height, icon: icon);
}

/// Secondary (glass, hairline) button.
class LineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final double height;
  final IconData? icon;
  const LineButton(this.text, {super.key, this.onTap, this.height = 48, this.icon});
  @override
  Widget build(BuildContext context) => BdButton(text, onTap: onTap, kind: BtnKind.secondary, height: height, icon: icon);
}

/// Amber pill (compact CTA).
class AccentPill extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final IconData? icon;
  const AccentPill(this.text, {super.key, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: S.tap),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: bd.accent, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 16, color: bd.accentContrast), const SizedBox(width: 6)],
                Text(text, style: T.sans(bd, size: 13.5, weight: FontWeight.w600, color: bd.accentContrast)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text action ("Accept", "Remove") with a full 44pt hit area.
class TextAction extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool accent;
  final bool faint;
  final double size;
  final IconData? icon;
  const TextAction(this.text, {super.key, this.onTap, this.accent = false, this.faint = false, this.size = 14, this.icon});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final color = onTap == null ? bd.faint.withValues(alpha: .6) : (accent ? bd.accentText : (faint ? bd.faint : bd.muted));
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Pressable(
        onTap: onTap ?? () {},
        enabled: onTap != null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: S.tap, minWidth: S.tap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: size + 3, color: color), const SizedBox(width: 6)],
              Text(text, style: T.sans(bd, size: size, color: color, weight: accent ? FontWeight.w600 : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A 44pt icon button, optionally on a glass disc.
class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool glass;
  final Color? color;
  final double size;
  const IconBtn(this.icon, {super.key, required this.onTap, required this.tooltip, this.glass = false, this.color, this.size = 22});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final c = color ?? (onTap == null ? bd.faint.withValues(alpha: .5) : bd.ink);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap ?? () {},
          enabled: onTap != null,
          child: SizedBox(
            width: S.tap,
            height: S.tap,
            child: Center(
              child: glass
                  ? Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: bd.glass, shape: BoxShape.circle, border: Border.all(color: bd.glassBorder, width: .8)),
                      child: Icon(icon, size: size - 2, color: c),
                    )
                  : Icon(icon, size: size, color: c),
            ),
          ),
        ),
      ),
    );
  }
}

/// The on/off switch (iOS proportions, house colours).
class BdToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  final String? label;
  const BdToggle({super.key, required this.on, required this.onChanged, this.label});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Semantics(
      toggled: on,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!on);
        },
        child: SizedBox(
          height: S.tap,
          child: Center(
            child: AnimatedContainer(
              duration: Motion.med,
              width: 50,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: on ? bd.accent : bd.ink.withValues(alpha: bd.dark ? .16 : .12), borderRadius: BorderRadius.circular(999)),
              child: AnimatedAlign(
                duration: Motion.med,
                curve: Motion.curve,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 3, offset: const Offset(0, 1))],
                  ),
                ),
              ),
            ),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: T.row(bd)),
              if (hint != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint!, style: T.caption(bd))),
            ]),
          ),
          const SizedBox(width: S.m),
          trailing,
        ]),
      ),
    );
  }
}

// ── grouped lists (settings-style) ───────────────────────────────────────────
/// A glass group of rows with inset hairlines between them.
class Group extends StatelessWidget {
  final List<Widget> children;
  final String? footer;
  const Group({super.key, required this.children, this.footer});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final rows = children.where((w) => w is! SizedBox || (w.width != 0 || w.height != 0)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Glass(
        padding: const EdgeInsets.symmetric(horizontal: S.l),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: .8, color: bd.line),
            rows[i],
          ],
        ]),
      ),
      if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, 0), child: Text(footer!, style: T.caption(bd))),
    ]);
  }
}

/// One row in a Group: leading icon, title/subtitle, trailing widget or chevron.
class GroupTile extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;
  const GroupTile({super.key, this.icon, required this.title, this.subtitle, this.trailing, this.onTap, this.chevron = false, this.destructive = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final color = destructive ? bd.accentText : bd.ink;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 21, color: destructive ? bd.accentText : bd.muted), const SizedBox(width: 14)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: T.row(bd, color: color)),
              if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: T.caption(bd))),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: S.s), trailing!],
          if (chevron) ...[const SizedBox(width: 4), Icon(Ph.caretRight, size: 16, color: bd.faint)],
        ]),
      ),
    );
    return onTap == null ? row : Semantics(button: true, child: Pressable(onTap: onTap!, child: row));
  }
}

// ── fields ───────────────────────────────────────────────────────────────────
/// Underlined text field (the web's form idiom), label above, error below.
class LineField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final String? label;
  final String? error;
  final bool italic;
  final double size;
  final bool autofocus;
  final bool obscure;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final int maxLines;
  final TextCapitalization caps;
  final int? maxLength;
  final List<String>? autofill;
  const LineField({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.error,
    this.italic = false,
    this.size = 16,
    this.autofocus = false,
    this.obscure = false,
    this.keyboard,
    this.action,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.maxLines = 1,
    this.caps = TextCapitalization.sentences,
    this.maxLength,
    this.autofill,
  });
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (label != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Label(label!)),
      TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: obscure,
        keyboardType: keyboard,
        textInputAction: action,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLines: maxLines,
        maxLength: maxLength,
        textCapitalization: caps,
        autofillHints: autofill,
        style: T.sans(bd, size: size).copyWith(fontStyle: italic ? FontStyle.italic : FontStyle.normal),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          hintText: hint,
          hintStyle: T.sans(bd, size: size, color: bd.faint),
          contentPadding: const EdgeInsets.only(bottom: 10, top: 8),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: error != null ? bd.accentText : bd.lineStrong)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: error != null ? bd.accentText : bd.ink, width: 1.4)),
        ),
      ),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: T.sans(bd, size: 13, color: bd.accentText))),
    ]);
  }
}

/// Filled glass input (48pt), for search and boxed fields.
class GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboard;
  final TextInputAction? action;
  final int maxLines;
  final bool autofocus;
  final TextCapitalization caps;
  final int? maxLength;
  final IconData? icon;
  const GlassField({super.key, required this.controller, this.hint, this.onChanged, this.onSubmitted, this.keyboard, this.action, this.maxLines = 1, this.autofocus = false, this.caps = TextCapitalization.sentences, this.maxLength, this.icon});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(color: bd.glass, borderRadius: BorderRadius.circular(rCtl), border: Border.all(color: bd.lineStrong, width: .8)),
      padding: EdgeInsets.only(left: icon != null ? 12 : 16, right: 12),
      child: Row(crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
        if (icon != null) Padding(padding: EdgeInsets.only(right: 8, top: maxLines > 1 ? 14 : 0), child: Icon(icon, size: 19, color: bd.faint)),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            keyboardType: keyboard,
            textInputAction: action,
            maxLines: maxLines,
            minLines: 1,
            autofocus: autofocus,
            textCapitalization: caps,
            maxLength: maxLength,
            style: T.body(bd),
            decoration: InputDecoration(border: InputBorder.none, isDense: true, counterText: '', hintText: hint, hintStyle: T.sans(bd, color: bd.faint), contentPadding: const EdgeInsets.symmetric(vertical: 13)),
          ),
        ),
      ]),
    );
  }
}

// ── page furniture ───────────────────────────────────────────────────────────
/// Large page title with an optional quiet caption on the right.
class PageHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final double size;
  const PageHeader(this.title, {super.key, this.trailing, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.xl),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: T.serif(bd, size: size), maxLines: 1, overflow: TextOverflow.ellipsis))),
        if (trailing != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(trailing!, style: T.caption(bd))),
      ]),
    );
  }
}

/// A pulsing placeholder in the final shape while data loads.
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
    final bd = context.bd;
    return FadeTransition(
      opacity: Tween(begin: .5, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(color: bd.glass, borderRadius: BorderRadius.circular(widget.radius), border: Border.all(color: bd.glassBorder, width: .8)),
      ),
    );
  }
}

/// Composed empty state: optional icon, a line of copy, an optional action.
class EmptyNote extends StatelessWidget {
  final String text;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  const EmptyNote(this.text, {super.key, this.icon, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3, horizontal: S.l),
      child: Column(children: [
        if (icon != null) ...[Icon(icon, size: 28, color: bd.faint), const SizedBox(height: S.m)],
        Text(text, textAlign: TextAlign.center, style: T.sans(bd, size: 14.5, color: bd.muted, height: 1.55)),
        if (action != null) ...[const SizedBox(height: S.s), TextAction(action!, accent: true, onTap: onAction)],
      ]),
    );
  }
}

/// A hairline-divided list (no card).
class Hairlines extends StatelessWidget {
  final List<Widget> children;
  const Hairlines({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, thickness: .8, color: bd.line),
        children[i],
      ],
    ]);
  }
}

/// Round initial avatar.
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
      decoration: BoxDecoration(color: bd.glassTop, shape: BoxShape.circle, border: Border.all(color: bd.glassBorder, width: .8)),
      child: Text(letter, style: T.serif(bd, size: size * .42, color: color)),
    );
  }
}

// ── sheets, toasts, confirmations ────────────────────────────────────────────
/// Bottom sheet in the house style. It rides ABOVE the keyboard (the whole sheet
/// lifts, so the primary button is never hidden), scrolls when tall, and dismisses
/// the keyboard on drag. Pass `title` for a standard header with a close button.
Future<R?> showBdSheet<R>(BuildContext context, {required WidgetBuilder builder, bool scroll = true, String? title}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.bd.scrim,
    builder: (ctx) {
      final bd = ctx.bd;
      final mq = MediaQuery.of(ctx);
      final keyboard = mq.viewInsets.bottom;
      final body = builder(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: (mq.size.height - keyboard - mq.padding.top - 12).clamp(200, double.infinity)),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(rSheet)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: DecoratedBox(
                decoration: BoxDecoration(color: bd.glassStrong, border: Border(top: BorderSide(color: bd.glassBorder, width: .8))),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Container(width: 36, height: 5, decoration: BoxDecoration(color: bd.lineStrong, borderRadius: BorderRadius.circular(99))),
                    ),
                  ),
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(S.gutter, 4, 8, 4),
                      child: Row(children: [
                        Expanded(child: Text(title, style: T.title(bd))),
                        IconBtn(Ph.x, tooltip: 'Close', onTap: () => Navigator.of(ctx).maybePop()),
                      ]),
                    ),
                  Flexible(
                    child: scroll
                        ? SingleChildScrollView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(S.gutter, title == null ? 8 : 4, S.gutter, S.xxl + (keyboard > 0 ? 0 : mq.padding.bottom)),
                            child: body,
                          )
                        : body,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    },
  );
}

OverlayEntry? _toastEntry;

/// Brief, non-blocking feedback. It rides the ROOT overlay, so it shows above
/// sheets too; it floats clear of the tab bar (or the keyboard) and is announced
/// to screen readers. A new toast replaces the one on screen.
void toast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastEntry?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      message: message,
      onDone: () {
        if (_toastEntry != entry) return;
        entry.remove();
        _toastEntry = null;
      },
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  const _Toast({required this.message, required this.onDone});
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  // One controller for the whole life (in · hold · out), so tests can settle it.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final Animation<double> _v = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Motion.curve)), weight: 7),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 86),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 7),
  ]).animate(_c);

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final bottom = keyboard > 0 ? keyboard + S.m : mq.padding.bottom + kTabBarSpace + S.m;
    return Positioned(
      left: S.gutter,
      right: S.gutter,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _v,
          builder: (context, child) => Opacity(opacity: _v.value, child: Transform.translate(offset: Offset(0, (1 - _v.value) * 10), child: child)),
          child: Center(
            child: Semantics(
              liveRegion: true,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  constraints: const BoxConstraints(minHeight: S.tap),
                  padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.m),
                  decoration: BoxDecoration(color: bd.dark ? const Color(0xFFF0EBE2) : const Color(0xFF1C1822), borderRadius: BorderRadius.circular(rCtl)),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: T.sans(bd, size: 14, weight: FontWeight.w500, height: 1.35, color: bd.dark ? const Color(0xFF14110E) : const Color(0xFFF7F4FA)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice in an action sheet.
class SheetAction {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool destructive;
  const SheetAction(this.label, {this.icon, required this.onTap, this.destructive = false});
}

/// An action sheet: a short list of choices plus Cancel, thumb-reachable. The
/// chosen action runs after the sheet has closed.
Future<void> showActions(BuildContext context, {String? title, String? message, required List<SheetAction> actions}) async {
  final picked = await showBdSheet<SheetAction>(context, builder: (ctx) {
    final bd = ctx.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null) Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text(title, style: T.section(bd))),
      if (message != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(message, style: T.caption(bd))),
      const SizedBox(height: S.s),
      Group(children: [
        for (final a in actions) GroupTile(icon: a.icon, title: a.label, destructive: a.destructive, onTap: () => Navigator.pop(ctx, a)),
      ]),
      const SizedBox(height: S.m),
      BdButton('Cancel', kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx)),
    ]);
  });
  picked?.onTap();
}

/// Confirm a consequential action with an action sheet (thumb-reachable, clear
/// destructive/cancel split) instead of a centred dialog.
Future<bool> confirm(BuildContext context, {required String title, required String body, String yes = 'Yes', String no = 'Keep'}) async {
  final r = await showBdSheet<bool>(context, builder: (ctx) {
    final bd = ctx.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      Text(title, style: T.title(bd)),
      const SizedBox(height: S.s),
      Text(body, style: T.bodyMuted(bd)),
      const SizedBox(height: S.xxl),
      BdButton(yes, kind: BtnKind.accent, onTap: () => Navigator.pop(ctx, true)),
      const SizedBox(height: S.s),
      BdButton(no, kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, false)),
    ]);
  });
  return r == true;
}

// ── data plumbing ────────────────────────────────────────────────────────────
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
