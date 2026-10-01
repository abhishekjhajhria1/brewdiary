// The shapes the venue app works with. Each mirrors a table or a server function's row;
// `fromRow` reads the snake_case JSON PostgREST returns.
import '../logic/roles.dart';
import '../logic/staff.dart';
import '../logic/venue_kinds.dart';

export '../logic/staff.dart' show StaffStatus, ClaimError;

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

  /// Guests may order and call staff from the table's link (051). Off by default.
  final bool tableService;

  /// How many people the licence allows inside at once (052) — the door counts against it.
  final int? capacity;
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
    this.tableService = false,
    this.capacity,
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
        tableService: v['table_service'] == true,
        capacity: (v['capacity'] as num?)?.toInt(),
        verified: v['verified'] == true,
        myRole: role,
      );

  LegalClass get legal => legalClass(kind, servesAlcohol: servesAlcohol);
  bool get sellsAlcohol => legal != LegalClass.noAlcohol;

  /// [capacity] 0 clears it.
  Venue copyWith({String? name, String? city, List<int>? quietNights, String? geohash, bool? servesAlcohol, bool? areaShare, bool? tableService, int? capacity, bool? verified}) => Venue(
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
        tableService: tableService ?? this.tableService,
        capacity: capacity == null ? this.capacity : (capacity > 0 ? capacity : null),
        verified: verified ?? this.verified,
        myRole: myRole,
      );
}

/// Someone on the team as the roster shows them (team_roster, 053). Owners and managers
/// also see who's waiting and who's paused, phone numbers, and why; everyone else sees the
/// active team. [name] is what the venue calls them (the details the owner entered), else
/// their profile name.
class StaffMember {
  final String id;
  final String handle;
  final String name;
  final StaffRole role;
  final bool thankable;
  final StaffStatus status;

  /// Owners and managers, and the person themself, only.
  final String? phone;
  final DateTime? joinedAt;
  final String? approvedBy;
  final DateTime? lockedAt;
  final String? lockReason;
  final String? reportTo;

  /// On the clock since — shown to the team so a shift lead knows who's in.
  final DateTime? onShiftSince;

  const StaffMember({
    required this.id,
    required this.handle,
    required this.name,
    required this.role,
    this.thankable = true,
    this.status = StaffStatus.active,
    this.phone,
    this.joinedAt,
    this.approvedBy,
    this.lockedAt,
    this.lockReason,
    this.reportTo,
    this.onShiftSince,
  });

  factory StaffMember.fromRoster(Map<String, dynamic> r) {
    final handle = (r['handle'] as String?) ?? '';
    final staffName = (r['staff_name'] as String?)?.trim();
    return StaffMember(
      id: r['user_id'] as String,
      handle: handle,
      name: (staffName?.isNotEmpty ?? false) ? staffName! : ((r['display_name'] as String?) ?? (handle.isEmpty ? 'someone' : handle)),
      role: StaffRole.parse(r['role'] as String?),
      thankable: r['thankable'] != false,
      status: StaffStatus.parse(r['status'] as String?),
      phone: r['phone'] as String?,
      joinedAt: _time(r['joined_at']),
      approvedBy: r['approved_by'] as String?,
      lockedAt: _time(r['locked_at']),
      lockReason: r['lock_reason'] as String?,
      reportTo: r['report_to'] as String?,
      onShiftSince: _time(r['on_shift_since']),
    );
  }

  bool get onShift => onShiftSince != null;

  StaffMember copyWith({
    String? name,
    StaffRole? role,
    bool? thankable,
    StaffStatus? status,
    String? phone,
    bool clearPhone = false,
    DateTime? lockedAt,
    String? lockReason,
    String? reportTo,
    bool clearLock = false,
    DateTime? onShiftSince,
    bool clearShift = false,
    String? approvedBy,
  }) =>
      StaffMember(
        id: id,
        handle: handle,
        name: name ?? this.name,
        role: role ?? this.role,
        thankable: thankable ?? this.thankable,
        status: status ?? this.status,
        phone: clearPhone ? null : (phone ?? this.phone),
        joinedAt: joinedAt,
        approvedBy: approvedBy ?? this.approvedBy,
        lockedAt: clearLock ? null : (lockedAt ?? this.lockedAt),
        lockReason: clearLock ? null : (lockReason ?? this.lockReason),
        reportTo: clearLock ? null : (reportTo ?? this.reportTo),
        onShiftSince: clearShift ? null : (onShiftSince ?? this.onShiftSince),
      );
}

DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class ProfileHit {
  final String id;
  final String handle;
  final String name;
  const ProfileHit({required this.id, required this.handle, required this.name});
}

/// The taste a guest shared when they opened this venue's table or menu link (056):
/// the card worked out on their phone. Never their diary, never other venues.
class GuestTaste {
  final List<String> into;
  final List<String> usually;
  final List<String> moods;
  final List<String> diet;
  final List<String> allergies;
  final bool alcoholFreeOften;
  final bool dryTonight;
  const GuestTaste({this.into = const [], this.usually = const [], this.moods = const [], this.diet = const [], this.allergies = const [], this.alcoholFreeOften = false, this.dryTonight = false});

  static List<String> _list(Object? v) => [for (final x in (v is List ? v : const [])) if (x is String && x.trim().isNotEmpty) x.trim()];

  factory GuestTaste.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return GuestTaste(
      into: _list(m['into']),
      usually: _list(m['usually']),
      moods: _list(m['moods']),
      diet: _list(m['diet']),
      allergies: _list(m['allergies']),
      alcoholFreeOften: m['alcohol_free_often'] == true,
      dryTonight: m['dry_tonight'] == true,
    );
  }

  bool get isEmpty => into.isEmpty && usually.isEmpty && moods.isEmpty && diet.isEmpty && allergies.isEmpty && !alcoholFreeOften && !dryTonight;
}

/// Someone in tonight who shared their taste with this venue.
class GuestTonight {
  final String userId;
  final String name;
  final String handle;
  final String? tableLabel;
  final GuestTaste taste;
  final DateTime sharedAt;
  const GuestTonight({required this.userId, required this.name, required this.handle, this.tableLabel, required this.taste, required this.sharedAt});
  ProfileHit get hit => ProfileHit(id: userId, handle: handle, name: name);
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

// ── staff access (053): the owner's code, lock-out, the history, the clock ───
/// The owner's code for a new employee, shown ONCE (only its hash is kept).
class StaffCode {
  final String? enrolmentId;
  final String code;
  final DateTime expiresAt;
  const StaffCode({this.enrolmentId, required this.code, required this.expiresAt});
}

/// Someone a manager added who hasn't typed their code yet (staff_enrolments_open).
class Enrolment {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final StaffRole role;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int attempts;
  final String? addedBy;
  const Enrolment({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.createdAt,
    required this.expiresAt,
    this.attempts = 0,
    this.addedBy,
  });

  factory Enrolment.fromRow(Map<String, dynamic> r) => Enrolment(
        id: r['id'] as String,
        name: (r['staff_name'] as String?) ?? '',
        email: (r['email'] as String?) ?? '',
        phone: r['phone'] as String?,
        role: StaffRole.parse(r['role'] as String?),
        createdAt: _time(r['created_at']) ?? DateTime.now(),
        expiresAt: _time(r['expires_at']) ?? DateTime.now(),
        attempts: _int(r['attempts']),
        addedBy: r['added_by'] as String?,
      );

  bool get expired => !expiresAt.isAfter(DateTime.now());

  /// Five wrong tries: the code is dead until a manager makes a new one.
  bool get usedUp => attempts >= 5;
}

/// A venue that added the email I signed in with, waiting for the owner's code
/// (my_staff_enrolments). Never carries the code itself.
class MyEnrolment {
  final String id;
  final String venueId;
  final String venueName;
  final VenueKind venueKind;
  final StaffRole role;
  final String? staffName;
  final String? addedBy;
  final DateTime expiresAt;
  final int triesLeft;
  const MyEnrolment({
    required this.id,
    required this.venueId,
    required this.venueName,
    this.venueKind = VenueKind.bar,
    required this.role,
    this.staffName,
    this.addedBy,
    required this.expiresAt,
    this.triesLeft = 5,
  });

