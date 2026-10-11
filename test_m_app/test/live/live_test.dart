// LIVE: the app's real data layer against a real Supabase — sign-up with an emailed
// code, the diary with a photo, friends, the feed, cheers and comments, circles,
// parties with host approval, plans, Split, the to-try list. Two real accounts, the
// real RLS, every call the screens make.
//
// Skipped unless built with a server address. Against a THROWAWAY local Supabase
// (never a real project — it creates accounts):
//   npx supabase start            # in any scratch folder; then load schema.sql + every migration
//   flutter test test/live --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
//     --dart-define=SUPABASE_ANON_KEY=<the local anon key> --dart-define=MAILPIT_URL=http://127.0.0.1:54324
// docs/12 has the whole recipe.
@Tags(['live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:brewdiary/config.dart';
import 'package:brewdiary/data/auth.dart';
import 'package:brewdiary/data/base.dart';
import 'package:brewdiary/data/circles.dart';
import 'package:brewdiary/data/entries.dart';
import 'package:brewdiary/data/export.dart';
import 'package:brewdiary/data/friends.dart';
import 'package:brewdiary/data/parties.dart';
import 'package:brewdiary/data/menus.dart';
import 'package:brewdiary/data/plans.dart';
import 'package:brewdiary/data/safety.dart';
import 'package:brewdiary/data/split.dart';
import 'package:brewdiary/data/table_order.dart';
import 'package:brewdiary/data/taste_share.dart';
import 'package:brewdiary/data/wishlist.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/misc.dart';
import 'package:brewdiary_core/types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _mailpit = String.fromEnvironment('MAILPIT_URL');

/// The throwaway database itself, for the one thing no app may do: approve a venue
/// (on a real project that's scripts/verify-venue.mjs, run by the maintainer).
const _dbUrl = String.fromEnvironment('LIVE_DB_URL');

/// The website (account deletion runs through its server route).
const _siteGiven = bool.hasEnvironment('SITE_URL');

Future<String> _sql(String q) async {
  final r = await Process.run('psql', [_dbUrl, '-X', '-Atq', '-v', 'ON_ERROR_STOP=1', '-c', q]);
  if (r.exitCode != 0) throw StateError('psql: ${r.stderr}');
  return '${r.stdout}'.trim();
}

/// Wait for something the app does in the background (auth listener, optimistic write).
Future<void> until(bool Function() ok, String what, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('waited for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// The app swallows background failures into logDebug (debugPrint '[brewdiary] …').
/// Here every one of them fails the test.
final _swallowed = <String>[];

/// A slow phone network, on demand: the diary's read reaches the server at once, but
/// its answer comes back late — after anything the phone writes meanwhile.
class _SlowReads extends http.BaseClient {
  final _inner = http.Client();
  bool on = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    if (on && request.method == 'GET' && request.url.path.endsWith('/rest/v1/entries')) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return res;
  }
}

final _net = _SlowReads();

String _stamp() => DateTime.now().millisecondsSinceEpoch.toRadixString(36);

class _Who {
  final String name;
  final String email;
  final String password = 'night-out-2026';
  String? id;
  _Who(this.name) : email = '${name.toLowerCase()}.${_stamp()}@example.com';
}

Future<void> _signIn(_Who w) async {
  await auth.signOut();
  await until(() => !auth.isAuthed, 'signed out');
  final r = await auth.signIn(w.email, w.password);
  expect(r.ok, isTrue, reason: 'sign in ${w.name}: ${r.error}');
  await until(() => auth.isAuthed && auth.meId == w.id, '${w.name} signed in');
}

/// The newest code Mailpit caught for this address.
Future<String> _codeFor(String email) async {
  final http = HttpClient();
  Future<Map<String, dynamic>> get(String path) async {
    final req = await http.getUrl(Uri.parse('$_mailpit$path'));
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  }

  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(end)) {
    final list = (await get('/api/v1/search?query=${Uri.encodeQueryComponent('to:"$email"')}'))['messages'] as List? ?? const [];
    if (list.isNotEmpty) {
      final msg = await get('/api/v1/message/${(list.first as Map)['ID']}');
      final m = RegExp(r'\b(\d{6})\b').firstMatch('${msg['Text']}');
      if (m != null) return m.group(1)!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('no code mailed to $email');
}

void main() {
  final live = Config.cloud;
  final mira = _Who('Mira');
  final arjun = _Who('Arjun');

  setUpAll(() async {
    if (!live) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // flutter_test answers every request with a 400 otherwise
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    final print0 = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null && m.startsWith('[brewdiary]')) _swallowed.add(m);
      print0(m, wrapWidth: wrapWidth);
    };
    await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey, authOptions: const FlutterAuthClientOptions(detectSessionInUri: false), httpClient: _net);
    auth.init();
    entryStore.wire();
    wishlist.wire();
  });

  setUp(() => _swallowed.clear());
  tearDown(() => expect(_swallowed, isEmpty, reason: 'the app swallowed a failure'));

  void liveTest(String name, Future<void> Function() body) => test(name, body, skip: live ? false : 'needs --dart-define=SUPABASE_URL (a throwaway local Supabase)', timeout: const Timeout(Duration(minutes: 2)));

  liveTest('a new diary with a password: the profile and a handle are made on first sight', () async {
    final r = await auth.signUp(mira.email, mira.password, mira.name);
    expect(r.ok, isTrue, reason: r.error);
    await until(() => auth.isAuthed, 'Mira signed in');
    mira.id = auth.meId;
    expect(auth.profile!.name, 'Mira');
    expect(auth.profile!.handle, isNotEmpty);
  });

  liveTest('a new diary with an emailed code (the default sign-in)', () async {
    if (_mailpit.isEmpty) return markTestSkipped('needs MAILPIT_URL');
    await auth.signOut();
    await until(() => !auth.isAuthed, 'signed out');
    final sent = await auth.sendEmailCode(arjun.email, create: true, name: arjun.name);
    expect(sent.ok, isTrue, reason: sent.error);
    final code = await _codeFor(arjun.email);
    final r = await auth.verifyEmailCode(arjun.email, code);
    expect(r.ok, isTrue, reason: r.error);
    await until(() => auth.isAuthed, 'Arjun signed in by code');
    arjun.id = auth.meId;
    expect(auth.profile!.name, 'Arjun');
    // A password too, so the rest of the walk can switch accounts quickly.
    await db!.auth.updateUser(UserAttributes(password: arjun.password));
  });

  late String negroni;
  liveTest('the diary: a drink with a photo lands, shared with friends, and survives a reload', () async {
    await _signIn(mira);
    final today = todayKey();
    final photo = Photo(id: newId(), url: File('test/fixtures/night.jpg').absolute.path);
    final e = entryStore.addEntry(date: today, drink: 'Mezcal Negroni', type: DrinkType.cocktail, mood: 'smoky', venue: 'Soka, Bandra', photos: [photo]);
    negroni = e.id;
    await until(() => entryStore.entries.any((x) => x.id == e.id && (x.photos?.firstOrNull?.url.startsWith('http') ?? false)), 'the photo uploaded');
    entryStore.setVisibility(e.id, EntryVisibility.friends);
    entryStore.addEntry(date: today, drink: 'Lime soda', type: DrinkType.none);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await entryStore.reload();
    final back = entryStore.entries.firstWhere((x) => x.id == e.id);
    expect(back.visibility, EntryVisibility.friends);
    expect(back.photos, hasLength(1));
    expect(entryStore.entries.where((x) => x.date == today), hasLength(2));
    // The picture is really in storage, and anyone with the link can load it.
    final res = await (await HttpClient().getUrl(Uri.parse(back.photos!.single.url))).close();
    expect(res.statusCode, 200);
  });

  liveTest('friends: find by handle, ask, accept — both see each other', () async {
    final arjunHandle = firstRow(await db!.from('profiles').select('handle').eq('id', arjun.id!))!['handle'] as String;
    final found = await FriendsApi.search(arjunHandle);
    expect(found.map((p) => p.id), contains(arjun.id));
    expect(await FriendsApi.sendRequest(arjun.id!), isNull);

    await _signIn(arjun);
    final reqs = await FriendsApi.requests();
    expect(reqs.map((r) => r.profile.id), [mira.id]);
    await FriendsApi.accept(reqs.single.friendshipId);
    expect((await FriendsApi.friends()).map((p) => p.id), [mira.id]);
    await _signIn(mira);
    expect((await FriendsApi.friends()).map((p) => p.id), [arjun.id]);
  });

  liveTest('the feed: a friend sees the shared drink (not the private one), cheers it, comments', () async {
    await _signIn(arjun);
    final feed = await FriendsApi.feed();
    expect(feed.map((f) => f.drink), ['Mezcal Negroni'], reason: 'only what was shared with friends');
    await FriendsApi.toggleCheers(negroni, false);
    await FriendsApi.addComment(negroni, 'Save me one next time.');
    final again = (await FriendsApi.feed()).single;
    expect(again.cheers, 1);
    expect(again.cheered, isTrue);
    expect(again.comments.single.body, 'Save me one next time.');
    expect(again.comments.single.authorName, 'Arjun');
    // A friend's mosaic: the shared days only.
    expect(await FriendsApi.friendDates(mira.id!), [todayKey()]);
  });

  liveTest('a drink logged while the diary is still loading stays — and sharing it lands', () async {
    await _signIn(mira);
    _net.on = true; // the app just opened on a slow network
    final loading = entryStore.reload();
    await Future<void>.delayed(const Duration(milliseconds: 150)); // the read has been answered, slowly on its way back
    final e = entryStore.addEntry(date: todayKey(), drink: 'Espresso tonic', type: DrinkType.coffee);
    await loading;
    _net.on = false;
    expect(entryStore.entries.any((x) => x.id == e.id), isTrue, reason: 'the load answered from before the drink landed — it must not erase it');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    entryStore.setVisibility(e.id, EntryVisibility.friends);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(firstRow(await db!.from('entries').select('visibility').eq('id', e.id))!['visibility'], 'friends');
  });

  liveTest('circles: make one, a friend joins by code, a drink shared into it shows', () async {
    await _signIn(mira);
    expect(await CirclesApi.create('Thursday regulars'), isNull);
    final circle = (await CirclesApi.mine()).single;
    await CirclesApi.share(negroni, circle.id);
    await _signIn(arjun);
    final joined = await CirclesApi.join(circle.inviteCode);
    expect(joined.error, isNull);
    expect(joined.name, 'Thursday regulars');
    final detail = await CirclesApi.detail(circle.id);
    expect(detail.members.map((m) => m.id).toSet(), {mira.id, arjun.id});
    expect(detail.entries.map((e) => e.drink), contains('Mezcal Negroni'));
  });

  liveTest('parties: host one, a guest asks by code, the host approves', () async {
    await _signIn(mira);
    final made = await PartiesApi.create(name: "Mira's birthday", date: todayKey(), venue: 'Soka, Bandra');
    expect(made.error, isNull);
    final party = (await PartiesApi.mine()).firstWhere((p) => p.id == made.id);
    await _signIn(arjun);
    final preview = await PartiesApi.preview(party.inviteCode);
    expect(preview?.name, "Mira's birthday");
    final joined = await PartiesApi.join(party.inviteCode);
    expect(joined.error, isNull);
    expect(joined.pending, isTrue, reason: 'the host approves guests');
    await _signIn(mira);
    var detail = await PartiesApi.detail(party.id);
    expect(detail.guests.firstWhere((g) => g.id == arjun.id).pending, isTrue);
    await PartiesApi.approveGuest(party.id, arjun.id!);
    detail = await PartiesApi.detail(party.id);
    expect(detail.guests.firstWhere((g) => g.id == arjun.id).pending, isFalse);
    await PartiesApi.share(negroni, party.id);
    await _signIn(arjun);
    await PartiesApi.setRsvp(party.id, Rsvp.going);
    expect((await PartiesApi.detail(party.id)).entries.map((e) => e.drink), contains('Mezcal Negroni'));
  });

  liveTest('plans: a friends-only plan, a friend asks to come, the host says yes', () async {
    await _signIn(mira);
    final made = await PlansApi.create(NewPlan(title: 'Rooftop Friday', date: dayKeyIn(3), time: '20:00', city: 'Mumbai', joinPolicy: JoinPolicy.friends));
    expect(made.error, isNull);
    await _signIn(arjun);
    expect((await PlansApi.upcoming()).map((p) => p.title), contains('Rooftop Friday'));
    expect(await PlansApi.requestJoin(made.id!, 'In!'), isNull);
    await _signIn(mira);
    final req = (await PlansApi.requests(made.id!)).single;
    expect(req.name, 'Arjun');
    expect(await PlansApi.respondJoin(req.joinId, true), isNull);
    expect((await PlansApi.requests(made.id!)).single.status, JoinStatus.approved);
  });

  liveTest('Split: an even split between friends, the balance, then settled to zero', () async {
    await _signIn(mira);
    expect(await SplitApi.addExpense(payerId: mira.id!, description: 'Soka round', amount: 1800, participantIds: [mira.id!, arjun.id!]), isNull);
    await _signIn(arjun);
    final s = await SplitApi.load();
    expect(s.expenses.single.shares.map((x) => x.amount), [900, 900]);
    final mine = computeBalances(s.expenses, s.settlements, arjun.id!);
    expect(mine[mira.id], -900, reason: 'Arjun owes Mira half');
    await SplitApi.settleUp(mira.id!, 900, friendOwesMe: false);
    final after = await SplitApi.load();
    expect(computeBalances(after.expenses, after.settlements, arjun.id!)[mira.id] ?? 0, 0);
  });

  liveTest('the to-try list follows the account', () async {
    await _signIn(mira);
    wishlist.add('Yuzu highball');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final saved = rows(await db!.from('wishlist_items').select('drink_name'));
    expect(saved.map((r) => r['drink_name']), contains('Yuzu highball'));
  });

  liveTest('my diary is only mine — a friend\'s shared drinks (feed, circle, party) never land in it', () async {
    // By now Mira's Negroni is shared with friends, into a circle and into a party —
    // all readable by Arjun. None of it may count as Arjun's own diary.
    await _signIn(arjun);
    await entryStore.reload();
    expect(entryStore.entries.where((e) => e.drink == 'Mezcal Negroni'), isEmpty, reason: "Mira's drink is not Arjun's diary");
    entryStore.addEntry(date: todayKey(), drink: 'Pour-over', type: DrinkType.coffee);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _signIn(mira);
    await entryStore.reload();
    expect(entryStore.entries.map((e) => e.drink), isNot(contains('Pour-over')));
    expect(entryStore.entries.map((e) => e.drink), contains('Mezcal Negroni'));
  });

  liveTest('a challenge in the circle: start one, a friend joins, the board counts kinds', () async {
    await _signIn(mira);
    final circle = (await CirclesApi.mine()).single;
    expect(await ChallengesApi.create(circle.id, kind: ChallengeKind.newDrinks, startsOn: dayKeyIn(-1), endsOn: dayKeyIn(6), title: 'Try something new'), isNull);
    final ch = (await ChallengesApi.forCircle(circle.id)).single;
    await _signIn(arjun);
    await ChallengesApi.join(ch.id);
    final board = await ChallengesApi.board((await ChallengesApi.forCircle(circle.id)).single);
    expect(board.map((r) => r.userId).toSet(), {mira.id, arjun.id});
  });

  liveTest('a new handle; the profile page shows a friend counts, never the diary', () async {
    await _signIn(mira);
    final handle = 'mira${_stamp()}';
    expect((await auth.updateHandle(handle)).ok, isTrue);
    expect(auth.profile!.handle, handle);
    await _signIn(arjun);
    final page = await DiscoverApi.publicProfile(handle);
    expect(page, isNotNull, reason: 'friends-only by default, and Arjun is a friend');
    expect(page!.total, greaterThan(0));
  });

  liveTest('safety: block someone (they vanish from search), unblock, report', () async {
    await _signIn(arjun);
    final miraHandle = firstRow(await db!.from('profiles').select('handle').eq('id', mira.id!))!['handle'] as String;
    expect(await SafetyApi.block(mira.id!), isNull);
    expect((await SafetyApi.blocks()).map((b) => b.id), [mira.id]);
    await SafetyApi.unblock(mira.id!);
    expect(await SafetyApi.blocks(), isEmpty);
    expect((await FriendsApi.search(miraHandle)).map((p) => p.id), contains(mira.id));
    expect(await SafetyApi.report(mira.id!, ReportReason.spam, note: 'live test'), isNull);
  });

  // ── the guest meets the bar ───────────────────────────────────────────────
  late String slug, tableCode, venueId;
  liveTest('a verified bar\'s table menu opens from its tag', () async {
    if (_dbUrl.isEmpty) return markTestSkipped('needs LIVE_DB_URL');
    // The owner signs up like anyone; the venue is approved by the maintainer.
    final ira = _Who('Ira');
    expect((await auth.signUp(ira.email, ira.password, ira.name)).ok, isTrue);
    await until(() => auth.isAuthed && auth.profile?.name == 'Ira', 'Ira signed in');
    final owner = auth.meId!;
    slug = 'amber-${_stamp()}';
    venueId = await _sql("insert into public.venues (name, slug, created_by, city, verified, table_service) values ('The Amber Room', '$slug', '$owner', 'Mumbai', true, true) returning id");
    await _sql("insert into public.venue_staff (venue_id, user_id, role) values ('$venueId', '$owner', 'owner') on conflict do nothing");
    await _sql("insert into public.venue_menu_items (venue_id, section, name, price, kind, station, position) values ('$venueId', 'Cocktails', 'Negroni', 650, 'cocktail', 'bar', 0), ('$venueId', 'Zero proof', 'Kokum Cooler', 220, 'soft', 'bar', 1)");
    await _sql("update public.venue_menu_items set no_alcohol = true where venue_id = '$venueId' and name = 'Kokum Cooler'");
    tableCode = await _sql("insert into public.venue_tables (venue_id, label, seats) values ('$venueId', 'T4', 4) returning code");

    await _signIn(arjun);
    final menu = await MenuApi.load(slug);
    expect(menu?.venueName, 'The Amber Room');
    expect(menu!.sections.expand((s) => s.items).map((i) => i.name), containsAll(['Negroni', 'Kokum Cooler']));
    final info = await TableApi.info(tableCode);
    expect(info?.tableLabel, 'T4');
    expect(info?.tableService, isTrue);
  });

  liveTest('taste at the table: shared with the bar for the night, the bar sees the taste card', () async {
    if (_dbUrl.isEmpty) return markTestSkipped('needs LIVE_DB_URL');
    await _signIn(arjun);
    final taste = TasteShareStore.instance;
    await taste.setConsent(true);
    await taste.setAllergies(['peanuts']);
    final share = await taste.share(code: tableCode);
    expect(share?.venueName, 'The Amber Room');
    expect((await taste.mine()).map((s) => s.venueId), [venueId]);
    final card = await taste.guestCode();
    expect(card?.code, matches(RegExp(r'^[A-Z0-9]{6}$')));

    // The bar's side (the owner, signed in): the taste card — never the diary.
    final staffEmail = await _sql("select u.email from auth.users u join public.venues v on v.created_by = u.id where v.id = '$venueId'");
    await auth.signOut();
    await until(() => !auth.isAuthed, 'signed out');
    expect((await auth.signIn(staffEmail, 'night-out-2026')).ok, isTrue);
    await until(() => auth.isAuthed && auth.profile?.name == 'Ira', 'Ira signed in');
    final tonight = rows(await db!.rpc('venue_guests_tonight', params: {'vid': venueId}));
    expect(tonight.map((r) => r['name']), ['Arjun']);
    expect((tonight.single['taste'] as Map)['allergies'], ['peanuts']);
    expect((tonight.single['taste'] as Map).containsKey('entries'), isFalse);
  });

  liveTest('ordering from the table: a request (never a price), then "bill please"', () async {
    if (_dbUrl.isEmpty) return markTestSkipped('needs LIVE_DB_URL');
    await _signIn(arjun);
    final kokum = await _sql("select id from public.venue_menu_items where venue_id = '$venueId' and name = 'Kokum Cooler'");
    await TableApi.order(tableCode, [{'item': kokum, 'qty': 2}], note: 'less ice');
    final mine = await TableApi.mine();
    expect(mine.first.status, 'pending');
    expect(mine.first.lines.single.qty, 2);
    await TableApi.call(tableCode, 'bill');
    expect(await _sql("select count(*) from public.table_calls where venue_id = '$venueId'"), '1');
  });

  liveTest('export everything: the diary, friends, circles, parties, plans, Split', () async {
    await _signIn(mira);
    final b = await ExportBundle.collect();
    expect(b.entries.map((e) => e.drink), contains('Mezcal Negroni'));
    expect(b.friends, hasLength(1));
    expect(b.circles.single.name, 'Thursday regulars');
    expect(b.parties.map((p) => p.name), contains("Mira's birthday"));
    expect(b.plans.map((p) => p.title), contains('Rooftop Friday'));
    expect(b.expenses.single.amount, 1800);
  });

  liveTest('removing a drink puts it away, never deletes it', () async {
    await _signIn(mira);
    final soda = entryStore.entries.firstWhere((e) => e.drink == 'Lime soda');
    entryStore.deleteEntry(soda.id);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await entryStore.reload();
    expect(entryStore.entries.any((e) => e.id == soda.id), isFalse);
    expect(await entryStore.archivedCount(), 1);
  });

  liveTest('delete my account: really gone — the diary, the photos, the friendship', () async {
    if (!_siteGiven || _dbUrl.isEmpty) return markTestSkipped('needs SITE_URL (the website, running) and LIVE_DB_URL');
    await _signIn(mira);
    final photos = await _sql("select count(*) from storage.objects where bucket_id = 'photos' and name like '${mira.id}/%'");
    expect(int.parse(photos), greaterThan(0), reason: 'a photo to erase');
    expect(await AccountApi.deleteAccount(), isNull);
    await until(() => !auth.isAuthed, 'signed out after deletion');
    expect(await _sql("select count(*) from auth.users where id = '${mira.id}'"), '0');
    expect(await _sql("select count(*) from public.entries where user_id = '${mira.id}'"), '0', reason: 'erasure, not archiving');
    expect(await _sql("select count(*) from public.friendships where requester_id = '${mira.id}' or addressee_id = '${mira.id}'"), '0');
    expect(await _sql("select count(*) from storage.objects where bucket_id = 'photos' and name like '${mira.id}/%'"), '0', reason: 'the photo files go too');
  });
}

String dayKeyIn(int days) => toKey(addDays(appNow(), days));
