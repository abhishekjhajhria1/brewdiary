// Who is signed in, which venue they're working, and what their role there lets them do.
//
// Since 053 a person's place on a team can change under them: a manager can pause their
// access at any moment. The database stops every call at once (only ACTIVE staff count);
// this keeps the app honest about it — it re-checks every minute while open, when the app
// comes back to the front, and straight after the database refuses something — and a
// person paused mid-shift sees who to report to, not a screen of errors.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../logic/roles.dart';
import 'backend.dart';
import 'models.dart';
import 'prefs.dart';

class Session extends ChangeNotifier with WidgetsBindingObserver {
  /// The app's one session. Tests swap in a fresh one per case.
  static Session instance = Session();
  static const _venueKey = 'bar.venue.v1';

  /// How often an open app re-checks the person's access (a lock-out, an approval).
  static const recheckEvery = Duration(seconds: 60);

  AppUser? user;
  List<Venue> venues = const [];
  Venue? venue;
  bool ready = false;
  String? error;

  /// Where I'm waiting for a manager's yes, or paused — with why and who to see (053).
  List<StaffAccess> access = const [];

  /// Venues that added my email and wait for the owner's code (053).
  List<MyEnrolment> enrolments = const [];

  /// Set when the venue I was working got locked: the gate shows who to report to.
  StaffAccess? lockedOut;

  /// Set when someone steps back to their venue list on purpose, so a refresh doesn't
  /// drop them straight back into their only venue.
  bool _onList = false;
  StreamSubscription<AppUser?>? _sub;
  Timer? _timer;
  bool _observing = false;
  Future<void>? _inFlight;
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  bool get signedIn => user != null;
  StaffRole? get role => venue?.myRole;

  /// What the current role may do here. The database checks again on every call — this
  /// only decides what to show.
  bool can(Cap cap) => role != null && roleCan(role!, cap);

  Future<void> restore() async {
    _sub?.cancel();
    _sub = Backend.i.authChanges.listen((u) async {
      final changed = u?.id != user?.id;
      user = u;
      if (u == null) {
        _clear();
        notifyListeners();
      } else if (changed) {
        await refreshVenues();
      } else {
        notifyListeners();
      }
    });
    user = Backend.i.currentUser;
    if (user != null) await refreshVenues(notify: false);
    ready = true;
    notifyListeners();
    venueRev.addListener(_onVenueChange);
    accessRev.addListener(_onRefused);
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    // The demo lives on the phone and changes only when you change it: no clock needed
    // (and none left running under the widget tests).
    if (!Backend.i.isDemo) {
      _timer?.cancel();
      _timer = Timer.periodic(recheckEvery, (_) {
        if (signedIn) unawaited(refreshVenues());
      });
    }
  }

  void _onVenueChange() => unawaited(refreshVenues());

  /// The database refused something: maybe a lock-out landed. Look again (at most every
  /// few seconds, so a screen full of refusals doesn't become a storm of checks).
  void _onRefused() {
    if (!signedIn || DateTime.now().difference(_lastCheck) < const Duration(seconds: 3)) return;
    unawaited(refreshVenues());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && signedIn) unawaited(refreshVenues());
  }

  /// Load where this person stands. One check runs at a time: a call made while one is
  /// running gets a fresh pass straight after it (what changed may have landed mid-check),
  /// and every caller waits for that.
  Future<void> refreshVenues({bool notify = true}) {
    _asked++;
    return _inFlight ??= _checkUntilFresh(notify).whenComplete(() => _inFlight = null);
  }

  int _asked = 0;
  Future<void> _checkUntilFresh(bool notify) async {
    var done = 0;
    while (done < _asked) {
      done = _asked;
      await _refresh(notify);
    }
  }

  Future<void> _refresh(bool notify) async {
    _lastCheck = DateTime.now();
    try {
      venues = await Backend.i.myVenues();
      error = null;
    } catch (e) {
      error = '$e';
    }
    // Waiting, paused and codes to type: a database without 053 simply has none.
    try {
      access = await Backend.i.myStaffStatus();
    } catch (_) {
      access = const [];
    }
    try {
      enrolments = await Backend.i.myEnrolments();
    } catch (_) {
      enrolments = const [];
    }
    final want = venue?.id ?? lockedOut?.venueId ?? Prefs.getString(_venueKey);
    final lock = access.where((a) => a.locked && a.venueId == want).firstOrNull;
    if (lock != null) {
      // Paused while working here (or since the last time the app was open).
      lockedOut = lock;
      venue = null;
    } else {
      if (lockedOut != null && venues.any((v) => v.id == lockedOut!.venueId)) {
        // Given access again: straight back in.
        Prefs.setString(_venueKey, lockedOut!.venueId);
        _onList = false;
      }
      lockedOut = null;
      final keep = venue?.id ?? Prefs.getString(_venueKey);
      venue = venues.where((v) => v.id == keep).firstOrNull ?? (venues.length == 1 && !_onList ? venues.first : null);
    }
    if (notify) notifyListeners();
  }

  /// After a sign-in completes: take the backend's user and load their venues.
  Future<void> adoptCurrentUser() async {
    user = Backend.i.currentUser;
    if (user != null) await refreshVenues(notify: false);
    notifyListeners();
  }

  void select(Venue v) {
    _onList = false;
    lockedOut = null;
    venue = v;
    Prefs.setString(_venueKey, v.id);
    notifyListeners();
  }

  /// Back to the venue list (someone who works at two places).
  void leaveVenue() {
    _onList = true;
    venue = null;
    lockedOut = null;
    Prefs.remove(_venueKey);
    notifyListeners();
  }

  /// Open the paused screen for a venue from the list.
  void showLock(StaffAccess a) {
    lockedOut = a;
    venue = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    await Backend.i.signOut();
    user = null;
    _clear();
    Prefs.remove(_venueKey);
    notifyListeners();
  }

  void _clear() {
    venues = const [];
    venue = null;
    access = const [];
    enrolments = const [];
    lockedOut = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    venueRev.removeListener(_onVenueChange);
    accessRev.removeListener(_onRefused);
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
