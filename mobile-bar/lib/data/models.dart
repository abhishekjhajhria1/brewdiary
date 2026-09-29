// The shapes the venue app works with. Each mirrors a table or a server function's row;
// `fromRow` reads the snake_case JSON PostgREST returns.
import '../logic/roles.dart';
import '../logic/venue_kinds.dart';

double _num(Object? v, [double fallback = 0]) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? fallback,
      _ => fallback,
    };
double? _numOrNull(Object? v) => v == null ? null : _num(v);
int _int(Object? v, [int fallback = 0]) => switch (v) {
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? fallback,
      _ => fallback,
    };
int? _intOrNull(Object? v) => v == null ? null : _int(v);

class AppUser {
  final String id;
  final String? email;
  final String name;
  final String handle;
  const AppUser({required this.id, this.email, required this.name, required this.handle});
}

class Venue {
  final String id;
  final String name;
  final String slug;
  final String createdBy;
  final String? city;
  final VenueKind kind;

  /// The owner's choice where it IS a choice (a restaurant, a café); fixed otherwise.
  final bool servesAlcohol;
  final String country;
  final String? region;
  final String currency;
  final List<int> quietNights;
  final String? geohash;

  /// Shares its anonymised totals with the area heat map, and so sees its spend layer (048).
  final bool areaShare;
  final bool verified;
  final StaffRole myRole;

  const Venue({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdBy,
    this.city,
    this.kind = VenueKind.bar,
    this.servesAlcohol = true,
    this.country = 'IN',
    this.region,
    this.currency = 'INR',
    this.quietNights = const [],
    this.geohash,
    this.areaShare = false,
    this.verified = false,
    this.myRole = StaffRole.bartender,
  });

  factory Venue.fromRow(Map<String, dynamic> v, StaffRole role) => Venue(
        id: v['id'] as String,
        name: v['name'] as String,
        slug: v['slug'] as String,
        createdBy: v['created_by'] as String,
        city: v['city'] as String?,
        kind: VenueKind.parse(v['kind'] as String?),
        servesAlcohol: (v['serves_alcohol'] as bool?) ?? VenueKind.parse(v['kind'] as String?).alwaysAlcohol,
        country: (v['country'] as String?) ?? 'IN',
        region: v['region'] as String?,
        currency: (v['currency'] as String?) ?? 'INR',
        quietNights: ((v['quiet_nights'] as List?) ?? const []).map((d) => _int(d)).toList(),
        geohash: v['geohash'] as String?,
        areaShare: v['area_share'] == true,
        verified: v['verified'] == true,
        myRole: role,
      );

  LegalClass get legal => legalClass(kind, servesAlcohol: servesAlcohol);
  bool get sellsAlcohol => legal != LegalClass.noAlcohol;

  Venue copyWith({String? name, String? city, List<int>? quietNights, String? geohash, bool? servesAlcohol, bool? areaShare, bool? verified}) => Venue(
        id: id,
        name: name ?? this.name,
        slug: slug,
        createdBy: createdBy,
        city: city ?? this.city,
        kind: kind,
        servesAlcohol: servesAlcohol ?? this.servesAlcohol,
        country: country,
        region: region,
        currency: currency,
        quietNights: quietNights ?? this.quietNights,
        geohash: geohash ?? this.geohash,
        areaShare: areaShare ?? this.areaShare,
        verified: verified ?? this.verified,
        myRole: myRole,
      );
}

class StaffMember {
  final String id;
  final String handle;
  final String name;
  final StaffRole role;
  final bool thankable;
  const StaffMember({required this.id, required this.handle, required this.name, required this.role, this.thankable = true});
}

class ProfileHit {
  final String id;
  final String handle;
  final String name;
  const ProfileHit({required this.id, required this.handle, required this.name});
}

enum VerificationStatus { pending, approved, rejected }

