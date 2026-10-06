// Per-device settings: the theme, and whether the app taps back (haptics).
import 'package:flutter/material.dart';

import 'prefs.dart';

/// Light · dark · system. Dark is the default — bars are dark.
class ThemeStore extends ChangeNotifier {
  static final instance = ThemeStore();
  static const _key = 'bar.theme';
  ThemeMode get mode => switch (Prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  bool get isDark => mode == ThemeMode.dark || (mode == ThemeMode.system && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
  void toggle() => set(isDark ? ThemeMode.light : ThemeMode.dark);
  void set(ThemeMode m) {
    Prefs.setString(_key, switch (m) { ThemeMode.light => 'light', ThemeMode.system => 'system', ThemeMode.dark => 'dark' });
    notifyListeners();
  }
}

/// Whether the app taps back under your finger — on by default. main.dart hands the
/// choice to the UI's haptic vocabulary (ui/widgets/motion.dart) and keeps it in step.
class HapticsStore extends ChangeNotifier {
  static final instance = HapticsStore();
  static const _key = 'bar.haptics';
  bool get on => Prefs.getString(_key) != 'off';

  void set(bool v) {
    Prefs.setString(_key, v ? 'on' : 'off');
    notifyListeners();
  }
}
