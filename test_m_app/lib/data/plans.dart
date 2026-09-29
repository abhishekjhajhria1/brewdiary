// Plans — pre-plan a night, let people you're connected to ask to join. A port of
// src/lib/plans.ts. Reads and sensitive writes are SECURITY DEFINER rpcs; the safety
// rules (join policy, blocks, "only the host decides") live in the database.
//
// join_policy is only ever private | invite | friends | fof — there is NO stranger
// tier, and the DB CHECK refuses anything else. Soft signals are COUNTS, never a rating.
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/misc.dart';
import 'auth.dart';
import 'base.dart';

enum JoinPolicy { private, invite, friends, fof }

const joinPolicyLabel = {
  JoinPolicy.private: 'Only me',
  JoinPolicy.invite: 'Invite only',
  JoinPolicy.friends: 'Friends',
  JoinPolicy.fof: 'Friends of friends',
};

enum PlanStatus { open, closed, cancelled }

enum JoinStatus { requested, approved, declined, withdrawn }

JoinPolicy _policy(Object? s) => JoinPolicy.values.firstWhere((p) => p.name == s, orElse: () => JoinPolicy.friends);
PlanStatus _status(Object? s) => PlanStatus.values.firstWhere((p) => p.name == s, orElse: () => PlanStatus.open);
JoinStatus? _join(Object? s) => s == null ? null : JoinStatus.values.where((p) => p.name == s).firstOrNull;

class Plan {
  final String id;
  final String hostId;
  final String hostName;
  final String hostHandle;
  final String title;
  final String date;
  final String? time;
  final String? city;
  final String? note;
  final List<String> drinks;
  final List<String> vibeTags;
  final JoinPolicy joinPolicy;
  final int? capacity;
  final int going;
  final JoinStatus? myStatus;
  const Plan({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.hostHandle,
    required this.title,
    required this.date,
    this.time,
    this.city,
    this.note,
    required this.drinks,
    required this.vibeTags,
    required this.joinPolicy,
    this.capacity,
    required this.going,
    this.myStatus,
  });
}

class MyPlan {
  final String id;
  final String title;
  final String date;
  final String? time;
  final String? city;
  final String? note;
  final List<String> drinks;
  final List<String> vibeTags;
  final JoinPolicy joinPolicy;
  final int? capacity;
  final PlanStatus status;
  final int going;
  final int pending;
  const MyPlan({
    required this.id,
    required this.title,
    required this.date,
    this.time,
    this.city,
    this.note,
    required this.drinks,
    required this.vibeTags,
    required this.joinPolicy,
    this.capacity,
    required this.status,
    required this.going,
    required this.pending,
  });
}

class PlanRequest {
  final String joinId;
  final String userId;
  final String name;
  final String handle;
  final String? message;
  final JoinStatus status;
  final String askedAt;
  const PlanRequest({required this.joinId, required this.userId, required this.name, required this.handle, this.message, required this.status, required this.askedAt});
}

class PlanSignals {
  final int mutualFriends;
  final int sharedDrinks;
  final bool hostVerified;
  final int hostVouches;
  final String? hostSince;
  const PlanSignals({required this.mutualFriends, required this.sharedDrinks, required this.hostVerified, required this.hostVouches, this.hostSince});
}

class PlanDay {
  final List<({String title, String? time})> items;
  final bool mine;
  const PlanDay(this.items, this.mine);
}

class NewPlan {
  final String title;
  final String date;
  final String? time;
  final String? city;
  final String? note;
  final List<String> drinks;
  final List<String> vibeTags;
  final JoinPolicy joinPolicy;
  final int? capacity;
  const NewPlan({
    required this.title,
    required this.date,
    this.time,
    this.city,
    this.note,
    this.drinks = const [],
    this.vibeTags = const [],
    this.joinPolicy = JoinPolicy.friends,
    this.capacity,
  });
}

String? _blank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

