// Who is signed in, which venue they're working, and what their role there lets them do.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/roles.dart';
import 'backend.dart';
import 'models.dart';
import 'prefs.dart';

class Session extends ChangeNotifier {
  /// The app's one session. Tests swap in a fresh one per case.
  static Session instance = Session();
  static const _venueKey = 'bar.venue.v1';

  AppUser? user;
  List<Venue> venues = const [];
  Venue? venue;
  bool ready = false;
  String? error;

  /// Set when someone steps back to their venue list on purpose, so a refresh doesn't
  /// drop them straight back into their only venue.
  bool _onList = false;
  StreamSubscription<AppUser?>? _sub;

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
        venues = const [];
        venue = null;
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
  }

  void _onVenueChange() => unawaited(refreshVenues());

  Future<void> refreshVenues({bool notify = true}) async {
    try {
      venues = await Backend.i.myVenues();
      error = null;
    } catch (e) {
      error = '$e';
    }
    final want = venue?.id ?? Prefs.getString(_venueKey);
    venue = venues.where((v) => v.id == want).firstOrNull ?? (venues.length == 1 && !_onList ? venues.first : null);
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
    venue = v;
    Prefs.setString(_venueKey, v.id);
    notifyListeners();
  }

  /// Back to the venue list (someone who works at two places).
  void leaveVenue() {
    _onList = true;
    venue = null;
    Prefs.remove(_venueKey);
    notifyListeners();
  }

  Future<void> signOut() async {
    await Backend.i.signOut();
    user = null;
    venues = const [];
    venue = null;
    Prefs.remove(_venueKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    venueRev.removeListener(_onVenueChange);
    super.dispose();
  }
}