  factory MyEnrolment.fromRow(Map<String, dynamic> r) => MyEnrolment(
        id: r['id'] as String,
        venueId: r['venue_id'] as String,
        venueName: (r['venue_name'] as String?) ?? 'a venue',
        venueKind: VenueKind.parse(r['venue_kind'] as String?),
        role: StaffRole.parse(r['role'] as String?),
        staffName: r['staff_name'] as String?,
        addedBy: r['added_by'] as String?,
        expiresAt: _time(r['expires_at']) ?? DateTime.now(),
        triesLeft: _int(r['tries_left'], 5),
      );
}

/// What typing the owner's code did (claim_staff_enrolment). A wrong code is an answer,
/// not an error: the database counts the try and says how many are left.
class ClaimResult {
  final bool ok;
  final String? venueId;
  final String? venueName;
  final StaffRole? role;
  final ClaimError? error;
  final int? left;
  const ClaimResult({required this.ok, this.venueId, this.venueName, this.role, this.error, this.left});

  factory ClaimResult.fromJson(Map<String, dynamic> j) => j['ok'] == true
      ? ClaimResult(ok: true, venueId: j['venue_id'] as String?, venueName: j['venue'] as String?, role: StaffRole.parse(j['role'] as String?))
      : ClaimResult(ok: false, error: ClaimError.parse(j['error'] as String?), left: _intOrNull(j['left']));
}

/// A venue where I'm waiting for a yes, or paused (my_staff_status). It carries the
/// venue's name because a paused person can no longer read the venue itself.
class StaffAccess {
  final String venueId;
  final String venueName;
  final VenueKind venueKind;
  final StaffRole role;
  final StaffStatus status;
  final String? lockReason;
  final DateTime? lockedAt;
  final String? reportTo;
  final String? reportToRole;
  const StaffAccess({
    required this.venueId,
    required this.venueName,
    this.venueKind = VenueKind.bar,
    required this.role,
    required this.status,
    this.lockReason,
    this.lockedAt,
    this.reportTo,
    this.reportToRole,
  });

  factory StaffAccess.fromRow(Map<String, dynamic> r) => StaffAccess(
        venueId: r['venue_id'] as String,
        venueName: (r['venue_name'] as String?) ?? 'a venue',
        venueKind: VenueKind.parse(r['venue_kind'] as String?),
        role: StaffRole.parse(r['role'] as String?),
        status: StaffStatus.parse(r['status'] as String?),
        lockReason: r['lock_reason'] as String?,
        lockedAt: _time(r['locked_at']),
        reportTo: r['report_to'] as String?,
        reportToRole: r['report_to_role'] as String?,
      );

  bool get locked => status == StaffStatus.locked;
}

/// One line of the team's history (staff_history). Names are resolved by the database.
class StaffEvent {
  final int id;
  final String kind;
  final String? actor;
  final String? subject;
  final Map<String, dynamic> detail;
  final DateTime at;
  const StaffEvent({required this.id, required this.kind, this.actor, this.subject, this.detail = const {}, required this.at});

  factory StaffEvent.fromRow(Map<String, dynamic> r) => StaffEvent(
        id: _int(r['id']),
        kind: (r['kind'] as String?) ?? '',
        actor: r['actor'] as String?,
        subject: r['subject'] as String?,
        detail: r['detail'] is Map ? Map<String, dynamic>.from(r['detail'] as Map) : const {},
        at: _time(r['created_at']) ?? DateTime.now(),
      );
}

/// Hours on the clock for one person since a date (shift_hours) — for pay, listed by name.
/// [minutes] are worked minutes, after unpaid breaks (054).
class ShiftRow {
  final String userId;
  final String name;
  final StaffRole role;
  final DateTime? onSince;
  final int minutes;
  final int breakMinutes;

  /// On a break right now, since when (054) — the floor needs to know who's off it.
  final DateTime? onBreakSince;
  const ShiftRow({required this.userId, required this.name, required this.role, this.onSince, required this.minutes, this.breakMinutes = 0, this.onBreakSince});

