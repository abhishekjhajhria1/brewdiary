// The real backend: the same Supabase project as the website and the guest app.
//
// The phone holds only the public anon key. What each person may read or write is
// decided by row-level security and the server functions (venue_can, record_spend,
// redeem_perk, …) — this file never decides anything the database doesn't. Inserts use
// client-generated ids and no `.select()` (the RLS / RETURNING gotcha), then read back.
import 'dart:async';
import 'dart:convert';

import 'package:brewdiary_core/handles.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../logic/area.dart' show HeatRow;
import '../logic/roles.dart';
import '../logic/venue_kinds.dart';
import 'backend.dart';
import 'models.dart';
import 'prefs.dart';

class SupabaseBackend implements Backend {
  SupabaseBackend() {
    _authSub = _c.auth.onAuthStateChange.listen((s) async {
      final u = s.session?.user;
      if (u == null) {
        _user = null;
        _auth.add(null);
        return;
      }
      try {
        _user = await _ensureProfile(u);
        _auth.add(_user);
      } catch (_) {
        // A profile read failing mustn't strand the session; the next call retries.
      }
    });
  }

  SupabaseClient get _c => Supabase.instance.client;
  // ignore: unused_field
  late final StreamSubscription<AuthState> _authSub;
  final _auth = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  @override
  bool get isDemo => false;

  String get _me {
    final id = _c.auth.currentUser?.id;
    if (id == null) throw const BackendError('Sign in first.');
    return id;
  }

