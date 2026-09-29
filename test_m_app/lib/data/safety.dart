// Safety & trust — ports of src/lib/safety.ts, vouch.ts, verify.ts, moderation.ts
// (my own sanction only), publicProfile.ts, trends.ts, venues.ts (discover),
// dataRights.ts. Everything a person needs to stay in control of their account.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth.dart';
import 'base.dart';

enum ReportReason { harassment, unsafe, fake, spam, other }

const reportReasons = {
  ReportReason.harassment: 'Harassing or abusive',
  ReportReason.unsafe: 'Made me feel unsafe',
  ReportReason.fake: 'Fake or impersonating',
  ReportReason.spam: 'Spam or scam',
  ReportReason.other: 'Something else',
};

class BlockedPerson {
  final String id;
  final String handle;
  final String name;
  const BlockedPerson(this.id, this.handle, this.name);
}

class SafetyApi {
  static Future<List<BlockedPerson>> blocks() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return [];
    final data = await c.from('blocks').select('blocked:profiles!blocks_blocked_id_fkey(id, handle, display_name)').eq('blocker_id', me);
    return rows(data).map((r) => r['blocked']).whereType<Map>().map((p) {
      final handle = p['handle'] as String? ?? '';
      return BlockedPerson(p['id'] as String, handle, (p['display_name'] as String?) ?? handle);
    }).toList();
  }

  /// Also withdraws/declines any live join between you (server-side).
  static Future<String?> block(String otherId) async {
    try {
      await db?.rpc('block_user', params: {'other': otherId});
      return null;
    } catch (_) {
      return "Couldn't block — try again.";
    } finally {
      safetyRev.bump();
      friendsRev.bump();
    }
  }

  static Future<void> unblock(String otherId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('blocks').delete().eq('blocker_id', me).eq('blocked_id', otherId);
    safetyRev.bump();
  }

  /// Write-only; reporting the same person twice is a silent no-op (dedup is never revealed).
  static Future<String?> report(String subjectUserId, ReportReason reason, {String? note, String? planId}) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    try {
      await c.from('reports').upsert(
        {'reporter_id': me, 'subject_user_id': subjectUserId, 'plan_id': planId, 'reason': reason.name, 'note': (note?.trim().isEmpty ?? true) ? null : note!.trim()},
        onConflict: 'reporter_id,subject_user_id',
        ignoreDuplicates: true,
      );
      return null;
    } catch (_) {
      return "Couldn't send the report — try again.";
    }
  }

  /// Am I suspended/banned? Shown to the person so a sanction is never silent.
  /// A suspension that has run out is no sanction at all.
  static Future<({bool banned, String? suspendedUntil})?> mySanction() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return null;
    try {
      final r = await c.from('user_sanctions').select('banned, suspended_until').eq('user_id', me).maybeSingle();
      if (r == null) return null;
      final banned = r['banned'] == true;
      final until = r['suspended_until'] as String?;
      if (!banned && (until == null || !DateTime.parse(until).isAfter(DateTime.now()))) return null;
      return (banned: banned, suspendedUntil: until);
    } catch (_) {
      return null;
    }
  }
}

class VouchApi {
  static Future<int> myCount() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 0;
    final res = await c.from('vouches').select('voucher_id').eq('vouchee_id', me).count();
    return res.count;
  }

  static Future<Set<String>> vouchedByMe() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return {};
    final data = await c.from('vouches').select('vouchee_id').eq('voucher_id', me);
    return rows(data).map((r) => r['vouchee_id'] as String).toSet();
  }

  static Future<String?> vouch(String voucheeId) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    try {
      await c.from('vouches').insert({'voucher_id': me, 'vouchee_id': voucheeId});
      return null;
    } catch (_) {
      return "Couldn't vouch — you can only vouch for a friend.";
    } finally {
      vouchRev.bump();
    }
  }

  static Future<void> unvouch(String voucheeId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('vouches').delete().eq('voucher_id', me).eq('vouchee_id', voucheeId);
    vouchRev.bump();
  }
}

// ── profile privacy + opt-ins ────────────────────────────────────────────────
enum ProfileVisibility { friends, fof, public }

const profileVisibilityLabel = {
  ProfileVisibility.friends: 'Friends',
  ProfileVisibility.fof: 'Friends of friends',
  ProfileVisibility.public: 'Anyone with the link',
};

