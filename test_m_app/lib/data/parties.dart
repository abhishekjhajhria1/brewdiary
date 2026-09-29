// Parties + the venue "room" layer a guest sees — ports of src/lib/parties.ts,
// points.ts (guest side), perks.ts (perk_status), kudos.ts (thank staff).
//
// A party_shares row exposes one entry to one party; the recap is derived from
// whatever guests shared in. Sparks/vibe are positive-only and server-authoritative.
import '../core/money.dart';
import 'auth.dart';
import 'base.dart';
import 'circles.dart' show SharedEntry;

enum Rsvp { going, maybe, no }

const rsvpLabel = {Rsvp.going: 'Going', Rsvp.maybe: 'Maybe', Rsvp.no: "Can't"};

class Party {
  final String id;
  final String name;
  final String hostId;
  final String? venue;

  /// Set when a venue opened this as a "room" (→ house perks, thank-the-bar, screen).
  final String? venueId;
  final String date;
  final String inviteCode;
  final int going;
  const Party({required this.id, required this.name, required this.hostId, this.venue, this.venueId, required this.date, required this.inviteCode, required this.going});
}

class PartyGuest {
  final String id;
  final String handle;
  final String name;
  final Rsvp rsvp;
  final bool pending;
  const PartyGuest({required this.id, required this.handle, required this.name, required this.rsvp, required this.pending});
}

class PartyDetail {
  final Party? party;
  final List<PartyGuest> guests;
  final List<SharedEntry> entries;
  const PartyDetail(this.party, this.guests, this.entries);
}

class PartyPreview {
  final String name;
  final String date;
  final String? venue;
  final String hostName;
  final int going;
  const PartyPreview(this.name, this.date, this.venue, this.hostName, this.going);
}

class PointRow {
  final String userId;
  final String name;
  final int sparks;
  final int vibe;
  const PointRow(this.userId, this.name, this.sparks, this.vibe);
}

class PerkTier {
  final String id;
  final bool isSpend;
  final double threshold;
  final String reward;
  final String currency;
  final double progress;
  final bool earned;
  final int claims;
  const PerkTier({required this.id, required this.isSpend, required this.threshold, required this.reward, required this.currency, required this.progress, required this.earned, required this.claims});
}

const vibeReasons = ['good sport', 'great vibe', 'kept it classy', 'MVP'];

/// Fixed and positive-only. A guest cannot write free text about a worker.
const kudosReasons = ['looked after us', 'great recommendation', 'made the night', 'quick and kind'];

Rsvp _rsvp(Object? s) => Rsvp.values.firstWhere((r) => r.name == s, orElse: () => Rsvp.going);

class PartiesApi {
  static Future<List<Party>> mine() async {
    final c = db;
    if (c == null || auth.meId == null) return [];
    final data = await c.from('parties').select('id, name, host_id, venue, date, invite_code, party_members(user_id, rsvp, status)').order('date', ascending: false);
    return rows(data)
        .map((r) => Party(
              id: r['id'] as String,
              name: r['name'] as String,
              hostId: r['host_id'] as String,
              venue: r['venue'] as String?,
              date: r['date'] as String,
              inviteCode: r['invite_code'] as String,
              going: rows(r['party_members']).where((m) => m['rsvp'] == 'going' && m['status'] == 'approved').length,
            ))
        .toList();
  }

  static Future<PartyDetail> detail(String partyId) async {
    final c = db;
    if (c == null || auth.meId == null) return const PartyDetail(null, [], []);
    final results = await Future.wait<dynamic>([
      c.from('parties').select('id, name, host_id, venue, venue_id, date, invite_code').eq('id', partyId).maybeSingle(),
      c.from('party_members').select('user_id, rsvp, status, member:profiles(id, handle, display_name)').eq('party_id', partyId),
      c
          .from('party_shares')
          .select('entry_id, entry:entries(id, user_id, date, drink, mood, note, venue, created_at, author:profiles(display_name, handle), entry_photos(id, url, sort_order))')
          .eq('party_id', partyId),
    ]);
    final guests = rows(results[1]).map((r) {
      final p = Map<String, dynamic>.from(r['member'] as Map);
      final handle = p['handle'] as String? ?? '';
      return PartyGuest(
        id: p['id'] as String,
        handle: handle,
        name: (p['display_name'] as String?) ?? handle,
        rsvp: _rsvp(r['rsvp']),
        pending: r['status'] == 'pending',
      );
    }).toList();
    final p = results[0] as Map<String, dynamic>?;
    final party = p == null
        ? null
        : Party(
            id: p['id'] as String,
            name: p['name'] as String,
            hostId: p['host_id'] as String,
            venue: p['venue'] as String?,
            venueId: p['venue_id'] as String?,
            date: p['date'] as String,
            inviteCode: p['invite_code'] as String,
            going: guests.where((g) => g.rsvp == Rsvp.going && !g.pending).length,
          );
    final entries = rows(results[2]).map((r) => SharedEntry.fromJoin(r['entry'], 'guest')).whereType<SharedEntry>().toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return PartyDetail(party, guests, entries);
  }

