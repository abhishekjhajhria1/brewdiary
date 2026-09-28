// The nightly reminder — a REAL scheduled notification on the phone.
//
// On the website this toggle only saved a flag and asked for permission; nothing
// ever fired. Here it schedules local notifications entirely on the device (no
// push server, no data leaves the phone): one each evening for the next four
// weeks, skipping any evening you've already written in — log tonight and
// tonight's reminder quietly cancels. Using the app rolls the window forward, so
// it keeps going while you keep the diary and goes quiet after a month away.
// Tapping it opens today's log sheet. Copy stays calm: an invitation to write a
// line, never a nudge to drink.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/date.dart';
import 'base.dart';
import 'entries.dart';

class ReminderStore extends ChangeNotifier {
  static final instance = ReminderStore();
  static const _key = 'brewdiary.reminder';
  static const _timeKey = 'brewdiary.reminder.time';

  /// The old single repeating reminder (cancelled on the next schedule).
  static const _legacyId = 7001;

  /// One id per evening in the window: 7100 = today, 7101 = tomorrow, …
  static const _baseId = 7100;
  static const _days = 28;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _wired = false;
  Timer? _debounce;
  String? _scheduled; // what's armed right now, so an edit that changes nothing doesn't re-arm

  /// Set when a reminder is tapped (or launched the app); the shell answers by
  /// opening today's log sheet, and clears it.
  final openToday = ValueNotifier<bool>(false);

  bool get on => Prefs.getString(_key) == 'on';

