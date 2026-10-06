// brewdiary — LIQUID GLASS tokens, ported from src/app/globals.css and tuned for a
// phone: a drink-hued ambient background with frosted surfaces floating over it,
// one amber accent, the mosaic glowing amber by count, high-contrast text.
// Dark is the default (the house style); Light and System are choices in Settings.
//
// Mobile tuning vs. the web tokens (all measured, WCAG AA):
//   • `faint` was 3.5:1 (dark) / 3.0:1 (light) — raised to ≥4.6:1 so hint text reads.
//   • light-theme text ON amber was 3.4:1 white — it's ink now (5.0:1).
//   • `accentText` is a deeper amber for amber-coloured TEXT on the light base (4.8:1).
//   • no drop shadows on surfaces: a translucent card showed its own shadow through
//     itself as a muddy band. Depth comes from the fill gradient + a hairline.
import 'package:flutter/cupertino.dart';
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
  final Color accentText;
  final Color accentContrast;
  final Color glass;
  final Color glassTop;
  final Color glassStrong;
  final Color glassBorder;
  final Color scrim;
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
    required this.accentText,
    required this.accentContrast,
    required this.glass,
    required this.glassTop,
    required this.glassStrong,
    required this.glassBorder,
    required this.scrim,
    required this.ambient,
    required this.dark,
  });

  static const light = BD(
    base: Color(0xFFECE7F2),
    ink: Color(0xFF1C1822),
    muted: Color(0xFF5D5668),
    faint: Color(0xFF6B6479),
    line: Color(0x1A1C1822),
    lineStrong: Color(0x2E1C1822),
    accent: Color(0xFFC07A22),
    accentText: Color(0xFF93570F),
    accentContrast: Color(0xFF1C1822),
    glass: Color(0x8CFFFFFF),
    glassTop: Color(0xB3FFFFFF),
    glassStrong: Color(0xD9FFFFFF),
    glassBorder: Color(0xB3FFFFFF),
    scrim: Color(0x661C1822),
    ambient: [Color(0x4DD88A2A), Color(0x42C94A6E), Color(0x3D3AB2A2), Color(0x387862E6)],
    dark: false,
  );

  static const darkTokens = BD(
    base: Color(0xFF0B0C12),
    ink: Color(0xFFF0EBE2),
    muted: Color(0xFFA59C93),
    faint: Color(0xFF938A81),
    line: Color(0x1FF0EBE2),
    lineStrong: Color(0x38F0EBE2),
    accent: Color(0xFFE6A64B),
    accentText: Color(0xFFE6A64B),
    accentContrast: Color(0xFF14110E),
    glass: Color(0x14FFFFFF),
    glassTop: Color(0x21FFFFFF),
    glassStrong: Color(0xE01A1B22),
    glassBorder: Color(0x24FFFFFF),
    scrim: Color(0x99000000),
    ambient: [Color(0x57E6A64B), Color(0x52D6336C), Color(0x472EC4B2), Color(0x4D846CFF)],
    dark: true,
  );

  /// Month-grid ramp (gentle — date numbers stay legible) and the year ramp (dramatic).
  Color cell(int level) => level <= 0 ? Colors.transparent : accent.withValues(alpha: const [0.0, .16, .28, .42, .58][level.clamp(0, 4)]);
  Color ycell(int level) => level <= 0 ? Colors.transparent : accent.withValues(alpha: const [0.0, .30, .52, .74, 1.0][level.clamp(0, 4)]);

  /// An opaque version of the sheet surface (dialogs, menus, pickers).
  Color get sheet => dark ? const Color(0xFF17181E) : const Color(0xFFF7F4FA);

  @override
  BD copyWith() => this;

  @override
  BD lerp(ThemeExtension<BD>? other, double t) => (other is BD && t > .5) ? other : this;
}

extension BDContext on BuildContext {
  BD get bd => Theme.of(this).extension<BD>()!;
}

// ── scale ────────────────────────────────────────────────────────────────────
/// One corner-radius scale, used everywhere.
const rCell = 6.0; // calendar squares
const rCtl = 12.0; // controls: buttons, fields, chips
const rTile = 20.0; // cards / surfaces
const rSheet = 28.0; // sheet tops

/// 4/8-pt spacing rhythm.
class S {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const x3 = 32.0;
  static const section = 40.0;

  /// Page gutter.
  static const gutter = 20.0;

  /// Minimum touch target (Material 48, Apple 44 — we honour 44 visually, 48 hit).
  static const tap = 44.0;
}

/// Motion: short, ease-out entering.
class Motion {
  static const fast = Duration(milliseconds: 150);
  static const med = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

/// Type voice — "editorial whisper": a humanist grotesque for everything, a
/// restrained editorial serif for moments (month name, titles).
class T {
  static const sansFamily = 'Hanken Grotesk';
  static const serifFamily = 'Newsreader';

  /// Hanken Grotesk has no ₹ — fall back to Newsreader for the glyphs it lacks.
  static const fallback = [serifFamily];

