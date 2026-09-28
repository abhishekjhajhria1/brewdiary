import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BrewdiaryApp());
}
