// The table's own link — bwdy.site/t/<code> (supabase/051, 059). What a table's or a
// counter's QR / NFC tag opens: the venue's menu with the place known, and — if the venue
// switched it on — ordering from the phone and "call staff / bill please / water". The
// twin of src/lib/tableOrder.ts.
//
// How an order goes in is the venue's choice (059): it waits for a staff member's OK, or
// it goes straight onto the bar's and kitchen's screens and printers. At a PICKUP POINT
// (a bar counter, a café's or a shop's counter) it gets a number to collect, and you see
// it turn ready here. Staff never learn who asked; you see only your own orders.
//
// Some venues take orders without an account: then this phone makes a secret (kept on
// it, never shown) and the server keeps only its hash — the same secret finds your
// orders again.
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'auth.dart';
import 'base.dart';

class TableInfo {
  final String code;
  final String venueSlug;
  final String venueName;
  final String venueKind;
  final String tableLabel;

  /// The venue takes orders and calls from phones here.
  final bool tableService;

  /// 'table', or 'pickup' — a counter: an order gets a number to collect (059).
  final String pointKind;

  /// Orders go straight to the bar and kitchen, no staff OK first.
  final bool ordersDirect;

  /// The kitchen has paused phone orders for a while.
  final bool ordersPaused;

  /// Orders without an account are welcome here.
  final bool ordersAnon;

  /// on_trade | off_trade | no_alcohol — a liquor store's bottles are never phone-ordered.
  final String legalClass;
  const TableInfo({
    required this.code,
    required this.venueSlug,
    required this.venueName,
    required this.tableLabel,
    this.venueKind = 'bar',
    this.tableService = false,
    this.pointKind = 'table',
    this.ordersDirect = false,
    this.ordersPaused = false,
    this.ordersAnon = false,
    this.legalClass = 'on_trade',
  });

  bool get isPickup => pointKind == 'pickup';
  bool get offTrade => legalClass == 'off_trade';

  /// A counter (a liquor store, sweet shop, bakery, shop): it has a shelf.
  bool get isCounter => const {'store', 'sweet_shop', 'bakery', 'shop'}.contains(venueKind);

  factory TableInfo.fromRow(String code, Map<String, dynamic> x) => TableInfo(
        code: code,
        venueSlug: '${x['venue_slug']}',
        venueName: '${x['venue_name']}',
        venueKind: (x['venue_kind'] as String?) ?? 'bar',
        tableLabel: '${x['table_label']}',
        tableService: x['table_service'] == true,
        pointKind: (x['point_kind'] as String?) ?? 'table',
        ordersDirect: x['orders_direct'] == true,
        ordersPaused: x['orders_paused'] == true,
        ordersAnon: x['orders_anon'] == true,
        legalClass: (x['legal_class'] as String?) ?? 'on_trade',
      );
}

/// One of your orders, as you follow it (order_status_json, 059).
class OrderStatus {
  final String id;

  /// pending (waiting for an OK) | sent | making | ready | served | declined | withdrawn
  final String status;
  final DateTime createdAt;
  final String venueName;
  final String point;
  final bool atPickup;
  final int? pickupNo;
  final String? declineReason;
  final List<({String name, int qty, String status})> lines;
  const OrderStatus({
    required this.id,
    required this.status,
    required this.createdAt,
    this.venueName = '',
    this.point = '',
    this.atPickup = false,
    this.pickupNo,
    this.declineReason,
    this.lines = const [],
  });

  factory OrderStatus.fromJson(Map<String, dynamic> j) => OrderStatus(
        id: j['id'] as String,
        status: (j['status'] as String?) ?? 'pending',
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        venueName: (j['venue_name'] as String?) ?? '',
        point: (j['point'] as String?) ?? '',
        atPickup: j['point_kind'] == 'pickup',
        pickupNo: (j['pickup_no'] as num?)?.toInt(),
        declineReason: j['decline_reason'] as String?,
        lines: [
          for (final l in (j['lines'] as List? ?? const []))
            (name: '${l['name']}', qty: ((l['qty'] as num?) ?? 1).toInt(), status: (l['status'] as String?) ?? 'sent'),
        ],
      );

  /// Still on its way: worth asking about again.
  bool get live => const {'pending', 'sent', 'making', 'ready'}.contains(status);

  /// The steps you see, and which one it's on (0-based). Waiting for an OK comes first
  /// only where the venue confirms; declined and withdrawn have no steps.
  static const steps = ['Sent', 'Making', 'Ready', atTableWord];
  static const atTableWord = 'Served';
  int get step => switch (status) { 'pending' || 'sent' => 0, 'making' => 1, 'ready' => 2, 'served' => 3, _ => -1 };

