// Auth + profile — a port of src/lib/profile.ts. Email + password via Supabase;
// when Supabase isn't configured it degrades to a local profile so the app still runs.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../core/date.dart';
import '../core/handles.dart';
import 'base.dart';

class Profile {
  final String id;
  final String name;
  final String handle;
  final String createdAt;

  /// Passed the live-camera check — an anti-bot trust signal, NOT identity.
  final bool presenceChecked;

  const Profile({required this.id, required this.name, required this.handle, required this.createdAt, this.presenceChecked = false});

  Profile copyWith({String? handle, bool? presenceChecked}) => Profile(
        id: id,
        name: name,
        handle: handle ?? this.handle,
        createdAt: createdAt,
        presenceChecked: presenceChecked ?? this.presenceChecked,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'handle': handle, 'createdAt': createdAt, 'presenceChecked': presenceChecked};
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'you',
        handle: j['handle'] as String? ?? '',
        createdAt: j['createdAt'] as String? ?? appNow().toIso8601String(),
        presenceChecked: j['presenceChecked'] == true,
      );

  static Profile fromRow(Map<String, dynamic> r) => Profile(
        id: r['id'] as String,
        name: (r['display_name'] as String?) ?? 'you',
        handle: (r['handle'] as String?) ?? '',
        createdAt: r['created_at'] as String,
        presenceChecked: r['presence_checked'] == true,
      );
}

enum AuthStatus { loading, authed, anon }

class AuthResult {
  final bool ok;
  final String? error;
  final bool needsConfirm;
  const AuthResult.success({this.needsConfirm = false})
      : ok = true,
        error = null;
  const AuthResult.failure(this.error)
      : ok = false,
        needsConfirm = false;
}

const _profileCols = 'id, display_name, handle, created_at, presence_checked';
const _localKey = 'brewdiary.profile.v1';

class AuthStore extends ChangeNotifier {
  AuthStore._();
  static final instance = AuthStore._();

  AuthStatus status = AuthStatus.loading;
  Profile? profile;
  StreamSubscription<AuthState>? _sub;
  bool _initialized = false;

  bool get isAuthed => status == AuthStatus.authed && profile != null;
  String? get meId => profile?.id;

  void _set(AuthStatus s, Profile? p) {
    status = s;
    profile = p;
    notifyListeners();
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    final c = db;
    if (c == null) {
      final local = Prefs.getJson<Map<String, dynamic>>(_localKey);
      local != null ? _set(AuthStatus.authed, Profile.fromJson(local)) : _set(AuthStatus.anon, null);
      return;
    }
    _applySession(c.auth.currentSession);
    _sub = c.auth.onAuthStateChange.listen((e) => _applySession(e.session));
  }

  Future<void> _applySession(Session? session) async {
    final user = session?.user;
    if (user == null) {
      _set(AuthStatus.anon, null);
      return;
    }
    if (profile?.id == user.id && status == AuthStatus.authed) return;
    try {
      _set(AuthStatus.authed, await _ensureProfile(user));
    } catch (e) {
      logDebug(e);
      _set(AuthStatus.anon, null);
    }
  }

  /// Read the profile row, creating it on first sight. `handle` is UNIQUE, so
  /// allocation is a short retry loop: our row already existing means a race (adopt
  /// it); otherwise the handle clashed, so try another word.
  Future<Profile> _ensureProfile(User user) async {
    final c = db!;
    final existing = await c.from('profiles').select(_profileCols).eq('id', user.id).maybeSingle();
    if (existing != null) return Profile.fromRow(existing);

    final name = ((user.userMetadata?['name'] as String?) ?? user.email?.split('@').first ?? 'you').trim();
    for (var attempt = 0; attempt < handleTries; attempt++) {
      try {
        final inserted = await c
            .from('profiles')
            .insert({'id': user.id, 'handle': coolHandle(name, attempt: attempt), 'display_name': name})
            .select(_profileCols)
            .single();
        return Profile.fromRow(inserted);
      } catch (_) {
        final mine = await c.from('profiles').select(_profileCols).eq('id', user.id).maybeSingle();
        if (mine != null) return Profile.fromRow(mine);
      }
    }
    throw Exception('could not allocate a unique handle');
  }

