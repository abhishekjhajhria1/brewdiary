// The screen stays on while a station's tickets or the ready board are open — a tablet
// on the pass that dims mid-rush is a missed order. MainActivity / AppDelegate answer
// brewdiary/awake; nothing else changes how the phone sleeps.
import 'package:flutter/services.dart';

const _awake = MethodChannel('brewdiary/awake');

Future<void> keepAwake(bool on) async {
  try {
    await _awake.invokeMethod<void>('set', on);
  } catch (_) {
    // A test, or a platform without the channel: the screen just sleeps as usual.
  }
}
