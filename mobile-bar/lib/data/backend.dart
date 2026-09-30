// Everything the venue app asks of the server, in one place.
//
// Two implementations: SupabaseBackend talks to the real database (RLS + server
// functions decide what each person may do), DemoBackend is a seeded venue that lives
// on the device. Screens only ever see this interface, so the demo, the tests and the
// real thing run the same screens.
import 'models.dart';
import '../logic/area.dart' show HeatRow;
import '../logic/host_brief.dart' show HostBrief;
import '../logic/roles.dart';
import '../logic/venue_kinds.dart';

/// A refusal or failure, worded for the person holding the phone. The database's own
/// refusals ("only a verified venue can record spend") are already plain English.
class BackendError implements Exception {
  final String message;

  /// A machine-readable reason where a screen acts on it: 'no_account' (that email has no
  /// brewdiary account yet), 'needs_update' (the database is a migration behind).
  final String? code;
  const BackendError(this.message, {this.code});
  @override
  String toString() => message;
}

abstract class Backend {
  static late Backend i;
  static void use(Backend b) => i = b;

  /// True for the seeded demo venue (nothing leaves the phone).
  bool get isDemo;

  // ── auth ──────────────────────────────────────────────────────────────────
  AppUser? get currentUser;

  /// Fires when someone signs in or out (including a session expiring).
  Stream<AppUser?> get authChanges;
  Future<void> signInWithPassword(String email, String password);

  /// Email a 6-digit code. [create] = start a new account with [name].
  Future<void> sendEmailCode(String email, {bool create = false, String? name});
  Future<void> verifyEmailCode(String email, String code);
  Future<void> signOut();

  // ── venues ────────────────────────────────────────────────────────────────
  Future<List<Venue>> myVenues();
  Future<Venue> createVenue({
    required String name,
    required String slug,
    String? city,
    required VenueKind kind,
    bool servesAlcohol,
    required String country,
    String? region,
  });
  /// [capacity] 0 clears it.
  Future<void> updateVenue(String venueId, {String? name, String? city, List<int>? quietNights, String? geohash, bool? servesAlcohol, bool? areaShare, bool? tableService, int? capacity});
  Future<void> deleteVenue(String venueId);

  Future<VerificationRequest?> verification(String venueId);
  Future<void> requestVerification(String venueId, String contact, {String? note});
  Future<void> withdrawVerification(String venueId);

  // ── team ──────────────────────────────────────────────────────────────────
  /// The roster. Owners and managers also get who's waiting and who's paused (053).
  Future<List<StaffMember>> staff(String venueId);

  /// Guests by name or @handle (the till, the guest book) — never how staff are added.
  Future<List<ProfileHit>> searchPeople(String query);
  Future<void> setStaffRole(String venueId, String userId, StaffRole role);
  Future<void> removeStaff(String venueId, String userId);
  Future<void> setThankable(String venueId, bool thankable);
  Future<StaffInvite> createInvite(String venueId, StaffRole role);

  /// Ask to join a team with a shared invite code; returns the venue's name. Since 053 the
  /// person waits for a manager's yes before they can do anything.
  Future<String> acceptInvite(String code);

  // ── staff access (053): the owner's code, approvals, lock-out, history ───
  /// Add an employee: their details and the role. Returns the code, shown ONCE — the
  /// employee signs in with [email] and types it.
  Future<StaffCode> enrolStaff(String venueId, {required String name, required String email, String? phone, required StaffRole role});

  /// A new code for someone added but not in yet; the old one stops working.
  Future<StaffCode> reissueCode(String enrolmentId);
  Future<void> revokeEnrolment(String enrolmentId);

  /// People added who haven't typed their code yet (expired ones too, to re-issue).
  Future<List<Enrolment>> openEnrolments(String venueId);

  /// Venues that added the email I'm signed in with, waiting for the owner's code.
  Future<List<MyEnrolment>> myEnrolments();

  /// Type the owner's code. A wrong code is an answer, not an error.
  Future<ClaimResult> claimEnrolment(String enrolmentId, String code);

  /// Where I'm waiting for a yes, or paused — with why and who to see.
  Future<List<StaffAccess>> myStaffStatus();
  Future<void> approveStaff(String venueId, String userId);
  Future<void> declineStaff(String venueId, String userId);

  /// Pause someone's access at once: every screen, table and function stops for them.
  /// [reportTo] is an owner or manager here (the caller when null).
  Future<void> lockStaff(String venueId, String userId, {String? reason, String? reportTo});
  Future<void> unlockStaff(String venueId, String userId);

  /// The venue's own details for someone: the name they go by, a phone number.
  Future<void> setStaffDetails(String venueId, String userId, {String? name, String? phone});

  /// The team's history (owners/managers), or one person's ([userId]).
  Future<List<StaffEvent>> staffHistory(String venueId, {String? userId, int limit = 100});

