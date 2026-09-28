// Circles (private groups) + their challenges — ports of src/lib/circles.ts and
// src/lib/challenges.ts. A circle_shares row exposes ONE entry to ONE circle without
// touching entries.visibility; the circle mosaic is derived from what members shared.
//
// Insert gotcha: tables whose select policy calls a SECURITY DEFINER fn trip
// PostgREST on INSERT..RETURNING — ids are generated client-side, no .select().
import '../core/misc.dart';
import 'auth.dart';
import 'base.dart';

class Circle {
  final String id;
  final String name;
  final String createdBy;
  final String inviteCode;
  final int memberCount;
  const Circle({required this.id, required this.name, required this.createdBy, required this.inviteCode, required this.memberCount});
}

class CircleMember {
  final String id;
  final String handle;
  final String name;
  const CircleMember(this.id, this.handle, this.name);
}

class SharedEntry {
  final String id;
  final String userId;
  final String authorName;
  final String date;
  final String createdAt;
  final String drink;
  final String? mood;
  final String? note;
  final String? venue;
  final List<String> photoUrls;
  const SharedEntry({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.date,
    required this.createdAt,
    required this.drink,
    this.mood,
    this.note,
    this.venue,
    this.photoUrls = const [],
  });

  static SharedEntry? fromJoin(Object? raw, String fallbackName) {
    if (raw is! Map) return null;
    final e = Map<String, dynamic>.from(raw);
    final author = e['author'] as Map?;
    final photos = rows(e['entry_photos'])..sort((a, b) => asInt(a['sort_order']).compareTo(asInt(b['sort_order'])));
    final c = db;
    return SharedEntry(
      id: e['id'] as String,
      userId: e['user_id'] as String,
      authorName: (author?['display_name'] as String?) ?? (author?['handle'] as String?) ?? fallbackName,
      date: e['date'] as String,
      createdAt: e['created_at'] as String,
      drink: e['drink'] as String,
      mood: e['mood'] as String?,
      note: e['note'] as String?,
      venue: e['venue'] as String?,
      photoUrls: c == null
          ? const []
          : photos.map((p) {
              final u = p['url'] as String;
              return u.startsWith('http') ? u : c.storage.from('photos').getPublicUrl(u);
            }).toList(),
    );
  }
}

class CircleDetail {
  final List<CircleMember> members;
  final List<SharedEntry> entries;
  const CircleDetail(this.members, this.entries);
}

class CirclesApi {
  static Future<List<Circle>> mine() async {
    final c = db;
    if (c == null || auth.meId == null) return [];
    final data = await c.from('circles').select('id, name, created_by, invite_code, circle_members(user_id)').order('created_at', ascending: true);
    return rows(data)
        .map((r) => Circle(
              id: r['id'] as String,
              name: r['name'] as String,
              createdBy: r['created_by'] as String,
              inviteCode: r['invite_code'] as String,
              memberCount: rows(r['circle_members']).length,
            ))
        .toList();
  }

  static Future<CircleDetail> detail(String circleId) async {
    final c = db;
    if (c == null) return const CircleDetail([], []);
    final results = await Future.wait([
      c.from('circle_members').select('user_id, member:profiles(id, handle, display_name)').eq('circle_id', circleId),
      c
          .from('circle_shares')
          .select('entry_id, entry:entries(id, user_id, date, drink, mood, note, venue, created_at, author:profiles(display_name, handle))')
          .eq('circle_id', circleId),
    ]);
    final members = rows(results[0]).map((r) {
      final p = Map<String, dynamic>.from(r['member'] as Map);
      final handle = p['handle'] as String? ?? '';
      return CircleMember(p['id'] as String, handle, (p['display_name'] as String?) ?? handle);
    }).toList();
    final entries = rows(results[1]).map((r) => SharedEntry.fromJoin(r['entry'], 'member')).whereType<SharedEntry>().toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return CircleDetail(members, entries);
  }

  static Future<Set<String>> sharesForEntry(String entryId) async {
    final c = db;
    if (c == null) return {};
    final data = await c.from('circle_shares').select('circle_id').eq('entry_id', entryId);
    return rows(data).map((r) => r['circle_id'] as String).toSet();
  }

  static Future<String?> create(String name) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    final clean = name.trim();
    if (clean.isEmpty) return 'name required';
    final id = newId();
    try {
      await c.from('circles').insert({'id': id, 'name': clean, 'created_by': me});
      await c.from('circle_members').insert({'circle_id': id, 'user_id': me});
      return null;
    } catch (e) {
      return '$e';
    } finally {
      circlesRev.bump();
    }
  }

  /// Returns the circle name, or throws a friendly message.
  static Future<({String? name, String? error})> join(String code) async {
    final c = db;
    if (c == null) return (name: null, error: 'offline');
    try {
      final data = await c.rpc('join_circle', params: {'code': code.trim()});
      return (name: (firstRow(data)?['name'] as String?) ?? 'circle', error: null);
    } catch (e) {
      return (name: null, error: '$e'.contains('invalid code') ? 'No circle with that code.' : '$e');
    } finally {
      circlesRev.bump();
    }
  }

  static Future<void> leave(String circleId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('circle_members').delete().eq('circle_id', circleId).eq('user_id', me);
    circlesRev.bump();
  }

  static Future<void> delete(String circleId) async {
    await db?.from('circles').delete().eq('id', circleId);
    circlesRev.bump();
  }

  static Future<void> share(String entryId, String circleId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('circle_shares').insert({'entry_id': entryId, 'circle_id': circleId, 'user_id': me});
    circlesRev.bump();
  }

  static Future<void> unshare(String entryId, String circleId) async {
    await db?.from('circle_shares').delete().eq('entry_id', entryId).eq('circle_id', circleId);
    circlesRev.bump();
  }
}

