// Device preferences and refresh signals — the same plumbing as the guest app.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Device preferences, loaded once at startup so reads are synchronous after that.
class Prefs {
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  /// For tests.
  static void useInstance(SharedPreferences p) => _p = p;

  static String? getString(String k) => _p.getString(k);
  static Future<void> setString(String k, String v) => _p.setString(k, v);
  static Future<void> remove(String k) => _p.remove(k);

  static T? getJson<T>(String k) {
    final raw = _p.getString(k);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setJson(String k, Object? v) => _p.setString(k, jsonEncode(v));
}

/// A refresh signal: mutations bump it, screens listening to it re-fetch.
class Rev extends ChangeNotifier {
  void bump() => notifyListeners();
}

final venueRev = Rev();
final staffRev = Rev();
final roomsRev = Rev();
final menuRev = Rev();
final perksRev = Rev();
final guestsRev = Rev();

const _uuid = Uuid();

/// Client-generated ids: inserts go out WITHOUT .select() (a definer read policy makes
/// PostgREST's INSERT … RETURNING fail), and a retried insert with the same id is a no-op.
String newId() => _uuid.v4();