  static Future<Set<String>> sharesForEntry(String entryId) async {
    final c = db;
    if (c == null) return {};
    final data = await c.from('party_shares').select('party_id').eq('entry_id', entryId);
    return rows(data).map((r) => r['party_id'] as String).toSet();
  }

  /// Works signed OUT (anon-callable rpc) — powers invite previews.
  static Future<PartyPreview?> preview(String code) async {
    final c = db;
    if (c == null) return null;
    final r = firstRow(await c.rpc('party_preview', params: {'code': code.trim()}));
    if (r == null) return null;
    return PartyPreview(r['name'] as String, r['date'] as String, r['venue'] as String?, (r['host_name'] as String?) ?? 'someone', asInt(r['going']));
  }

  static Future<({String? id, String? error})> create({required String name, required String date, String? venue}) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return (id: null, error: 'offline');
    final n = name.trim();
    if (n.isEmpty) return (id: null, error: 'name required');
    final id = newId();
    try {
      await c.from('parties').insert({'id': id, 'name': n, 'host_id': me, 'date': date, 'venue': (venue?.trim().isEmpty ?? true) ? null : venue!.trim()});
      await c.from('party_members').insert({'party_id': id, 'user_id': me});
      return (id: id, error: null);
    } catch (e) {
      return (id: null, error: '$e');
    } finally {
      partiesRev.bump();
    }
  }

  static Future<({String? id, String? name, bool pending, String? error})> join(String code) async {
    final c = db;
    if (c == null) return (id: null, name: null, pending: false, error: 'offline');
    try {
      final r = firstRow(await c.rpc('join_party', params: {'code': code.trim()}));
      if (r == null) return (id: null, name: null, pending: false, error: 'No party with that code.');
      return (id: r['id'] as String, name: r['name'] as String, pending: (r['status'] ?? 'pending') == 'pending', error: null);
    } catch (e) {
      return (id: null, name: null, pending: false, error: '$e'.contains('invalid code') ? 'No party with that code.' : '$e');
    } finally {
      partiesRev.bump();
    }
  }

  static Future<void> setRsvp(String partyId, Rsvp rsvp) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('party_members').update({'rsvp': rsvp.name}).eq('party_id', partyId).eq('user_id', me);
    partiesRev.bump();
  }

  static Future<void> approveGuest(String partyId, String userId) async {
    await db?.rpc('approve_party_member', params: {'pid': partyId, 'uid': userId});
    partiesRev.bump();
  }

  static Future<void> declineGuest(String partyId, String userId) async {
    await db?.from('party_members').delete().eq('party_id', partyId).eq('user_id', userId);
    partiesRev.bump();
  }

  static Future<void> leave(String partyId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('party_members').delete().eq('party_id', partyId).eq('user_id', me);
    partiesRev.bump();
  }

  static Future<void> delete(String partyId) async {
    await db?.from('parties').delete().eq('id', partyId);
    partiesRev.bump();
  }

  static Future<void> share(String entryId, String partyId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('party_shares').insert({'entry_id': entryId, 'party_id': partyId, 'user_id': me});
    partiesRev.bump();
  }

  static Future<void> unshare(String entryId, String partyId) async {
    await db?.from('party_shares').delete().eq('entry_id', entryId).eq('party_id', partyId);
    partiesRev.bump();
  }
}

List<PointRow> _pointRows(Object? data) => rows(data)
    .map((r) => PointRow(r['user_id'] as String, (r['display_name'] as String?) ?? 'guest', asInt(r['sparks']), asInt(r['vibe'])))
    .toList()
  ..sort((a, b) {
    var c = b.sparks.compareTo(a.sparks);
    if (c != 0) return c;
    c = b.vibe.compareTo(a.vibe);
    return c != 0 ? c : a.name.compareTo(b.name);
  });

