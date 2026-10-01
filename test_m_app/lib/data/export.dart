// Everything that goes into "Your diary, as a book" (the PDF export): the diary
// itself, what you did in Together, Split, your to-try list, what venues keep on
// you, and your conversations with Ninkasi. Gathered on the phone; nothing is
// sent anywhere, and each cloud read that fails just leaves its section out.
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/misc.dart';
import 'package:brewdiary_core/types.dart';

import 'auth.dart';
import 'base.dart';
import 'circles.dart';
import 'entries.dart';
import 'friends.dart';
import 'parties.dart';
import 'plans.dart';
import 'safety.dart';
import 'settings.dart';
import 'split.dart';
import 'wishlist.dart';

class ExportBundle {
  final String name;
  final String? handle;
  final String? memberSince; // ISO
  final DateTime generated;
  final String currency;
  final List<Entry> entries;
  final List<String> friends;
  final List<({String name, int members})> circles;
  final List<({String name, String date, String? venue})> parties;
  final List<({String title, String date, String? city})> plans;
  final List<({String body, String at})> comments;
  final List<({String what, double amount, String at, bool paidByMe})> expenses;
  final List<({String drink, bool done})> wishlist;
  final List<({String venue, String body, List<String> tags})> venueNotes;
  final int visits;
  final List<({String reward, String at})> perks;
  final List<({DateTime at, String user, String assistant})> chats;

  const ExportBundle({
    required this.name,
    this.handle,
    this.memberSince,
    required this.generated,
    this.currency = 'INR',
    required this.entries,
    this.friends = const [],
    this.circles = const [],
    this.parties = const [],
    this.plans = const [],
    this.comments = const [],
    this.expenses = const [],
    this.wishlist = const [],
    this.venueNotes = const [],
    this.visits = 0,
    this.perks = const [],
    this.chats = const [],
  });

  /// Read it all. Signed out, that's the diary, the to-try list and the chats.
  static Future<ExportBundle> collect() async {
    final me = auth.meId;
    final profile = auth.profile;
    final c = db;
    Future<T> safe<T>(Future<T> Function() f, T fallback) async {
      try {
        return await f();
      } catch (_) {
        return fallback;
      }
    }

    final cloud = c != null && me != null && me != 'local';
    final results = await Future.wait<Object?>([
      if (cloud) ...[
        safe(FriendsApi.friends, const <SocialProfile>[]),
        safe(CirclesApi.mine, const <Circle>[]),
        safe(PartiesApi.mine, const <Party>[]),
        safe(PlansApi.mine, const <MyPlan>[]),
        safe(() async => rows(await c.from('comments').select('body, created_at').eq('user_id', me).order('created_at')), const <Map<String, dynamic>>[]),
        safe(SplitApi.load, (expenses: const <Expense>[], settlements: const <Settlement>[])),
        safe(VenueBooksApi.mine, const <VenueBook>[]),
        safe(() async => rows(await c.from('venue_checkins').select('on_date').eq('user_id', me)).length, 0),
        safe(() async => rows(await c.from('perk_redemptions').select('reward, redeemed_at').eq('user_id', me).order('redeemed_at')), const <Map<String, dynamic>>[]),
      ],
    ]);
    T at<T>(int i, T fallback) => cloud ? results[i] as T : fallback;

    final friends = at(0, const <SocialProfile>[]);
    final circles = at(1, const <Circle>[]);
    final parties = at(2, const <Party>[]);
    final plans = at(3, const <MyPlan>[]);
    final comments = at(4, const <Map<String, dynamic>>[]);
    final split = at(5, (expenses: const <Expense>[], settlements: const <Settlement>[]));
    final books = at(6, const <VenueBook>[]);
    final visits = at(7, 0);
    final perks = at(8, const <Map<String, dynamic>>[]);

    return ExportBundle(
      name: profile?.name ?? 'You',
      handle: profile?.handle.isNotEmpty == true ? profile!.handle : null,
      memberSince: profile?.createdAt,
      generated: appNow(),
      currency: PlaceStore.instance.currency,
      entries: [...entryStore.entries],
      friends: [for (final f in friends) f.handle.isEmpty ? f.name : '${f.name} @${f.handle}'],
      circles: [for (final x in circles) (name: x.name, members: x.memberCount)],
      parties: [for (final p in parties) (name: p.name, date: p.date, venue: p.venue)],
      plans: [for (final p in plans) (title: p.title, date: p.date, city: p.city)],
      comments: [for (final r in comments) (body: '${r['body']}', at: '${r['created_at']}')],
      expenses: [for (final e in split.expenses) (what: e.description, amount: e.amount, at: e.createdAt, paidByMe: e.payerId == me)],
      wishlist: [for (final w in WishlistStore.instance.items) (drink: w.drink, done: w.done)],
      venueNotes: [for (final b in books) (venue: b.venueName, body: b.body, tags: b.tags)],
      visits: visits,
      perks: [for (final r in perks) (reward: '${r['reward']}', at: '${r['redeemed_at']}')],
      chats: [
        for (final s in TrainingStore.instance.samples)
          (at: DateTime.fromMillisecondsSinceEpoch((s['at'] as num?)?.toInt() ?? 0), user: '${s['user'] ?? ''}', assistant: '${s['assistant'] ?? ''}'),
      ],
    );
  }
}