class ProfileSettings {
  final ProfileVisibility visibility;
  final String socialHandle;
  final bool shareTrends;
  final String? trendsGeo;
  final bool competeVisible;
  const ProfileSettings({this.visibility = ProfileVisibility.friends, this.socialHandle = '', this.shareTrends = false, this.trendsGeo, this.competeVisible = false});
}

class ProfileApi {
  static Future<ProfileSettings> settings() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return const ProfileSettings();
    final r = await c.from('profiles').select('profile_visibility, social_handle, share_trends, trends_geo, compete_visible').eq('id', me).maybeSingle();
    if (r == null) return const ProfileSettings();
    return ProfileSettings(
      visibility: ProfileVisibility.values.firstWhere((v) => v.name == r['profile_visibility'], orElse: () => ProfileVisibility.friends),
      socialHandle: (r['social_handle'] as String?) ?? '',
      shareTrends: r['share_trends'] == true,
      trendsGeo: r['trends_geo'] as String?,
      competeVisible: r['compete_visible'] == true,
    );
  }

  static Future<void> _update(Map<String, dynamic> patch) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('profiles').update(patch).eq('id', me);
    profileRev.bump();
  }

  static Future<void> setVisibility(ProfileVisibility v) => _update({'profile_visibility': v.name});
  static Future<void> setSocialHandle(String h) => _update({'social_handle': h.trim().isEmpty ? null : h.trim()});
  static Future<void> setShareTrends(bool v) => _update({'share_trends': v});

  /// Store (or clear) the coarse area cell. Raw coordinates never leave the device.
  static Future<void> setTrendsGeo(String? geohash) => _update({'trends_geo': geohash == null ? null : (geohash.length > 12 ? geohash.substring(0, 12) : geohash)});
}

class PublicProfileData {
  final String displayName;
  final String handle;
  final String? socialHandle;
  final Map<String, int> counts;
  final int total;
  final int kinds;
  const PublicProfileData({required this.displayName, required this.handle, this.socialHandle, required this.counts, required this.total, required this.kinds});
}

class Trend {
  final String kind; // drink | mood
  final String name;
  final int users;
  final int logs;
  const Trend(this.kind, this.name, this.users, this.logs);
}

class DiscoverVenue {
  final String name;
  final String slug;
  final String? city;
  final String country;
  final bool isStore;
  final bool openTonight;
  const DiscoverVenue({required this.name, required this.slug, this.city, required this.country, required this.isStore, required this.openTonight});
}

class DiscoverApi {
  /// Opt-in public profile — counts only, never the diary itself.
  static Future<PublicProfileData?> publicProfile(String handle) async {
    final c = db;
    if (c == null || handle.isEmpty) return null;
    final r = firstRow(await c.rpc('public_profile', params: {'h': handle}));
    if (r == null) return null;
    final counts = <String, int>{};
    for (final d in asStrings(r['dates'])) {
      counts[d] = (counts[d] ?? 0) + 1;
    }
    return PublicProfileData(
      displayName: (r['display_name'] as String?) ?? handle,
      handle: (r['handle'] as String?) ?? handle,
      socialHandle: r['social_handle'] as String?,
      counts: counts,
      total: asInt(r['total']),
      kinds: asInt(r['kinds']),
    );
  }

  static List<Trend> _trends(Object? data) =>
      rows(data).map((r) => Trend(r['kind'] as String? ?? 'drink', r['name'] as String? ?? '', asInt(r['users']), asInt(r['logs']))).toList();

  /// k-anonymous trends across consenting users.
  static Future<List<Trend>> tasteTrends([int daysBack = 14]) async {
    final c = db;
    if (c == null || auth.meId == null) return [];
    return _trends(await c.rpc('taste_trends', params: {'days_back': daysBack}));
  }

  static Future<List<Trend>> areaTrends(String geo, [int daysBack = 30]) async {
    final c = db;
    if (c == null || auth.meId == null || geo.isEmpty) return [];
    return _trends(await c.rpc('area_taste_trends', params: {'in_geo': geo, 'days_back': daysBack}));
  }