  TimeOfDay get time {
    final raw = Prefs.getString(_timeKey) ?? '21:30';
    final p = raw.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 21, minute: int.tryParse(p.elementAtOrNull(1) ?? '') ?? 30);
  }

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Unknown zone name — fall back to UTC scheduling; the time will still repeat daily.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      // A pacing nudge just opens the app; the nightly reminder opens today's sheet.
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != _pacePayload) openToday.value = true;
      },
    );
    _ready = true;
  }

  /// Re-arm on launch so a reboot or reinstall never silently drops the reminder,
  /// and follow the diary from here on: a new entry can cancel tonight's.
  Future<void> restore() async {
    if (!_wired) {
      _wired = true;
      entryStore.addListener(_rearmSoon);
      AppLifecycleListener(onResume: _rearmSoon);
    }
    if (!on) return;
    try {
      await _init();
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if ((launch?.didNotificationLaunchApp ?? false) && launch?.notificationResponse?.payload != _pacePayload) openToday.value = true;
      await _schedule();
    } catch (e) {
      logDebug(e);
    }
  }

  void _rearmSoon() {
    if (!on) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => _schedule().catchError((Object e) => logDebug(e)));
  }

  Future<bool> _requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return true;
  }

  Future<void> _cancelAll() async {
    await _plugin.cancel(id: _legacyId);
    for (var d = 0; d < _days; d++) {
      await _plugin.cancel(id: _baseId + d);
    }
    _scheduled = null;
  }

  /// The evenings to remind, as (days from today, wall-clock time): the next
  /// [days] evenings at [t], less any already past and any you've written in.
  static List<(int, DateTime)> evenings(DateTime now, TimeOfDay t, Set<String> written, {int days = _days}) {
    final out = <(int, DateTime)>[];
    for (var d = 0; d < days; d++) {
      final at = DateTime(now.year, now.month, now.day + d, t.hour, t.minute);
      if (at.isAfter(now) && !written.contains(toKey(at))) out.add((d, at));
    }
    return out;
  }

  Future<void> _schedule({bool force = false}) async {
    await _init();
    final n = tz.TZDateTime.now(tz.local);
    final now = DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second);
    final t = time;
    final due = evenings(now, t, {for (final e in entryStore.entries) e.date});
    final plan = [toKey(now), '${t.hour}:${t.minute}', for (final (d, _) in due) d].join('|');
    if (!force && plan == _scheduled) return;
    await _cancelAll();
    for (final (d, at) in due) {
      await _plugin.zonedSchedule(
        id: _baseId + d,
        scheduledDate: tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute),
        title: 'brewdiary',
        body: 'A line for today? Tap to open your diary.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('nightly', 'Nightly reminder', channelDescription: 'One gentle reminder to write in your diary.', importance: Importance.defaultImportance),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    _scheduled = plan;
  }

  /// Turn it on (asks permission first) or off. Returns false if permission was refused.
  Future<bool> setOn(bool value) async {
    if (!value) {
      await Prefs.setString(_key, 'off');
      notifyListeners();
      _debounce?.cancel();
      try {
        await _init();
        await _cancelAll();
      } catch (_) {}
      return true;
    }
    try {
      await _init();
      if (!await _requestPermission()) return false;
      await Prefs.setString(_key, 'on');
      await _schedule(force: true);
      notifyListeners();
      return true;
    } catch (e) {
      logDebug(e);
      return false;
    }
  }

  Future<void> setTime(TimeOfDay t) async {
    await Prefs.setString(_timeKey, '${t.hour}:${t.minute}');
    notifyListeners();
    if (on) await _schedule(force: true);
  }

  // ── pacing: a few water-break nudges for one night ─────────────────────────
  // Opt-in, per night, and it only ever says "slow down": a glass of water between
  // rounds. It never counts drinks and never suggests another.
  static const _paceBase = 7300;
  static const _paceMax = 8;
  static const _paceKey = 'brewdiary.pace.until';
  static const _pacePayload = 'pace';
  static const paceMessages = [
    'Water break? A glass between rounds keeps the night a good one.',
    'Pace check — no rush. Water first, then decide.',
    'How are you feeling? A glass of water now is a good call.',
    'Halfway-ish. Water, a snack, and you\'re set.',
    'Last nudge from me: water before the next one, and a plan for getting home.',
  ];

  /// When tonight's nudges run out, or null if pacing is off.
  DateTime? get pacingUntil {
    final raw = Prefs.getString(_paceKey);
    final t = raw == null ? null : DateTime.tryParse(raw);
    return t != null && t.isAfter(DateTime.now()) ? t : null;
  }

  bool get pacing => pacingUntil != null;

  /// The nudge times: every [every], [count] times, starting one interval from now.
  static List<DateTime> paceTimes(DateTime now, {Duration every = const Duration(minutes: 45), int count = 5}) =>
      [for (var i = 1; i <= count.clamp(1, _paceMax); i++) now.add(every * i)];

  /// Turn tonight's nudges on (asks permission first). False if refused.
  Future<bool> startPacing({Duration every = const Duration(minutes: 45), int count = 5}) async {
    try {
      await _init();
      if (!await _requestPermission()) return false;
      await _cancelPacing();
      final times = paceTimes(DateTime.now(), every: every, count: count);
      for (var i = 0; i < times.length; i++) {
        await _plugin.zonedSchedule(
          id: _paceBase + i,
          scheduledDate: tz.TZDateTime.from(times[i], tz.local),
          title: 'brewdiary',
          body: paceMessages[i % paceMessages.length],
          payload: _pacePayload,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('pace', 'Pace the night', channelDescription: 'Water-break nudges you switch on for one night.', importance: Importance.defaultImportance),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      await Prefs.setString(_paceKey, times.last.toIso8601String());
      notifyListeners();
      return true;
    } catch (e) {
      logDebug(e);
      return false;
    }
  }

  Future<void> stopPacing() async {
    await Prefs.remove(_paceKey);
    notifyListeners();
    try {
      await _init();
      await _cancelPacing();
    } catch (_) {}
  }

  Future<void> _cancelPacing() async {
    for (var i = 0; i < _paceMax; i++) {
      await _plugin.cancel(id: _paceBase + i);
    }
  }
}
