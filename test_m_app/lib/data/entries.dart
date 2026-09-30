// Entry store — a port of src/lib/store.ts. Two modes, one API:
//   • logged OUT → local mode: entries live on the device (the onboarding diary).
//   • logged IN  → remote mode: entries live in Supabase, scoped to the user.
// On sign-in, local entries are migrated up. Writes are OPTIMISTIC: the cache updates
// immediately (snappy darken), the DB write runs in the background and rolls back
// on failure. Everything visual stays DERIVED from these rows.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/seed.dart';
import 'package:brewdiary_core/types.dart';
import 'auth.dart';
import 'base.dart';

const _localKey = 'brewdiary.entries.v1';
const _entryCols = 'id, date, drink, type, mood, note, venue, who_with, visibility, created_at, entry_photos(id, url, sort_order)';

class EntryStore extends ChangeNotifier {
  EntryStore._();
  static final instance = EntryStore._();

  List<Entry> _cache = const [];
  bool _remote = false;
  String? _user;
  bool _wired = false;

  List<Entry> get entries => _cache;

  void _setCache(List<Entry> next) {
    _cache = List.unmodifiable(next);
    notifyListeners();
  }

  // ── local persistence ─────────────────────────────────────────────────────
  List<Entry> _readLocal() {
    final raw = Prefs.getJson<List<dynamic>>(_localKey);
    if (raw == null) return const [];
    return raw.map(Entry.tryParse).whereType<Entry>().toList();
  }

  Future<void> _writeLocal(List<Entry> list) => Prefs.setJson(_localKey, list.map((e) => e.toJson()).toList());

  // ── DB mapping ────────────────────────────────────────────────────────────
  String _publicUrl(String path) => db!.storage.from('photos').getPublicUrl(path);

  Entry _rowToEntry(Map<String, dynamic> r) {
    final photoRows = rows(r['entry_photos'])..sort((a, b) => asInt(a['sort_order']).compareTo(asInt(b['sort_order'])));
    final photos = photoRows.map((p) => Photo(id: p['id'] as String, url: _publicUrl(p['url'] as String))).toList();
    return Entry(
      id: r['id'] as String,
      date: r['date'] as String,
      createdAt: r['created_at'] as String,
      drink: r['drink'] as String,
      type: DrinkType.parse(r['type'] as String?),
      mood: r['mood'] as String?,
      note: r['note'] as String?,
      venue: r['venue'] as String?,
      whoWith: (r['who_with'] as List?)?.cast<String>(),
      visibility: r['visibility'] == 'friends' ? EntryVisibility.friends : EntryVisibility.private,
      photos: photos.isEmpty ? null : photos,
    );
  }

  Map<String, dynamic> _entryToRow(Entry e, String userId) => {
        'id': e.id,
        'user_id': userId,
        'date': e.date,
        'drink': e.drink,
        'type': e.type?.name,
        'mood': e.mood,
        'note': e.note,
        'venue': e.venue,
        'who_with': e.whoWith,
        'visibility': e.visibility.name,
      };

  // ── photo storage ─────────────────────────────────────────────────────────
  /// Upload any on-device photos to the bucket + insert entry_photos rows.
  Future<List<Photo>?> _syncPhotos(String entryId, List<Photo>? photos, String userId) async {
    final c = db;
    if (c == null || photos == null || photos.isEmpty) return photos;
    final out = <Photo>[];
    var order = 0;
    for (final p in photos) {
      if (p.isLocal) {
        try {
          final bytes = await File(p.url).readAsBytes();
          final path = '$userId/$entryId/${p.id}';
          await c.storage.from('photos').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
          await c.from('entry_photos').insert({'id': p.id, 'entry_id': entryId, 'user_id': userId, 'url': path, 'sort_order': order});
          out.add(Photo(id: p.id, url: _publicUrl(path)));
        } catch (e) {
          logDebug(e);
        }
      } else {
        out.add(p);
      }
      order++;
    }
    return out;
  }

  Future<void> _reconcilePhotos(String entryId, List<Photo> photos, String userId) async {
    final c = db;
    if (c == null) return;
    final keep = photos.map((p) => p.id).toSet();
    final existing = rows(await c.from('entry_photos').select('id, url').eq('entry_id', entryId));
    for (final row in existing) {
      if (!keep.contains(row['id'])) {
        await c.storage.from('photos').remove([row['url'] as String]);
        await c.from('entry_photos').delete().eq('id', row['id'] as String);
      }
    }
    await _syncPhotos(entryId, photos.where((p) => p.isLocal).toList(), userId);
  }

  // ── remote ops ────────────────────────────────────────────────────────────
  Future<void> reload() async {
    final c = db;
    if (c == null || !_remote) return;
    try {
      final data = await c.from('entries').select(_entryCols).order('date', ascending: true);
      _setCache(rows(data).map(_rowToEntry).toList());
    } catch (e) {
      logDebug(e);
    }
  }