class PlansApi {
  static Future<List<Plan>> upcoming() async {
    final c = db;
    if (c == null || auth.meId == null) return [];
    return rows(await c.rpc('upcoming_plans'))
        .map((r) => Plan(
              id: r['id'] as String,
              hostId: r['host_id'] as String,
              hostName: (r['host_name'] as String?) ?? (r['host_handle'] as String? ?? ''),
              hostHandle: r['host_handle'] as String? ?? '',
              title: r['title'] as String,
              date: r['plan_date'] as String,
              time: r['plan_time'] as String?,
              city: r['city'] as String?,
              note: r['note'] as String?,
              drinks: asStrings(r['drinks']),
              vibeTags: asStrings(r['vibe_tags']),
              joinPolicy: _policy(r['join_policy']),
              capacity: r['capacity'] == null ? null : asInt(r['capacity']),
              going: asInt(r['going'], 1),
              myStatus: _join(r['my_status']),
            ))
        .toList();
  }

  static Future<List<MyPlan>> mine() async {
    final c = db;
    if (c == null || auth.meId == null) return [];
    return rows(await c.rpc('my_plans'))
        .map((r) => MyPlan(
              id: r['id'] as String,
              title: r['title'] as String,
              date: r['plan_date'] as String,
              time: r['plan_time'] as String?,
              city: r['city'] as String?,
              note: r['note'] as String?,
              drinks: asStrings(r['drinks']),
              vibeTags: asStrings(r['vibe_tags']),
              joinPolicy: _policy(r['join_policy']),
              capacity: r['capacity'] == null ? null : asInt(r['capacity']),
              status: _status(r['status']),
              going: asInt(r['going'], 1),
              pending: asInt(r['pending']),
            ))
        .toList();
  }

  static Future<List<PlanRequest>> requests(String planId) async {
    final c = db;
    if (c == null) return [];
    return rows(await c.rpc('plan_requests', params: {'pid': planId}))
        .map((r) => PlanRequest(
              joinId: r['join_id'] as String,
              userId: r['user_id'] as String,
              name: (r['name'] as String?) ?? (r['handle'] as String? ?? ''),
              handle: r['handle'] as String? ?? '',
              message: r['message'] as String?,
              status: _join(r['status']) ?? JoinStatus.requested,
              askedAt: r['asked_at'] as String? ?? '',
            ))
        .toList();
  }

  static Future<PlanSignals?> signals(String planId) async {
    final c = db;
    if (c == null) return null;
    final r = firstRow(await c.rpc('plan_signals', params: {'pid': planId}));
    if (r == null) return null;
    return PlanSignals(
      mutualFriends: asInt(r['mutual_friends']),
      sharedDrinks: asInt(r['shared_drinks']),
      hostVerified: r['host_verified'] == true,
      hostVouches: asInt(r['host_vouches']),
      hostSince: r['host_since'] as String?,
    );
  }

  /// `YYYY-MM-DD` → the plan(s) I have that day (my own or approved joins).
  static Future<Map<String, PlanDay>> planDays() async {
    final c = db;
    if (c == null || auth.meId == null) return {};
    final m = <String, PlanDay>{};
    for (final r in rows(await c.rpc('my_plan_days'))) {
      final key = r['plan_date'] as String;
      final cur = m[key] ?? const PlanDay([], false);
      m[key] = PlanDay([...cur.items, (title: r['title'] as String, time: r['plan_time'] as String?)], cur.mine || r['host'] == true);
    }
    return m;
  }

  static Future<List<({String userId, String name, String handle})>> invitees(String planId) async {
    final c = db;
    if (c == null) return [];
    return rows(await c.rpc('plan_invitees', params: {'pid': planId}))
        .map((r) => (userId: r['user_id'] as String, name: (r['display_name'] as String?) ?? (r['handle'] as String? ?? ''), handle: r['handle'] as String? ?? ''))
        .toList();
  }

  static Future<String?> invite(String planId, String userId) async {
    final c = db;
    if (c == null) return 'offline';
    try {
      await c.rpc('invite_to_plan', params: {'pid': planId, 'target': userId});
      return null;
    } catch (e) {
      return RegExp("can't invite|blocked", caseSensitive: false).hasMatch('$e') ? "You can't invite this person." : "Couldn't send that invite — try again.";
    } finally {
      plansRev.bump();
    }
  }