class PointsApi {
  static Future<List<PointRow>> partyBoard(String partyId) async {
    final c = db;
    if (c == null) return [];
    return _pointRows(await c.rpc('party_points_board', params: {'pid': partyId}));
  }

  /// Friends who ALSO opted in — nobody is ranked in front of friends without asking.
  static Future<List<PointRow>> friendsBoard() async {
    final c = db;
    if (c == null) return [];
    return _pointRows(await c.rpc('friends_board'));
  }

  /// SERVER-AUTHORITATIVE check-in: award_checkin decides the reason.
  static Future<bool> checkIn(String partyId) async {
    final c = db;
    if (c == null) return false;
    try {
      final data = await c.rpc('award_checkin', params: {'pid': partyId});
      return data == true;
    } catch (_) {
      return false;
    } finally {
      pointsRev.bump();
    }
  }

  static Future<bool> hasCheckedIn(String partyId) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return false;
    final data = await c
        .from('point_events')
        .select('id')
        .eq('party_id', partyId)
        .eq('subject_user_id', me)
        .eq('currency', 'spark')
        .eq('reason', 'checkin')
        .limit(1);
    return rows(data).isNotEmpty;
  }

  /// Positive-only + one-per-reason are enforced in the DB; a repeat is a no-op.
  static Future<String?> giveVibe(String partyId, String subjectId, String reason) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    try {
      await c.from('point_events').insert({'party_id': partyId, 'subject_user_id': subjectId, 'awarder_id': me, 'currency': 'vibe', 'reason': reason, 'value': 1});
      return null;
    } catch (e) {
      return RegExp('duplicate|unique|23505', caseSensitive: false).hasMatch('$e') ? null : '$e';
    } finally {
      pointsRev.bump();
    }
  }

  static Future<bool> competeVisible() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return false;
    final r = await c.from('profiles').select('compete_visible').eq('id', me).maybeSingle();
    return r?['compete_visible'] == true;
  }

  static Future<void> setCompeteVisible(bool value) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('profiles').update({'compete_visible': value}).eq('id', me);
    pointsRev.bump();
    profileRev.bump();
  }

  static Future<({bool onBoard, bool showTab})> roomConsent(String partyId) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return (onBoard: false, showTab: false);
    final r = await c.from('room_consent').select('on_board, show_tab').eq('party_id', partyId).eq('user_id', me).maybeSingle();
    return (onBoard: r?['on_board'] == true, showTab: r?['show_tab'] == true);
  }

  /// A tab can never show for someone who isn't on the board.
  static Future<void> setRoomConsent(String partyId, {required bool onBoard, required bool showTab}) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('room_consent').upsert({'party_id': partyId, 'user_id': me, 'on_board': onBoard, 'show_tab': onBoard && showTab});
    pointsRev.bump();
  }

  static Future<List<PerkTier>> perkTiers(String venueId) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return [];
    final data = await c.rpc('perk_status', params: {'vid': venueId, 'uid': me});
    return rows(data)
        .map((r) => PerkTier(
              id: r['perk_id'] as String,
              isSpend: r['kind'] == 'spend',
              threshold: asDouble(r['threshold']),
              reward: r['reward'] as String,
              currency: (r['currency'] as String?) ?? defaultCurrency,
              progress: asDouble(r['progress']),
              earned: r['earned'] == true,
              claims: asInt(r['claims']),
            ))
        .toList();
  }

  /// 0 = Sun … 6 = Sat (JS convention, as stored).
  static Future<List<int>> quietNights(String venueId) async {
    final c = db;
    if (c == null) return [];
    final r = await c.from('venues').select('quiet_nights').eq('id', venueId).maybeSingle();
    return ((r?['quiet_nights'] as List?) ?? const []).map((e) => asInt(e)).toList();
  }

  static Future<List<({String id, String name})>> roomStaff(String partyId) async {
    final c = db;
    if (c == null) return [];
    return rows(await c.rpc('room_staff', params: {'pid': partyId})).map((r) => (id: r['id'] as String, name: (r['name'] as String?) ?? 'staff')).toList();
  }

  static Future<String?> thankStaff(String partyId, String staffId, String reason) async {
    final c = db;
    if (c == null) return 'offline';
    try {
      await c.rpc('thank_staff', params: {'pid': partyId, 'sid': staffId, 'why': reason});
      return null;
    } catch (e) {
      return RegExp('not taking thanks', caseSensitive: false).hasMatch('$e') ? "They've turned thanks off." : "Couldn't send that — try again.";
    }
  }
}