class VerificationRequest {
  final VerificationStatus status;
  final String contact;
  final String? note;
  final DateTime createdAt;
  const VerificationRequest({required this.status, required this.contact, this.note, required this.createdAt});
}

class StaffInvite {
  final String code;
  final StaffRole role;
  final DateTime expiresAt;
  const StaffInvite({required this.code, required this.role, required this.expiresAt});
}

/// A room: tonight's party with the venue's name on it.
class Room {
  final String id;
  final String name;
  final String date; // YYYY-MM-DD
  final String inviteCode;
  final DateTime? boardUntil;
  const Room({required this.id, required this.name, required this.date, required this.inviteCode, this.boardUntil});
  bool get boardLive => boardUntil == null ? date == _today() : DateTime.now().isBefore(boardUntil!);
}

String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

class RoomGuest {
  final String id;
  final String name;
  const RoomGuest({required this.id, required this.name});
}

enum PerkKind { visits, spend }

class PerkTier {
  final String id;
  final PerkKind kind;
  final double threshold;
  final String reward;
  final String currency;
  final bool rewardAlcoholic;
  const PerkTier({required this.id, required this.kind, required this.threshold, required this.reward, this.currency = 'INR', this.rewardAlcoholic = false});

  factory PerkTier.fromRow(Map<String, dynamic> r) => PerkTier(
        id: r['id'] as String,
        kind: r['kind'] == 'spend' ? PerkKind.spend : PerkKind.visits,
        threshold: _num(r['threshold']),
        reward: (r['reward'] as String?) ?? '',
        currency: (r['currency'] as String?) ?? 'INR',
        rewardAlcoholic: r['reward_alcoholic'] == true,
      );
}

/// One guest's standing on one tier (perk_status()).
class PerkStanding {
  final String perkId;
  final PerkKind kind;
  final double threshold;
  final String reward;
  final String currency;
  final double progress;
  final bool earned;
  final int claims;
  const PerkStanding({
    required this.perkId,
    required this.kind,
    required this.threshold,
    required this.reward,
    required this.currency,
    required this.progress,
    required this.earned,
    required this.claims,
  });

  factory PerkStanding.fromRow(Map<String, dynamic> r) => PerkStanding(
        perkId: r['perk_id'] as String,
        kind: r['kind'] == 'spend' ? PerkKind.spend : PerkKind.visits,
        threshold: _num(r['threshold']),
        reward: (r['reward'] as String?) ?? '',
        currency: (r['currency'] as String?) ?? 'INR',
        progress: _num(r['progress']),
        earned: r['earned'] == true,
        claims: _int(r['claims']),
      );
}

class MenuItem {
  final String id;
  final String section;
  final String name;
  final String? description;
  final double? price;
  final String? kind; // the diary's DrinkType names, plus 'food'
  final bool noAlcohol;
  final bool available;
  final int position;
  const MenuItem({
    required this.id,
    required this.section,
    required this.name,
    this.description,
    this.price,
    this.kind,
    this.noAlcohol = false,
    this.available = true,
    this.position = 0,
  });

  factory MenuItem.fromRow(Map<String, dynamic> r) => MenuItem(
        id: r['id'] as String,
        section: (r['section'] as String?) ?? 'Menu',
        name: r['name'] as String,
        description: r['description'] as String?,
        price: _numOrNull(r['price']),
        kind: r['kind'] as String?,
        noAlcohol: r['no_alcohol'] == true,
        available: r['available'] != false,
        position: _int(r['position']),
      );

  MenuItem copyWith({String? section, String? name, String? description, double? price, String? kind, bool? noAlcohol, bool? available, int? position}) => MenuItem(
        id: id,
        section: section ?? this.section,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        kind: kind ?? this.kind,
        noAlcohol: noAlcohol ?? this.noAlcohol,
        available: available ?? this.available,
        position: position ?? this.position,
      );
}

