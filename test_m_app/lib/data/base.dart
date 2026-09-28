// Shared plumbing for the data layer: device preferences, the (optional) Supabase
// client, refresh signals, and id generation.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';

/// Device preferences — the mobile counterpart of the web's localStorage. Loaded
/// once at startup so reads are synchronous everywhere after that.
class Prefs {
  static late SharedPreferences _p;
  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  /// For tests.
  static void useInstance(SharedPreferences p) => _p = p;

  static String? getString(String k) => _p.getString(k);
  static Future<void> setString(String k, String v) => _p.setString(k, v);
  static Future<void> remove(String k) => _p.remove(k);
  static Set<String> keys() => _p.getKeys();

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

/// The backend, or null in local mode. Callers guard: `final c = db; if (c == null) …`.
SupabaseClient? get db => Config.cloud ? Supabase.instance.client : null;

/// A refresh signal: mutations bump it, screens listening to it re-fetch. The
/// mobile version of the web's per-module `version` + `bump()`.
class Rev extends ChangeNotifier {
  void bump() => notifyListeners();
}

final friendsRev = Rev();
final circlesRev = Rev();
final partiesRev = Rev();
final plansRev = Rev();
final pointsRev = Rev();
final splitRev = Rev();
final challengesRev = Rev();
final safetyRev = Rev();
final vouchRev = Rev();
final profileRev = Rev();

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Supabase returns either a single row or a list from an rpc — normalize to a list.
List<Map<String, dynamic>> rows(Object? data) {
  if (data == null) return [];
  if (data is List) return data.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  if (data is Map) return [Map<String, dynamic>.from(data)];
  return [];
}

Map<String, dynamic>? firstRow(Object? data) {
  final r = rows(data);
  return r.isEmpty ? null : r.first;
}

int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double asDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

List<String> asStrings(Object? v) => v is List ? v.map((e) => '$e').toList() : const [];

void logDebug(Object e) {
  if (kDebugMode) debugPrint('[brewdiary] $e');
}