  /// True only if the rows actually landed — the local diary is never cleared otherwise.
  Future<bool> _migrateLocalToRemote(List<Entry> local, String userId) async {
    final c = db;
    if (c == null || local.isEmpty) return true;
    try {
      await c.from('entries').insert(local.map((e) => _entryToRow(e, userId)).toList());
    } catch (_) {
      return false;
    }
    for (final e in local) {
      await _syncPhotos(e.id, e.photos, userId);
    }
    return true;
  }

  Future<void> _applyAuth() async {
    final a = auth;
    if (a.status == AuthStatus.loading) return;
    if (a.isAuthed && db != null && a.meId != 'local') {
      if (_remote && _user == a.meId) return;
      _user = a.meId;
      _remote = true;
      final local = _readLocal();
      if (local.isNotEmpty && await _migrateLocalToRemote(local, _user!)) await _writeLocal(const []);
      await reload();
    } else {
      _remote = false;
      _user = null;
      _setCache(_readLocal());
    }
  }

  void wire() {
    if (_wired) return;
    _wired = true;
    _setCache(_readLocal());
    _applyAuth();
    auth.addListener(_applyAuth);
  }

  // ── public API (mirrors the web store) ────────────────────────────────────
  Entry addEntry({
    required String date,
    required String drink,
    String? mood,
    String? note,
    DrinkType? type,
    String? venue,
    List<String>? whoWith,
    List<Photo>? photos,
  }) {
    final m = mood?.trim();
    final entry = Entry(
      id: newId(),
      createdAt: appNow().toUtc().toIso8601String(),
      date: date,
      drink: drink.trim(),
      mood: (m == null || m.isEmpty) ? null : m,
      note: note,
      type: type,
      venue: venue,
      whoWith: whoWith,
      photos: photos,
    );
    _setCache([..._cache, entry]);

    final c = db;
    if (_remote && _user != null && c != null) {
      final userId = _user!;
      () async {
        try {
          await c.from('entries').insert(_entryToRow(entry, userId));
        } catch (e) {
          logDebug(e);
          _setCache(_cache.where((x) => x.id != entry.id).toList());
          return;
        }
        // A spark for VARIETY (a new drink) or a DRY DAY — fired only once the row is
        // really in the database; the server checks the diary before it pays.
        c.rpc('award_diary', params: {
          'kind': entry.type == DrinkType.none ? 'dry-day' : 'new-drink',
          'key': entry.type == DrinkType.none ? entry.date : entry.drink,
        }).catchError((_) => null);
        final synced = await _syncPhotos(entry.id, entry.photos, userId);
        if (!identical(synced, entry.photos)) {
          _setCache(_cache.map((x) => x.id == entry.id ? x.copyWith(photos: () => synced) : x).toList());
        }
      }();
    } else {
      _writeLocal(_cache);
    }
    return entry;
  }

  /// Patch an entry. Only the fields you pass change (nullable setters use closures
  /// so "clear this field" and "leave it alone" are distinguishable).
  void updateEntry(Entry updated, {bool photosChanged = false}) {
    _setCache(_cache.map((e) => e.id == updated.id ? updated : e).toList());
    final c = db;
    if (_remote && _user != null && c != null) {
      final userId = _user!;
      () async {
        try {
          await c.from('entries').update({
            'date': updated.date,
            'drink': updated.drink,
            'type': updated.type?.name,
            'mood': updated.mood,
            'note': updated.note,
            'venue': updated.venue,
            'who_with': updated.whoWith,
            'visibility': updated.visibility.name,
          }).eq('id', updated.id);
          if (photosChanged) {
            await _reconcilePhotos(updated.id, updated.photos ?? const [], userId);
            await reload();
          }
        } catch (e) {
          logDebug(e);
        }
      }();
    } else {
      _writeLocal(_cache);
    }
  }

  void setVisibility(String id, EntryVisibility v) {
    final e = _cache.where((x) => x.id == id).firstOrNull;
    if (e != null) updateEntry(e.copyWith(visibility: v));
  }

  void deleteEntry(String id) {
    _setCache(_cache.where((e) => e.id != id).toList());
    final c = db;
    if (_remote && _user != null && c != null) {
      c.from('entries').delete().eq('id', id).catchError((_) => null);
    } else {
      _writeLocal(_cache);
    }
  }

  void resetAll() {
    final c = db;
    final userId = _user;
    _setCache(const []);
    if (_remote && userId != null && c != null) {
      c.from('entries').delete().eq('user_id', userId).catchError((_) => null);
    } else {
      _writeLocal(const []);
    }
  }

  /// Wipe and re-seed the demo history.
  void reseed() => replaceAll(seedEntries());

  /// Replace the whole diary (used by import). Malformed rows are dropped upstream.
  void replaceAll(List<Entry> clean) {
    final c = db;
    final userId = _user;
    _setCache(clean);
    if (_remote && userId != null && c != null) {
      () async {
        try {
          await c.from('entries').delete().eq('user_id', userId);
          if (clean.isNotEmpty) await c.from('entries').insert(clean.map((e) => _entryToRow(e, userId)).toList());
        } catch (e) {
          logDebug(e);
        }
      }();
    } else {
      _writeLocal(clean);
    }
  }
}

EntryStore get entryStore => EntryStore.instance;
