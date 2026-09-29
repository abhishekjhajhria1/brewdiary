// Test plumbing: real fonts, and a one-call boot of the app on the DEMO venue (no
// Supabase values — the same data the demo mode shows).
import 'dart:io';

import 'package:brewdiary_bar/app.dart';
import 'package:brewdiary_bar/data/backend.dart';
import 'package:brewdiary_bar/data/demo_backend.dart';
import 'package:brewdiary_bar/data/prefs.dart';
import 'package:brewdiary_bar/data/session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.view(File(p).readAsBytesSync().buffer)));
    }
    await loader.load();
  }

  await load('Hanken Grotesk', ['assets/fonts/HankenGrotesk.ttf', 'assets/fonts/HankenGrotesk-Italic.ttf']);
  await load('Newsreader', ['assets/fonts/Newsreader.ttf', 'assets/fonts/Newsreader-Italic.ttf']);
  await load('Phosphor', ['assets/fonts/Phosphor.ttf']);
  await load('PhosphorFill', ['assets/fonts/Phosphor-Fill.ttf']);
  await load('PhosphorBold', ['assets/fonts/Phosphor-Bold.ttf']);
}

/// Boot the app on a fresh demo venue. Returns the backend so a test can poke at it.
Future<DemoBackend> bootApp(WidgetTester t, {bool signedIn = true, Size size = const Size(390, 844), Map<String, Object> prefs = const {}}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({...prefs});
  Prefs.useInstance(await SharedPreferences.getInstance());
  final backend = DemoBackend.seeded(signedIn: signedIn);
  Backend.use(backend);
  Session.instance = Session();
  await Session.instance.restore();
  await t.pumpWidget(const BarApp());
  await t.pumpAndSettle();
  return backend;
}

/// Tap the first widget showing [text] and settle.
Future<void> tapText(WidgetTester t, String text) async {
  await t.tap(find.text(text).first);
  await t.pumpAndSettle();
}
