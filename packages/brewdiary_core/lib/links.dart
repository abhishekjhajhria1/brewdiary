// What a QR code or an NFC tag can carry, read the same way by both apps (and twinned
// in src/lib/scanCodes.ts, with the same test cases):
//
//   • a table's link       https://bwdy.site/t/<code>      (051) — the menu, the table known
//   • a pickup point's     https://bwdy.site/t/<code>      (059) — the same link; the server
//                                                           says it's a counter
//   • a venue's menu       https://bwdy.site/m/<slug>      (042)
//   • the ready board      https://bwdy.site/ready/<code>  (059) — numbers, for a screen
//   • a guest card         bwdy:g:<CODE>                    (056) — the 6 letters, for the bar
//   • a shopping list      bwdy:l:<slug>:<item>.<qty>,…     (059) — shown at a counter's till
//
// A guest card and a list are not links on purpose: a phone camera that isn't ours shows
// them as text and opens nothing. A list names products and quantities, never who.
import 'dart:convert';

import 'menus.dart' show menuSlugFrom, tableCodeFrom;

/// The ready board's link: a screen by the counter shows pickup numbers.
String readyUrl(String code, [String origin = 'https://bwdy.site']) => '${origin.replaceAll(RegExp(r'/$'), '')}/ready/$code';

/// A ready-board link (`/ready/<code>`) → the pickup point's code, or null.
String? readyCodeFrom(Uri uri) {
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.length < 2 || seg[0] != 'ready') return null;
  final code = seg[1].trim().toLowerCase();
  return RegExp(r'^[0-9a-z]{8}$').hasMatch(code) ? code : null;
}

// ── a guest card ────────────────────────────────────────────────────────────
final _guestCode = RegExp(r'^[A-HJ-NP-Z2-9]{6}$');

/// What a guest card's QR holds.
String guestCardQr(String code) => 'bwdy:g:${code.trim().toUpperCase()}';

/// A scanned guest card (or the 6 letters typed) → the code, or null.
String? guestCodeFromScan(String raw) {
  var s = raw.trim().toUpperCase();
  if (s.startsWith('BWDY:G:')) s = s.substring(7);
  return _guestCode.hasMatch(s) ? s : null;
}

// ── a shopping list ─────────────────────────────────────────────────────────
final _slug = RegExp(r'^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])$');

/// The most lines a list carries — a basket, not a stockroom.
const maxListLines = 40;

/// A uuid in 22 characters (base64url, no padding): a shorter QR scans faster.
String packId(String uuid) {
  final hex = uuid.replaceAll('-', '').toLowerCase();
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) throw FormatException('not a uuid: $uuid');
  final bytes = [for (var i = 0; i < 32; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The other way; null for anything that isn't 22 base64url characters.
String? unpackId(String packed) {
  if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(packed)) return null;
  final List<int> bytes;
  try {
    bytes = base64Url.decode('$packed==');
  } on FormatException {
    return null;
  }
  if (bytes.length != 16) return null;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// What a list's QR holds: the shop and what's on it. Quantities are 1–99; the same
/// product twice is added up; past [maxListLines] lines the rest is left off.
String shopListQr(String slug, List<({String productId, int qty})> lines) {
  final merged = <String, int>{};
  for (final l in lines) {
    if (l.qty < 1) continue;
    merged[l.productId] = ((merged[l.productId] ?? 0) + l.qty).clamp(1, 99);
  }
  final parts = [for (final e in merged.entries.take(maxListLines)) '${packId(e.key)}.${e.value}'];
  return 'bwdy:l:${slug.trim().toLowerCase()}:${parts.join(',')}';
}

/// A scanned list → the shop's slug and its lines, or null if it isn't one.
({String slug, List<({String productId, int qty})> lines})? parseShopList(String raw) {
  final s = raw.trim();
  if (!s.startsWith('bwdy:l:')) return null;
  final rest = s.substring(7);
  final i = rest.indexOf(':');
  if (i < 0) return null;
  final slug = rest.substring(0, i);
  if (!_slug.hasMatch(slug)) return null;
  final lines = <({String productId, int qty})>[];
  for (final part in rest.substring(i + 1).split(',')) {
    if (part.isEmpty) continue;
    final dot = part.lastIndexOf('.');
    if (dot < 0) return null;
    final id = unpackId(part.substring(0, dot));
    final qty = int.tryParse(part.substring(dot + 1));
    if (id == null || qty == null || qty < 1 || qty > 99) return null;
    lines.add((productId: id, qty: qty));
    if (lines.length > maxListLines) return null;
  }
  return lines.isEmpty ? null : (slug: slug, lines: lines);
}

// ── one scan, any of the above ──────────────────────────────────────────────
enum ScanKind { table, menu, ready, guestCard, shopList, unknown }

/// What a scanned code (or a tag's link) is. [value] is the table code, menu slug,
/// ready-board code or guest code; a list is read with [parseShopList].
({ScanKind kind, String? value}) classifyScan(String raw) {
  final s = raw.trim();
  if (s.toLowerCase().startsWith('bwdy:g:')) {
    final c = guestCodeFromScan(s);
    return (kind: c == null ? ScanKind.unknown : ScanKind.guestCard, value: c);
  }
  if (s.startsWith('bwdy:l:')) return (kind: parseShopList(s) == null ? ScanKind.unknown : ScanKind.shopList, value: null);
  final uri = Uri.tryParse(s);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || !_ourHost(uri.host)) return (kind: ScanKind.unknown, value: null);
  if (tableCodeFrom(uri) case final c?) return (kind: ScanKind.table, value: c);
  if (menuSlugFrom(uri) case final m?) return (kind: ScanKind.menu, value: m);
  if (readyCodeFrom(uri) case final r?) return (kind: ScanKind.ready, value: r);
  return (kind: ScanKind.unknown, value: null);
}

/// bwdy.site and its subdomains (www., bar.) — never a look-alike.
bool _ourHost(String host) {
  final h = host.toLowerCase();
  return h == 'bwdy.site' || h.endsWith('.bwdy.site') || h == 'localhost' || h == '127.0.0.1';
}

// ── an NFC tag's link (an NDEF "U" record) ──────────────────────────────────
// The NFC Forum URI record shortens a link's start to one byte. Only the prefixes a
// brewdiary link can have are written; any of them is read.
const _uriPrefixes = ['', 'http://www.', 'https://www.', 'http://', 'https://'];

/// The payload of a URI record for [url]: the prefix byte, then the rest in UTF-8.
List<int> ndefUriPayload(String url) {
  // The longest prefix that fits ("https://www." before "https://").
  for (final i in const [2, 1, 4, 3]) {
    if (url.startsWith(_uriPrefixes[i])) return [i, ...utf8.encode(url.substring(_uriPrefixes[i].length))];
  }
  return [0, ...utf8.encode(url)];
}

/// A URI record's payload → the link, or null for a prefix we don't write.
String? uriFromNdefPayload(List<int> payload) {
  if (payload.isEmpty || payload[0] >= _uriPrefixes.length) return null;
  try {
    return _uriPrefixes[payload[0]] + utf8.decode(payload.sublist(1));
  } on FormatException {
    return null;
  }
}
