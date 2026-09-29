// The table's own link — bwdy.site/t/<code> (supabase/051). What a table's QR or NFC
// tag opens: the venue's menu with the table known, and — if the venue switched it on —
// ordering from the phone and "call staff / bill please / water". The twin of
// src/lib/tableOrder.ts.
//
// A guest only ASKS: an order is a request the staff accept onto the table's tab or
// decline with a reason. Staff never learn who asked; you see only your own requests.
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'base.dart';

class TableInfo {
  final String code;
  final String venueSlug;
  final String venueName;
  final String tableLabel;

  /// The venue takes orders and calls from phones at this table.
  final bool tableService;
  const TableInfo({required this.code, required this.venueSlug, required this.venueName, required this.tableLabel, this.tableService = false});
}

class MyRequest {
  final String id;
  final String status; // pending | accepted | declined | withdrawn
  final List<({String name, int qty})> lines;
  final String? declineReason;
  const MyRequest({required this.id, required this.status, required this.lines, this.declineReason});

  String get statusWords => switch (status) {
        'pending' => 'waiting for staff',
        'accepted' => 'on its way',
        'declined' => 'declined${declineReason == null ? '' : ' — $declineReason'}',
        _ => 'withdrawn',
      };
}

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class TableApi {
  /// null = no active table with that code at a verified venue.
  static Future<TableInfo?> info(String code) async {
    final c = db;
    if (c == null) throw StateError('not connected');
    final r = rows(await c.rpc('table_info', params: {'in_code': code}));
    if (r.isEmpty) return null;
    final x = r.first;
    return TableInfo(code: code, venueSlug: '${x['venue_slug']}', venueName: '${x['venue_name']}', tableLabel: '${x['table_label']}', tableService: x['table_service'] == true);
  }

  /// [lines]: what and how many — never a price (the staff's is final).
  static Future<void> order(String code, List<Map<String, Object>> lines, {String? note}) async {
    await db!.rpc('request_order', params: {'in_code': code, 'req': _uuid(), 'lines': lines, 'req_note': note});
  }

  static Future<void> call(String code, String kind) => db!.rpc('call_table_staff', params: {'in_code': code, 'call_kind': kind});

  static Future<void> withdraw(String id) => db!.rpc('withdraw_request', params: {'req': id});

  /// My own requests from the last 12 hours (RLS returns only mine), newest first.
  static Future<List<MyRequest>> mine() async {
    final c = db;
    if (c == null) return const [];
    final since = DateTime.now().subtract(const Duration(hours: 12)).toUtc().toIso8601String();
    final r = await c.from('order_requests').select('id, status, lines, decline_reason').gte('created_at', since).order('created_at', ascending: false).limit(10);
    return [
      for (final x in r)
        MyRequest(
          id: x['id'] as String,
          status: x['status'] as String,
          lines: [for (final l in (x['lines'] as List? ?? const [])) (name: '${l['name']}', qty: (l['qty'] as num).toInt())],
          declineReason: x['decline_reason'] as String?,
        ),
    ];
  }
}

/// The database says why in plain words (051 raises sentences); anything else is the
/// connection.
String tableError(Object e) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) {
    final m = e.message.trim();
    return m[0].toUpperCase() + m.substring(1);
  }
  return 'Couldn\'t reach brewdiary — try again.';
}