  // ── the time clock (053): for pay, never a ranking ────────────────────────
  /// When I clocked in here, or null when I'm off.
  Future<DateTime?> myShift(String venueId);
  Future<DateTime> clockIn(String venueId);
  Future<void> clockOut(String venueId);

  /// A manager clocks out someone who forgot (written to the history).
  Future<void> endShift(String venueId, String userId);

  /// Minutes on the clock per person since [since], listed by name.
  Future<List<ShiftRow>> shiftHours(String venueId, DateTime since);

  // ── the rota (054): plan the week, publish it, swaps, time off ────────────
  /// The rota for [from, to) as I may see it: drafts too if I plan it, what's on offer,
  /// time off, and the team.
  Future<RotaWeek> rotaWeek(String venueId, DateTime from, DateTime to);

  /// Add ([id] null or new) or change a shift; [userId] null leaves it open. Returns its id.
  Future<String> saveRotaShift(String venueId, {String? id, String? userId, required StaffRole role, String? areaId, required DateTime starts, required DateTime ends, int breakMinutes = 0, String? note});
  Future<void> deleteRotaShift(String shiftId);

  /// Publish the drafts in [from, to); returns how many.
  Future<int> publishRota(String venueId, DateTime from, DateTime to);

  /// Copy [from, to) by [byDays] days at the same local times ([tz]); returns how many.
  Future<int> copyRota(String venueId, DateTime from, DateTime to, int byDays, {required String tz});
  Future<void> offerShift(String shiftId);
  Future<void> takeShift(String shiftId);
  Future<void> decideSwap(String swapId, bool approve);
  Future<void> withdrawSwap(String swapId);

  /// My requests; the team's too for whoever plans the rota.
  Future<List<TimeOff>> timeOffList(String venueId);

  /// [from] is the first day's start, [to] the start of the day after the last.
  Future<void> requestTimeOff(String venueId, DateTime from, DateTime to, {String? note});
  Future<void> decideTimeOff(String id, bool approve);
  Future<void> cancelTimeOff(String id);

  /// The weekdays I can't work (0 = Sunday … 6 = Saturday).
  Future<void> setCannotWork(String venueId, List<int> days);

  // ── breaks, timesheets, corrections (054) ─────────────────────────────────
  /// Where I stand on the clock here, or null when I'm off.
  Future<ShiftState?> shiftState(String venueId);
  /// Start a break (always unpaid — only an owner or manager marks one paid).
  Future<void> startBreak(String venueId);
  Future<void> endBreak(String venueId);

  /// Mark someone's break paid, or unpaid again — never your own (set_break_paid).
  Future<void> setBreakPaid(String breakId, bool paid);

  /// One person's worked shifts in [from, to), with breaks and every correction.
  Future<List<TimesheetShift>> timesheet(String venueId, String userId, DateTime from, DateTime to);

  /// Fix someone's times, with a reason (the old times are kept).
  Future<void> correctShift(String shiftId, DateTime start, DateTime end, String reason);
  Future<void> addMissedShift(String venueId, String userId, DateTime start, DateTime end, {int breakMinutes = 0, required String reason});

  // ── pay and payroll (054) ─────────────────────────────────────────────────
  /// Hourly rates by user id: the team's for owners/managers, my own otherwise.
  Future<Map<String, double?>> payRates(String venueId);
  Future<void> setPayRate(String venueId, String userId, double? rate);

  /// Per person per day, [from]..[to] inclusive, days in the venue's time zone [tz].
  Future<List<PayrollDay>> payroll(String venueId, DateTime from, DateTime to, {required String tz});

  // ── tonight: rooms, guests, vibe, tabs, perks ────────────────────────────
  Future<List<Room>> rooms(String venueId);
  Future<Room> openRoom(Venue venue, {int boardHours = 6});
  Future<List<RoomGuest>> roomGuests(String roomId);
  Future<void> giveVibe(String roomId, String guestId, String reason);
  Future<void> recordSpend(String roomId, String guestId, double amount);
  Future<List<PerkStanding>> perkStatus(String venueId, String guestId);
  Future<void> redeemPerk(String perkId, String guestId);

  /// A counter (shop, bakery, liquor store) punches a guest's card: once a day.
  Future<void> recordVisit(String venueId, String guestId);

  // ── menu ──────────────────────────────────────────────────────────────────
  Future<List<MenuItem>> menu(String venueId);
  Future<void> saveMenuItem(String venueId, MenuItem item, {bool isNew = false});
  Future<void> removeMenuItem(String itemId);

  // ── perks ─────────────────────────────────────────────────────────────────
  Future<List<PerkTier>> perks(String venueId);
  Future<void> addPerk(String venueId, {required PerkKind kind, required double threshold, required String reward, bool rewardAlcoholic = false});
  Future<void> removePerk(String perkId);

