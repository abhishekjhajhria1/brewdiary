// Per-device preferences — ports of goals.ts, features.ts, waterPref.ts, age.ts,
// money.ts (currency), calendarView.ts, theme.ts, pantry.ts, training.ts. Each is a
// tiny ChangeNotifier over device storage: private intentions never leave the phone.
import 'package:flutter/material.dart';

import 'package:brewdiary_core/jurisdiction.dart';
import 'package:brewdiary_core/misc.dart';
import 'package:brewdiary_core/money.dart';
import 'package:brewdiary_core/types.dart';
import 'base.dart';

// ── theme (dark-default, like the web; Light and System are choices) ─────────
class ThemeStore extends ChangeNotifier {
  static final instance = ThemeStore();
  static const _key = 'brewdiary.theme';
  ThemeMode get mode => switch (Prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  /// The effective theme right now (resolving System against the device).
  bool get isDark => mode == ThemeMode.dark || (mode == ThemeMode.system && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);
  void toggle() => set(isDark ? ThemeMode.light : ThemeMode.dark);
  void set(ThemeMode m) {
    Prefs.setString(_key, switch (m) { ThemeMode.light => 'light', ThemeMode.system => 'system', ThemeMode.dark => 'dark' });
    notifyListeners();
  }
}

// ── haptics (on by default; Settings can switch them off) ────────────────────
/// Whether brewdiary taps back under your finger. main.dart hands the choice to
/// the UI's haptic vocabulary (ui/widgets/motion.dart) and keeps it in step.
class HapticsStore extends ChangeNotifier {
  static final instance = HapticsStore();
  static const _key = 'brewdiary.haptics.v1';
  bool get on => Prefs.getString(_key) != 'off';

  void set(bool v) {
    Prefs.setString(_key, v ? 'on' : 'off');
    notifyListeners();
  }
}

// ── calendar view (month | year) ─────────────────────────────────────────────
enum CalendarView { month, year }

class CalendarViewStore extends ChangeNotifier {
  static final instance = CalendarViewStore();
  static const _key = 'brewdiary.calendarView.v1';
  CalendarView get view => Prefs.getString(_key) == 'year' ? CalendarView.year : CalendarView.month;
  void toggle() {
    Prefs.setString(_key, view == CalendarView.month ? 'year' : 'month');
    notifyListeners();
  }
}

// ── gentle limits ────────────────────────────────────────────────────────────
enum GoalKey { weeklyLimit, dryDays }

const goalMax = {GoalKey.weeklyLimit: 50, GoalKey.dryDays: 7};

class GoalsStore extends ChangeNotifier {
  static final instance = GoalsStore();
  static const _key = 'brewdiary.goals.v1';

  Map<String, dynamic> get _raw => Prefs.getJson<Map<String, dynamic>>(_key) ?? {};
  int? get weeklyLimit => (_raw['weeklyLimit'] as num?)?.toInt();
  int? get dryDays => (_raw['dryDays'] as num?)?.toInt();
  bool get anySet => weeklyLimit != null || dryDays != null;

  /// Set a goal, or pass null to switch it off. Clamped to sane bounds.
  void set(GoalKey key, int? value) {
    final next = Map<String, dynamic>.from(_raw);
    if (value == null || value <= 0) {
      next.remove(key.name);
    } else {
      next[key.name] = value > goalMax[key]! ? goalMax[key] : value;
    }
    Prefs.setJson(_key, next);
    notifyListeners();
  }
}

// ── extras (opt-in trackers) ─────────────────────────────────────────────────
enum ExtraKey { cigarettes, water }

class ExtraDef {
  final ExtraKey key;
  final String label;
  final String hint;
  final String unit;
  final bool counter;

  /// Each +1 writes a REAL diary entry with this name + kind.
  final String entryDrink;
  final DrinkType entryType;
  const ExtraDef(this.key, this.label, this.hint, this.unit, this.counter, this.entryDrink, this.entryType);
}

const extras = [
  ExtraDef(ExtraKey.cigarettes, 'Cigarettes', 'A small +/- counter on each day, to keep an honest tally.', 'cigarette', true, 'Cigarette', DrinkType.other),
  ExtraDef(ExtraKey.water, 'Water', 'Count glasses of water alongside the day — a gentle nudge to hydrate.', 'glass', true, 'Water', DrinkType.soft),
];

class ExtrasStore extends ChangeNotifier {
  static final instance = ExtrasStore();
  static const _key = 'brewdiary.extras.v1';
  static const _waterKey = 'brewdiary.water.mlPerGlass.v1';

  Map<String, dynamic> get _flags => Prefs.getJson<Map<String, dynamic>>(_key) ?? {};
  bool isOn(ExtraKey k) => _flags[k.name] == true;
  void set(ExtraKey k, bool on) {
    Prefs.setJson(_key, {..._flags, k.name: on});
    notifyListeners();
  }