  /// Variable fonts: map the requested weight onto the `wght` axis so every
  /// platform renders the real weight (not a synthetic bold).
  static List<FontVariation> _wght(FontWeight w, {double? opsz}) => [
        FontVariation('wght', w.value.toDouble()),
        if (opsz != null) FontVariation('opsz', opsz.clamp(6, 72)),
      ];

  static TextStyle sans(BD bd, {double size = 15, FontWeight weight = FontWeight.w400, Color? color, double? height, double? spacing}) => TextStyle(
        fontFamily: sansFamily, fontFamilyFallback: fallback,
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

  /// The `.label` micro-caption: 11px, tracked, uppercase, medium. Use sparingly —
  /// stat captions and form-field labels, not every section header.
  static TextStyle label(BD bd, {Color? color}) => sans(bd, size: 11, spacing: 11 * .14, weight: FontWeight.w500, color: color ?? bd.muted);

  // Named steps of the type scale (12 · 13 · 15 · 17 · 20 · 28 · 40).
  static TextStyle caption(BD bd, {Color? color}) => sans(bd, size: 12.5, color: color ?? bd.faint, height: 1.45);
  static TextStyle body(BD bd, {Color? color}) => sans(bd, size: 15, color: color ?? bd.ink, height: 1.5);
  static TextStyle bodyMuted(BD bd) => sans(bd, size: 15, color: bd.muted, height: 1.55);
  static TextStyle row(BD bd, {Color? color}) => sans(bd, size: 16, color: color ?? bd.ink, height: 1.3);
  /// Section titles, as on the website: small, spaced capitals (the text is upper-cased by SectionHeader).
  static TextStyle section(BD bd) => sans(bd, size: 11.5, weight: FontWeight.w500, spacing: 11.5 * .16, color: bd.muted, height: 1.25);
  static TextStyle title(BD bd) => serif(bd, size: 28, height: 1.1);
  static TextStyle largeTitle(BD bd) => serif(bd, size: 40, height: 1.0);

  /// Raw styles for the share cards (fixed colours, not theme tokens).
  static TextStyle rawSans(double size, Color color, {FontWeight weight = FontWeight.w400, double? spacing}) =>
      TextStyle(fontFamily: sansFamily, fontFamilyFallback: fallback, fontSize: size, color: color, fontWeight: weight, fontVariations: _wght(weight), letterSpacing: spacing);
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
  final text = base.textTheme.apply(fontFamily: T.sansFamily, fontFamilyFallback: T.fallback, bodyColor: bd.ink, displayColor: bd.ink);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(rTile));
  return base.copyWith(
    scaffoldBackgroundColor: bd.base,
    canvasColor: bd.base,
    textTheme: text,
    colorScheme: base.colorScheme.copyWith(
      primary: bd.accent,
      onPrimary: bd.accentContrast,
      secondary: bd.accent,
      onSecondary: bd.accentContrast,
      surface: bd.sheet,
      onSurface: bd.ink,
      surfaceContainerHighest: bd.sheet,
      error: bd.accentText,
      outline: bd.lineStrong,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: bd.accent, selectionColor: bd.accent.withValues(alpha: .28), selectionHandleColor: bd.accent),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: bd.ink.withValues(alpha: .04),
    dividerColor: bd.line,
    dividerTheme: DividerThemeData(color: bd.line, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: bd.muted, size: 22),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: bd.accent, linearTrackColor: bd.line, circularTrackColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: bd.dark ? const Color(0xFFF0EBE2) : const Color(0xFF1C1822),
      contentTextStyle: T.sans(bd, size: 14, color: bd.dark ? const Color(0xFF14110E) : const Color(0xFFF7F4FA), weight: FontWeight.w500),
      actionTextColor: bd.accentText,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rCtl)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: bd.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: shape,
      titleTextStyle: T.title(bd),
      contentTextStyle: T.bodyMuted(bd),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, elevation: 0, modalElevation: 0),
    popupMenuTheme: PopupMenuThemeData(
      color: bd.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rCtl), side: BorderSide(color: bd.line)),
      textStyle: T.row(bd),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: bd.sheet, borderRadius: BorderRadius.circular(8), border: Border.all(color: bd.line)),
      textStyle: T.sans(bd, size: 13),
    ),
    // Fallbacks only — the app uses its own glass pickers (ui/widgets/pickers.dart).
    datePickerTheme: DatePickerThemeData(backgroundColor: bd.sheet, surfaceTintColor: Colors.transparent, shape: shape, headerForegroundColor: bd.ink),
    timePickerTheme: TimePickerThemeData(backgroundColor: bd.sheet, shape: shape),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: bd.dark ? Brightness.dark : Brightness.light,
      primaryColor: bd.accent,
      textTheme: CupertinoTextThemeData(
        dateTimePickerTextStyle: T.sans(bd, size: 21),
        pickerTextStyle: T.sans(bd, size: 20),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    extensions: [bd],
  );
}
