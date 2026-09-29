// The demo venue: a seeded bar and a sweet shop that live entirely on this phone.
//
// It powers the app when no Supabase values are built in — screenshots, the widget
// tests, and showing an owner what the app does before they sign up. It keeps the
// same rules the database enforces where a demo would otherwise mislead (a perk can't
// be claimed before it's earned, a card is punched once a day, a sweet shop's reward
// is never alcohol), so what you see here is what you'd get for real.
import 'dart:async';
import 'dart:math' as math;

import 'backend.dart';
import 'models.dart';
import 'prefs.dart';
import '../logic/area.dart' show HeatRow;
import '../logic/host_brief.dart';
import '../logic/roles.dart';
import '../logic/venue_kinds.dart';

class DemoBackend implements Backend {
  DemoBackend._();

  @override
  bool get isDemo => true;

  static const me = AppUser(id: 'demo-me', email: 'you@demo.local', name: 'You (demo)', handle: 'demo-owner');

  AppUser? _user;
  final _auth = StreamController<AppUser?>.broadcast();

  final List<Venue> _venues = [];
  final Map<String, List<StaffMember>> _staff = {};
  final Map<String, List<Room>> _rooms = {};
  final Map<String, List<RoomGuest>> _guests = {};
  final Map<String, List<MenuItem>> _menu = {};
  final Map<String, List<PerkTier>> _perks = {};
  final Map<String, VerificationRequest> _verifications = {};
  final Map<String, GuestCard> _cards = {}; // key: venueId|guestId
  final Map<String, double> _progress = {}; // key: perkId|guestId
  final Map<String, int> _claims = {};
  final Set<String> _punched = {}; // venueId|guestId|day
  final Map<String, Set<String>> _vibes = {}; // roomId|guestId → reasons

  static final _people = [
    const ProfileHit(id: 'g-anita', handle: 'anita', name: 'Anita'),
    const ProfileHit(id: 'g-rohan', handle: 'rohan', name: 'Rohan'),
    const ProfileHit(id: 'g-meera', handle: 'meera', name: 'Meera'),
    const ProfileHit(id: 'g-kabir', handle: 'kabir', name: 'Kabir'),
    const ProfileHit(id: 'g-zoya', handle: 'zoya', name: 'Zoya'),
    const ProfileHit(id: 'g-dev', handle: 'dev', name: 'Dev'),
    const ProfileHit(id: 's-ira', handle: 'ira', name: 'Ira'),
    const ProfileHit(id: 's-sam', handle: 'sam', name: 'Sam'),
    const ProfileHit(id: 's-noor', handle: 'noor', name: 'Noor'),
  ];

