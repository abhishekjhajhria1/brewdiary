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
import '../logic/service.dart' show nightStart;
import '../logic/staff.dart';
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

  // Service (051): the floor, tabs, lines, the inbox, the waitlist, per venue.
  final Map<String, List<VenueArea>> _areas = {};
  final Map<String, List<VenueTable>> _tables = {};
  final Map<String, List<ServiceTab>> _tabs = {}; // all tabs, any status
  final Map<String, List<OrderLine>> _lines = {}; // tabId → lines
  final Map<String, List<InboxItem>> _inbox = {};
  final Map<String, List<WaitParty>> _wait = {};
  final Map<String, List<Map<String, Object>>> _payments = {}; // tabId → payments

  // The counter (050): a shelf, a stock ledger, suppliers and sales per venue.
  final Map<String, List<ShopProduct>> _products = {};
  final List<({String venueId, String productId, int qty, String reason, DateTime at})> _moves = [];
  final Map<String, List<ShopSupplier>> _suppliers = {};
  final Map<String, double> _sales = {}; // saleId → total (a retry returns it)

  // Staff access (053): codes not typed yet, where "you" wait or are paused, the history,
  // the clock. The same rules the database keeps, so the demo never shows a power the real
  // app wouldn't have.
  final List<_Code> _codes = []; // every venue's codes; [_Code.forMe] = one that added "you"
  final List<StaffAccess> _myAccess = [];
  final Map<String, List<({String? subjectId, StaffEvent e})>> _history = {}; // venueId → newest first
  final Map<String, DateTime> _onShift = {}; // venueId|userId → since
  final Map<String, int> _weekMinutes = {}; // venueId|userId → minutes this week, finished shifts
  final Map<String, StaffRole> _invites = {}; // invite code → role (for this venue list)
  int _eventId = 100;

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
      tableService: true,
      capacity: 120,
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
    const cellar = Venue(
      id: 'demo-cellar',
      name: 'Cellar Door Wines',
      slug: 'cellar-door',
      createdBy: 'demo-me',
      city: 'Bengaluru',
      kind: VenueKind.store,
      servesAlcohol: true,
      country: 'IN',
      region: 'KA',
      currency: 'INR',
      geohash: 'tdr1v9',
      verified: true,
      myRole: StaffRole.owner,
    );
    _venues.addAll([bar, sweets, cellar]);
    _staff[cellar.id] = [const StaffMember(id: 'demo-me', handle: 'demo-owner', name: 'You (demo)', role: StaffRole.owner)];
    _rooms[cellar.id] = [];
    _menu[cellar.id] = [];
    _perks[cellar.id] = [const PerkTier(id: 'p4', kind: PerkKind.visits, threshold: 6, reward: 'A bag of ice on us')];
    _products[cellar.id] = const [
      ShopProduct(id: 'w1', name: 'Single Malt', brand: 'Amrut', category: 'spirit', size: 750, unit: 'ml', price: 3400, mrp: 3500, barcode: '8901234000011'),
      ShopProduct(id: 'w2', name: 'Craft Lager (can)', brand: 'Bira 91', category: 'beer', size: 500, unit: 'ml', price: 180, mrp: 190),
      ShopProduct(id: 'w3', name: 'Chenin Blanc', brand: 'Sula', category: 'wine', size: 750, unit: 'ml', price: 1100, mrp: 1150),
      ShopProduct(id: 'w4', name: 'Tonic Water', brand: 'Svami', category: 'soft', size: 300, unit: 'ml', price: 60),
      ShopProduct(id: 'w5', name: 'Ice (2 kg)', category: 'other', price: 50),
    ];
    _suppliers[cellar.id] = const [ShopSupplier(id: 'sup1', name: 'Karnataka State Beverages', licence: 'CL-2'), ShopSupplier(id: 'sup2', name: 'Fizz & Co', licence: null)];
    _products[sweets.id] = const [
      ShopProduct(id: 'k10', name: 'Kaju Katli', category: 'sweet', unit: 'g', byWeight: true, price: 1200),
      ShopProduct(id: 'k11', name: 'Motichoor Ladoo', category: 'sweet', unit: 'g', byWeight: true, price: 880),
      ShopProduct(id: 'k12', name: 'Masala Chai', category: 'soft', price: 40),
    ];
    _suppliers[sweets.id] = const [];
    final seedAt = DateTime.now().subtract(const Duration(days: 2));
    for (final (id, qty) in [('w1', 12), ('w2', 96), ('w3', 24), ('w4', 48), ('w5', 20)]) {
      _moves.add((venueId: cellar.id, productId: id, qty: qty, reason: 'receive', at: seedAt));
    }
    for (final (id, qty) in [('k10', 5000), ('k11', 4000), ('k12', 200)]) {
      _moves.add((venueId: sweets.id, productId: id, qty: qty, reason: 'receive', at: seedAt));
    }

    final t0 = DateTime.now();
    _staff[bar.id] = [
      StaffMember(id: 'demo-me', handle: 'demo-owner', name: 'You (demo)', role: StaffRole.owner, joinedAt: t0.subtract(const Duration(days: 40))),
      StaffMember(id: 's-ira', handle: 'ira', name: 'Ira', role: StaffRole.manager, phone: '+91 98450 11223', joinedAt: t0.subtract(const Duration(days: 38))),
      StaffMember(id: 's-sam', handle: 'sam', name: 'Sam', role: StaffRole.bartender, phone: '+91 99000 44556', joinedAt: t0.subtract(const Duration(days: 30))),
      StaffMember(id: 's-noor', handle: 'noor', name: 'Noor', role: StaffRole.server, joinedAt: t0.subtract(const Duration(days: 6)), approvedBy: 'You (demo)'),
      StaffMember(id: 's-kabir', handle: 'kabir.k', name: 'Kabir', role: StaffRole.server, status: StaffStatus.pending, joinedAt: t0.subtract(const Duration(hours: 5))),
      StaffMember(
        id: 's-leo',
        handle: 'leo',
        name: 'Leo',
        role: StaffRole.bartender,
        status: StaffStatus.locked,
        phone: '+91 90080 77889',
        joinedAt: t0.subtract(const Duration(days: 21)),
        lockedAt: t0.subtract(const Duration(days: 1)),
        lockReason: 'Missed two shifts — come and see me before the next one.',
        reportTo: 'You (demo)',
      ),
    ];
    _onShift['${bar.id}|s-ira'] = t0.subtract(const Duration(hours: 3));
    _onShift['${bar.id}|s-sam'] = t0.subtract(const Duration(hours: 2, minutes: 10));
    for (final (id, m) in [('demo-me', 610), ('s-ira', 1265), ('s-sam', 985), ('s-noor', 1500)]) {
      _weekMinutes['${bar.id}|$id'] = m;
    }
    _codes.add(_Code(
      id: 'enrol-rahul',
      venueId: bar.id,
      name: 'Rahul S.',
      email: 'rahul@example.com',
      phone: '+91 98765 43210',
      role: StaffRole.server,
      code: '305117',
      createdAt: t0.subtract(const Duration(hours: 3)),
      expiresAt: t0.add(const Duration(hours: 45)),
      addedBy: 'You (demo)',
    ));
    void was(String venueId, String kind, {String? actor, String? subject, String? subjectId, Map<String, dynamic> detail = const {}, required Duration ago}) =>
        (_history[venueId] ??= []).add((subjectId: subjectId, e: StaffEvent(id: _eventId++, kind: kind, actor: actor, subject: subject, detail: detail, at: t0.subtract(ago))));
    was(bar.id, 'enrolled', actor: 'You (demo)', detail: {'role': 'server', 'name': 'Rahul S.'}, ago: const Duration(hours: 3));
    was(bar.id, 'requested', subject: 'Kabir', subjectId: 's-kabir', actor: 'Kabir', detail: {'role': 'server', 'via': 'invite'}, ago: const Duration(hours: 5));
    was(bar.id, 'locked', actor: 'You (demo)', subject: 'Leo', subjectId: 's-leo', detail: {'role': 'bartender', 'reason': 'Missed two shifts — come and see me before the next one.'}, ago: const Duration(days: 1));
    was(bar.id, 'joined', actor: 'Noor', subject: 'Noor', subjectId: 's-noor', detail: {'role': 'server', 'via': 'code'}, ago: const Duration(days: 6));
    was(bar.id, 'role_changed', actor: 'You (demo)', subject: 'Sam', subjectId: 's-sam', detail: {'from': 'server', 'to': 'bartender'}, ago: const Duration(days: 12));
    was(bar.id, 'joined', actor: 'You (demo)', subject: 'You (demo)', subjectId: 'demo-me', detail: {'role': 'owner', 'via': 'created'}, ago: const Duration(days: 40));
    for (final list in _history.values) {
      list.sort((a, b) => b.e.at.compareTo(a.e.at));
    }

    // Where "you" stand elsewhere: a café that added your email (type 482913), and a bar
    // that paused your access and asked you to see its manager.
    _codes.add(_Code(
      id: 'enrol-nilgiri',
      venueId: 'demo-cafe',
      name: 'You (demo)',
      email: me.email!,
      role: StaffRole.server,
      code: '482913',
      createdAt: t0.subtract(const Duration(hours: 2)),
      expiresAt: t0.add(const Duration(hours: 46)),
      addedBy: 'Meenakshi',
      forMe: const Venue(
        id: 'demo-cafe',
        name: 'Café Nilgiri',
        slug: 'cafe-nilgiri',
        createdBy: 's-meenakshi',
        city: 'Bengaluru',
        kind: VenueKind.cafe,
        servesAlcohol: false,
        country: 'IN',
        currency: 'INR',
        verified: true,
        myRole: StaffRole.server,
      ),
    ));
    _myAccess.add(StaffAccess(
      venueId: 'demo-taphouse',
      venueName: 'The Tap House',
      venueKind: VenueKind.bar,
      role: StaffRole.bartender,
      status: StaffStatus.locked,
      lockReason: 'Please see me before your next shift — about Saturday\'s cash-up.',
      lockedAt: t0.subtract(const Duration(hours: 2)),
      reportTo: 'Arjun',
      reportToRole: 'manager',
    ));
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
      const MenuItem(id: 'm5', section: 'Food', name: 'Masala Fries', price: 260, kind: 'food', position: 4, station: 'kitchen', diet: 'veg'),
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

    _seedService(bar.id);

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
    if (offline) throw _noSignal;
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
  Future<void> updateVenue(String venueId, {String? name, String? city, List<int>? quietNights, String? geohash, bool? servesAlcohol, bool? areaShare, bool? tableService, int? capacity}) async {
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
      tableService: tableService,
      capacity: capacity,
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
  bool _manages(String venueId) => roleCan(_myRole(venueId), Cap.manageTeam);

  static int _statusRank(StaffStatus s) => switch (s) {
        StaffStatus.pending => 0,
        StaffStatus.active => 1,
        StaffStatus.locked => 2,
      };

  @override
  Future<List<StaffMember>> staff(String venueId) async {
    final manage = _manages(venueId);
    final list = [
      for (final m in [...?_staff[venueId]])
        if (manage || m.status == StaffStatus.active || m.id == me.id)
          m.copyWith(
            onShiftSince: _onShift['$venueId|${m.id}'],
            clearShift: _onShift['$venueId|${m.id}'] == null,
            // phones and lock details are for owners, managers and the person themself
            clearPhone: !manage && m.id != me.id,
            clearLock: !manage && m.id != me.id,
          ),
    ];
    list.sort((a, b) {
      final s = _statusRank(a.status).compareTo(_statusRank(b.status));
      if (s != 0) return s;
      return a.role.rank != b.role.rank ? a.role.rank.compareTo(b.role.rank) : a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  Future<List<ProfileHit>> searchPeople(String query) async {
    final q = query.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (q.length < 2) return const [];
    return _people.where((p) => p.name.toLowerCase().contains(q) || p.handle.contains(q)).toList();
  }

  StaffRole _myRole(String venueId) => _venue(venueId).myRole;

  StaffMember _member(String venueId, String userId) =>
      (_staff[venueId] ?? const <StaffMember>[]).firstWhere((m) => m.id == userId, orElse: () => throw const BackendError('They\'re not on this team.'));

  void _replace(String venueId, StaffMember m) {
    final list = _staff[venueId]!;
    list[list.indexWhere((x) => x.id == m.id)] = m;
  }

  void _log(String venueId, String kind, {String? subjectId, String? subject, Map<String, dynamic> detail = const {}}) {
    (_history[venueId] ??= []).insert(
      0,
      (subjectId: subjectId, e: StaffEvent(id: _eventId++, kind: kind, actor: me.name, subject: subject, detail: detail, at: DateTime.now())),
    );
  }

  @override
  Future<void> setStaffRole(String venueId, String userId, StaffRole role) async {
    final s = _member(venueId, userId);
    if (userId == me.id) throw const BackendError('Nobody changes their own role.');
    final mine = _myRole(venueId);
    if (!canGrant(mine, role) || !canGrant(mine, s.role)) throw const BackendError('You can\'t change that role.');
    _replace(venueId, s.copyWith(role: role));
    _log(venueId, 'role_changed', subjectId: s.id, subject: s.name, detail: {'from': s.role.db, 'to': role.db});
    staffRev.bump();
  }

  @override
  Future<void> removeStaff(String venueId, String userId) async {
    final list = _staff[venueId] ?? [];
    final target = list.where((s) => s.id == userId).firstOrNull;
    if (target == null) return;
    if (userId != me.id && !canGrant(_myRole(venueId), target.role)) throw const BackendError('You can\'t remove them.');
    list.removeWhere((s) => s.id == userId);
    _onShift.remove('$venueId|$userId');
    _log(venueId, userId == me.id ? 'left' : 'removed', subjectId: userId, subject: target.name, detail: {'role': target.role.db, 'status': target.status.db});
    staffRev.bump();
  }

  @override
  Future<void> setThankable(String venueId, bool thankable) async {
    final list = _staff[venueId] ?? [];
    final i = list.indexWhere((s) => s.id == me.id);
    if (i < 0) return;
    list[i] = list[i].copyWith(thankable: thankable);
    staffRev.bump();
  }

  @override
  Future<StaffInvite> createInvite(String venueId, StaffRole role) async {
    if (!canGrant(_myRole(venueId), role)) throw const BackendError('You can\'t invite someone as that.');
    final r = math.Random();
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    final code = List.generate(10, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    _invites[code] = role;
    return StaffInvite(code: code, role: role, expiresAt: DateTime.now().add(const Duration(days: 7)));
  }

  /// In the demo, a code "you" made yourself is for someone else; any other 10-letter code
  /// asks to join a bakery down the road, and you wait for its manager's yes.
  @override
  Future<String> acceptInvite(String code) async {
    final c = code.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]{10}$').hasMatch(c)) throw const BackendError('That invite code didn\'t work — ask for a new one.');
    if (_invites.containsKey(c)) throw const BackendError('That code is for someone joining your team — share it with them.');
    if (!_myAccess.any((a) => a.venueId == 'demo-bakery')) {
      _myAccess.add(const StaffAccess(venueId: 'demo-bakery', venueName: 'Blue Door Bakery', venueKind: VenueKind.bakery, role: StaffRole.server, status: StaffStatus.pending));
    }
    venueRev.bump();
    return 'Blue Door Bakery';
  }

  // ── staff access (053) ────────────────────────────────────────────────────
  static String _newCode() => (100000 + math.Random().nextInt(900000)).toString();

  _Code _code(String id) => _codes.firstWhere((c) => c.id == id, orElse: () => throw const BackendError('No such code.'));

  @override
  Future<StaffCode> enrolStaff(String venueId, {required String name, required String email, String? phone, required StaffRole role}) async {
    final mine = _myRole(venueId);
    if (!roleCan(mine, Cap.manageTeam) || !canGrant(mine, role)) {
      throw BackendError('Your role can\'t add someone as ${role.db}.');
    }
    final nm = name.trim();
    final em = email.trim().toLowerCase();
    final ph = phone?.trim() ?? '';
    if (nm.isEmpty || nm.length > 60) throw const BackendError('Add their name (up to 60 letters).');
    if (!validStaffEmail(em)) throw const BackendError('That email doesn\'t look right.');
    if (ph.isNotEmpty && !validStaffPhone(ph)) throw const BackendError('That phone number doesn\'t look right.');
    if (em == me.email && (_staff[venueId] ?? const []).any((m) => m.id == me.id)) {
      throw const BackendError('Someone with that email is already on this team.');
    }
    for (final c in _codes.where((c) => c.venueId == venueId && c.email == em && c.open)) {
      c.closed = true; // one open code per person per venue
    }
    final now = DateTime.now();
    final c = _Code(
      id: newId(),
      venueId: venueId,
      name: nm,
      email: em,
      phone: ph.isEmpty ? null : ph,
      role: role,
      code: _newCode(),
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 48)),
      addedBy: me.name,
    );
    _codes.add(c);
    _log(venueId, 'enrolled', detail: {'role': role.db, 'name': nm});
    staffRev.bump();
    return StaffCode(enrolmentId: c.id, code: c.code, expiresAt: c.expiresAt);
  }

  @override
  Future<StaffCode> reissueCode(String enrolmentId) async {
    final c = _code(enrolmentId);
    if (!c.open) throw const BackendError('That code is closed — add them again.');
    final mine = _myRole(c.venueId);
    if (!roleCan(mine, Cap.manageTeam) || !canGrant(mine, c.role)) throw const BackendError('Your role can\'t do that.');
    c
      ..code = _newCode()
      ..attempts = 0
      ..expiresAt = DateTime.now().add(const Duration(hours: 48));
    _log(c.venueId, 'code_reissued', detail: {'role': c.role.db, 'name': c.name});
    staffRev.bump();
    return StaffCode(enrolmentId: c.id, code: c.code, expiresAt: c.expiresAt);
  }

  @override
  Future<void> revokeEnrolment(String enrolmentId) async {
    final c = _code(enrolmentId);
    final mine = _myRole(c.venueId);
    if (!roleCan(mine, Cap.manageTeam) || !canGrant(mine, c.role)) throw const BackendError('Your role can\'t do that.');
    if (!c.open) return;
    c.closed = true;
    _log(c.venueId, 'enrolment_revoked', detail: {'role': c.role.db, 'name': c.name});
    staffRev.bump();
  }

  @override
  Future<List<Enrolment>> openEnrolments(String venueId) async {
    if (!_manages(venueId)) throw const BackendError('Your role doesn\'t manage the team here.');
    return [
      for (final c in _codes.where((c) => c.venueId == venueId && c.open && c.forMe == null).toList().reversed)
        Enrolment(id: c.id, name: c.name, email: c.email, phone: c.phone, role: c.role, createdAt: c.createdAt, expiresAt: c.expiresAt, attempts: c.attempts, addedBy: c.addedBy),
    ];
  }

  @override
  Future<List<MyEnrolment>> myEnrolments() async {
    _needUser();
    if (offline) throw _noSignal;
    final now = DateTime.now();
    return [
      for (final c in _codes)
        if (c.forMe != null && c.open && c.expiresAt.isAfter(now) && c.attempts < 5 && !_venues.any((v) => v.id == c.venueId))
          MyEnrolment(id: c.id, venueId: c.venueId, venueName: c.forMe!.name, venueKind: c.forMe!.kind, role: c.role, staffName: c.name, addedBy: c.addedBy, expiresAt: c.expiresAt, triesLeft: 5 - c.attempts),
    ];
  }

  @override
  Future<ClaimResult> claimEnrolment(String enrolmentId, String code) async {
    _needUser();
    final c = _codes.where((c) => c.id == enrolmentId && c.forMe != null).firstOrNull;
    if (c == null) return const ClaimResult(ok: false, error: ClaimError.notFound);
    if (!c.open) return const ClaimResult(ok: false, error: ClaimError.closed);
    if (!c.expiresAt.isAfter(DateTime.now())) return const ClaimResult(ok: false, error: ClaimError.expired);
    if (c.attempts >= 5) return const ClaimResult(ok: false, error: ClaimError.tooMany);
    if (code.trim() != c.code) {
      c.attempts++;
      return ClaimResult(ok: false, error: c.attempts >= 5 ? ClaimError.tooMany : ClaimError.wrongCode, left: 5 - c.attempts);
    }
    final v = c.forMe!;
    c.closed = true;
    _venues.add(v);
    _staff[v.id] = [
      const StaffMember(id: 's-meenakshi', handle: 'meenakshi', name: 'Meenakshi', role: StaffRole.owner),
      StaffMember(id: me.id, handle: me.handle, name: me.name, role: c.role, joinedAt: DateTime.now(), approvedBy: c.addedBy),
    ];
    _rooms[v.id] = [];
    _menu[v.id] = [];
    _perks[v.id] = [];
    _log(v.id, 'joined', subjectId: me.id, subject: me.name, detail: {'role': c.role.db, 'via': 'code'});
    venueRev.bump();
    return ClaimResult(ok: true, venueId: v.id, venueName: v.name, role: c.role);
  }

  /// For the walk-throughs: an owner somewhere else pauses "you" at [venueId] (what a
  /// manager's phone would do to yours), or gives you access again.
  void pauseMe(String venueId, {String? reason, required String reportTo, String reportToRole = 'owner'}) {
    final v = _venue(venueId);
    _venues.removeWhere((x) => x.id == venueId);
    _paused[venueId] = v;
    _myAccess.add(StaffAccess(venueId: v.id, venueName: v.name, venueKind: v.kind, role: v.myRole, status: StaffStatus.locked, lockReason: reason, lockedAt: DateTime.now(), reportTo: reportTo, reportToRole: reportToRole));
    _onShift.remove('$venueId|${me.id}');
    venueRev.bump(); // the real app hears of it within a minute, or on the next refused call
  }

  void unpauseMe(String venueId) {
    final v = _paused.remove(venueId);
    if (v == null) return;
    _myAccess.removeWhere((a) => a.venueId == venueId);
    _venues.add(v);
    venueRev.bump();
  }

  final Map<String, Venue> _paused = {};

  /// For the walk-throughs: the phone has no signal, so where you stand can't be read.
  bool offline = false;
  static const _noSignal = BackendError('Couldn\'t reach brewdiary — check your connection and try again.');

  @override
  Future<List<StaffAccess>> myStaffStatus() async {
    _needUser();
    if (offline) throw _noSignal;
    return List.unmodifiable(_myAccess);
  }

  void _needManage(String venueId, StaffRole target, String what) {
    final mine = _myRole(venueId);
    if (!roleCan(mine, Cap.manageTeam) || !canGrant(mine, target)) throw BackendError('Your role can\'t $what a ${target.db}.');
  }

  @override
  Future<void> approveStaff(String venueId, String userId) async {
    final m = _member(venueId, userId);
    if (m.status != StaffStatus.pending) throw const BackendError('They\'re not waiting for a yes.');
    _needManage(venueId, m.role, 'approve');
    _replace(venueId, m.copyWith(status: StaffStatus.active, approvedBy: me.name));
    _log(venueId, 'approved', subjectId: m.id, subject: m.name, detail: {'role': m.role.db, 'via': 'approved'});
    staffRev.bump();
  }

  @override
  Future<void> declineStaff(String venueId, String userId) async {
    final m = _member(venueId, userId);
    if (m.status != StaffStatus.pending) throw const BackendError('They\'re not waiting for a yes.');
    _needManage(venueId, m.role, 'decline');
    _staff[venueId]!.removeWhere((x) => x.id == userId);
    _log(venueId, 'declined', subjectId: m.id, subject: m.name, detail: {'role': m.role.db, 'status': 'pending'});
    staffRev.bump();
  }

  @override
  Future<void> lockStaff(String venueId, String userId, {String? reason, String? reportTo}) async {
    if (userId == me.id) throw const BackendError('You can\'t lock yourself out.');
    if (_venue(venueId).createdBy == userId) throw const BackendError('The owner can\'t be locked out.');
    final m = _member(venueId, userId);
    _needManage(venueId, m.role, 'lock out');
    if (m.status == StaffStatus.pending) throw const BackendError('They\'re still waiting — decline them instead.');
    final why = reason?.trim() ?? '';
    if (why.length > 200) throw const BackendError('Keep the reason under 200 letters.');
    final to = reportTo == null ? null : (_staff[venueId] ?? const <StaffMember>[]).where((x) => x.id == reportTo).firstOrNull;
    if (reportTo != null && (to == null || !to.role.isManagement || to.status != StaffStatus.active)) {
      throw const BackendError('They can only be asked to report to an owner or a manager here.');
    }
    _replace(venueId, m.copyWith(status: StaffStatus.locked, lockedAt: DateTime.now(), lockReason: why.isEmpty ? null : why, reportTo: to?.name ?? me.name));
    if (m.status != StaffStatus.locked) {
      _log(venueId, 'locked', subjectId: m.id, subject: m.name, detail: {'role': m.role.db, if (why.isNotEmpty) 'reason': why});
    }
    _endShift(venueId, userId);
    staffRev.bump();
    shiftRev.bump();
  }

  @override
  Future<void> unlockStaff(String venueId, String userId) async {
    final m = _member(venueId, userId);
    _needManage(venueId, m.role, 'unlock');
    if (m.status != StaffStatus.locked) return;
    _replace(venueId, m.copyWith(status: StaffStatus.active, clearLock: true));
    _log(venueId, 'unlocked', subjectId: m.id, subject: m.name, detail: {'role': m.role.db});
    staffRev.bump();
  }

  @override
  Future<void> setStaffDetails(String venueId, String userId, {String? name, String? phone}) async {
    final m = _member(venueId, userId);
    if (userId != me.id) _needManage(venueId, m.role, 'change the details of');
    final nm = name?.trim() ?? '';
    final ph = phone?.trim() ?? '';
    if (nm.length > 60) throw const BackendError('Keep the name under 60 letters.');
    if (ph.isNotEmpty && !validStaffPhone(ph)) throw const BackendError('That phone number doesn\'t look right.');
    _replace(venueId, m.copyWith(name: nm.isEmpty ? null : nm, phone: ph.isEmpty ? null : ph, clearPhone: ph.isEmpty));
    _log(venueId, 'details_changed', subjectId: m.id, subject: nm.isEmpty ? m.name : nm);
    staffRev.bump();
  }

  @override
  Future<List<StaffEvent>> staffHistory(String venueId, {String? userId, int limit = 100}) async {
    if (!roleCan(_myRole(venueId), Cap.auditLog) && userId != me.id) {
      throw const BackendError('Your role doesn\'t see the team\'s history.');
    }
    return [
      for (final h in _history[venueId] ?? const <({String? subjectId, StaffEvent e})>[])
        if (userId == null || h.subjectId == userId) h.e,
    ].take(limit.clamp(1, 500)).toList();
  }

  // ── the time clock (053) ──────────────────────────────────────────────────
  void _endShift(String venueId, String userId) {
    final since = _onShift.remove('$venueId|$userId');
    if (since == null) return;
    final k = '$venueId|$userId';
    final start = since.isBefore(weekStart(DateTime.now())) ? weekStart(DateTime.now()) : since;
    _weekMinutes[k] = (_weekMinutes[k] ?? 0) + DateTime.now().difference(start).inMinutes;
  }

  @override
  Future<DateTime?> myShift(String venueId) async => _onShift['$venueId|${me.id}'];

  @override
  Future<DateTime> clockIn(String venueId) async {
    if (!roleCan(_myRole(venueId), Cap.ownShift)) throw const BackendError('You can\'t clock in here right now.');
    final since = _onShift.putIfAbsent('$venueId|${me.id}', DateTime.now);
    shiftRev.bump();
    staffRev.bump();
    return since;
  }

  @override
  Future<void> clockOut(String venueId) async {
    if (_onShift['$venueId|${me.id}'] == null) throw const BackendError('You\'re not clocked in.');
    _endShift(venueId, me.id);
    shiftRev.bump();
    staffRev.bump();
  }

  @override
  Future<void> endShift(String venueId, String userId) async {
    if (!roleCan(_myRole(venueId), Cap.editRota)) throw const BackendError('Your role doesn\'t manage shifts here.');
    if (_onShift['$venueId|$userId'] == null) throw const BackendError('They\'re not clocked in.');
    _endShift(venueId, userId);
    final m = _member(venueId, userId);
    _log(venueId, 'shift_ended_by_manager', subjectId: userId, subject: m.name);
    shiftRev.bump();
    staffRev.bump();
  }

  @override
  Future<List<ShiftRow>> shiftHours(String venueId, DateTime since) async {
    final everyone = roleCan(_myRole(venueId), Cap.editRota);
    final now = DateTime.now();
    final monday = weekStart(now);
    // The demo keeps this week's finished shifts; earlier weeks run at the same pace.
    final daysBefore = since.isBefore(monday) ? monday.difference(since).inDays : 0;
    final daysThisWeek = math.max(1, now.difference(monday).inDays + 1);
    final rows = <ShiftRow>[];
    for (final m in _staff[venueId] ?? const <StaffMember>[]) {
      if (!everyone && m.id != me.id) continue;
      final k = '$venueId|${m.id}';
      final week = _weekMinutes[k] ?? 0;
      final open = _onShift[k];
      final openMins = open == null ? 0 : now.difference(open.isBefore(since) ? since : open).inMinutes;
      rows.add(ShiftRow(userId: m.id, name: m.name, role: m.role, onSince: open, minutes: week + (week * daysBefore / daysThisWeek).round() + openMins));
    }
    rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rows;
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

  // ── the counter (050) ─────────────────────────────────────────────────────
  @override
  Future<List<ShopProduct>> products(String venueId) async => [...(_products[venueId] ?? const [])];

  @override
  Future<void> saveProduct(String venueId, ShopProduct p, {bool isNew = false}) async {
    final v = _venue(venueId);
    if (!roleCan(v.myRole, Cap.editMenu)) throw const BackendError('Your role here can\'t do that.');
    if (p.name.trim().isEmpty) throw const BackendError('Give it a name.');
    if (p.mrp != null && p.price > p.mrp!) throw const BackendError('The price can\'t be above the MRP.');
    if (p.isAlcohol && !v.sellsAlcohol) throw BackendError('A ${v.kind.label.toLowerCase()} sells no alcohol — it can\'t list ${p.name}.');
    final list = _products.putIfAbsent(venueId, () => []);
    final i = list.indexWhere((x) => x.id == p.id);
    if (i < 0) {
      list.add(p);
    } else {
      list[i] = p;
    }
    stockRev.bump();
  }

  @override
  Future<Map<String, int>> stock(String venueId) async {
    final out = <String, int>{for (final p in _products[venueId] ?? const <ShopProduct>[]) p.id: 0};
    for (final m in _moves.where((m) => m.venueId == venueId)) {
      out[m.productId] = (out[m.productId] ?? 0) + m.qty;
    }
    return out;
  }

  String _venueOfProduct(String productId) =>
      _products.entries.firstWhere((e) => e.value.any((p) => p.id == productId), orElse: () => throw const BackendError('No such product.')).key;

  @override
  Future<void> receiveStock(String productId, int qty, {String? supplierId, String? invoice}) async {
    final vid = _venueOfProduct(productId);
    if (!roleCan(_venue(vid).myRole, Cap.receiveStock)) throw const BackendError('Your role here can\'t do that.');
    if (qty < 1) throw const BackendError('Receive at least one.');
    _moves.add((venueId: vid, productId: productId, qty: qty, reason: 'receive', at: DateTime.now()));
    stockRev.bump();
  }

  @override
  Future<void> adjustStock(String productId, int qty, String why, {String? note}) async {
    final vid = _venueOfProduct(productId);
    if (!roleCan(_venue(vid).myRole, Cap.adjustStock)) throw const BackendError('Your role here can\'t do that.');
    if (qty == 0) throw const BackendError('Adjust by a real amount.');
    if (why == 'adjust' && (note ?? '').trim().length < 3) throw const BackendError('An adjustment needs a note (a count, a breakage…).');
    _moves.add((venueId: vid, productId: productId, qty: qty, reason: why, at: DateTime.now()));
    stockRev.bump();
  }

  @override
  Future<List<ShopSupplier>> suppliers(String venueId) async => [...(_suppliers[venueId] ?? const [])];

  @override
  Future<void> addSupplier(String venueId, String name, {String? licence}) async {
    if (name.trim().isEmpty) throw const BackendError('Give the supplier a name.');
    _suppliers.putIfAbsent(venueId, () => []).add(ShopSupplier(id: newId(), name: name.trim(), licence: (licence ?? '').trim().isEmpty ? null : licence!.trim()));
    stockRev.bump();
  }

  @override
  Future<SaleStatus> saleStatus(String venueId) async {
    final v = _venue(venueId);
    // The demo pretends Karnataka's retail rules are researched. The real ones are
    // rows in retail_alcohol_rules with their source; until then the till says no.
    if (v.region == 'KA') return const SaleStatus(researched: true, allowedNow: true, minAge: 21, maxMl: 2250, saleStart: '10:00', saleEnd: '22:30');
    return const SaleStatus(researched: false, allowedNow: false, reason: 'We haven\'t researched the retail alcohol rules here yet, so alcohol can\'t be rung up. Everything else can.', minAge: 21);
  }

  @override
  Future<double> ringSale(String venueId, String saleId, List<Map<String, Object>> lines, String paidBy, {bool idChecked = false}) async {
    if (_sales.containsKey(saleId)) return _sales[saleId]!;
    final v = _venue(venueId);
    if (!roleCan(v.myRole, Cap.takePayment)) throw const BackendError('Your role here can\'t do that.');
    final shelf = {for (final p in _products[venueId] ?? const <ShopProduct>[]) p.id: p};
    var total = 0.0, ml = 0.0, alcohol = false;
    for (final l in lines) {
      final p = shelf[l['product']] ?? (throw const BackendError('A product isn\'t on this venue\'s shelf.'));
      final q = l['qty'] as int;
      total += p.byWeight ? (p.price * q / 1000 * 100).round() / 100 : p.price * q;
      if (p.isAlcohol) {
        alcohol = true;
        ml += (p.size ?? 0) * q;
      }
    }
    if (alcohol) {
      final st = await saleStatus(venueId);
      if (!st.researched || !st.allowedNow) throw BackendError(st.reason ?? 'Alcohol can\'t be sold here right now.');
      if (!idChecked) throw BackendError('Check ID first: ${st.minAge ?? 21} or over.');
      if (st.maxMl != null && ml > st.maxMl!) throw BackendError('That\'s over the per-sale limit here (${st.maxMl} ml).');
    }
    for (final l in lines) {
      _moves.add((venueId: venueId, productId: l['product'] as String, qty: -(l['qty'] as int), reason: 'sale', at: DateTime.now()));
    }
    _sales[saleId] = total;
    stockRev.bump();
    return total;
  }

  @override
  Future<List<RegisterRow>> exciseRegister(String venueId, DateTime from, DateTime to) async {
    final v = _venue(venueId);
    if (!roleCan(v.myRole, Cap.reports)) throw const BackendError('Your role here can\'t do that.');
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final out = <RegisterRow>[];
    for (var d = day(from); !d.isAfter(day(to)); d = d.add(const Duration(days: 1))) {
      for (final p in (_products[venueId] ?? const <ShopProduct>[]).where((p) => p.isAlcohol)) {
        final ms = _moves.where((m) => m.venueId == venueId && m.productId == p.id);
        int sum(bool Function(({String venueId, String productId, int qty, String reason, DateTime at})) f) => ms.where(f).fold(0, (s, m) => s + m.qty);
        out.add(RegisterRow(
          day: d,
          productId: p.id,
          name: p.name,
          brand: p.brand,
          size: p.size,
          opening: sum((m) => day(m.at).isBefore(d)),
          received: sum((m) => day(m.at) == d && m.reason == 'receive'),
          sold: -sum((m) => day(m.at) == d && m.reason == 'sale'),
          other: sum((m) => day(m.at) == d && m.reason != 'receive' && m.reason != 'sale'),
          closing: sum((m) => !day(m.at).isAfter(d)),
        ));
      }
    }
    return out;
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

  // ── service (051) ─────────────────────────────────────────────────────────
  void _seedService(String vid) {
    final now = DateTime.now();
    _areas[vid] = const [VenueArea(id: 'a-bar', name: 'Bar', position: 0), VenueArea(id: 'a-floor', name: 'Floor', position: 1), VenueArea(id: 'a-patio', name: 'Patio', position: 2)];
    _tables[vid] = [
      for (var i = 1; i <= 4; i++) VenueTable(id: 'tb-b$i', areaId: 'a-bar', label: 'B$i', seats: 2, code: 'demob00$i', position: i),
      for (var i = 1; i <= 6; i++) VenueTable(id: 'tb-t$i', areaId: 'a-floor', label: 'T$i', seats: i.isEven ? 4 : 2, code: 'demot00$i', position: 10 + i),
      for (var i = 1; i <= 3; i++) VenueTable(id: 'tb-p$i', areaId: 'a-patio', label: 'P$i', seats: 6, code: 'demop00$i', position: 20 + i),
    ];
    MenuItem m(String id) => _menu[vid]!.firstWhere((x) => x.id == id);
    OrderLine line(String id, String tab, String item, int qty, String status, int minsAgo, {String? note, int? seat, String source = 'staff'}) {
      final it = m(item);
      return OrderLine(id: id, tabId: tab, menuItemId: it.id, name: it.name, unitPrice: it.price ?? 0, qty: qty, note: note, seat: seat, station: it.station, status: status, source: source, createdAt: now.subtract(Duration(minutes: minsAgo)), readyAt: status == 'ready' || status == 'served' ? now.subtract(Duration(minutes: minsAgo ~/ 2)) : null);
    }

    _tabs[vid] = [
      ServiceTab(id: 'tab-t2', tableId: 'tb-t2', covers: 4, openedAt: now.subtract(const Duration(minutes: 42))),
      ServiceTab(id: 'tab-t5', tableId: 'tb-t5', covers: 2, openedAt: now.subtract(const Duration(minutes: 18))),
      ServiceTab(id: 'tab-b1', tableId: 'tb-b1', covers: 1, openedAt: now.subtract(const Duration(minutes: 9))),
    ];
    _lines['tab-t2'] = [
      line('l1', 'tab-t2', 'm1', 2, 'served', 40, seat: 1),
      line('l2', 'tab-t2', 'm5', 1, 'ready', 22, note: 'extra crispy'),
      line('l3', 'tab-t2', 'm4', 2, 'preparing', 12),
    ];
    _lines['tab-t5'] = [line('l4', 'tab-t5', 'm2', 1, 'sent', 6), line('l5', 'tab-t5', 'm5', 1, 'sent', 6, note: 'no chilli')];
    _lines['tab-b1'] = [line('l6', 'tab-b1', 'm3', 1, 'served', 8)];
    _inbox[vid] = [
      InboxItem(kind: 'order', id: 'rq1', tableId: 'tb-t3', tableLabel: 'T3', createdAt: now.subtract(const Duration(minutes: 2)), lines: const [
        (item: 'm4', name: 'Kokum Cooler', qty: 2, note: null, alcohol: false),
        (item: 'm3', name: 'Hazy IPA (pint)', qty: 1, note: null, alcohol: true),
      ], note: 'celebrating!', hasAlcohol: true),
      InboxItem(kind: 'call', id: 'cl1', tableId: 'tb-t2', tableLabel: 'T2', createdAt: now.subtract(const Duration(minutes: 1)), callKind: 'bill'),
    ];
    _wait[vid] = [
      WaitParty(id: 'w1', name: 'Priya', party: 4, quotedMin: 15, createdAt: now.subtract(const Duration(minutes: 11))),
      WaitParty(id: 'w2', name: 'Party of 2', party: 2, quotedMin: 10, createdAt: now.subtract(const Duration(minutes: 3))),
    ];
  }

  void _can(String venueId, Cap cap) {
    if (!roleCan(_venue(venueId).myRole, cap)) throw const BackendError('Your role here can\'t do that.');
  }

  String _venueOfTab(String tabId) => _tabs.entries.firstWhere((e) => e.value.any((t) => t.id == tabId), orElse: () => throw const BackendError('No such tab.')).key;

  ServiceTab _tab(String tabId) => _tabs[_venueOfTab(tabId)]!.firstWhere((t) => t.id == tabId);

  void _putTab(ServiceTab t) {
    final list = _tabs[_venueOfTab(t.id)]!;
    list[list.indexWhere((x) => x.id == t.id)] = t;
  }

  @override
  Future<List<VenueArea>> areas(String venueId) async => [...(_areas[venueId] ?? const [])];

  @override
  Future<void> saveArea(String venueId, VenueArea area, {bool isNew = false}) async {
    _can(venueId, Cap.editSettings);
    if (area.name.trim().isEmpty) throw const BackendError('Give the area a name.');
    final list = _areas.putIfAbsent(venueId, () => []);
    final i = list.indexWhere((a) => a.id == area.id);
    i < 0 ? list.add(area) : list[i] = area;
    floorRev.bump();
  }

  @override
  Future<List<VenueTable>> tables(String venueId) async => [...(_tables[venueId] ?? const [])];

  @override
  Future<void> saveTable(String venueId, VenueTable table, {bool isNew = false}) async {
    _can(venueId, Cap.editSettings);
    if (_venue(venueId).kind.isCounter) throw const BackendError('A counter has no tables.');
    if (table.label.trim().isEmpty) throw const BackendError('Give the table a label.');
    final list = _tables.putIfAbsent(venueId, () => []);
    if (list.any((t) => t.id != table.id && t.label == table.label.trim())) throw const BackendError('That label is taken.');
    final i = list.indexWhere((t) => t.id == table.id);
    final saved = table.code.isEmpty
        ? VenueTable(id: table.id, areaId: table.areaId, label: table.label.trim(), seats: table.seats, code: newId().replaceAll('-', '').substring(0, 8), active: table.active, position: table.position)
        : table;
    i < 0 ? list.add(saved) : list[i] = saved;
    floorRev.bump();
  }

  @override
  Future<String> rotateTableCode(String tableId) async {
    final vid = _tables.entries.firstWhere((e) => e.value.any((t) => t.id == tableId)).key;
    _can(vid, Cap.editSettings);
    final list = _tables[vid]!;
    final i = list.indexWhere((t) => t.id == tableId);
    final code = newId().replaceAll('-', '').substring(0, 8);
    final t = list[i];
    list[i] = VenueTable(id: t.id, areaId: t.areaId, label: t.label, seats: t.seats, code: code, active: t.active, position: t.position);
    floorRev.bump();
    return code;
  }

  @override
  Future<List<ServiceTab>> openTabs(String venueId) async => [...(_tabs[venueId] ?? const <ServiceTab>[]).where((t) => t.status == 'open')];

  @override
  Future<void> openTab(String venueId, String tabId, {String? tableId, String? name, int? covers}) async {
    _can(venueId, Cap.takeOrders);
    final list = _tabs.putIfAbsent(venueId, () => []);
    if (list.any((t) => t.id == tabId)) return;
    if (tableId == null && (name ?? '').trim().isEmpty) throw const BackendError('A tab without a table needs a name (Bar 3, the birthday…).');
    list.add(ServiceTab(id: tabId, tableId: tableId, name: (name ?? '').trim().isEmpty ? null : name!.trim(), covers: covers, openedAt: DateTime.now()));
    _lines[tabId] = [];
    floorRev.bump();
  }

  @override
  Future<List<OrderLine>> tabLines(String tabId) async => [...(_lines[tabId] ?? const [])];

  @override
  Future<void> addLines(String tabId, List<Map<String, Object?>> lines) async {
    final vid = _venueOfTab(tabId);
    _can(vid, Cap.takeOrders);
    if (_tab(tabId).status != 'open') throw const BackendError('That tab is closed.');
    final menu = {for (final m in _menu[vid] ?? const <MenuItem>[]) m.id: m};
    final out = _lines.putIfAbsent(tabId, () => []);
    for (final l in lines) {
      final m = menu[l['item']] ?? (throw const BackendError('An item isn\'t on this venue\'s menu.'));
      if (!m.available) throw BackendError('${m.name} is off tonight (86\'d).');
      out.add(OrderLine(id: newId(), tabId: tabId, menuItemId: m.id, name: m.name, unitPrice: m.price ?? 0, qty: (l['qty'] as int?) ?? 1, note: l['note'] as String?, seat: l['seat'] as int?, station: m.station, source: (l['source'] as String?) ?? 'staff', createdAt: DateTime.now()));
    }
    floorRev.bump();
  }

  OrderLine _line(String lineId) => _lines.values.expand((x) => x).firstWhere((l) => l.id == lineId, orElse: () => throw const BackendError('No such line.'));

  void _putLine(OrderLine l) {
    final list = _lines[l.tabId]!;
    list[list.indexWhere((x) => x.id == l.id)] = l;
  }

  @override
  Future<void> setLineStatus(String lineId, String status) async {
    final l = _line(lineId);
    final vid = _venueOfTab(l.tabId);
    _can(vid, status == 'served' ? Cap.takeOrders : (l.station == 'kitchen' ? Cap.kitchenStation : (l.station == 'bar' ? Cap.barStation : Cap.takeOrders)));
    const order = ['sent', 'preparing', 'ready', 'served'];
    if (l.status == 'void' || order.indexOf(status) <= order.indexOf(l.status)) throw BackendError('That line is already ${l.status}.');
    _putLine(l.copyWith(status: status, readyAt: status == 'ready' || status == 'served' ? (l.readyAt ?? DateTime.now()) : null));
    floorRev.bump();
  }

  @override
  Future<void> voidLine(String lineId, String reason) async {
    final l = _line(lineId);
    if (reason.trim().length < 3) throw const BackendError('Say why (a mistake, sent back…).');
    final vid = _venueOfTab(l.tabId);
    final own = l.status == 'sent' && DateTime.now().difference(l.createdAt).inMinutes < 10;
    if (!(own && roleCan(_venue(vid).myRole, Cap.voidOwn)) && !roleCan(_venue(vid).myRole, Cap.approveVoids)) {
      throw const BackendError('A supervisor needs to void this one.');
    }
    _putLine(l.copyWith(status: 'void', voidReason: reason.trim()));
    floorRev.bump();
  }

  @override
  Future<double> closeTab(String tabId, List<Map<String, Object>> payments, {double? tip}) async {
    final vid = _venueOfTab(tabId);
    _can(vid, Cap.takePayment);
    final t = _tab(tabId);
    if (t.status != 'open') throw BackendError('That tab is already ${t.status}.');
    final sub = (_lines[tabId] ?? const <OrderLine>[]).fold<double>(0, (s, l) => s + l.total);
    _payments[tabId] = payments;
    _putTab(ServiceTab(id: t.id, tableId: t.tableId, name: t.name, covers: t.covers, status: 'closed', openedAt: t.openedAt, subtotal: sub, tip: tip));
    floorRev.bump();
    return sub;
  }

  @override
  Future<void> voidTab(String tabId, String reason) async {
    final vid = _venueOfTab(tabId);
    _can(vid, Cap.approveVoids);
    if (reason.trim().length < 3) throw const BackendError('Say why.');
    if ((_lines[tabId] ?? const <OrderLine>[]).any((l) => l.status == 'served')) throw const BackendError('Something on this tab was served — settle it instead.');
    final t = _tab(tabId);
    _putTab(ServiceTab(id: t.id, tableId: t.tableId, name: t.name, covers: t.covers, status: 'void', openedAt: t.openedAt, subtotal: 0));
    floorRev.bump();
  }

  @override
  Future<List<OrderLine>> stationLines(String venueId, String station) async {
    final tables = {for (final t in _tables[venueId] ?? const <VenueTable>[]) t.id: t.label};
    final out = <OrderLine>[];
    for (final t in (_tabs[venueId] ?? const <ServiceTab>[]).where((t) => t.status == 'open')) {
      for (final l in _lines[t.id] ?? const <OrderLine>[]) {
        if (l.station == station && const ['sent', 'preparing', 'ready'].contains(l.status)) {
          out.add(OrderLine(id: l.id, tabId: l.tabId, menuItemId: l.menuItemId, name: l.name, unitPrice: l.unitPrice, qty: l.qty, note: l.note, seat: l.seat, station: l.station, status: l.status, source: l.source, createdAt: l.createdAt, readyAt: l.readyAt, tableLabel: tables[t.tableId], tabName: t.name));
        }
      }
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  @override
  Future<List<InboxItem>> inbox(String venueId) async {
    _can(venueId, Cap.floorView);
    return [...(_inbox[venueId] ?? const [])];
  }

  @override
  Future<void> acceptRequest(String requestId, String tabId) async {
    final vid = _inbox.entries.firstWhere((e) => e.value.any((i) => i.id == requestId), orElse: () => throw const BackendError('That request is gone.')).key;
    _can(vid, Cap.takeOrders);
    final r = _inbox[vid]!.firstWhere((i) => i.id == requestId);
    if (!(_tabs[vid] ?? const <ServiceTab>[]).any((t) => t.id == tabId)) await openTab(vid, tabId, tableId: r.tableId);
    await addLines(tabId, [for (final l in r.lines) {'item': l.item, 'qty': l.qty, 'note': l.note, 'source': 'guest'}]);
    _inbox[vid]!.removeWhere((i) => i.id == requestId);
    floorRev.bump();
  }

  @override
  Future<void> declineRequest(String requestId, {String? reason}) async {
    for (final list in _inbox.values) {
      list.removeWhere((i) => i.id == requestId);
    }
    floorRev.bump();
  }

  @override
  Future<void> resolveCall(String callId) async {
    for (final list in _inbox.values) {
      list.removeWhere((i) => i.id == callId);
    }
    floorRev.bump();
  }

  @override
  Future<List<WaitParty>> waitlist(String venueId) async => [...(_wait[venueId] ?? const [])];

  @override
  Future<void> addToWaitlist(String venueId, WaitParty p) async {
    _can(venueId, Cap.seatGuests);
    if (p.name.trim().isEmpty) throw const BackendError('A first name, or "party of 4".');
    _wait.putIfAbsent(venueId, () => []).add(p);
    floorRev.bump();
  }

  @override
  Future<void> setWaitStatus(String partyId, String status) async {
    for (final list in _wait.values) {
      final i = list.indexWhere((p) => p.id == partyId);
      if (i >= 0) {
        final p = list[i];
        list[i] = WaitParty(id: p.id, name: p.name, party: p.party, quotedMin: p.quotedMin, note: p.note, status: status, createdAt: p.createdAt);
      }
    }
    floorRev.bump();
  }

  @override
  Future<ServiceBoard> serviceBoard(String venueId) async {
    _can(venueId, Cap.liveBoard);
    final tabs = _tabs[venueId] ?? const <ServiceTab>[];
    final open = tabs.where((t) => t.status == 'open').toList();
    final closed = tabs.where((t) => t.status == 'closed').toList();
    final all = [for (final t in open) ...?_lines[t.id]];
    final methods = <String, double>{'upi': 18400, 'card': 12650, 'cash': 4200};
    for (final t in closed) {
      for (final p in _payments[t.id] ?? const <Map<String, Object>>[]) {
        final k = '${p['method']}'.toLowerCase();
        methods[k] = (methods[k] ?? 0) + ((p['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    return ServiceBoard(
      openTabs: open.length,
      covers: open.fold(0, (s, t) => s + (t.covers ?? 0)),
      bills: 14 + closed.length,
      sales: 35250 + closed.fold<double>(0, (s, t) => s + (t.subtotal ?? 0)),
      tips: 1800 + closed.fold<double>(0, (s, t) => s + (t.tip ?? 0)),
      barWaiting: all.where((l) => l.station == 'bar' && (l.status == 'sent' || l.status == 'preparing')).length,
      kitchenWaiting: all.where((l) => l.station == 'kitchen' && (l.status == 'sent' || l.status == 'preparing')).length,
      barMinutes: 6.5,
      kitchenMinutes: 14,
      voids: 1,
      requests: (_inbox[venueId] ?? const <InboxItem>[]).where((i) => i.kind == 'order').length,
      calls: (_inbox[venueId] ?? const <InboxItem>[]).where((i) => i.kind == 'call').length,
      waiting: (_wait[venueId] ?? const <WaitParty>[]).where((p) => p.status == 'waiting').length,
      methods: methods,
    );
  }

  // ── the door ──────────────────────────────────────────────────────────────
  final _door = <String, List<(DateTime, int)>>{};

  @override
  Future<DoorCount> doorCount(String venueId) async {
    _can(venueId, Cap.floorView);
    final since = nightStart(DateTime.now());
    final taps = (_door[venueId] ??= _seedDoor(venueId)).where((t) => !t.$1.isBefore(since));
    final sum = taps.fold<int>(0, (s, t) => s + t.$2);
    return DoorCount(
      inside: sum < 0 ? 0 : sum,
      cameIn: taps.where((t) => t.$2 > 0).fold(0, (s, t) => s + t.$2),
      capacity: _venues.firstWhere((v) => v.id == venueId).capacity,
    );
  }

  List<(DateTime, int)> _seedDoor(String venueId) {
    if (_venues.firstWhere((v) => v.id == venueId).capacity == null) return [];
    final now = DateTime.now();
    final since = nightStart(now);
    // Never before tonight started, so the demo reads the same at any hour.
    DateTime ago(int m) {
      final t = now.subtract(Duration(minutes: m));
      return t.isBefore(since) ? since : t;
    }

    return [(ago(90), 12), (ago(60), 8), (ago(40), -4), (ago(5), 6)];
  }

  @override
  Future<void> doorTick(String venueId, int n) async {
    _can(venueId, Cap.seatGuests);
    if (n == 0 || n < -12 || n > 12) throw const BackendError('Count 1 to 12 at a time.');
    (_door[venueId] ??= _seedDoor(venueId)).add((DateTime.now(), n));
    doorRev.bump();
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

/// A code a manager made for someone (staff_enrolments, 053). [forMe] marks one made for
/// the demo's own "you" at another venue: typing it joins that venue.
class _Code {
  final String id;
  final String venueId;
  final String name;
  final String email;
  final String? phone;
  final StaffRole role;
  String code;
  final DateTime createdAt;
  DateTime expiresAt;
  int attempts = 0;
  bool closed = false;
  final String addedBy;
  final Venue? forMe;
  _Code({
    required this.id,
    required this.venueId,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.code,
    required this.createdAt,
    required this.expiresAt,
    required this.addedBy,
    this.forMe,
  });

  bool get open => !closed;
}
