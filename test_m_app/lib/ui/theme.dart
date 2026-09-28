// brewdiary — LIQUID GLASS tokens, ported 1:1 from src/app/globals.css.
// A vibrant drink-hued ambient background with frosted-glass tiles floating over it.
// One amber accent; the mosaic glows amber by count; text stays high-contrast.
// Dark is the default. No AI-slop purple/neon, no emoji as UI chrome.
import 'package:flutter/material.dart';

@immutable
class BD extends ThemeExtension<BD> {
  final Color base;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;
  final Color lineStrong;
  final Color accent;
  final Color accentContrast;
  final Color glass;
  final Color glassStrong;
  final Color glassBorder;
  final Color shadow;
  final List<Color> ambient; // four blob colours
  final bool dark;

  const BD({
    required this.base,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentContrast,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.shadow,
    required this.ambient,
    required this.dark,
  });

  static const light = BD(
    base: Color(0xFFECE7F2),
    ink: Color(0xFF1C1822),
    muted: Color(0xFF5D5668),
    faint: Color(0xFF8B8398),
    line: Color(0x1A1C1822),
    lineStrong: Color(0x2E1C1822),
    accent: Color(0xFFC07A22),
    accentContrast: Color(0xFFFFFDF8),
    glass: Color(0x80FFFFFF),
    glassStrong: Color(0xB8FFFFFF),
    glassBorder: Color(0xA6FFFFFF),
    shadow: Color(0x1F281E3C),
    ambient: [Color(0x4DD88A2A), Color(0x42C94A6E), Color(0x3D3AB2A2), Color(0x387862E6)],
    dark: false,
  );

  static const darkTokens = BD(
    base: Color(0xFF0B0C12),
    ink: Color(0xFFF0EBE2),
    muted: Color(0xFFA59C93),
    faint: Color(0xFF6F6760),
    line: Color(0x1FF0EBE2),
    lineStrong: Color(0x38F0EBE2),
    accent: Color(0xFFE6A64B),
    accentContrast: Color(0xFF14110E),
    glass: Color(0x12FFFFFF),
    glassStrong: Color(0x1FFFFFFF),
    glassBorder: Color(0x29FFFFFF),
    shadow: Color(0x66000000),
    ambient: [Color(0x57E6A64B), Color(0x52D6336C), Color(0x472EC4B2), Color(0x4D846CFF)],
    dark: true,
  );

  /// Month-grid ramp (gentle — date numbers stay legible) and the year ramp (dramatic).
  Color cell(int level) => level <= 0 ? Colors.transparent : accent.withValues(alpha: const [0.0, .14, .26, .40, .56][level.clamp(0, 4)]);
  Color ycell(int level) => level <= 0 ? Colors.transparent : accent.withValues(alpha: const [0.0, .30, .52, .74, 1.0][level.clamp(0, 4)]);

  @override
  BD copyWith() => this;

  @override
  BD lerp(ThemeExtension<BD>? other, double t) => (other is BD && t > .5) ? other : this;
}

extension BDContext on BuildContext {
  BD get bd => Theme.of(this).extension<BD>()!;
}

// Radii from the web tokens.
const rCtl = 10.0;
const rCell = 5.0;
const rTile = 20.0;

/// Type voice — "editorial whisper": a humanist grotesque for everything, a
/// restrained editorial serif for moments (month name, titles).
class T {
  static const sansFamily = 'Hanken Grotesk';
  static const serifFamily = 'Newsreader';

  /// Variable fonts: map the requested weight onto the `wght` axis so every
  /// platform renders the real weight (not a synthetic bold).
  static List<FontVariation> _wght(FontWeight w, {double? opsz}) => [
        FontVariation('wght', w.value.toDouble()),
        if (opsz != null) FontVariation('opsz', opsz.clamp(6, 72)),
      ];

  static TextStyle sans(BD bd, {double size = 15, FontWeight weight = FontWeight.w400, Color? color, double? height, double? spacing}) => TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        fontWeight: weight,
        fontVariations: _wght(weight),
        color: color ?? bd.ink,
        height: height,
        letterSpacing: spacing,
      );

  static TextStyle serif(BD bd, {double size = 28, Color? color, bool italic = false, double height = 1.0, FontWeight weight = FontWeight.w400}) => TextStyle(
        fontFamily: serifFamily,
        fontSize: size,
        fontWeight: weight,
        fontVariations: _wght(weight, opsz: size),
        color: color ?? bd.ink,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        height: height,
        letterSpacing: -0.02 * size,
      );

  /// The `.label` class: 11px, +0.16em tracking, uppercase, medium.
  static TextStyle label(BD bd, {Color? color}) => sans(bd, size: 11, spacing: 11 * .16, weight: FontWeight.w500, color: color ?? bd.muted);

  /// Raw styles for the share cards (fixed colours, not theme tokens).
  static TextStyle rawSans(double size, Color color, {FontWeight weight = FontWeight.w400, double? spacing}) =>
      TextStyle(fontFamily: sansFamily, fontSize: size, color: color, fontWeight: weight, fontVariations: _wght(weight), letterSpacing: spacing);
  static TextStyle rawSerif(double size, Color color, {FontWeight weight = FontWeight.w400, bool italic = false, double? height}) => TextStyle(
      fontFamily: serifFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontVariations: _wght(weight, opsz: size),
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      height: height);

  static const tnum = [FontFeature.tabularFigures()];
}

ThemeData buildTheme(BD bd) {
  final base = bd.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final text = base.textTheme.apply(fontFamily: T.sansFamily, bodyColor: bd.ink, displayColor: bd.ink);
  return base.copyWith(
    scaffoldBackgroundColor: bd.base,
    canvasColor: bd.base,
    textTheme: text,
    colorScheme: base.colorScheme.copyWith(
      primary: bd.accent,
      onPrimary: bd.accentContrast,
      secondary: bd.accent,
      surface: bd.base,
      onSurface: bd.ink,
      error: bd.accent,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: bd.accent, selectionColor: bd.accent.withValues(alpha: .28), selectionHandleColor: bd.accent),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: bd.line,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: bd.ink,
      contentTextStyle: T.sans(bd, color: bd.base, size: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rCtl)),
    ),
    extensions: [bd],
  );
}
