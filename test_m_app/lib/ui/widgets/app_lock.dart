// An optional lock for the diary: Face ID, a fingerprint or the phone's own PIN to
// open brewdiary, and a plain cover over it in the app switcher. Off unless you
// switch it on (Settings › Your data).
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/base.dart';
import '../theme.dart';
import 'common.dart';
import 'page.dart';

class AppLockStore extends ChangeNotifier {
  static final instance = AppLockStore();
  static const _key = 'brewdiary.applock';
  final _auth = LocalAuthentication();

  bool get enabled => Prefs.getString(_key) == 'on';

  /// Can this phone lock at all (biometrics or a device PIN)?
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlock({String reason = 'Unlock your brewdiary'}) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }

  /// Turning it on takes one successful unlock, so nobody locks themselves out.
  Future<bool> setEnabled(bool on) async {
    if (on && !await unlock(reason: 'Confirm it\'s you to lock brewdiary')) return false;
    on ? await Prefs.setString(_key, 'on') : await Prefs.remove(_key);
    notifyListeners();
    return true;
  }
}

/// Sits over the whole app: locked at launch and after the app was away, covered
/// while it's in the app switcher.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final store = AppLockStore.instance;
  late bool _locked = store.enabled;
  bool _covered = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!store.enabled) {
      if (_covered || _locked) setState(() => _covered = _locked = false);
      return;
    }
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (!_asking) setState(() => _covered = true);
      case AppLifecycleState.paused:
        setState(() => _locked = _covered = true);
      case AppLifecycleState.resumed:
        setState(() => _covered = false);
        if (_locked) _ask();
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _ask() async {
    if (_asking) return;
    _asking = true;
    final ok = await store.unlock();
    _asking = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final shield = _locked || _covered;
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (shield)
        Positioned.fill(
          child: Material(
            color: bd.base,
            child: Ambient(
              child: SafeArea(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Wordmark(),
                    const SizedBox(height: S.xl),
                    Icon(Ph.lock, size: 34, color: bd.accentText),
                    if (_locked) ...[
                      const SizedBox(height: S.l),
                      Text('Your diary is locked.', style: T.row(bd)),
                      const SizedBox(height: S.l),
                      SizedBox(width: 220, child: BdButton('Unlock', icon: Ph.fingerprint, onTap: _ask)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
