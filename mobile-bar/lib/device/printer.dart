// A station's ticket printer on the venue's Wi-Fi: raw ESC/POS to port 9100. Set per
// device (Prefs), because it's the tablet on the pass that sits next to the printer.
import 'dart:io';

import '../data/prefs.dart';
import '../logic/kot.dart';

String _key(String venueId, String station) => 'printer.$venueId.$station';
String _autoKey(String venueId, String station) => 'printer.auto.$venueId.$station';

/// This device's printer for a station ("192.168.1.50:9100"), or null.
String? printerFor(String venueId, String station) => Prefs.getString(_key(venueId, station));

/// Whether this device prints every new order for the station.
bool autoPrint(String venueId, String station) => Prefs.getString(_autoKey(venueId, station)) == '1' && printerFor(venueId, station) != null;

Future<void> setPrinter(String venueId, String station, String? address, {bool auto = true}) async {
  if (address == null || address.trim().isEmpty) {
    await Prefs.remove(_key(venueId, station));
    await Prefs.remove(_autoKey(venueId, station));
    return;
  }
  await Prefs.setString(_key(venueId, station), address.trim());
  await Prefs.setString(_autoKey(venueId, station), auto ? '1' : '0');
}

/// How a ticket is sent — [sendToPrinter], except under a widget test (which has no
/// network inside its fake clock, and checks the ticket instead).
Future<void> Function(String address, List<int> bytes) printSender = sendToPrinter;

/// Sends [bytes] to the printer at [address]. Throws a [PrinterError] worded for staff.
Future<void> sendToPrinter(String address, List<int> bytes, {Duration timeout = const Duration(seconds: 4)}) async {
  final p = parsePrinter(address);
  if (p == null) throw const PrinterError('That doesn\'t look like a printer\'s address — it\'s like 192.168.1.50.');
  Socket? s;
  try {
    s = await Socket.connect(p.host, p.port, timeout: timeout);
    s.add(bytes);
    await s.flush();
  } on SocketException {
    throw PrinterError('The printer at ${p.host} didn\'t answer — is it on, and on the same Wi-Fi?');
  } finally {
    await s?.close();
    s?.destroy();
  }
}

class PrinterError implements Exception {
  final String message;
  const PrinterError(this.message);
  @override
  String toString() => message;
}
