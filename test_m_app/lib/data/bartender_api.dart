// Ninkasi over the wire. The phone never holds an AI key: it streams from the
// website's /api/bartender route (rate-limited, size-capped, provider-agnostic),
// exactly like the browser does. She is the real model or she is honestly away —
// never a script pretending to be her.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'package:brewdiary_core/bartender.dart';
import 'base.dart';

/// Why Ninkasi couldn't answer, worded for the person holding the phone.
class NinkasiUnavailable implements Exception {
  final String message;
  const NinkasiUnavailable(this.message);
  @override
  String toString() => message;
}

class BartenderApi {
  /// Emits the growing reply text; fails with [NinkasiUnavailable].
  static Stream<String> ask(List<ChatMessage> messages, BartenderContext ctx, {required bool collect}) async* {
    final client = http.Client();
    var acc = '';
    try {
      final req = http.Request('POST', Config.api('/api/bartender'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'messages': messages.map((m) => m.toJson()).toList(),
          'context': ctx.toJson(),
          'collect': collect,
        });
      // Send the session token so a consented exchange can be attributed server-side.
      final token = db?.auth.currentSession?.accessToken;
      if (token != null) req.headers['Authorization'] = 'Bearer $token';

      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(const Duration(seconds: 20));
      } catch (e) {
        logDebug(e);
        throw const NinkasiUnavailable("Ninkasi can't be reached — check your connection and ask again.");
      }
      if (res.statusCode == 503) throw const NinkasiUnavailable("Ninkasi isn't switched on yet.");
      if (res.statusCode == 429) throw const NinkasiUnavailable('Too many questions at once — ask again in a minute.');
      if (res.statusCode >= 300) throw const NinkasiUnavailable("Ninkasi couldn't answer just now — ask again.");
      try {
        await for (final chunk in res.stream.transform(utf8.decoder)) {
          acc += chunk;
          yield acc;
        }
      } catch (e) {
        logDebug(e);
        throw const NinkasiUnavailable('The line dropped mid-answer — ask again.');
      }
      if (acc.trim().isEmpty) throw const NinkasiUnavailable("Ninkasi couldn't answer just now — ask again.");
    } finally {
      client.close();
    }
  }
}
