// What a build made without the server's address shows instead of the app. brewdiary
// never runs on pretend accounts: it is the real server or this page.
import 'package:flutter/material.dart';

import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/page.dart';

class NotConnectedApp extends StatelessWidget {
  const NotConnectedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => MaterialApp(
        title: 'brewdiary',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(BD.light),
        darkTheme: buildTheme(BD.darkTokens),
        themeMode: ThemeStore.instance.mode,
        home: const NotConnectedScreen(),
      ),
    );
  }
}

class NotConnectedScreen extends StatelessWidget {
  const NotConnectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: S.gutter, vertical: S.x3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Wordmark(size: 40),
                  const SizedBox(height: S.x3),
                  Glass(
                    padding: const EdgeInsets.all(S.xl),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Not connected yet', style: T.title(bd)),
                      const SizedBox(height: S.m),
                      Text(
                        'This copy of brewdiary was built without the address of its server, so there is nowhere to keep your diary. '
                        'Install the version from the app store, or ask whoever gave you this file for the connected build.',
                        style: T.bodyMuted(bd),
                      ),
                    ]),
                  ),
                  const SizedBox(height: S.xl),
                  Text('For the developer: build with --dart-define-from-file=env.json holding SUPABASE_URL and SUPABASE_ANON_KEY (see docs/12).', style: T.caption(bd)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
