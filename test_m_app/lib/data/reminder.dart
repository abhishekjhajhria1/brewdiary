// The nightly reminder — a REAL scheduled notification on the phone.
//
// On the website this toggle only saved a flag and asked for permission; nothing
// ever fired. Here it schedules a local notification that repeats daily at the
// chosen time, entirely on the device (no push server, no data leaves the phone).
// Copy stays calm: an invitation to write a line, never a nudge to drink.
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'base.dart';

class ReminderStore extends ChangeNotifier {
  static final instance = ReminderStore();
  static const _key = 'brewdiary.reminder';
  static const _timeKey = 'brewdiary.reminder.time';
  static const _id = 7001;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

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
    );
    _ready = true;
  }

  /// Re-arm on launch so a reboot or reinstall never silently drops the reminder.
  Future<void> restore() async {
    if (!on) return;
    try {
      await _schedule();
    } catch (e) {
      logDebug(e);
    }
  }

  Future<bool> _requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return true;
  }

  Future<void> _schedule() async {
    await _init();
    final now = tz.TZDateTime.now(tz.local);
    final t = time;
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, t.hour, t.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _plugin.cancel(id: _id);
    await _plugin.zonedSchedule(
      id: _id,
      scheduledDate: at,
      title: 'brewdiary',
      body: 'A line for today? Tap to open your diary.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('nightly', 'Nightly reminder', channelDescription: 'One gentle reminder to write in your diary.', importance: Importance.defaultImportance),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Turn it on (asks permission first) or off. Returns false if permission was refused.
  Future<bool> setOn(bool value) async {
    if (!value) {
      await Prefs.setString(_key, 'off');
      notifyListeners();
      try {
        await _init();
        await _plugin.cancel(id: _id);
      } catch (_) {}
      return true;
    }
    try {
      await _init();
      if (!await _requestPermission()) return false;
      await Prefs.setString(_key, 'on');
      await _schedule();
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
    if (on) await _schedule();
  }
}