/// venue_insights() v2 — counts only. A null split was HIDDEN (fewer than 5 people):
/// render it as "—", never as 0.
class VenueInsights {
  final int rooms;
  final int guests;
  final int? newGuests;
  final int? returningGuests;
  final int quietVisits;
  final int otherVisits;
  final int? perksEarned;
  final int perksClaimed;
  final int tabs;
  final double takings;
  final int kudos;
  final List<int> visitsByDow; // index 0 = Sunday
  final int prevGuests;
  final double prevTakings;
  const VenueInsights({
    this.rooms = 0,
    this.guests = 0,
    this.newGuests,
    this.returningGuests,
    this.quietVisits = 0,
    this.otherVisits = 0,
    this.perksEarned,
    this.perksClaimed = 0,
    this.tabs = 0,
    this.takings = 0,
    this.kudos = 0,
    this.visitsByDow = const [0, 0, 0, 0, 0, 0, 0],
    this.prevGuests = 0,
    this.prevTakings = 0,
  });

  factory VenueInsights.fromRow(Map<String, dynamic> r) => VenueInsights(
        rooms: _int(r['rooms']),
        guests: _int(r['guests']),
        newGuests: _intOrNull(r['new_guests']),
        returningGuests: _intOrNull(r['returning_guests']),
        quietVisits: _int(r['quiet_visits']),
        otherVisits: _int(r['other_visits']),
        perksEarned: _intOrNull(r['perks_earned']),
        perksClaimed: _int(r['perks_claimed']),
        tabs: _int(r['tabs']),
        takings: _num(r['takings']),
        kudos: _int(r['kudos']),
        visitsByDow: r['visits_by_dow'] is List ? (r['visits_by_dow'] as List).map((x) => _int(x)).toList() : const [0, 0, 0, 0, 0, 0, 0],
        prevGuests: _int(r['prev_guests']),
        prevTakings: _num(r['prev_takings']),
      );
}

/// A public fact about a place near the venue (049): an event, an opening, a price.
class AreaSignal {
  final String id;
  final String kind; // event | opening | closing | holiday | hours | price | venue | trend | weather | news
  final String title;
  final String? detail;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final String? cell;
  final Map<String, Object> facts;
  final String source;
  final String? sourceUrl;
  const AreaSignal({required this.id, required this.kind, required this.title, this.detail, this.startsOn, this.endsOn, this.cell, this.facts = const {}, required this.source, this.sourceUrl});

  factory AreaSignal.fromRow(Map<String, dynamic> r) => AreaSignal(
        id: r['id'] as String,
        kind: r['kind'] as String,
        title: r['title'] as String,
        detail: r['detail'] as String?,
        startsOn: r['starts_on'] == null ? null : DateTime.tryParse(r['starts_on'] as String),
        endsOn: r['ends_on'] == null ? null : DateTime.tryParse(r['ends_on'] as String),
        cell: r['cell'] as String?,
        facts: {for (final e in ((r['facts'] as Map?) ?? const {}).entries) '${e.key}': e.value as Object},
        source: (r['source'] as String?) ?? '',
        sourceUrl: r['source_url'] as String?,
      );
}

class AreaTrend {
  final String kind; // 'drink' | 'mood'
  final String name;
  final int users;
  const AreaTrend({required this.kind, required this.name, required this.users});
}

/// The first-party card staff see for one guest (venue_guest_card()).
class GuestCard {
  final int visits;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final int tabs;
  final double totalSpend;
  final int perksClaimed;
  final bool hasEarned;
  final bool beenHere;
  final String note;
  final List<String> tags;
  const GuestCard({
    this.visits = 0,
    this.firstSeen,
    this.lastSeen,
    this.tabs = 0,
    this.totalSpend = 0,
    this.perksClaimed = 0,
    this.hasEarned = false,
    this.beenHere = false,
    this.note = '',
    this.tags = const [],
  });