  // ── insights & the area ───────────────────────────────────────────────────
  Future<VenueInsights?> insights(String venueId, {int days = 30});
  Future<List<AreaTrend>> areaTrends(String geohash, {int days = 30});

  /// The area heat map (048): groups of 5+ people who said yes, never a person.
  /// [tz] is the venue's time zone, so "evening" means the venue's evening.
  Future<List<HeatRow>> areaMap(String venueId, {int days = 30, String tz = 'UTC'});

  /// Public facts about places in the venue's area (049): events, openings, prices.
  /// Any staff member; empty until the venue is verified and placed.
  Future<List<AreaSignal>> areaSignals(String venueId, {int daysAhead = 14});
  Future<int> teamKudos(String venueId, {int days = 30});
  Future<List<KudosLine>> myKudos(String venueId);

  // ── service (051): the floor, tabs, stations, the bill, the inbox ─────────
  Future<List<VenueArea>> areas(String venueId);
  Future<void> saveArea(String venueId, VenueArea area, {bool isNew = false});
  Future<List<VenueTable>> tables(String venueId);
  Future<void> saveTable(String venueId, VenueTable table, {bool isNew = false});

  /// Retires every printed tag for the table; returns the new code.
  Future<String> rotateTableCode(String tableId);

  Future<List<ServiceTab>> openTabs(String venueId);
  Future<void> openTab(String venueId, String tabId, {String? tableId, String? name, int? covers});

  /// Every line on a tab (void ones too — the screen shows them struck through).
  Future<List<OrderLine>> tabLines(String tabId);

  /// [lines]: [{item, qty, note, seat}] — the server prices them.
  Future<void> addLines(String tabId, List<Map<String, Object?>> lines);
  Future<void> setLineStatus(String lineId, String status);
  Future<void> voidLine(String lineId, String reason);

  /// Staff say how it was paid ([payments]: [{method, amount}]); returns the subtotal.
  Future<double> closeTab(String tabId, List<Map<String, Object>> payments, {double? tip});
  Future<void> voidTab(String tabId, String reason);

  /// The bar's or the kitchen's open tickets (sent, preparing, ready).
  Future<List<OrderLine>> stationLines(String venueId, String station);

  Future<List<InboxItem>> inbox(String venueId);
  Future<void> acceptRequest(String requestId, String tabId);
  Future<void> declineRequest(String requestId, {String? reason});
  Future<void> resolveCall(String callId);

  Future<List<WaitParty>> waitlist(String venueId);
  Future<void> addToWaitlist(String venueId, WaitParty p);
  Future<void> setWaitStatus(String partyId, String status);

  Future<ServiceBoard> serviceBoard(String venueId);

  // ── the door (052): counts, never people ──────────────────────────────────
  Future<DoorCount> doorCount(String venueId);

  /// [n] people in (positive) or out (negative), 1 to 12 at a time.
  Future<void> doorTick(String venueId, int n);

  // ── the counter (050): products, stock, sales, the register ───────────────
  Future<List<ShopProduct>> products(String venueId);
  Future<void> saveProduct(String venueId, ShopProduct p, {bool isNew = false});

  /// On hand per product id — the ledger's sum.
  Future<Map<String, int>> stock(String venueId);
  Future<void> receiveStock(String productId, int qty, {String? supplierId, String? invoice});
  Future<void> adjustStock(String productId, int qty, String why, {String? note});
  Future<List<ShopSupplier>> suppliers(String venueId);
  Future<void> addSupplier(String venueId, String name, {String? licence});

  /// What the law allows at this till right now (dry day, hours, age, per-sale limit).
  Future<SaleStatus> saleStatus(String venueId);

  /// Rings a sale; the server prices it and returns the total. [saleId] makes a retry safe.
  Future<double> ringSale(String venueId, String saleId, List<Map<String, Object>> lines, String paidBy, {bool idChecked = false});
  Future<List<RegisterRow>> exciseRegister(String venueId, DateTime from, DateTime to);

  // ── guest book ────────────────────────────────────────────────────────────
  Future<GuestCard?> guestCard(String venueId, String guestId);
  Future<void> setGuestNote(String venueId, String guestId, String body, List<String> tags);

  // ── Ninkasi for hosts ─────────────────────────────────────────────────────
  /// Streams Ninkasi's reply. [brief] holds only what this manager can already see.
  Stream<String> advise(Map<String, dynamic> brief, List<Map<String, String>> messages);

  /// Ninkasi for the whole team (/api/host-ai): a question about the shift. Throws a
  /// [BackendError] when she's out of reach, and the screen answers from the same rules.
  Stream<String> askHost(HostBrief brief, List<Map<String, String>> messages);
}
