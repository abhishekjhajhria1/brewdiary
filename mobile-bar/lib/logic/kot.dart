// The kitchen order ticket (KOT) — what a thermal printer on the pass prints when an
// order lands, so a kitchen or a bar with no screen still gets every order. Pure: the
// bytes are ESC/POS, the language nearly every receipt printer speaks (Epson TM-T20/T82
// and the generic 58/80 mm printers sold everywhere), sent raw to port 9100.
//
// No prices and never who ordered: where it goes, what to make, the notes, the time.
import 'dart:convert';

import '../data/models.dart';

const _esc = 0x1b, _gs = 0x1d;

/// Characters a printer's default code page can't show, made plain (curly quotes,
/// dashes, accents); anything else non-ASCII becomes '?'.
String printable(String s) {
  const map = {
    '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...', '×': 'x', '·': '-', '₹': 'Rs ', '€': 'EUR ', '£': 'GBP ',
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'ß': 'ss',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (r >= 0x20 && r < 0x7f) {
      b.write(c);
    } else if (map[c] != null) {
      b.write(map[c]);
    } else if (map[c.toLowerCase()] != null) {
      b.write(map[c.toLowerCase()]!.toUpperCase());
    } else if (r == 0x0a) {
      b.write(' ');
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

/// [text] wrapped to [width] columns, breaking at spaces where it can.
List<String> wrap(String text, int width) {
  final out = <String>[];
  var line = '';
  for (final word in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
    var w = word;
    while (w.length > width) {
      if (line.isNotEmpty) {
        out.add(line);
        line = '';
      }
      out.add(w.substring(0, width));
      w = w.substring(width);
    }
    if (line.isEmpty) {
      line = w;
    } else if (line.length + 1 + w.length <= width) {
      line = '$line $w';
    } else {
      out.add(line);
      line = w;
    }
  }
  if (line.isNotEmpty) out.add(line);
  return out;
}

/// A ticket's text, line by line, as it's laid out on paper (also what the test reads).
List<String> kotLines({required String station, required String where, int? pickupNo, required List<OrderLine> lines, required DateTime at, bool fromPhone = false, bool reprint = false, int width = 42}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final head = pickupNo != null ? 'PICKUP $pickupNo' : printable(where).toUpperCase();
  return [
    if (reprint) '** REPRINT **',
    head,
    '${station.toUpperCase()}${fromPhone ? ' - PHONE ORDER' : ''} - ${two(at.hour)}:${two(at.minute)}',
    '-' * width,
    for (final l in lines) ...[
      ...wrap('${l.qty} x ${printable(l.name)}', width),
      if (l.seat != null) '   seat ${l.seat}',
      if (l.note != null && l.note!.trim().isNotEmpty) ...wrap(printable(l.note!), width - 3).map((s) => '   > $s'),
    ],
    '-' * width,
  ];
}

/// The ESC/POS bytes for one ticket: the place in double size, the lines in bold, a cut.
List<int> kotBytes({required String station, required String where, int? pickupNo, required List<OrderLine> lines, required DateTime at, bool fromPhone = false, bool reprint = false, int width = 42}) {
  final text = kotLines(station: station, where: where, pickupNo: pickupNo, lines: lines, at: at, fromPhone: fromPhone, reprint: reprint, width: width);
  final out = <int>[_esc, 0x40]; // initialise
  void line(String s) => out.addAll([...ascii.encode(s), 0x0a]);
  var i = 0;
  if (reprint) line(text[i++]);
  // The place (or the pickup number), centred and double size.
  out.addAll([_esc, 0x61, 1, _gs, 0x21, 0x11]);
  line(text[i++]);
  out.addAll([_gs, 0x21, 0x00, _esc, 0x61, 0]);
  line(text[i++]);
  line(text[i++]);
  out.addAll([_esc, 0x45, 1, _gs, 0x21, 0x01]); // bold, double height
  for (; i < text.length - 1; i++) {
    line(text[i]);
  }
  out.addAll([_esc, 0x45, 0, _gs, 0x21, 0x00]);
  line(text.last);
  out.addAll([0x0a, 0x0a, 0x0a, _gs, 0x56, 66, 0]); // feed, then a partial cut
  return out;
}

/// A test page: proves the printer is the right one and it's reachable.
List<int> testPageBytes(String venue, String station) => [
      _esc, 0x40, _esc, 0x61, 1, _gs, 0x21, 0x11,
      ...ascii.encode(printable(venue)), 0x0a,
      _gs, 0x21, 0x00,
      ...ascii.encode('${station.toUpperCase()} printer - brewdiary bar'), 0x0a,
      ...ascii.encode('New orders print here.'), 0x0a,
      0x0a, 0x0a, 0x0a, _gs, 0x56, 66, 0,
    ];

/// "192.168.1.50" or "192.168.1.50:9100" → host and port, or null.
({String host, int port})? parsePrinter(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^([a-zA-Z0-9.-]+)(?::(\d{1,5}))?$').firstMatch(s);
  if (m == null) return null;
  final port = m.group(2) == null ? 9100 : int.parse(m.group(2)!);
  if (port < 1 || port > 65535) return null;
  return (host: m.group(1)!, port: port);
}

/// The lines in [now] that weren't in what was already printed, by ticket (tab).
Map<String, List<OrderLine>> unprinted(List<OrderLine> now, Set<String> printed) {
  final out = <String, List<OrderLine>>{};
  for (final l in now) {
    if (printed.contains(l.id) || l.status != 'sent') continue;
    out.putIfAbsent(l.tabId, () => []).add(l);
  }
  return out;
}
