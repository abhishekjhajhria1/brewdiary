import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/auth.dart';
import 'data/base.dart';
import 'data/entries.dart';
import 'data/reminder.dart';
import 'data/wishlist.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  if (Config.cloud) {
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
  }
  // Wire the stores once: auth first, then the diary + to-try list follow it.
  auth.init();
  entryStore.wire();
  wishlist.wire();
  ReminderStore.instance.restore();

  // Phones stay upright; foldables and tablets (600dp+ on the short side) rotate freely.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  if (view.physicalSize.shortestSide / view.devicePixelRatio < 600) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  // Ask Android for the panel's fastest refresh rate (90/120 Hz) — some phones keep
  // apps at 60 Hz unless asked. iPhones get ProMotion from Info.plist.
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }
  runApp(const BrewdiaryApp());
}