  factory ShiftRow.fromRow(Map<String, dynamic> r) => ShiftRow(
        userId: r['user_id'] as String,
        name: (r['name'] as String?) ?? 'someone',
        role: StaffRole.parse(r['role'] as String?),
        onSince: _time(r['on_since']),
        minutes: _int(r['minutes']),
        breakMinutes: _int(r['break_minutes']),
        onBreakSince: _time(r['on_break_since']),
      );
}

// ── the rota, breaks and payroll (054) ───────────────────────────────────────
/// Someone asked to give a shift away, or to take one (rota_swaps). [status] is 'offered'
/// (waiting for a taker) or 'taken' (waiting for a manager's yes).
class RotaSwap {
  final String id;
  final String status;
  final String? fromUser;
  final String? toUser;
  final String? toName;
  const RotaSwap({required this.id, required this.status, this.fromUser, this.toUser, this.toName});

  factory RotaSwap.fromJson(Map<String, dynamic> j) => RotaSwap(
        id: j['id'] as String,
        status: (j['status'] as String?) ?? 'offered',
        fromUser: j['from_user'] as String?,
        toUser: j['to_user'] as String?,
        toName: j['to_name'] as String?,
      );

  bool get taken => status == 'taken';
}

/// A planned shift. [userId] null = an OPEN shift anyone who can work the role may ask for.
class RotaShift {
  final String id;
  final String? userId;
  final String? name;

  /// False when the person is paused or has left: someone should cover it.
  final bool active;
  final StaffRole role;
  final String? areaId;
  final String? area;
  final DateTime startsAt;
  final DateTime endsAt;
  final int breakMinutes;
  final String? note;
  final bool published;
  final RotaSwap? swap;
  const RotaShift({
    required this.id,
    this.userId,
    this.name,
    this.active = true,
    required this.role,
    this.areaId,
    this.area,
    required this.startsAt,
    required this.endsAt,
    this.breakMinutes = 0,
    this.note,
    this.published = false,
    this.swap,
  });

  factory RotaShift.fromJson(Map<String, dynamic> j) => RotaShift(
        id: j['id'] as String,
        userId: j['user_id'] as String?,
        name: j['name'] as String?,
        active: j['active'] != false,
        role: StaffRole.parse(j['role'] as String?),
        areaId: j['area_id'] as String?,
        area: j['area'] as String?,
        startsAt: _time(j['starts_at']) ?? DateTime.now(),
        endsAt: _time(j['ends_at']) ?? DateTime.now(),
        breakMinutes: _int(j['break_minutes']),
        note: j['note'] as String?,
        published: j['published'] == true,
        swap: j['swap'] is Map ? RotaSwap.fromJson(Map<String, dynamic>.from(j['swap'] as Map)) : null,
      );

  bool get open => userId == null;

  /// Planned minutes: the shift less its planned break.
  int get minutes => endsAt.difference(startsAt).inMinutes - breakMinutes;

  RotaShift copyWith({String? userId, bool clearUser = false, String? name, bool? published, RotaSwap? swap, bool clearSwap = false, bool? active}) => RotaShift(
        id: id,
        userId: clearUser ? null : (userId ?? this.userId),
        name: clearUser ? null : (name ?? this.name),
        active: active ?? this.active,
        role: role,
        areaId: areaId,
        area: area,
        startsAt: startsAt,
        endsAt: endsAt,
        breakMinutes: breakMinutes,
        note: note,
        published: published ?? this.published,
        swap: clearSwap ? null : (swap ?? this.swap),
      );
}

/// Asked-for or given time off (time_off). [endsAt] is the start of the day after the last.
class TimeOff {
  final String id;
  final String userId;
  final String? name;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status; // requested | approved | declined | cancelled
  final String? note;
  final String? decidedBy;
  const TimeOff({required this.id, required this.userId, this.name, required this.startsAt, required this.endsAt, required this.status, this.note, this.decidedBy});

  factory TimeOff.fromJson(Map<String, dynamic> j) => TimeOff(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String?,
        startsAt: _time(j['starts_at']) ?? DateTime.now(),
        endsAt: _time(j['ends_at']) ?? DateTime.now(),
        status: (j['status'] as String?) ?? 'requested',
        note: j['note'] as String?,
        decidedBy: j['decided_by'] as String?,
      );