  Future<AuthResult> signUp(String email, String password, String name) async {
    final c = db;
    if (c == null) {
      final p = Profile(id: 'local', name: name.trim().isEmpty ? 'you' : name.trim(), handle: '', createdAt: appNow().toIso8601String());
      await Prefs.setJson(_localKey, p.toJson());
      _set(AuthStatus.authed, p);
      return const AuthResult.success();
    }
    try {
      final res = await c.auth.signUp(email: email.trim(), password: password, data: {'name': name.trim()});
      if (res.session?.user != null) {
        await _applySession(res.session);
        return const AuthResult.success();
      }
      return const AuthResult.success(needsConfirm: true);
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('$e');
    }
  }

  Future<AuthResult> signIn(String email, String password) async {
    final c = db;
    if (c == null) {
      final p = profile ??
          (Prefs.getJson<Map<String, dynamic>>(_localKey) != null
              ? Profile.fromJson(Prefs.getJson<Map<String, dynamic>>(_localKey)!)
              : Profile(id: 'local', name: 'you', handle: '', createdAt: appNow().toIso8601String()));
      await Prefs.setJson(_localKey, p.toJson());
      _set(AuthStatus.authed, p);
      return const AuthResult.success();
    }
    try {
      await c.auth.signInWithPassword(email: email.trim(), password: password);
      return const AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    } catch (e) {
      return AuthResult.failure('$e');
    }
  }

  Future<void> signOut() async {
    final c = db;
    if (c == null) {
      await Prefs.remove(_localKey);
      _set(AuthStatus.anon, null);
      return;
    }
    await c.auth.signOut();
  }

  /// Email a reset link. It opens the website's /reset page, which finishes the job.
  Future<AuthResult> sendPasswordReset(String email) async {
    final c = db;
    if (c == null) return const AuthResult.failure('Password reset needs the cloud backend.');
    try {
      await c.auth.resetPasswordForEmail(email.trim(), redirectTo: '${Config.siteUrl}/reset');
      return const AuthResult.success();
    } on AuthException catch (e) {
      return AuthResult.failure(e.message);
    }
  }

  /// Claim a new (generated) handle. The only failure that matters is the race where
  /// two people grab the same word — reported as "taken" so the UI can re-roll.
  Future<AuthResult> updateHandle(String handle) async {
    final p = profile;
    if (p == null) return const AuthResult.failure('Not signed in.');
    final c = db;
    if (c == null) {
      final next = p.copyWith(handle: handle);
      await Prefs.setJson(_localKey, next.toJson());
      _set(AuthStatus.authed, next);
      return const AuthResult.success();
    }
    try {
      await c.from('profiles').update({'handle': handle}).eq('id', p.id);
      _set(AuthStatus.authed, p.copyWith(handle: handle));
      return const AuthResult.success();
    } on PostgrestException catch (e) {
      if (RegExp('duplicate|unique', caseSensitive: false).hasMatch(e.message)) return const AuthResult.failure('taken');
      return AuthResult.failure(e.message);
    }
  }

  /// Persist that the person passed the live-camera check (soft anti-bot signal).
  Future<bool> markPresenceChecked() async {
    final p = profile;
    if (p == null) return false;
    final c = db;
    if (c == null) {
      final next = p.copyWith(presenceChecked: true);
      await Prefs.setJson(_localKey, next.toJson());
      _set(AuthStatus.authed, next);
      return true;
    }
    try {
      await c.from('profiles').update({'presence_checked': true, 'presence_checked_at': DateTime.now().toUtc().toIso8601String()}).eq('id', p.id);
      _set(AuthStatus.authed, p.copyWith(presenceChecked: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

AuthStore get auth => AuthStore.instance;