  /// A demo venue already signed in — or, with [signedIn] false, the sign-in screen.
  factory DemoBackend.seeded({bool signedIn = true}) {
    final b = DemoBackend._();
    b._seed();
    if (signedIn) b._user = me;
    return b;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _seed() {
    const bar = Venue(
      id: 'demo-bar',
      name: 'The Amber Room',
      slug: 'the-amber-room',
      createdBy: 'demo-me',
      city: 'Bengaluru',
      kind: VenueKind.bar,
      servesAlcohol: true,
      country: 'IN',
      currency: 'INR',
      quietNights: [2],
      geohash: 'tdr1v9',
      areaShare: true,
      verified: true,
      myRole: StaffRole.owner,
    );
    const sweets = Venue(
      id: 'demo-sweets',
      name: 'Mithai Mahal',
      slug: 'mithai-mahal',
      createdBy: 's-ira',
      city: 'Bengaluru',
      kind: VenueKind.sweetShop,
      servesAlcohol: false,
      country: 'IN',
      currency: 'INR',
      geohash: 'tdr1',
      verified: true,
      myRole: StaffRole.manager,
    );
    _venues.addAll([bar, sweets]);

    _staff[bar.id] = [
      const StaffMember(id: 'demo-me', handle: 'demo-owner', name: 'You (demo)', role: StaffRole.owner),
      const StaffMember(id: 's-ira', handle: 'ira', name: 'Ira', role: StaffRole.manager),
      const StaffMember(id: 's-sam', handle: 'sam', name: 'Sam', role: StaffRole.bartender),
      const StaffMember(id: 's-noor', handle: 'noor', name: 'Noor', role: StaffRole.server),
    ];
    _staff[sweets.id] = [
      const StaffMember(id: 's-ira', handle: 'ira', name: 'Ira', role: StaffRole.owner),
      const StaffMember(id: 'demo-me', handle: 'demo-owner', name: 'You (demo)', role: StaffRole.manager),
    ];

    final today = _day(DateTime.now());
    final room = Room(id: 'demo-room', name: 'The Amber Room · tonight', date: today, inviteCode: 'amberfox', boardUntil: DateTime.now().add(const Duration(hours: 5)));
    _rooms[bar.id] = [room];
    _rooms[sweets.id] = [];
    _guests[room.id] = [for (final p in _people.where((p) => p.id.startsWith('g-'))) RoomGuest(id: p.id, name: p.name)];

    _menu[bar.id] = [
      const MenuItem(id: 'm1', section: 'Cocktails', name: 'Negroni', price: 450, kind: 'cocktail', position: 0),
      const MenuItem(id: 'm2', section: 'Cocktails', name: 'Espresso Martini', price: 520, kind: 'cocktail', position: 1),
      const MenuItem(id: 'm3', section: 'Beer', name: 'Hazy IPA (pint)', price: 380, kind: 'beer', position: 2),
      const MenuItem(id: 'm4', section: 'Zero proof', name: 'Kokum Cooler', price: 220, kind: 'soft', noAlcohol: true, position: 3),
      const MenuItem(id: 'm5', section: 'Food', name: 'Masala Fries', price: 260, kind: 'food', position: 4),
    ];
    _menu[sweets.id] = [
      const MenuItem(id: 'k1', section: 'Sweets', name: 'Kaju Katli (250 g)', price: 360, kind: 'food', noAlcohol: true, position: 0),
      const MenuItem(id: 'k2', section: 'Sweets', name: 'Motichoor Ladoo (250 g)', price: 240, kind: 'food', noAlcohol: true, position: 1),
      const MenuItem(id: 'k3', section: 'Drinks', name: 'Masala Chai', price: 40, kind: 'tea', noAlcohol: true, position: 2),
    ];

    _perks[bar.id] = [
      const PerkTier(id: 'p1', kind: PerkKind.visits, threshold: 3, reward: 'A coffee on us'),
      const PerkTier(id: 'p2', kind: PerkKind.visits, threshold: 10, reward: 'A dessert on us'),
    ];
    _perks[sweets.id] = [
      const PerkTier(id: 'p3', kind: PerkKind.visits, threshold: 5, reward: '100 g of kaju katli'),
    ];

    // Anita has earned the coffee; Rohan is close.
    _progress['p1|g-anita'] = 3;
    _progress['p2|g-anita'] = 6;
    _progress['p1|g-rohan'] = 2;
    _progress['p2|g-rohan'] = 2;

    final now = DateTime.now();
    _cards['${bar.id}|g-anita'] = GuestCard(
      visits: 6,
      firstSeen: now.subtract(const Duration(days: 58)),
      lastSeen: now,
      tabs: 5,
      totalSpend: 9400,
      perksClaimed: 1,
      hasEarned: true,
      beenHere: true,
      note: 'Likes her Negroni with less Campari. Celebrating a new job this month.',
      tags: const ['regular', 'less bitter'],
    );
    for (final g in _people.where((p) => p.id.startsWith('g-') && p.id != 'g-anita')) {
      _cards['${bar.id}|${g.id}'] = GuestCard(visits: 1 + g.name.length % 4, firstSeen: now.subtract(Duration(days: 3 + g.name.length * 4)), lastSeen: now, tabs: 1, totalSpend: 1200.0 + g.name.length * 150, beenHere: true);
    }
  }

  void _needUser() {
    if (_user == null) throw const BackendError('Sign in first.');
  }

  Venue _venue(String id) => _venues.firstWhere((v) => v.id == id, orElse: () => throw const BackendError('No such venue.'));

  // ── auth ──────────────────────────────────────────────────────────────────
  @override
  AppUser? get currentUser => _user;
  @override
  Stream<AppUser?> get authChanges => _auth.stream;

  @override
  Future<void> signInWithPassword(String email, String password) async {
    if (!email.contains('@')) throw const BackendError('That email doesn\'t look right.');
    if (password.length < 6) throw const BackendError('Wrong email or password.');
    _user = me;
    _auth.add(_user);
  }

  @override
  Future<void> sendEmailCode(String email, {bool create = false, String? name}) async {
    if (!email.contains('@')) throw const BackendError('That email doesn\'t look right.');
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    if (code.trim().length != 6) throw const BackendError('That code didn\'t work — check it and try again.');
    _user = me;
    _auth.add(_user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _auth.add(null);
  }

  // ── venues ────────────────────────────────────────────────────────────────
  @override
  Future<List<Venue>> myVenues() async {
    _needUser();
    return List.unmodifiable(_venues);
  }

  @override
  Future<Venue> createVenue({
    required String name,
    required String slug,
    String? city,
    required VenueKind kind,
    bool servesAlcohol = false,
    required String country,
    String? region,
  }) async {
    _needUser();
    if (_venues.any((v) => v.slug == slug)) throw const BackendError('That address is taken — try another.');
    final v = Venue(
      id: newId(),
      name: name,
      slug: slug,
      createdBy: me.id,
      city: city,
      kind: kind,
      servesAlcohol: kind.alwaysAlcohol || (kind.alcoholIsChoice && servesAlcohol),
      country: country,
      region: region,
      myRole: StaffRole.owner,
    );
    _venues.add(v);
    _staff[v.id] = [StaffMember(id: me.id, handle: me.handle, name: me.name, role: StaffRole.owner)];
    _rooms[v.id] = [];
    _menu[v.id] = [];
    _perks[v.id] = [];
    venueRev.bump();
    return v;
  }

  @override
  Future<void> updateVenue(String venueId, {String? name, String? city, List<int>? quietNights, String? geohash, bool? servesAlcohol, bool? areaShare}) async {
    final i = _venues.indexWhere((v) => v.id == venueId);
    if (i < 0) throw const BackendError('No such venue.');
    final v = _venues[i];
    if (name != null && name.trim().isEmpty) throw const BackendError('Name can\'t be empty.');
    _venues[i] = v.copyWith(
      name: name?.trim(),
      city: city?.trim(),
      quietNights: quietNights,
      geohash: geohash,
      areaShare: areaShare,
      servesAlcohol: servesAlcohol == null || !v.kind.alcoholIsChoice ? null : servesAlcohol,
    );
    venueRev.bump();
  }

  @override
  Future<void> deleteVenue(String venueId) async {
    final v = _venue(venueId);
    if (v.myRole != StaffRole.owner) throw const BackendError('Only the owner can delete a venue.');
    _venues.removeWhere((x) => x.id == venueId);
    venueRev.bump();
  }

  @override
  Future<VerificationRequest?> verification(String venueId) async => _verifications[venueId];

  @override
  Future<void> requestVerification(String venueId, String contact, {String? note}) async {
    if (contact.trim().length < 3) throw const BackendError('Add a phone or email we can reach you on.');
    _verifications[venueId] = VerificationRequest(status: VerificationStatus.pending, contact: contact.trim(), note: note, createdAt: DateTime.now());
    venueRev.bump();
  }

  @override
  Future<void> withdrawVerification(String venueId) async {
    _verifications.remove(venueId);
    venueRev.bump();
  }

  // ── team ──────────────────────────────────────────────────────────────────
  @override
  Future<List<StaffMember>> staff(String venueId) async {
    final list = [...?_staff[venueId]];
    list.sort((a, b) => a.role.rank != b.role.rank ? a.role.rank.compareTo(b.role.rank) : a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<List<ProfileHit>> searchPeople(String query) async {
    final q = query.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (q.length < 2) return const [];
    return _people.where((p) => p.name.toLowerCase().contains(q) || p.handle.contains(q)).toList();
  }

  StaffRole _myRole(String venueId) => _venue(venueId).myRole;

  @override
  Future<void> addStaff(String venueId, String userId, StaffRole role) async {
    if (!canGrant(_myRole(venueId), role)) throw const BackendError('You can\'t give that role.');
    final list = _staff[venueId] ??= [];
    if (list.any((s) => s.id == userId)) return;
    final p = _people.firstWhere((p) => p.id == userId, orElse: () => ProfileHit(id: userId, handle: userId, name: userId));
    list.add(StaffMember(id: p.id, handle: p.handle, name: p.name, role: role));
    staffRev.bump();
  }

  @override
  Future<void> setStaffRole(String venueId, String userId, StaffRole role) async {
    final list = _staff[venueId] ?? [];
    final i = list.indexWhere((s) => s.id == userId);
    if (i < 0) throw const BackendError('They\'re not on the team.');
    final mine = _myRole(venueId);
    if (!canGrant(mine, role) || !canGrant(mine, list[i].role)) throw const BackendError('You can\'t change that role.');
    final s = list[i];
    list[i] = StaffMember(id: s.id, handle: s.handle, name: s.name, role: role, thankable: s.thankable);
    staffRev.bump();
  }

  @override
  Future<void> removeStaff(String venueId, String userId) async {
    final list = _staff[venueId] ?? [];
    final target = list.where((s) => s.id == userId).firstOrNull;
    if (target == null) return;
    if (userId != me.id && !canGrant(_myRole(venueId), target.role)) throw const BackendError('You can\'t remove them.');
    list.removeWhere((s) => s.id == userId);
    staffRev.bump();
  }

  @override
  Future<void> setThankable(String venueId, bool thankable) async {
    final list = _staff[venueId] ?? [];
    final i = list.indexWhere((s) => s.id == me.id);
    if (i < 0) return;
    final s = list[i];
    list[i] = StaffMember(id: s.id, handle: s.handle, name: s.name, role: s.role, thankable: thankable);
    staffRev.bump();
  }

  @override
  Future<StaffInvite> createInvite(String venueId, StaffRole role) async {
    if (!canGrant(_myRole(venueId), role)) throw const BackendError('You can\'t invite someone as that.');
    final r = math.Random();
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    final code = List.generate(8, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    return StaffInvite(code: code, role: role, expiresAt: DateTime.now().add(const Duration(days: 7)));
  }

  @override
  Future<String> acceptInvite(String code) async {
    if (code.trim().length < 6) throw const BackendError('That invite code didn\'t work.');
    return _venues.first.name;
  }

  // ── tonight ───────────────────────────────────────────────────────────────
  @override
  Future<List<Room>> rooms(String venueId) async => [...?_rooms[venueId]];

  @override
  Future<Room> openRoom(Venue venue, {int boardHours = 6}) async {
    if (venue.kind.isCounter) throw const BackendError('A counter doesn\'t run rooms — it punches cards at the till.');
    final code = newId().replaceAll('-', '').substring(0, 8);
    final room = Room(id: newId(), name: '${venue.name} · tonight', date: _day(DateTime.now()), inviteCode: code, boardUntil: DateTime.now().add(Duration(hours: boardHours)));
    (_rooms[venue.id] ??= []).insert(0, room);
    _guests[room.id] = [];
    roomsRev.bump();
    return room;
  }

  @override
  Future<List<RoomGuest>> roomGuests(String roomId) async => [...?_guests[roomId]];

  @override
  Future<void> giveVibe(String roomId, String guestId, String reason) async {
    final set = _vibes['$roomId|$guestId'] ??= {};
    if (!set.add(reason)) throw const BackendError('You\'ve already said that tonight.');
  }

  @override
  Future<void> recordSpend(String roomId, String guestId, double amount) async {
    if (amount <= 0) throw const BackendError('Amount must be positive.');
    final venueId = _rooms.entries.firstWhere((e) => e.value.any((r) => r.id == roomId)).key;
    final key = '$venueId|$guestId';
    final c = _cards[key] ?? const GuestCard(beenHere: true);
    _cards[key] = GuestCard(
      visits: c.visits,
      firstSeen: c.firstSeen,
      lastSeen: DateTime.now(),
      tabs: c.tabs + 1,
      totalSpend: c.totalSpend + amount,
      perksClaimed: c.perksClaimed,
      hasEarned: c.hasEarned,
      beenHere: true,
      note: c.note,
      tags: c.tags,
    );
    for (final p in _perks[venueId] ?? const <PerkTier>[]) {
      if (p.kind == PerkKind.spend) _progress['${p.id}|$guestId'] = (_progress['${p.id}|$guestId'] ?? 0) + amount;
    }
    guestsRev.bump();
  }

  @override
  Future<List<PerkStanding>> perkStatus(String venueId, String guestId) async => [
        for (final p in _perks[venueId] ?? const <PerkTier>[])
          PerkStanding(
            perkId: p.id,
            kind: p.kind,
            threshold: p.threshold,
            reward: p.reward,
            currency: p.currency,
            progress: _progress['${p.id}|$guestId'] ?? 0,
            earned: (_progress['${p.id}|$guestId'] ?? 0) >= p.threshold,
            claims: _claims['${p.id}|$guestId'] ?? 0,
          ),
      ];

  @override
  Future<void> redeemPerk(String perkId, String guestId) async {
    final key = '$perkId|$guestId';
    final tier = _perks.values.expand((l) => l).firstWhere((p) => p.id == perkId, orElse: () => throw const BackendError('No such perk.'));
    if ((_progress[key] ?? 0) < tier.threshold) throw const BackendError('Not earned yet.');
    _progress[key] = 0; // progress counts since the last claim
    _claims[key] = (_claims[key] ?? 0) + 1;
    guestsRev.bump();
  }

  @override
  Future<void> recordVisit(String venueId, String guestId) async {
    if (guestId == me.id) throw const BackendError('You cannot punch your own card.');
    final key = '$venueId|$guestId|${_day(DateTime.now())}';
    if (!_punched.add(key)) return; // twice in a day is once
    for (final p in _perks[venueId] ?? const <PerkTier>[]) {
      if (p.kind == PerkKind.visits) {
        final quiet = _venue(venueId).quietNights.contains(DateTime.now().weekday % 7);
        _progress['${p.id}|$guestId'] = (_progress['${p.id}|$guestId'] ?? 0) + (quiet ? 2 : 1);
      }
    }
    final c = _cards['$venueId|$guestId'];
    _cards['$venueId|$guestId'] = GuestCard(
      visits: (c?.visits ?? 0) + 1,
      firstSeen: c?.firstSeen ?? DateTime.now(),
      lastSeen: DateTime.now(),
      tabs: c?.tabs ?? 0,
      totalSpend: c?.totalSpend ?? 0,
      perksClaimed: c?.perksClaimed ?? 0,
      beenHere: true,
      note: c?.note ?? '',
      tags: c?.tags ?? const [],
    );
    guestsRev.bump();
  }

  // ── menu ──────────────────────────────────────────────────────────────────
  @override
  Future<List<MenuItem>> menu(String venueId) async {
    final l = [...?_menu[venueId]]..sort((a, b) => a.position.compareTo(b.position));
    return l;
  }

  @override
  Future<void> saveMenuItem(String venueId, MenuItem item, {bool isNew = false}) async {
    final l = _menu[venueId] ??= [];
    if (isNew) {
      if (l.length >= 400) throw const BackendError('A menu holds at most 400 items.');
      l.add(item);
    } else {
      final i = l.indexWhere((x) => x.id == item.id);
      if (i >= 0) l[i] = item;
    }
    menuRev.bump();
  }

  @override
  Future<void> removeMenuItem(String itemId) async {
    for (final l in _menu.values) {
      l.removeWhere((x) => x.id == itemId);
    }
    menuRev.bump();
  }

  // ── perks ─────────────────────────────────────────────────────────────────
  @override
  Future<List<PerkTier>> perks(String venueId) async {
    final l = [...?_perks[venueId]]..sort((a, b) => a.threshold.compareTo(b.threshold));
    return l;
  }

  @override
  Future<void> addPerk(String venueId, {required PerkKind kind, required double threshold, required String reward, bool rewardAlcoholic = false}) async {
    final v = _venue(venueId);
    final l = _perks[venueId] ??= [];
    if (!v.verified) throw const BackendError('Perks start once your venue is verified.');
    if (l.length >= 3) throw const BackendError('Three tiers is the most — a card people can remember.');
    if (rewardAlcoholic && !v.sellsAlcohol) throw const BackendError('This venue doesn\'t sell alcohol, so its reward can\'t be a drink with alcohol.');
    if (v.kind == VenueKind.store && (rewardAlcoholic || kind == PerkKind.spend)) {
      throw const BackendError('A liquor store\'s card counts visits and never rewards with alcohol.');
    }
    l.add(PerkTier(id: newId(), kind: kind, threshold: threshold, reward: reward.trim(), rewardAlcoholic: rewardAlcoholic, currency: v.currency));
    perksRev.bump();
  }

  @override
  Future<void> removePerk(String perkId) async {
    for (final l in _perks.values) {
      l.removeWhere((p) => p.id == perkId);
    }
    perksRev.bump();
  }

  // ── insights & the area ───────────────────────────────────────────────────
  @override
  Future<VenueInsights?> insights(String venueId, {int days = 30}) async {
    final shop = _venue(venueId).kind.isCounter;
    return VenueInsights(
      rooms: shop ? 0 : 18,
      guests: shop ? 41 : 64,
      newGuests: shop ? 12 : 22,
      returningGuests: shop ? 29 : 42,
      quietVisits: shop ? 6 : 14,
      otherVisits: shop ? 58 : 120,
      perksEarned: shop ? 5 : 9,
      perksClaimed: shop ? 7 : 11,
      tabs: shop ? 0 : 96,
      takings: shop ? 0 : 214500,
      kudos: shop ? 3 : 27,
      visitsByDow: shop ? const [11, 6, 5, 7, 8, 12, 15] : const [14, 6, 3, 9, 18, 36, 48],
      prevGuests: shop ? 37 : 55,
      prevTakings: shop ? 0 : 188000,
    );
  }

  @override
  Future<List<AreaTrend>> areaTrends(String geohash, {int days = 30}) async => const [
        AreaTrend(kind: 'drink', name: 'Hazy IPA', users: 23),
        AreaTrend(kind: 'drink', name: 'Filter coffee', users: 19),
        AreaTrend(kind: 'drink', name: 'Espresso Martini', users: 14),
        AreaTrend(kind: 'drink', name: 'Kombucha', users: 8),
        AreaTrend(kind: 'mood', name: 'cozy', users: 17),
        AreaTrend(kind: 'mood', name: 'celebratory', users: 11),
      ];

  @override
  Future<List<HeatRow>> areaMap(String venueId, {int days = 30, String tz = 'UTC'}) async {
    final v = _venue(venueId);
    if (!v.verified) throw const BackendError('The area map opens once your venue is verified.');
    if ((v.geohash ?? '').length < 5) throw const BackendError('Set your venue\'s location first (Setup).');
    final area = v.geohash!.substring(0, 4);
    // A made-up Bengaluru evening: a busy centre, coffee to the south, zero-proof east.
    // Every figure a multiple of 5, as the real map returns them.
    const seed = <String, (int, Map<String, int>, Map<String, int>, Map<String, int>, int?)>{
      'v': (45, {'cocktails': 15, 'explorer': 10, 'beer': 10, 'coffee_tea': 5}, {'cocktail': 25, 'beer': 20, 'coffee': 15, 'soft': 10}, {'evening': 25, 'late': 20}, 1000),
      'y': (30, {'beer': 10, 'cocktails': 10, 'zero_proof': 5}, {'beer': 20, 'cocktail': 10, 'soft': 10}, {'evening': 15, 'late': 10}, 1000),
      'u': (25, {'coffee_tea': 15, 'explorer': 5}, {'coffee': 20, 'tea': 10}, {'morning': 10, 'afternoon': 10}, 500),
      't': (20, {'coffee_tea': 10, 'wine': 5}, {'coffee': 15, 'wine': 5}, {'afternoon': 10, 'evening': 5}, 500),
      'w': (15, {'zero_proof': 10}, {'soft': 10, 'coffee': 5}, {'evening': 10}, null),
      's': (10, {'coffee_tea': 5}, {'coffee': 10}, {'morning': 5}, 0),
      'g': (10, {'wine': 5}, {'wine': 5, 'cocktail': 5}, {'evening': 5}, 2500),
      'z': (5, {}, {'beer': 5}, {'late': 5}, null),
      'k': (15, {'coffee_tea': 5, 'zero_proof': 5}, {'coffee': 10, 'soft': 5}, {'morning': 5, 'afternoon': 5}, 500),
      'm': (10, {'explorer': 5}, {'wine': 5, 'beer': 5}, {'evening': 5}, 1000),
      '7': (5, {}, {'tea': 5}, {'afternoon': 5}, null),
    };
    final days_ = days <= 7 ? 7 : (days <= 30 ? 30 : 90);
    final scale = days_ == 7 ? 0.4 : (days_ == 90 ? 1.6 : 1.0);
    int k(int n) => ((n * scale) ~/ 5) * 5;
    final rows = <HeatRow>[];
    seed.forEach((ch, d) {
      final cell = '$area$ch';
      if (k(d.$1) < 5) return;
      rows.add(HeatRow(cell, 'people', '', k(d.$1)));
      d.$2.forEach((l, n) {
        if (k(n) >= 5) rows.add(HeatRow(cell, 'persona', l, k(n)));
      });
      d.$3.forEach((l, n) {
        if (k(n) >= 5) rows.add(HeatRow(cell, 'taste', l, k(n)));
      });
      d.$4.forEach((l, n) {
        if (k(n) >= 5) rows.add(HeatRow(cell, 'hours', l, k(n)));
      });
      if (v.areaShare && d.$5 != null) rows.add(HeatRow(cell, 'spend', '${d.$5}', k(d.$1)));
    });
    return rows;
  }

  @override
  Future<List<AreaSignal>> areaSignals(String venueId, {int daysAhead = 14}) async {
    final v = _venue(venueId);
    if (!v.verified || (v.geohash ?? '').length < 4) return const [];
    final area = v.geohash!.substring(0, 4);
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day);
    return [
      AreaSignal(id: 's1', kind: 'event', title: 'Dussehra fair at the palace grounds', detail: 'Three evenings of stalls and music; the road closes from 5 pm.', startsOn: d.add(const Duration(days: 2)), endsOn: d.add(const Duration(days: 4)), cell: '${area}y', source: 'city events listing'),
      AreaSignal(id: 's2', kind: 'holiday', title: 'Dry day: Gandhi Jayanti', detail: 'No alcohol may be sold in the state for the day.', startsOn: d.add(const Duration(days: 3)), source: 'state excise calendar'),
      AreaSignal(id: 's3', kind: 'opening', title: 'A new brewpub opened on 12th Main', cell: '${area}v', facts: const {'rating': 4.4, 'review_count': 120}, source: 'maps listing'),
      const AreaSignal(id: 's4', kind: 'price', title: 'A craft pint nearby costs ₹350–450', facts: {'price_min': 350, 'price_max': 450}, source: 'menu survey'),
      AreaSignal(id: 's5', kind: 'event', title: 'Cricket final, big screens across town', startsOn: d.add(const Duration(days: 6)), source: 'sports calendar'),
    ];
  }

  @override
  Future<int> teamKudos(String venueId, {int days = 30}) async => _venue(venueId).kind.isCounter ? 3 : 27;

  @override
  Future<List<KudosLine>> myKudos(String venueId) async => const [KudosLine('looked after us', 6), KudosLine('great recommendation', 4), KudosLine('quick and kind', 2)];

  // ── guest book ────────────────────────────────────────────────────────────
  @override
  Future<GuestCard?> guestCard(String venueId, String guestId) async => _cards['$venueId|$guestId'] ?? const GuestCard();

  @override
  Future<void> setGuestNote(String venueId, String guestId, String body, List<String> tags) async {
    final c = _cards['$venueId|$guestId'];
    if (c == null || !c.beenHere) throw const BackendError('You can only note a guest who has been to your venue.');
    _cards['$venueId|$guestId'] = GuestCard(
      visits: c.visits,
      firstSeen: c.firstSeen,
      lastSeen: c.lastSeen,
      tabs: c.tabs,
      totalSpend: c.totalSpend,
      perksClaimed: c.perksClaimed,
      hasEarned: c.hasEarned,
      beenHere: true,
      note: body.length > 2000 ? body.substring(0, 2000) : body,
      tags: tags.take(12).toList(),
    );
    guestsRev.bump();
  }

  // ── Ninkasi ───────────────────────────────────────────────────────────────
  @override
  Stream<String> advise(Map<String, dynamic> brief, List<Map<String, String>> messages) async* {
    final text = messages.isEmpty
        ? 'This is the demo venue, so I\'m reading made-up numbers — but here is how I\'d read them. Friday and Saturday carry the week and Tuesday is nearly empty: you\'ve already marked it quiet, so tell your regulars a Tuesday visit counts double toward their card. Your team was thanked 27 times this month — say so at the next pre-shift.'
        : 'In the demo I answer from a script. Sign in with your real venue and I\'ll read your own numbers — totals only, never a single guest.';
    for (final w in text.split(' ')) {
      await Future<void>.delayed(const Duration(milliseconds: 8));
      yield '$w ';
    }
  }

  @override
  Stream<String> askHost(HostBrief brief, List<Map<String, String>> messages) async* {
    final q = messages.lastWhere((m) => m['role'] == 'user', orElse: () => const {'content': ''})['content'] ?? '';
    for (final w in hostFallbackAnswer(brief, q).split(' ')) {
      await Future<void>.delayed(const Duration(milliseconds: 6));
      yield '$w ';
    }
  }
}