  /// The last day off (the day before [endsAt]).
  DateTime get lastDay => DateTime(endsAt.year, endsAt.month, endsAt.day).subtract(const Duration(days: 1));
}

/// Someone on the team as the rota sees them. [cannotWork] (0 = Sunday … 6 = Saturday) is
/// there for whoever plans, and for the person themself.
class RotaMember {
  final String userId;
  final String name;
  final StaffRole role;
  final List<int>? cannotWork;
  const RotaMember({required this.userId, required this.name, required this.role, this.cannotWork});

  factory RotaMember.fromJson(Map<String, dynamic> j) => RotaMember(
        userId: j['user_id'] as String,
        name: (j['name'] as String?) ?? 'someone',
        role: StaffRole.parse(j['role'] as String?),
        cannotWork: j['cannot_work'] is List ? [for (final d in j['cannot_work'] as List) _int(d)] : null,
      );
}

/// A week (or up to five) of the rota, as the caller may see it (rota_week).
class RotaWeek {
  final bool canPlan;
  final List<RotaShift> shifts;
  final List<TimeOff> timeOff;
  final List<RotaMember> team;
  const RotaWeek({required this.canPlan, required this.shifts, required this.timeOff, required this.team});

  factory RotaWeek.fromJson(Map<String, dynamic> j) => RotaWeek(
        canPlan: j['can_plan'] == true,
        shifts: [for (final x in (j['shifts'] as List? ?? const [])) RotaShift.fromJson(Map<String, dynamic>.from(x as Map))],
        timeOff: [for (final x in (j['time_off'] as List? ?? const [])) TimeOff.fromJson(Map<String, dynamic>.from(x as Map))],
        team: [for (final x in (j['team'] as List? ?? const [])) RotaMember.fromJson(Map<String, dynamic>.from(x as Map))],
      );
}

/// Where I stand on the clock (my_shift_state): on since, on a break since, and unpaid
/// break minutes so far this shift.
class ShiftState {
  final DateTime onSince;
  final DateTime? breakSince;
  final bool breakPaid;
  final int breakMinutes;
  const ShiftState({required this.onSince, this.breakSince, this.breakPaid = false, this.breakMinutes = 0});

  factory ShiftState.fromRow(Map<String, dynamic> r) => ShiftState(
        onSince: _time(r['on_since']) ?? DateTime.now(),
        breakSince: _time(r['break_since']),
        breakPaid: r['break_paid'] == true,
        breakMinutes: _int(r['break_minutes']),
      );

  bool get onBreak => breakSince != null;
}

/// One change to a worked shift's times, kept for good (shift_corrections).
class ShiftCorrection {
  final String kind; // corrected | added
  final String reason;
  final DateTime at;
  final String? by;
  final DateTime? oldStarted;
  final DateTime? oldEnded;
  final DateTime newStarted;
  final DateTime newEnded;
  const ShiftCorrection({required this.kind, required this.reason, required this.at, this.by, this.oldStarted, this.oldEnded, required this.newStarted, required this.newEnded});

  factory ShiftCorrection.fromJson(Map<String, dynamic> j) => ShiftCorrection(
        kind: (j['kind'] as String?) ?? 'corrected',
        reason: (j['reason'] as String?) ?? '',
        at: _time(j['at']) ?? DateTime.now(),
        by: j['by'] as String?,
        oldStarted: _time(j['old_started']),
        oldEnded: _time(j['old_ended']),
        newStarted: _time(j['new_started']) ?? DateTime.now(),
        newEnded: _time(j['new_ended']) ?? DateTime.now(),
      );
}

/// A break on a worked shift (shift_breaks). Unpaid unless an owner or manager marked it
/// paid — nobody decides that for themself.
class ShiftBreak {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool paid;
  const ShiftBreak({required this.id, required this.startedAt, this.endedAt, this.paid = false});

