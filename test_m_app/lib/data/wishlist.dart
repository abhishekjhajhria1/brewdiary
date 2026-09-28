// "To try" list — a port of src/lib/wishlist.ts. Local when logged out, Supabase
// (wishlist_items) when signed in, optimistic writes, local→remote on sign-in.
import 'package:flutter/foundation.dart';

import 'auth.dart';
import 'base.dart';

class WishItem {
  final String id;
  final String drink;
  final String createdAt;
  final bool done;
  const WishItem({required this.id, required this.drink, required this.createdAt, this.done = false});

  WishItem withDone(bool d) => WishItem(id: id, drink: drink, createdAt: createdAt, done: d);
  Map<String, dynamic> toJson() => {'id': id, 'drink': drink, 'createdAt': createdAt, 'done': done};
  factory WishItem.fromJson(Map<String, dynamic> j) =>
      WishItem(id: j['id'] as String, drink: j['drink'] as String, createdAt: j['createdAt'] as String, done: j['done'] == true);
}

const _key = 'brewdiary.wishlist.v1';

class WishlistStore extends ChangeNotifier {
  static final instance = WishlistStore();

  List<WishItem> _cache = const [];
  bool _remote = false;
  String? _user;
  bool _wired = false;

  List<WishItem> get items => _cache;

  void _set(List<WishItem> next) {
    _cache = List.unmodifiable(next);
    notifyListeners();
  }

  List<WishItem> _readLocal() =>
      (Prefs.getJson<List<dynamic>>(_key) ?? const []).map((e) => WishItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  void _writeLocal() => Prefs.setJson(_key, _cache.map((w) => w.toJson()).toList());

  Map<String, dynamic> _toRow(WishItem w, String userId) =>
      {'id': w.id, 'user_id': userId, 'drink_name': w.drink, 'fulfilled': w.done};

  Future<void> _loadRemote() async {
    final c = db;
    if (c == null) return;
    try {
      final data = await c.from('wishlist_items').select('id, drink_name, created_at, fulfilled').order('created_at', ascending: false);
      _set(rows(data)
          .map((r) => WishItem(id: r['id'] as String, drink: r['drink_name'] as String, createdAt: r['created_at'] as String, done: r['fulfilled'] == true))
          .toList());
    } catch (e) {
      logDebug(e);
    }
  }

  Future<void> _applyAuth() async {
    final a = auth;
    if (a.status == AuthStatus.loading) return;
    final c = db;
    if (a.isAuthed && c != null && a.meId != 'local') {
      if (_remote && _user == a.meId) return;
      _user = a.meId;
      _remote = true;
      final local = _readLocal();
      if (local.isNotEmpty) {
        try {
          await c.from('wishlist_items').insert(local.map((w) => _toRow(w, _user!)).toList());
          await Prefs.setJson(_key, const []);
        } catch (e) {
          logDebug(e);
        }
      }
      await _loadRemote();
    } else {
      _remote = false;
      _user = null;
      _set(_readLocal());
    }
  }

  void wire() {
    if (_wired) return;
    _wired = true;
    _set(_readLocal());
    _applyAuth();
    auth.addListener(_applyAuth);
  }

  void add(String drink) {
    final d = drink.trim();
    if (d.isEmpty) return;
    if (_cache.any((w) => !w.done && w.drink.toLowerCase() == d.toLowerCase())) return;
    final item = WishItem(id: newId(), drink: d, createdAt: DateTime.now().toUtc().toIso8601String());
    _set([item, ..._cache]);
    final c = db;
    if (_remote && _user != null && c != null) {
      c.from('wishlist_items').insert(_toRow(item, _user!)).catchError((_) {
        _set(_cache.where((w) => w.id != item.id).toList());
        return null;
      });
    } else {
      _writeLocal();
    }
  }

  Future<void> remove(String id) async {
    final prev = _cache;
    _set(_cache.where((w) => w.id != id).toList());
    final c = db;
    if (_remote && _user != null && c != null) {
      try {
        await c.from('wishlist_items').delete().eq('id', id).eq('user_id', _user!);
      } catch (_) {
        _set(prev);
      }
    } else {
      _writeLocal();
    }
  }

  void toggle(String id) {
    final target = _cache.where((w) => w.id == id).firstOrNull;
    if (target == null) return;
    final done = !target.done;
    _set(_cache.map((w) => w.id == id ? w.withDone(done) : w).toList());
    final c = db;
    if (_remote && _user != null && c != null) {
      c.from('wishlist_items').update({'fulfilled': done}).eq('id', id).catchError((_) => null);
    } else {
      _writeLocal();
    }
  }
}

WishlistStore get wishlist => WishlistStore.instance;
