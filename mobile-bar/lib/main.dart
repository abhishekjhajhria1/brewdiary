import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'app.dart';
import 'config.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/prefs.dart';
import 'data/session.dart';
import 'data/settings.dart';
import 'data/supabase_backend.dart';
import 'ui/widgets/motion.dart' show Haptics;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  if (Config.cloud) {
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
    Backend.use(SupabaseBackend());
  } else {
    Backend.use(DemoBackend.seeded());
  }
  await Session.instance.restore();
  // Haptics follow the switch on More, from the first frame on.
  void haptics() => Haptics.enabled = HapticsStore.instance.on;
  haptics();
  HapticsStore.instance.addListener(haptics);

  // Phones stay upright; tablets (600dp+ on the short side) rotate — a bar or kitchen
  // screen runs landscape.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  if (view.physicalSize.shortestSide / view.devicePixelRatio < 600) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }
  runApp(const BarApp());
}