  factory ShiftBreak.fromJson(Map<String, dynamic> j) => ShiftBreak(
        id: j['id'] as String,
        startedAt: _time(j['started_at']) ?? DateTime.now(),
        endedAt: _time(j['ended_at']),
        paid: j['paid'] == true,
      );

  /// Whole minutes, rounded (still going: so far).
  int get minutes => ((endedAt ?? DateTime.now()).difference(startedAt).inSeconds / 60).round();
}

/// A worked shift on someone's timesheet (staff_timesheet).
class TimesheetShift {
  final String shiftId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int workedMinutes;
  final int unpaidBreakMinutes;
  final int paidBreakMinutes;
  final List<ShiftCorrection> corrections;
  final List<ShiftBreak> breaks;
  const TimesheetShift({
    required this.shiftId,
    required this.startedAt,
    this.endedAt,
    required this.workedMinutes,
    this.unpaidBreakMinutes = 0,
    this.paidBreakMinutes = 0,
    this.corrections = const [],
    this.breaks = const [],
  });

  factory TimesheetShift.fromRow(Map<String, dynamic> r) => TimesheetShift(
        shiftId: r['shift_id'] as String,
        startedAt: _time(r['started_at']) ?? DateTime.now(),
        endedAt: _time(r['ended_at']),
        workedMinutes: _int(r['worked_minutes']),
        unpaidBreakMinutes: _int(r['unpaid_break_minutes']),
        paidBreakMinutes: _int(r['paid_break_minutes']),
        corrections: [
          for (final c in (r['corrections'] is List ? r['corrections'] as List : const []))
            ShiftCorrection.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        breaks: [
          for (final b in (r['breaks'] is List ? r['breaks'] as List : const [])) ShiftBreak.fromJson(Map<String, dynamic>.from(b as Map)),
        ],
      );

  bool get corrected => corrections.isNotEmpty;
}

/// One person's day for payroll (payroll_days), in the venue's time zone. [role] is 'left'
/// for someone no longer on the team; [pay] is null when no rate was set.
class PayrollDay {
  final String userId;
  final String name;
  final String role;
  final DateTime day;
  final int shifts;
  final String? firstIn;
  final String? lastOut;
  final int workedMinutes;
  final int unpaidBreakMinutes;
  final int paidBreakMinutes;
  final int plannedMinutes;
  final bool stillOn;
  final bool corrected;
  final double? hourlyRate;
  final double? pay;
  const PayrollDay({
    required this.userId,
    required this.name,
    required this.role,
    required this.day,
    this.shifts = 0,
    this.firstIn,
    this.lastOut,
    this.workedMinutes = 0,
    this.unpaidBreakMinutes = 0,
    this.paidBreakMinutes = 0,
    this.plannedMinutes = 0,
    this.stillOn = false,
    this.corrected = false,
    this.hourlyRate,
    this.pay,
  });

  factory PayrollDay.fromJson(Map<String, dynamic> r) {
    final d = DateTime.tryParse('${r['day']}') ?? DateTime.now();
    return PayrollDay(
      userId: r['user_id'] as String,
      name: (r['name'] as String?) ?? 'someone',
      role: (r['role'] as String?) ?? '',
      day: DateTime(d.year, d.month, d.day),
      shifts: _int(r['shifts']),
      firstIn: r['first_in'] as String?,
      lastOut: r['last_out'] as String?,
      workedMinutes: _int(r['worked_minutes']),
      unpaidBreakMinutes: _int(r['unpaid_break_minutes']),
      paidBreakMinutes: _int(r['paid_break_minutes']),
      plannedMinutes: _int(r['planned_minutes']),
      stillOn: r['still_on'] == true,
      corrected: r['corrected'] == true,
      hourlyRate: _numOrNull(r['hourly_rate']),
      pay: _numOrNull(r['pay']),
    );
  }
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
    this.station = 'bar',
    this.diet,
    this.allergens = const [],
  });

  /// Where its ticket goes (051): the bar, the kitchen, or nowhere (served as is).
  final String station;

  /// India's menu mark: veg, non_veg, egg or vegan (null when unmarked).
  final String? diet;