  String get words => switch (status) {
        'pending' => 'waiting for the staff to confirm',
        'sent' => atPickup ? 'sent — they\'ll start on it' : 'sent to the bar and kitchen',
        'making' => 'being made',
        'ready' => atPickup ? 'ready — collect it${point.isEmpty ? '' : ' at $point'}' : 'ready — on its way to you',
        'served' => atPickup ? 'collected' : 'served',
        'declined' => 'declined${declineReason == null ? '' : ' — $declineReason'}',
        _ => 'cancelled',
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

/// This phone's own order secret (48 hex characters): made once, kept on the phone.
String deviceSecret() {
  const key = 'brewdiary.order.device';
  final have = Prefs.getString(key);
  if (have != null && RegExp(r'^[0-9a-f]{32,64}$').hasMatch(have)) return have;
  final r = Random.secure();
  final s = List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  Prefs.setString(key, s);
  return s;
}

/// The database hasn't had 059 yet: the 051 calls still work.
bool _behind(Object e) => e is PostgrestException && const {'PGRST202', '42883'}.contains(e.code);

class TableApi {
  /// null = no active table with that code at a verified venue.
  static Future<TableInfo?> info(String code) async {
    final c = db;
    if (c == null) throw StateError('not connected');
    final r = rows(await c.rpc('table_info', params: {'in_code': code}));
    if (r.isEmpty) return null;
    return TableInfo.fromRow(code, r.first);
  }

  static bool get _signedIn => auth.isAuthed;

  /// [lines]: what and how many — never a price (the server prices it). Returns how it
  /// went in: waiting for an OK, or already on the tickets (with a pickup number).
  static Future<OrderStatus?> order(String code, List<Map<String, Object>> lines, {String? note}) async {
    final c = db!;
    final req = _uuid();
    try {
      final j = _signedIn
          ? await c.rpc('place_order', params: {'in_code': code, 'req': req, 'lines': lines, 'req_note': note})
          : await c.rpc('place_order_guest', params: {'in_code': code, 'req': req, 'device': deviceSecret(), 'lines': lines, 'req_note': note});
      return j is Map ? OrderStatus.fromJson(Map<String, dynamic>.from(j)) : null;
    } catch (e) {
      if (!_behind(e) || !_signedIn) rethrow;
      await c.rpc('request_order', params: {'in_code': code, 'req': req, 'lines': lines, 'req_note': note}); // before 059
      return null;
    }
  }

  static Future<void> call(String code, String kind) => _signedIn
      ? db!.rpc('call_table_staff', params: {'in_code': code, 'call_kind': kind})
      : db!.rpc('call_table_staff_guest', params: {'in_code': code, 'device': deviceSecret(), 'call_kind': kind});

  static Future<void> withdraw(String id) => _signedIn ? db!.rpc('withdraw_request', params: {'req': id}) : db!.rpc('withdraw_guest_order', params: {'req': id, 'device': deviceSecret()});

  /// My own orders from the last 12 hours, newest first.
  static Future<List<OrderStatus>> mine() async {
    final c = db;
    if (c == null) return const [];
    try {
      final j = _signedIn ? await c.rpc('my_orders') : await c.rpc('guest_orders', params: {'device': deviceSecret()});
      return [for (final x in (j as List? ?? const [])) OrderStatus.fromJson(Map<String, dynamic>.from(x as Map))];
    } catch (e) {
      if (!_behind(e) || !_signedIn) rethrow;
      // Before 059: the requests themselves (RLS returns only mine).
      final since = DateTime.now().subtract(const Duration(hours: 12)).toUtc().toIso8601String();
      final r = await c.from('order_requests').select('id, status, lines, decline_reason, created_at').gte('created_at', since).order('created_at', ascending: false).limit(10);
      return [
        for (final x in r)
          OrderStatus(
            id: x['id'] as String,
            status: x['status'] == 'accepted' ? 'sent' : x['status'] as String,
            createdAt: DateTime.tryParse('${x['created_at']}')?.toLocal() ?? DateTime.now(),
            declineReason: x['decline_reason'] as String?,
            lines: [for (final l in (x['lines'] as List? ?? const [])) (name: '${l['name']}', qty: (l['qty'] as num).toInt(), status: 'sent')],
          ),
      ];
    }
  }
}

/// One thing on a counter's shelf (store_shelf(), 059): in stock, at its price — never
/// how many are left.
class ShelfItem {
  final String id;
  final String name;
  final String? brand;
  final String category;
  final double? size;
  final String? unit;
  final bool byWeight;
  final double price;
  final double? mrp;
  final bool alcohol;
  const ShelfItem({required this.id, required this.name, this.brand, this.category = 'other', this.size, this.unit, this.byWeight = false, required this.price, this.mrp, this.alcohol = false});

  String get title => brand == null || brand!.isEmpty ? name : '$brand $name';
  String get pack => size == null ? '' : '${size! % 1 == 0 ? size!.toInt() : size} ${unit ?? ''}'.trim();
}

class Shelf {
  final String venueName;
  final String currency;
  final List<ShelfItem> items;
  const Shelf({required this.venueName, required this.currency, required this.items});
}

class ShelfApi {
  /// A counter's shelf, or null when it isn't a verified counter (or has nothing in stock).
  static Future<Shelf?> load(String slug) async {
    final r = rows(await db!.rpc('store_shelf', params: {'in_slug': slug}));
    if (r.isEmpty) return null;
    return Shelf(
      venueName: '${r.first['venue_name']}',
      currency: (r.first['currency'] as String?) ?? 'INR',
      items: [
        for (final x in r)
          ShelfItem(
            id: x['product_id'] as String,
            name: '${x['name']}',
            brand: x['brand'] as String?,
            category: (x['category'] as String?) ?? 'other',
            size: (x['size'] as num?)?.toDouble(),
            unit: x['unit'] as String?,
            byWeight: x['sold_by'] == 'weight',
            price: ((x['price'] as num?) ?? 0).toDouble(),
            mrp: (x['mrp'] as num?)?.toDouble(),
            alcohol: x['is_alcohol'] == true,
          ),
      ],
    );
  }
}

/// The database says why in plain words (051/059 raise sentences); anything else is the
/// connection.
String tableError(Object e) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) {
    final m = e.message.trim();
    return m[0].toUpperCase() + m.substring(1);
  }
  return 'Couldn\'t reach brewdiary — try again.';
}
