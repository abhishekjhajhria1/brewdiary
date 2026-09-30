// Ninkasi over the wire. The phone never holds an AI key: it streams from the
// website's /api/bartender route (rate-limited, size-capped, provider-agnostic),
// exactly like the browser does. If the server can't be reached, the scripted
// fallback keeps her in character.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'package:brewdiary_core/bartender.dart';
import 'base.dart';

class BartenderStream {
  /// Emits the growing reply text. `mode` is 'live', 'fallback' or 'offline'.
  final Stream<String> text;
  final Future<String> mode;
  const BartenderStream(this.text, this.mode);
}

class BartenderApi {
  static BartenderStream ask(List<ChatMessage> messages, BartenderContext ctx, {required bool collect}) {
    final modeFuture = Completer<String>();
    void setMode(String m) {
      if (!modeFuture.isCompleted) modeFuture.complete(m);
    }


    Stream<String> gen() async* {
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

        final res = await client.send(req).timeout(const Duration(seconds: 20));
        if (res.statusCode == 429) {
          setMode('live');
          yield "Slow down, love — the bar's busy. Try again in a moment.";
          return;
        }
        if (res.statusCode >= 300) throw Exception('status ${res.statusCode}');
        setMode(res.headers['x-bartender-mode'] ?? 'live');
        await for (final chunk in res.stream.transform(utf8.decoder)) {
          acc += chunk;
          yield acc;
        }
      } catch (e) {
        logDebug(e);
        setMode('offline');
        if (acc.isEmpty) yield fallbackReply(messages, ctx);
      } finally {
        client.close();
      }
    }

    return BartenderStream(gen(), modeFuture.future);
  }
}
