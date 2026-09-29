// Together data — a port of src/lib/friends.ts. RLS already guarantees a feed query
// only returns friends' friends-visible entries, so the feed is just
// `entries where visibility=friends and not me`.
import 'auth.dart';
import 'base.dart';

class SocialProfile {
  final String id;
  final String handle;
  final String name;
  const SocialProfile({required this.id, required this.handle, required this.name});

  static SocialProfile fromRow(Map<String, dynamic> r) {
    final handle = (r['handle'] as String?) ?? '';
    return SocialProfile(id: r['id'] as String, handle: handle, name: (r['display_name'] as String?) ?? handle);
  }

  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();
}

class FeedComment {
  final String id;
  final String userId;
  final String body;
  final String createdAt;
  final String authorName;
  const FeedComment({required this.id, required this.userId, required this.body, required this.createdAt, required this.authorName});
}

class FeedEntry {
  final String id;
  final String userId;
  final SocialProfile author;
  final String date;
  final String createdAt;
  final String drink;
  final String? mood;
  final String? note;
  final String? venue;
  final int cheers;
  final bool cheered;
  final List<FeedComment> comments;
  const FeedEntry({
    required this.id,
    required this.userId,
    required this.author,
    required this.date,
    required this.createdAt,
    required this.drink,
    this.mood,
    this.note,
    this.venue,
    required this.cheers,
    required this.cheered,
    required this.comments,
  });
}

class FriendRequest {
  final String friendshipId;
  final SocialProfile profile;
  const FriendRequest(this.friendshipId, this.profile);
}

class FriendsApi {
  static Future<List<SocialProfile>> friends() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return [];
    final data = await c
        .from('friendships')
        .select(
            'requester_id, addressee_id, requester:profiles!friendships_requester_id_fkey(id,handle,display_name), addressee:profiles!friendships_addressee_id_fkey(id,handle,display_name)')
        .eq('status', 'accepted')
        .or('requester_id.eq.$me,addressee_id.eq.$me');
    return rows(data).map((r) {
      final other = r['requester_id'] == me ? r['addressee'] : r['requester'];
      return SocialProfile.fromRow(Map<String, dynamic>.from(other as Map));
    }).toList();
  }

  static Future<List<FriendRequest>> requests() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return [];
    final data = await c
        .from('friendships')
        .select('id, requester:profiles!friendships_requester_id_fkey(id,handle,display_name)')
        .eq('addressee_id', me)
        .eq('status', 'pending');
    return rows(data).map((r) => FriendRequest(r['id'] as String, SocialProfile.fromRow(Map<String, dynamic>.from(r['requester'] as Map)))).toList();
  }

  static Future<List<FeedEntry>> feed() async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return [];
    final data = await c
        .from('entries')
        .select(
            'id,user_id,date,drink,mood,note,venue,created_at, author:profiles(id,handle,display_name), reactions(user_id), comments(id,user_id,body,created_at, author:profiles(display_name))')
        .eq('visibility', 'friends')
        .neq('user_id', me)
        .order('created_at', ascending: false)
        .limit(50);
    return rows(data).map((r) {
      final reactions = rows(r['reactions']);
      final comments = rows(r['comments'])
          .map((cm) => FeedComment(
                id: cm['id'] as String,
                userId: cm['user_id'] as String,
                body: cm['body'] as String,
                createdAt: cm['created_at'] as String,
                authorName: ((cm['author'] as Map?)?['display_name'] as String?) ?? 'friend',
              ))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return FeedEntry(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        author: SocialProfile.fromRow(Map<String, dynamic>.from(r['author'] as Map)),
        date: r['date'] as String,
        createdAt: r['created_at'] as String,
        drink: r['drink'] as String,
        mood: r['mood'] as String?,
        note: r['note'] as String?,
        venue: r['venue'] as String?,
        cheers: reactions.length,
        cheered: reactions.any((x) => x['user_id'] == me),
        comments: comments,
      );
    }).toList();
  }

  /// A friend's shared days (for their mosaic).
  static Future<List<String>> friendDates(String friendId) async {
    final c = db;
    if (c == null) return [];
    final data = await c.from('entries').select('id, date').eq('user_id', friendId).eq('visibility', 'friends');
    return rows(data).map((r) => r['date'] as String).toList();
  }

  /// Block-aware people search (a SECURITY DEFINER rpc drops anyone on either side
  /// of a block). Wildcard/grouping chars are stripped so no ilike pattern sneaks in.
  static Future<List<SocialProfile>> search(String query) async {
    final c = db;
    if (c == null) return [];
    final q = query.trim().replaceFirst(RegExp(r'^@+'), '').replaceAll(RegExp(r'[%,()]'), '');
    if (q.length < 2) return [];
    final data = await c.rpc('search_users', params: {'q': q});
    return rows(data).map(SocialProfile.fromRow).toList();
  }

  static Future<String?> sendRequest(String addresseeId) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return 'offline';
    try {
      await c.from('friendships').insert({'requester_id': me, 'addressee_id': addresseeId, 'status': 'pending'});
      return null;
    } catch (e) {
      return '$e';
    } finally {
      friendsRev.bump();
    }
  }

  static Future<void> accept(String friendshipId) async {
    await db?.from('friendships').update({'status': 'accepted', 'responded_at': DateTime.now().toUtc().toIso8601String()}).eq('id', friendshipId);
    friendsRev.bump();
  }

  static Future<void> decline(String friendshipId) async {
    await db?.from('friendships').delete().eq('id', friendshipId);
    friendsRev.bump();
  }

  static Future<void> toggleCheers(String entryId, bool cheered) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return;
    if (cheered) {
      await c.from('reactions').delete().eq('entry_id', entryId).eq('user_id', me).eq('type', 'cheers');
    } else {
      await c.from('reactions').insert({'entry_id': entryId, 'user_id': me, 'type': 'cheers'});
    }
    friendsRev.bump();
  }

  static Future<void> addComment(String entryId, String body) async {
    final c = db;
    final me = auth.meId;
    final text = body.trim();
    if (c == null || me == null || text.isEmpty) return;
    await c.from('comments').insert({'entry_id': entryId, 'user_id': me, 'body': text});
    friendsRev.bump();
  }
}