  /// A LISTING, never an offer: name, city, whether a room is running. The database
  /// backs this up — discover_venues() never joins venue_perks.
  static Future<List<DiscoverVenue>> venues(String? country) async {
    final c = db;
    if (c == null) return [];
    return rows(await c.rpc('discover_venues', params: {'in_country': country, 'lim': 30}))
        .map((r) => DiscoverVenue(
              name: r['name'] as String,
              slug: r['slug'] as String? ?? '',
              city: r['city'] as String?,
              country: r['country'] as String? ?? '',
              isStore: r['kind'] == 'store',
              openTonight: r['open_tonight'] == true,
            ))
        .toList();
  }
}

// ── data rights (GDPR Arts. 15 & 17, India's DPDP Act) ───────────────────────
class AccountApi {
  /// Everything we hold about you, as pretty JSON (the caller shares/saves it).
  static Future<({String? json, String? error})> exportEverything() async {
    final c = db;
    if (c == null) return (json: null, error: "You're signed out — there's nothing stored in the cloud to export.");
    final me = auth.meId;
    if (me == null) return (json: null, error: "You're signed out.");
    Future<Object?> q(Future<Object?> f) => f.catchError((_) => null);
    final results = await Future.wait([
      q(c.from('profiles').select().eq('id', me).maybeSingle()),
      q(c.from('entries').select().eq('user_id', me)),
      q(c.from('wishlist_items').select().eq('user_id', me)),
      q(c.from('expenses').select().eq('payer_id', me)),
      q(c.from('expense_shares').select().eq('user_id', me)),
      q(c.from('point_events').select().eq('subject_user_id', me)),
      q(c.from('spend_events').select().eq('subject_user_id', me)),
      q(c.from('room_consent').select().eq('user_id', me)),
    ]);
    final payload = {
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'note': "Everything brewdiary holds about you. Points and tabs are included because they're about you, even though only a venue could write them.",
      'profile': results[0],
      'entries': results[1] ?? [],
      'wishlist': results[2] ?? [],
      'expenses': results[3] ?? [],
      'expense_shares': results[4] ?? [],
      'points': results[5] ?? [],
      'spend': results[6] ?? [],
      'venue_screen_consent': results[7] ?? [],
      'on_this_device_only': {
        'goals': Prefs.getJson<Object>('brewdiary.goals.v1'),
        'extras': Prefs.getJson<Object>('brewdiary.extras.v1'),
        'currency': Prefs.getString('brewdiary.currency.v1'),
        'country': Prefs.getString('brewdiary.country.v1'),
      },
    };
    return (json: const JsonEncoder.withIndent('  ').convert(payload), error: null);
  }

  /// Delete the account and everything in it — really, via the website's server
  /// route (it holds the service key). WHO is decided by the bearer token.
  static Future<String?> deleteAccount() async {
    final c = db;
    final token = c?.auth.currentSession?.accessToken;
    if (c == null || token == null) return "You're signed out.";
    try {
      final res = await http.post(Config.api('/api/account/delete'), headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode >= 300) {
        try {
          return (jsonDecode(res.body) as Map)['error'] as String? ?? "Couldn't delete the account — please try again.";
        } catch (_) {
          return "Couldn't delete the account — please try again.";
        }
      }
    } catch (_) {
      return "Couldn't reach the server — check your connection and try again.";
    }
    for (final k in Prefs.keys().where((k) => k.startsWith('brewdiary.')).toList()) {
      await Prefs.remove(k);
    }
    await c.auth.signOut();
    return null;
  }
}

// ── the venue guest book, seen from the guest's side ─────────────────────────
class VenueBook {
  final String venueId;
  final String venueName;
  final String body;
  final List<String> tags;
  const VenueBook(this.venueId, this.venueName, this.body, this.tags);
}

class VenueBooksApi {
  /// Every venue that keeps a first-party note on me — never my diary.
  static Future<List<VenueBook>> mine() async {
    final c = db;
    if (c == null || auth.meId == null) return [];
    return rows(await c.rpc('my_venue_books'))
        .map((r) => VenueBook(r['venue_id'] as String, (r['venue_name'] as String?) ?? 'a venue', (r['body'] as String?) ?? '', asStrings(r['tags'])))
        .toList();
  }

  static Future<String?> forget(String venueId) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    try {
      await c.from('venue_guest_notes').delete().eq('venue_id', venueId).eq('subject_id', me);
      return null;
    } catch (e) {
      return '$e';
    }
  }
}