// ── challenges ───────────────────────────────────────────────────────────────
enum ChallengeKind { mostLogged, mostKinds, longestStreak, freeform }

extension ChallengeKindX on ChallengeKind {
  String get db => const ['most_logged', 'most_kinds', 'longest_streak', 'freeform'][index];
  String get label => const ['Most logged', 'Most kinds', 'Longest run', 'Competition'][index];
  String get unit => const ['logged', 'kinds', 'nights running', ''][index];
  bool get isFreeform => this == ChallengeKind.freeform;
  static ChallengeKind parse(String? s) => ChallengeKind.values.firstWhere((k) => k.db == s, orElse: () => ChallengeKind.mostLogged);
}

const scoredKinds = [ChallengeKind.mostLogged, ChallengeKind.mostKinds, ChallengeKind.longestStreak];

class Challenge {
  final String id;
  final String circleId;
  final String createdBy;
  final ChallengeKind kind;
  final String? title;
  final String? rule;
  final String? winnerId;
  final String startsOn;
  final String endsOn;
  final List<String> participantIds;
  const Challenge({
    required this.id,
    required this.circleId,
    required this.createdBy,
    required this.kind,
    this.title,
    this.rule,
    this.winnerId,
    required this.startsOn,
    required this.endsOn,
    required this.participantIds,
  });
}

class BoardRow {
  final String userId;
  final String name;
  final int value;
  const BoardRow(this.userId, this.name, this.value);
}

class ChallengesApi {
  static Future<List<Challenge>> forCircle(String circleId) async {
    final c = db;
    if (c == null) return [];
    final data = await c
        .from('challenges')
        .select('id, circle_id, created_by, kind, title, rule, winner_id, starts_on, ends_on, challenge_members(user_id)')
        .eq('circle_id', circleId)
        .order('created_at', ascending: false);
    return rows(data)
        .map((r) => Challenge(
              id: r['id'] as String,
              circleId: r['circle_id'] as String,
              createdBy: r['created_by'] as String,
              kind: ChallengeKindX.parse(r['kind'] as String?),
              title: r['title'] as String?,
              rule: r['rule'] as String?,
              winnerId: r['winner_id'] as String?,
              startsOn: r['starts_on'] as String,
              endsOn: r['ends_on'] as String,
              participantIds: rows(r['challenge_members']).map((m) => m['user_id'] as String).toList(),
            ))
        .toList();
  }

  static Future<List<BoardRow>> board(Challenge ch) async {
    final c = db;
    if (c == null) return [];
    final data = await c.rpc('challenge_board', params: {'cid': ch.id});
    final list = rows(data).map((r) {
      final value = switch (ch.kind) {
        ChallengeKind.mostLogged => asInt(r['total']),
        ChallengeKind.mostKinds => asInt(r['kinds']),
        ChallengeKind.longestStreak => longestRun(asStrings(r['dates'])),
        ChallengeKind.freeform => 0,
      };
      return BoardRow(r['user_id'] as String, (r['display_name'] as String?) ?? 'member', value);
    }).toList()
      ..sort((a, b) {
        final v = b.value.compareTo(a.value);
        return v != 0 ? v : a.name.compareTo(b.name);
      });
    return list;
  }

  static Future<String?> create(String circleId, {required ChallengeKind kind, required String startsOn, required String endsOn, String? title, String? rule}) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    final id = newId();
    try {
      await c.from('challenges').insert({
        'id': id,
        'circle_id': circleId,
        'created_by': me,
        'kind': kind.db,
        'starts_on': startsOn,
        'ends_on': endsOn,
        'title': (title?.trim().isEmpty ?? true) ? null : title!.trim(),
        'rule': (rule?.trim().isEmpty ?? true) ? null : rule!.trim(),
      });
      await c.from('challenge_members').insert({'challenge_id': id, 'user_id': me});
      return null;
    } catch (e) {
      return '$e';
    } finally {
      challengesRev.bump();
    }
  }

  static Future<void> setWinner(String challengeId, String? winnerId) async {
    await db?.rpc('set_challenge_winner', params: {'cid': challengeId, 'winner': winnerId});
    challengesRev.bump();
  }

  static Future<void> join(String challengeId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('challenge_members').insert({'challenge_id': challengeId, 'user_id': me});
    challengesRev.bump();
  }

  static Future<void> leave(String challengeId) async {
    final me = auth.meId;
    if (me == null) return;
    await db?.from('challenge_members').delete().eq('challenge_id', challengeId).eq('user_id', me);
    challengesRev.bump();
  }

  static Future<void> delete(String challengeId) async {
    await db?.from('challenges').delete().eq('id', challengeId);
    challengesRev.bump();
  }
}