  /// From the EU's 14.
  final List<String> allergens;

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
        station: (r['station'] as String?) ?? (r['kind'] == 'food' ? 'kitchen' : 'bar'),
        diet: r['diet'] as String?,
        allergens: [for (final a in (r['allergens'] as List?) ?? const []) '$a'],
      );

  MenuItem copyWith({String? section, String? name, String? description, double? price, String? kind, bool? noAlcohol, bool? available, int? position, String? station, String? diet, List<String>? allergens}) => MenuItem(
        id: id,
        section: section ?? this.section,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        kind: kind ?? this.kind,
        noAlcohol: noAlcohol ?? this.noAlcohol,
        available: available ?? this.available,
        position: position ?? this.position,
        station: station ?? this.station,
        diet: diet ?? this.diet,
        allergens: allergens ?? this.allergens,
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

// ── service (051) ───────────────────────────────────────────────────────────
class VenueArea {
  final String id;
  final String name;
  final int position;
  const VenueArea({required this.id, required this.name, this.position = 0});
}

class VenueTable {
  final String id;
  final String? areaId;
  final String label;
  final int seats;

  /// What the table's QR / NFC tag carries: bwdy.site/t/<code>.
  final String code;
  final bool active;
  final int position;
  const VenueTable({required this.id, this.areaId, required this.label, this.seats = 4, required this.code, this.active = true, this.position = 0});

  factory VenueTable.fromRow(Map<String, dynamic> r) => VenueTable(
        id: r['id'] as String,
        areaId: r['area_id'] as String?,
        label: r['label'] as String,
        seats: _int(r['seats']),
        code: r['code'] as String,
        active: r['active'] != false,
        position: _int(r['position']),
      );
}

class ServiceTab {
  final String id;
  final String? tableId;
  final String? name;
  final int? covers;
  final String status; // open | closed | void
  final DateTime openedAt;
  final double? subtotal;
  final double? tip;
  const ServiceTab({required this.id, this.tableId, this.name, this.covers, this.status = 'open', required this.openedAt, this.subtotal, this.tip});

  factory ServiceTab.fromRow(Map<String, dynamic> r) => ServiceTab(
        id: r['id'] as String,
        tableId: r['table_id'] as String?,
        name: r['name'] as String?,
        covers: (r['covers'] as num?)?.toInt(),
        status: (r['status'] as String?) ?? 'open',
        openedAt: DateTime.parse(r['opened_at'] as String).toLocal(),
        subtotal: _numOrNull(r['subtotal']),
        tip: _numOrNull(r['tip']),
      );
}

class OrderLine {
  final String id;
  final String tabId;
  final String? menuItemId;
  final String name;
  final double unitPrice;
  final int qty;
  final String? note;
  final int? seat;
  final String station; // bar | kitchen | none
  final String status; // sent | preparing | ready | served | void
  final String source; // staff | guest
  final DateTime createdAt;
  final DateTime? readyAt;
  final String? voidReason;

  /// For station tickets: where it's going.
  final String? tableLabel;
  final String? tabName;
  const OrderLine({
    required this.id,
    required this.tabId,
    this.menuItemId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    this.note,
    this.seat,
    this.station = 'bar',
    this.status = 'sent',
    this.source = 'staff',
    required this.createdAt,
    this.readyAt,
    this.voidReason,
    this.tableLabel,
    this.tabName,
  });

  double get total => status == 'void' ? 0 : unitPrice * qty;

  OrderLine copyWith({String? status, DateTime? readyAt, String? voidReason}) => OrderLine(
        id: id,
        tabId: tabId,
        menuItemId: menuItemId,
        name: name,
        unitPrice: unitPrice,
        qty: qty,
        note: note,
        seat: seat,
        station: station,
        status: status ?? this.status,
        source: source,
        createdAt: createdAt,
        readyAt: readyAt ?? this.readyAt,
        voidReason: voidReason ?? this.voidReason,
        tableLabel: tableLabel,
        tabName: tabName,
      );

  factory OrderLine.fromRow(Map<String, dynamic> r) {
    final tab = r['tab'] as Map?;
    final table = tab?['table'] as Map?;
    return OrderLine(
      id: r['id'] as String,
      tabId: r['tab_id'] as String,
      menuItemId: r['menu_item_id'] as String?,
      name: r['name'] as String,
      unitPrice: _numOrNull(r['unit_price']) ?? 0,
      qty: _int(r['qty']),
      note: r['note'] as String?,
      seat: (r['seat'] as num?)?.toInt(),
      station: (r['station'] as String?) ?? 'bar',
      status: (r['status'] as String?) ?? 'sent',
      source: (r['source'] as String?) ?? 'staff',
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      readyAt: r['ready_at'] == null ? null : DateTime.parse(r['ready_at'] as String).toLocal(),
      voidReason: r['void_reason'] as String?,
      tableLabel: table?['label'] as String?,
      tabName: tab?['name'] as String?,
    );
  }
}

/// A guest's order request or a table call, as the floor's inbox shows it — never who.
class InboxItem {
  final String kind; // order | call
  final String id;
  final String tableId;
  final String tableLabel;
  final DateTime createdAt;
  final List<({String item, String name, int qty, String? note, bool alcohol})> lines;
  final String? note;
  final String? callKind; // staff | bill | water
  final bool hasAlcohol;
  const InboxItem({required this.kind, required this.id, required this.tableId, required this.tableLabel, required this.createdAt, this.lines = const [], this.note, this.callKind, this.hasAlcohol = false});

  factory InboxItem.fromRow(Map<String, dynamic> r) => InboxItem(
        kind: r['item_kind'] as String,
        id: r['id'] as String,
        tableId: r['table_id'] as String,
        tableLabel: (r['table_label'] as String?) ?? '',
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        lines: [
          for (final l in (r['lines'] as List?) ?? const [])
            (item: '${l['item']}', name: '${l['name']}', qty: (l['qty'] as num).toInt(), note: l['note'] as String?, alcohol: l['alcohol'] == true),
        ],
        note: r['note'] as String?,
        callKind: r['call_kind'] as String?,
        hasAlcohol: r['has_alcohol'] == true,
      );
}

class WaitParty {
  final String id;
  final String name;
  final int party;
  final int? quotedMin;
  final String? note;
  final String status; // waiting | seated | left
  final DateTime createdAt;
  const WaitParty({required this.id, required this.name, required this.party, this.quotedMin, this.note, this.status = 'waiting', required this.createdAt});
}

/// Tonight at the door (door_count()): counts, never people.
class DoorCount {
  final int inside;
  final int cameIn;
  final int? capacity;
  const DoorCount({this.inside = 0, this.cameIn = 0, this.capacity});
}

/// The live board (service_board()): business numbers only.
class ServiceBoard {
  final int openTabs, covers, bills, barWaiting, kitchenWaiting, voids, requests, calls, waiting;
  final double sales, tips;
  final double? barMinutes, kitchenMinutes;
  final Map<String, double> methods;
  const ServiceBoard({
    this.openTabs = 0,
    this.covers = 0,
    this.bills = 0,
    this.barWaiting = 0,
    this.kitchenWaiting = 0,
    this.voids = 0,
    this.requests = 0,
    this.calls = 0,
    this.waiting = 0,
    this.sales = 0,
    this.tips = 0,
    this.barMinutes,
    this.kitchenMinutes,
    this.methods = const {},
  });

  factory ServiceBoard.fromJson(Map<String, dynamic> j) => ServiceBoard(
        openTabs: _int(j['open_tabs']),
        covers: _int(j['covers']),
        bills: _int(j['bills']),
        barWaiting: _int(j['bar_waiting']),
        kitchenWaiting: _int(j['kitchen_waiting']),
        voids: _int(j['voids']),
        requests: _int(j['requests']),
        calls: _int(j['calls']),
        waiting: _int(j['waiting']),
        sales: _numOrNull(j['sales']) ?? 0,
        tips: _numOrNull(j['tips']) ?? 0,
        barMinutes: _numOrNull(j['bar_minutes']),
        kitchenMinutes: _numOrNull(j['kitchen_minutes']),
        methods: {for (final e in ((j['methods'] as Map?) ?? const {}).entries) '${e.key}': _numOrNull(e.value) ?? 0},
      );
}