  List<ExtraDef> get enabledCounters => extras.where((e) => e.counter && isOn(e.key)).toList();

  int? get waterMl {
    final n = int.tryParse(Prefs.getString(_waterKey) ?? '');
    return n != null && n > 0 ? n : null;
  }

  void setWaterMl(int? ml) {
    if (ml != null && ml > 0) {
      Prefs.setString(_waterKey, '$ml');
    } else {
      Prefs.remove(_waterKey);
    }
    notifyListeners();
  }

  String? waterVolume(int glasses) => waterMl == null ? null : formatVolume(glasses * waterMl!);
}

// ── where you are: age gate + country + currency ─────────────────────────────
// v2 deliberately (see age.ts): the old flat-18 confirmations are not worth anything.
class PlaceStore extends ChangeNotifier {
  static final instance = PlaceStore();
  static const _ageKey = 'brewdiary.age.v2';
  static const _countryKey = 'brewdiary.country.v1';
  static const _clearedKey = 'brewdiary.agebar.v1';
  static const _currencyKey = 'brewdiary.currency.v1';

  /// The safe fallback when we don't know where someone is.
  static const legalAge = 21;

  bool get ageConfirmed => Prefs.getString(_ageKey) == 'ok';
  String? get country => Prefs.getString(_countryKey);
  String get currency => Prefs.getString(_currencyKey) ?? defaultCurrency;
  int get _clearedBar => int.tryParse(Prefs.getString(_clearedKey) ?? '') ?? 0;

  int legalAgeFor(String? country) => minDrinkingAge(country);

  void saveCountry(String code) {
    Prefs.setString(_countryKey, code.toUpperCase());
    // Their money follows from where they are — changeable later in You → settings.
    Prefs.setString(_currencyKey, currencyForCountry(code));
    notifyListeners();
  }

  void saveCurrency(String code) {
    Prefs.setString(_currencyKey, code.toUpperCase());
    notifyListeners();
  }

  /// Verify a date of birth against the legal age WHERE THEY ARE. Persists only on
  /// success, and never the date itself — only the (capped) bar they cleared.
  bool confirmAge(DateTime dob, String? country) {
    final age = ageFrom(dob);
    final ok = age >= legalAgeFor(country);
    if (ok) {
      Prefs.setString(_ageKey, 'ok');
      Prefs.setString(_clearedKey, '${age > 25 ? 25 : age}');
      if (country != null) saveCountry(country);
      notifyListeners();
    }
    return ok;
  }

  bool canMoveTo(String country) => _clearedBar >= legalAgeFor(country);

  /// The traveller's switch. Returns null on success, or the age that must be re-confirmed.
  int? moveTo(String country) {
    if (!canMoveTo(country)) return legalAgeFor(country);
    saveCountry(country);
    return null;
  }
}

// ── your home bar (pantry) ───────────────────────────────────────────────────
class PantryStore extends ChangeNotifier {
  static final instance = PantryStore();
  static const _key = 'brewdiary.pantry.v1';
  static const _cap = 60;

  List<String> get items => (Prefs.getJson<List<dynamic>>(_key) ?? const []).map((e) => '$e').toList();

  void add(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    final rest = items.where((i) => i.toLowerCase() != n.toLowerCase()).toList();
    final next = [n, ...rest];
    Prefs.setJson(_key, next.length > _cap ? next.sublist(0, _cap) : next);
    notifyListeners();
  }

  void remove(String name) {
    Prefs.setJson(_key, items.where((i) => i != name).toList());
    notifyListeners();
  }
}

// ── "Help train Ninkasi" consent + the on-device copy ────────────────────────
class TrainingStore extends ChangeNotifier {
  static final instance = TrainingStore();
  static const _key = 'brewdiary.training.v1';
  static const _prefKey = 'brewdiary.training.enabled';

  bool get collecting => Prefs.getString(_prefKey) != 'off';
  void setCollecting(bool on) {
    Prefs.setString(_prefKey, on ? 'on' : 'off');
    notifyListeners();
  }

  List<Map<String, dynamic>> get samples =>
      (Prefs.getJson<List<dynamic>>(_key) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  int get count => samples.length;

  void log({required String user, required String assistant, String? context}) {
    if (!collecting || user.trim().isEmpty || assistant.trim().isEmpty) return;
    Prefs.setJson(_key, [
      ...samples,
      {'id': newId(), 'at': DateTime.now().millisecondsSinceEpoch, 'user': user, 'assistant': assistant, 'context': context},
    ]);
    notifyListeners();
  }

  void clear() {
    Prefs.remove(_key);
    notifyListeners();
  }
}