  static Future<String?> uninvite(String planId, String userId) async {
    final c = db;
    if (c == null) return 'offline';
    try {
      await c.rpc('uninvite_from_plan', params: {'pid': planId, 'target': userId});
      return null;
    } catch (_) {
      return "Couldn't update the guest list — try again.";
    } finally {
      plansRev.bump();
    }
  }

  static Future<String?> respondInvite(String planId, bool going) async {
    final c = db;
    if (c == null) return 'offline';
    try {
      await c.rpc('respond_invite', params: {'pid': planId, 'going': going});
      return null;
    } catch (e) {
      if (RegExp('full', caseSensitive: false).hasMatch('$e')) return 'This plan is full.';
      if (RegExp('taking people', caseSensitive: false).hasMatch('$e')) return "This plan isn't taking people right now.";
      return "Couldn't update that — try again.";
    } finally {
      plansRev.bump();
    }
  }

  static Future<({String? id, String? error})> create(NewPlan p) async {
    final c = db;
    final me = auth.meId;
    if (c == null || me == null) return (id: null, error: 'offline');
    final title = p.title.trim();
    if (title.isEmpty) return (id: null, error: 'Give your night a title.');
    if (p.date.isEmpty) return (id: null, error: 'Pick a date.');
    if (p.date.compareTo(todayKey()) < 0) return (id: null, error: "A plan can't be in the past.");
    final id = newId();
    try {
      await c.from('plans').insert({
        'id': id,
        'host_id': me,
        'title': title,
        'plan_date': p.date,
        'plan_time': _blank(p.time),
        'city': _blank(p.city),
        'note': _blank(p.note),
        'drinks': dedupeTags(p.drinks),
        'vibe_tags': dedupeTags(p.vibeTags),
        'join_policy': p.joinPolicy.name,
        'capacity': (p.capacity ?? 0) > 0 ? p.capacity : null,
      });
      return (id: id, error: null);
    } catch (e) {
      return (id: null, error: '$e');
    } finally {
      plansRev.bump();
    }
  }

  static Future<String?> setStatus(String planId, PlanStatus status) async {
    try {
      await db?.from('plans').update({'status': status.name}).eq('id', planId);
      return null;
    } catch (e) {
      return '$e';
    } finally {
      plansRev.bump();
    }
  }

  static Future<void> delete(String planId) async {
    await db?.from('plans').delete().eq('id', planId);
    plansRev.bump();
  }

  static Future<String?> requestJoin(String planId, [String? message]) async {
    final c = db;
    if (c == null) return 'offline';
    try {
      await c.rpc('request_join', params: {'pid': planId, 'msg': _blank(message)});
      return null;
    } catch (e) {
      final m = '$e';
      if (RegExp('full', caseSensitive: false).hasMatch(m)) return 'This plan is full.';
      if (RegExp('taking people', caseSensitive: false).hasMatch(m)) return "This plan isn't taking people right now.";
      if (RegExp("can't join|allowed", caseSensitive: false).hasMatch(m)) return "You can't join this plan.";
      return "Couldn't send that — try again.";
    } finally {
      plansRev.bump();
    }
  }

  static Future<String?> respondJoin(String joinId, bool approve) async {
    final c = db;
    if (c == null) return 'offline';
    try {
      await c.rpc('respond_join', params: {'jid': joinId, 'approve': approve});
      return null;
    } catch (e) {
      return RegExp('full', caseSensitive: false).hasMatch('$e') ? 'The plan is full.' : "Couldn't record that — try again.";
    } finally {
      plansRev.bump();
    }
  }

  static Future<String?> withdraw(String planId) async {
    final c = db;
    if (c == null) return 'offline';
    try {
      await c.rpc('withdraw_join', params: {'pid': planId});
      return null;
    } catch (_) {
      return "Couldn't update that — try again.";
    } finally {
      plansRev.bump();
    }
  }
}