  factory GuestCard.fromRow(Map<String, dynamic> r) => GuestCard(
        visits: _int(r['visits']),
        firstSeen: r['first_seen'] == null ? null : DateTime.tryParse(r['first_seen'] as String),
        lastSeen: r['last_seen'] == null ? null : DateTime.tryParse(r['last_seen'] as String),
        tabs: _int(r['tabs']),
        totalSpend: _num(r['total_spend']),
        perksClaimed: _int(r['perks_claimed']),
        hasEarned: r['has_earned'] == true,
        beenHere: r['been_here'] == true,
        note: (r['note'] as String?) ?? '',
        tags: r['tags'] is List ? (r['tags'] as List).map((t) => '$t').toList() : const [],
      );
}

class KudosLine {
  final String reason;
  final int n;
  const KudosLine(this.reason, this.n);
}

// ── the counter (050) ───────────────────────────────────────────────────────
const alcoholCategories = {'spirit', 'beer', 'wine', 'other_alcohol'};

/// One thing on the till's shelf. Sold by weight → price is per kg, quantities are grams.
class ShopProduct {
  final String id;
  final String name;
  final String? brand;
  final String category; // spirit | beer | wine | other_alcohol | soft | food | sweet | other
  final double? size;
  final String unit; // ml | g | piece
  final bool byWeight;
  final double price;
  final double? mrp;
  final String? barcode;
  final bool active;
  const ShopProduct({required this.id, required this.name, this.brand, required this.category, this.size, this.unit = 'piece', this.byWeight = false, required this.price, this.mrp, this.barcode, this.active = true});

  bool get isAlcohol => alcoholCategories.contains(category);

  /// "750 ml", "per kg", "" — what one unit is.
  String get pack => byWeight ? 'per kg' : (size == null ? '' : '${size!.toStringAsFixed(size! % 1 == 0 ? 0 : 1)} ${unit == 'piece' ? 'pc' : unit}');

  factory ShopProduct.fromRow(Map<String, dynamic> r) => ShopProduct(
        id: r['id'] as String,
        name: r['name'] as String,
        brand: r['brand'] as String?,
        category: r['category'] as String,
        size: (r['size'] as num?)?.toDouble(),
        unit: (r['unit'] as String?) ?? 'piece',
        byWeight: r['sold_by'] == 'weight',
        price: (r['price'] as num).toDouble(),
        mrp: (r['mrp'] as num?)?.toDouble(),
        barcode: r['barcode'] as String?,
        active: r['active'] != false,
      );

  Map<String, dynamic> toRow(String venueId) => {
        'id': id,
        'venue_id': venueId,
        'name': name.trim(),
        'brand': (brand ?? '').trim().isEmpty ? null : brand!.trim(),
        'category': category,
        'size': size,
        'unit': unit,
        'sold_by': byWeight ? 'weight' : 'unit',
        'price': price,
        'mrp': mrp,
        'barcode': (barcode ?? '').trim().isEmpty ? null : barcode!.trim(),
        'active': active,
      };
}

class ShopSupplier {
  final String id;
  final String name;
  final String? licence;
  const ShopSupplier({required this.id, required this.name, this.licence});
}

/// What the law allows at this till right now (store_sale_status()).
class SaleStatus {
  final bool researched;
  final bool allowedNow;
  final String? reason;
  final int? minAge;
  final int? maxMl;
  final String? saleStart; // HH:MM
  final String? saleEnd;
  const SaleStatus({required this.researched, required this.allowedNow, this.reason, this.minAge, this.maxMl, this.saleStart, this.saleEnd});
}

/// One line of the excise register: one alcohol product on one day.
class RegisterRow {
  final DateTime day;
  final String productId;
  final String name;
  final String? brand;
  final double? size;
  final int opening, received, sold, other, closing;
  const RegisterRow({required this.day, required this.productId, required this.name, this.brand, this.size, required this.opening, required this.received, required this.sold, required this.other, required this.closing});
}
