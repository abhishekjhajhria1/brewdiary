// The root: themes, then a gate — signed out → sign in; no venue chosen → your venues;
// otherwise the venue shell, whose tabs follow your role.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/session.dart';
import 'data/settings.dart';
import 'ui/screens/sign_in_screen.dart';
import 'ui/screens/venues_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class BarApp extends StatelessWidget {
  const BarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => MaterialApp(
        title: 'brewdiary bar',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildTheme(BD.light),
        darkTheme: buildTheme(BD.darkTokens),
        themeMode: ThemeStore.instance.mode,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
            child: MediaQuery(
              data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: .9, maxScaleFactor: 1.3)),
              child: KeyboardScope(inset: mq.viewInsets.bottom, child: child!),
            ),
          );
        },
        home: const RootGate(),
      ),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final s = Session.instance;
        final Widget page;
        if (!s.ready) {
          page = const _Splash(key: ValueKey('splash'));
        } else if (!s.signedIn) {
          page = const SignInScreen(key: ValueKey('signin'));
        } else if (s.venue == null) {
          page = const VenuesScreen(key: ValueKey('venues'));
        } else {
          page = Shell(key: ValueKey('shell-${s.venue!.id}'));
        }
        return AnimatedSwitcher(duration: Motion.med, child: page);
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(child: Center(child: Text('brewdiary bar', style: T.serif(bd, size: 32, italic: true)))),
    );
  }
}