  /// Run a call and turn whatever went wrong into one plain sentence.
  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on BackendError {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const BackendError('That already exists.');
      if (e.code == '42501' || e.message.contains('row-level security')) {
        throw const BackendError('Your role here can\'t do that.');
      }
      throw BackendError(_sentence(e.message));
    } on AuthException catch (e) {
      throw BackendError(_sentence(e.message));
    } catch (_) {
      throw const BackendError('Couldn\'t reach brewdiary — check your connection and try again.');
    }
  }

  static String _sentence(String m) {
    final t = m.trim();
    if (t.isEmpty) return 'Something went wrong — try again.';
    final s = t[0].toUpperCase() + t.substring(1);
    return s.endsWith('.') ? s : '$s.';
  }

  // ── auth ──────────────────────────────────────────────────────────────────
  @override
  AppUser? get currentUser {
    final u = _c.auth.currentUser;
    if (u == null) return null;
    return _user?.id == u.id ? _user : AppUser(id: u.id, email: u.email, name: (u.userMetadata?['name'] as String?) ?? 'you', handle: '');
  }

  @override
  Stream<AppUser?> get authChanges => _auth.stream;

  /// Read the profile row, creating it on first sight (the same loop as the guest app:
  /// `handle` is UNIQUE, so a clash means try another word).
  Future<AppUser> _ensureProfile(User user) async {
    const cols = 'id, display_name, handle';
    final existing = await _c.from('profiles').select(cols).eq('id', user.id).maybeSingle();
    if (existing != null) {
      return AppUser(id: user.id, email: user.email, name: (existing['display_name'] as String?) ?? 'you', handle: (existing['handle'] as String?) ?? '');
    }
    final name = ((user.userMetadata?['name'] as String?) ?? user.email?.split('@').first ?? 'you').trim();
    for (var attempt = 0; attempt < handleTries; attempt++) {
      final handle = coolHandle(name, attempt: attempt);
      try {
        await _c.from('profiles').insert({'id': user.id, 'handle': handle, 'display_name': name});
        return AppUser(id: user.id, email: user.email, name: name, handle: handle);
      } catch (_) {
        final mine = await _c.from('profiles').select(cols).eq('id', user.id).maybeSingle();
        if (mine != null) {
          return AppUser(id: user.id, email: user.email, name: (mine['display_name'] as String?) ?? name, handle: (mine['handle'] as String?) ?? '');
        }
      }
    }
    throw const BackendError('Couldn\'t set up your profile — try again.');
  }

  @override
  Future<void> signInWithPassword(String email, String password) => _run(() async {
        final r = await _c.auth.signInWithPassword(email: email.trim(), password: password);
        if (r.user != null) _user = await _ensureProfile(r.user!);
      });

  @override
  Future<void> sendEmailCode(String email, {bool create = false, String? name}) => _run(() => _c.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: create,
        data: create && (name?.trim().isNotEmpty ?? false) ? {'name': name!.trim()} : null,
      ));

  @override
  Future<void> verifyEmailCode(String email, String code) => _run(() async {
        try {
          final r = await _c.auth.verifyOTP(type: OtpType.email, email: email.trim(), token: code.trim());
          if (r.user != null) _user = await _ensureProfile(r.user!);
        } on AuthException {
          throw const BackendError('That code didn\'t work — check it and try again.');
        }
      });

  @override
  Future<void> signOut() => _run(() async {
        await _c.auth.signOut();
        _user = null;
      });

  // ── venues ────────────────────────────────────────────────────────────────
  @override
  Future<List<Venue>> myVenues() => _run(() async {
        final rows = await _c.from('venue_staff').select('role, venue:venues(*)').eq('user_id', _me);
        final out = <Venue>[];
        for (final r in rows) {
          final v = r['venue'];
          if (v is Map<String, dynamic>) {
            // The creator is the owner whatever the staff row says (venue_role(), 045).
            final role = v['created_by'] == _me ? StaffRole.owner : StaffRole.parse(r['role'] as String?);
            out.add(Venue.fromRow(v, role));
          }
        }
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return out;
      });

  @override
  Future<Venue> createVenue({
    required String name,
    required String slug,
    String? city,
    required VenueKind kind,
    bool servesAlcohol = false,
    required String country,
    String? region,
  }) =>
      _run(() async {
        final id = newId();
        final me = _me;
        try {
          await _c.from('venues').insert({
            'id': id,
            'name': name.trim(),
            'slug': slug,
            'created_by': me,
            'city': (city?.trim().isEmpty ?? true) ? null : city!.trim(),
            'kind': kind.db,
            'serves_alcohol': sellsAlcohol(kind, servesAlcohol: servesAlcohol),
            'country': country.toUpperCase(),
            'region': (region?.trim().isEmpty ?? true) ? null : region!.trim().toUpperCase(),
          });
        } on PostgrestException catch (e) {
          if (e.code == '23505') throw const BackendError('That web address is taken — try another.');
          rethrow;
        }
        await _c.from('venue_staff').insert({'venue_id': id, 'user_id': me, 'role': 'owner'});
        venueRev.bump();
        final v = await _c.from('venues').select().eq('id', id).single();
        return Venue.fromRow(v, StaffRole.owner);
      });

  @override
  Future<void> updateVenue(String venueId, {String? name, String? city, List<int>? quietNights, String? geohash, bool? servesAlcohol, bool? areaShare}) => _run(() async {
        final patch = <String, dynamic>{};
        if (name != null) {
          if (name.trim().isEmpty) throw const BackendError('Name can\'t be empty.');
          patch['name'] = name.trim();
        }
        if (city != null) patch['city'] = city.trim().isEmpty ? null : city.trim();
        if (quietNights != null) patch['quiet_nights'] = (quietNights.toSet().where((d) => d >= 0 && d <= 6).toList()..sort());
        if (geohash != null) patch['geohash'] = geohash.isEmpty ? null : geohash.substring(0, geohash.length.clamp(0, 12));
        if (servesAlcohol != null) patch['serves_alcohol'] = servesAlcohol;
        if (areaShare != null) patch['area_share'] = areaShare;
        if (patch.isEmpty) return;
        await _c.from('venues').update(patch).eq('id', venueId);
        venueRev.bump();
      });

  @override
  Future<void> deleteVenue(String venueId) => _run(() async {
        await _c.from('venues').delete().eq('id', venueId);
        venueRev.bump();
      });

  @override
  Future<VerificationRequest?> verification(String venueId) => _run(() async {
        final r = await _c.from('venue_verifications').select('status, contact, note, created_at').eq('venue_id', venueId).maybeSingle();
        if (r == null) return null;
        return VerificationRequest(
          status: VerificationStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => VerificationStatus.pending),
          contact: (r['contact'] as String?) ?? '',
          note: r['note'] as String?,
          createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
        );
      });

  @override
  Future<void> requestVerification(String venueId, String contact, {String? note}) => _run(() async {
        if (contact.trim().length < 3) throw const BackendError('Add a phone or email we can reach you on.');
        await _c.from('venue_verifications').insert({
          'venue_id': venueId,
          'requested_by': _me,
          'contact': contact.trim(),
          'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
        });
        venueRev.bump();
      });

  @override
  Future<void> withdrawVerification(String venueId) => _run(() async {
        await _c.from('venue_verifications').delete().eq('venue_id', venueId);
        venueRev.bump();
      });

  // ── team ──────────────────────────────────────────────────────────────────
  @override
  Future<List<StaffMember>> staff(String venueId) => _run(() async {
        final rows = await _c.from('venue_staff').select('role, thankable, member:profiles(id, handle, display_name)').eq('venue_id', venueId);
        final list = [
          for (final r in rows)
            if (r['member'] is Map)
              StaffMember(
                id: r['member']['id'] as String,
                handle: (r['member']['handle'] as String?) ?? '',
                name: (r['member']['display_name'] as String?) ?? (r['member']['handle'] as String?) ?? 'someone',
                role: StaffRole.parse(r['role'] as String?),
                thankable: r['thankable'] != false,
              ),
        ];
        list.sort((a, b) => a.role.rank != b.role.rank ? a.role.rank.compareTo(b.role.rank) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  @override
  Future<List<ProfileHit>> searchPeople(String query) => _run(() async {
        final q = query.trim().replaceFirst(RegExp(r'^@+'), '').replaceAll(RegExp(r'[%,()]'), '');
        if (q.length < 2) return const <ProfileHit>[];
        final rows = await _c.rpc('search_users', params: {'q': q});
        return [
          for (final r in (rows as List? ?? const []))
            ProfileHit(id: r['id'] as String, handle: (r['handle'] as String?) ?? '', name: (r['display_name'] as String?) ?? (r['handle'] as String?) ?? 'someone'),
        ];
      });

  @override
  Future<void> addStaff(String venueId, String userId, StaffRole role) => _run(() async {
        try {
          await _c.from('venue_staff').insert({'venue_id': venueId, 'user_id': userId, 'role': role.db});
        } on PostgrestException catch (e) {
          if (e.code == '23505') return; // already on the team
          rethrow;
        }
        staffRev.bump();
      });

  @override
  Future<void> setStaffRole(String venueId, String userId, StaffRole role) => _run(() async {
        await _c.rpc('set_staff_role', params: {'vid': venueId, 'uid': userId, 'new_role': role.db});
        staffRev.bump();
      });

  @override
  Future<void> removeStaff(String venueId, String userId) => _run(() async {
        await _c.from('venue_staff').delete().eq('venue_id', venueId).eq('user_id', userId);
        staffRev.bump();
      });

  @override
  Future<void> setThankable(String venueId, bool thankable) => _run(() async {
        await _c.rpc('set_thankable', params: {'vid': venueId, 'on_off': thankable});
        staffRev.bump();
      });

  @override
  Future<StaffInvite> createInvite(String venueId, StaffRole role) => _run(() async {
        final code = await _c.rpc('create_staff_invite', params: {'vid': venueId, 'invite_role': role.db});
        return StaffInvite(code: '$code', role: role, expiresAt: DateTime.now().add(const Duration(days: 7)));
      });

  @override
  Future<String> acceptInvite(String code) => _run(() async {
        final name = await _c.rpc('accept_staff_invite', params: {'invite_code': code.trim().toLowerCase()});
        venueRev.bump();
        return '$name';
      });

  // ── tonight ───────────────────────────────────────────────────────────────
  @override
  Future<List<Room>> rooms(String venueId) => _run(() async {
        final rows = await _c.from('parties').select('id, name, date, invite_code, board_until').eq('venue_id', venueId).order('date', ascending: false).limit(20);
        return [
          for (final r in rows)
            Room(
              id: r['id'] as String,
              name: r['name'] as String,
              date: '${r['date']}',
              inviteCode: r['invite_code'] as String,
              boardUntil: r['board_until'] == null ? null : DateTime.tryParse('${r['board_until']}'),
            ),
        ];
      });

  @override
  Future<Room> openRoom(Venue venue, {int boardHours = 6}) => _run(() async {
        if (venue.kind.isCounter) throw const BackendError('A counter doesn\'t run rooms — it punches cards at the till.');
        final id = newId();
        final now = DateTime.now();
        final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final until = now.add(Duration(hours: boardHours)).toUtc().toIso8601String();
        await _c.from('parties').insert({'id': id, 'name': '${venue.name} · tonight', 'host_id': _me, 'date': day, 'venue_id': venue.id, 'board_until': until});
        // The host joins their own room, exactly as parties.ts createParty() does.
        await _c.from('party_members').insert({'party_id': id, 'user_id': _me});
        roomsRev.bump();
        final r = await _c.from('parties').select('id, name, date, invite_code, board_until').eq('id', id).single();
        return Room(id: id, name: r['name'] as String, date: '${r['date']}', inviteCode: r['invite_code'] as String, boardUntil: DateTime.tryParse('${r['board_until']}'));
      });

  @override
  Future<List<RoomGuest>> roomGuests(String roomId) => _run(() async {
        final rows = await _c.rpc('room_guests', params: {'pid': roomId});
        return [for (final r in (rows as List? ?? const [])) RoomGuest(id: r['id'] as String, name: (r['name'] as String?) ?? 'guest')];
      });

  @override
  Future<void> giveVibe(String roomId, String guestId, String reason) => _run(() async {
        final ok = await _c.rpc('staff_award', params: {'pid': roomId, 'uid': guestId, 'reason': reason});
        if (ok == false) throw const BackendError('You\'ve already said that tonight.');
      });

  @override
  Future<void> recordSpend(String roomId, String guestId, double amount) => _run(() async {
        await _c.rpc('record_spend', params: {'pid': roomId, 'uid': guestId, 'amt': amount});
        guestsRev.bump();
      });

  @override
  Future<List<PerkStanding>> perkStatus(String venueId, String guestId) => _run(() async {
        final rows = await _c.rpc('perk_status', params: {'vid': venueId, 'uid': guestId});
        return [for (final r in (rows as List? ?? const [])) PerkStanding.fromRow(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<void> redeemPerk(String perkId, String guestId) => _run(() async {
        await _c.rpc('redeem_perk', params: {'pk': perkId, 'uid': guestId});
        guestsRev.bump();
      });

  @override
  Future<void> recordVisit(String venueId, String guestId) => _run(() async {
        await _c.rpc('record_visit', params: {'vid': venueId, 'uid': guestId});
        guestsRev.bump();
      });

  // ── menu ──────────────────────────────────────────────────────────────────
  @override
  Future<List<MenuItem>> menu(String venueId) => _run(() async {
        final rows = await _c.from('venue_menu_items').select().eq('venue_id', venueId).order('position');
        return [for (final r in rows) MenuItem.fromRow(r)];
      });

  @override
  Future<void> saveMenuItem(String venueId, MenuItem item, {bool isNew = false}) => _run(() async {
        final row = {
          'section': item.section.trim().isEmpty ? 'Menu' : item.section.trim(),
          'name': item.name.trim(),
          'description': (item.description?.trim().isEmpty ?? true) ? null : item.description!.trim(),
          'price': item.price,
          'kind': item.kind,
          'no_alcohol': item.noAlcohol,
          'available': item.available,
          'position': item.position,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        if (isNew) {
          await _c.from('venue_menu_items').insert({'id': item.id, 'venue_id': venueId, ...row});
        } else {
          await _c.from('venue_menu_items').update(row).eq('id', item.id);
        }
        menuRev.bump();
      });

  @override
  Future<void> removeMenuItem(String itemId) => _run(() async {
        await _c.from('venue_menu_items').delete().eq('id', itemId);
        menuRev.bump();
      });

  // ── perks ─────────────────────────────────────────────────────────────────
  @override
  Future<List<PerkTier>> perks(String venueId) => _run(() async {
        final rows = await _c.from('venue_perks').select('id, kind, threshold, reward, currency, reward_alcoholic').eq('venue_id', venueId).order('threshold');
        return [for (final r in rows) PerkTier.fromRow(r)];
      });

  @override
  Future<void> addPerk(String venueId, {required PerkKind kind, required double threshold, required String reward, bool rewardAlcoholic = false}) => _run(() async {
        await _c.from('venue_perks').insert({
          'id': newId(),
          'venue_id': venueId,
          'kind': kind.name,
          'threshold': threshold,
          'reward': reward.trim(),
          'reward_alcoholic': rewardAlcoholic,
        });
        perksRev.bump();
      });

  @override
  Future<void> removePerk(String perkId) => _run(() async {
        await _c.from('venue_perks').delete().eq('id', perkId);
        perksRev.bump();
      });

  // ── insights & the area ───────────────────────────────────────────────────
  @override
  Future<VenueInsights?> insights(String venueId, {int days = 30}) => _run(() async {
        final r = await _c.rpc('venue_insights', params: {'vid': venueId, 'days': days});
        final row = r is List ? (r.isEmpty ? null : r.first) : r;
        return row == null ? null : VenueInsights.fromRow(Map<String, dynamic>.from(row as Map));
      });

  @override
  Future<List<AreaTrend>> areaTrends(String geohash, {int days = 30}) => _run(() async {
        final rows = await _c.rpc('area_taste_trends', params: {'in_geo': geohash, 'days_back': days});
        return [
          for (final r in (rows as List? ?? const []))
            AreaTrend(kind: (r['kind'] as String?) ?? 'drink', name: (r['name'] as String?) ?? '', users: (r['users'] as num?)?.toInt() ?? 0),
        ];
      });

  @override
  Future<List<HeatRow>> areaMap(String venueId, {int days = 30, String tz = 'UTC'}) => _run(() async {
        final rows = await _c.rpc('area_heat_map', params: {'vid': venueId, 'days_back': days, 'tz': tz});
        return [
          for (final r in (rows as List? ?? const []))
            HeatRow(r['cell'] as String, r['layer'] as String, (r['label'] as String?) ?? '', (r['people'] as num).toInt()),
        ];
      });

  @override
  Future<List<AreaSignal>> areaSignals(String venueId, {int daysAhead = 14}) => _run(() async {
        final rows = await _c.rpc('venue_area_signals', params: {'vid': venueId, 'days_ahead': daysAhead});
        return [for (final r in (rows as List? ?? const [])) AreaSignal.fromRow(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<int> teamKudos(String venueId, {int days = 30}) => _run(() async {
        final n = await _c.rpc('venue_kudos_total', params: {'vid': venueId, 'since_days': days});
        return (n as num?)?.toInt() ?? 0;
      });

  @override
  Future<List<KudosLine>> myKudos(String venueId) => _run(() async {
        final rows = await _c.rpc('my_kudos', params: {'vid': venueId});
        return [for (final r in (rows as List? ?? const [])) KudosLine((r['reason'] as String?) ?? '', (r['n'] as num?)?.toInt() ?? 0)];
      });

  // ── guest book ────────────────────────────────────────────────────────────
  @override
  Future<GuestCard?> guestCard(String venueId, String guestId) => _run(() async {
        final r = await _c.rpc('venue_guest_card', params: {'vid': venueId, 'uid': guestId});
        final row = r is List ? (r.isEmpty ? null : r.first) : r;
        return row == null ? null : GuestCard.fromRow(Map<String, dynamic>.from(row as Map));
      });

  @override
  Future<void> setGuestNote(String venueId, String guestId, String body, List<String> tags) => _run(() async {
        final clean = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).map((t) => t.length > 24 ? t.substring(0, 24) : t).take(12).toList();
        await _c.rpc('set_guest_note', params: {'vid': venueId, 'uid': guestId, 'in_body': body.length > 2000 ? body.substring(0, 2000) : body, 'in_tags': clean});
        guestsRev.bump();
      });

  // ── Ninkasi for hosts ─────────────────────────────────────────────────────
  @override
  Stream<String> advise(Map<String, dynamic> brief, List<Map<String, String>> messages) async* {
    final req = http.Request('POST', Config.api('/api/venue-ai'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'brief': brief, 'messages': messages});
    final token = _c.auth.currentSession?.accessToken;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    http.StreamedResponse res;
    try {
      res = await http.Client().send(req).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const BackendError('Ninkasi is out of reach — check your connection.');
    }
    if (res.statusCode == 429) throw const BackendError('Give her a moment with the last set of books, then ask again.');
    if (res.statusCode >= 400) throw const BackendError('Ninkasi couldn\'t read that — try again.');
    yield* res.stream.transform(utf8.decoder);
  }
}
