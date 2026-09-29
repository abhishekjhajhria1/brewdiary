// Everything the venue app asks of the server, in one place.
//
// Two implementations: SupabaseBackend talks to the real database (RLS + server
// functions decide what each person may do), DemoBackend is a seeded venue that lives
// on the device. Screens only ever see this interface, so the demo, the tests and the
// real thing run the same screens.
import 'models.dart';
import '../logic/area.dart' show HeatRow;
import '../logic/roles.dart';
import '../logic/venue_kinds.dart';

/// A refusal or failure, worded for the person holding the phone. The database's own
/// refusals ("only a verified venue can record spend") are already plain English.
class BackendError implements Exception {
  final String message;
  const BackendError(this.message);
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
  Future<void> updateVenue(String venueId, {String? name, String? city, List<int>? quietNights, String? geohash, bool? servesAlcohol, bool? areaShare});
  Future<void> deleteVenue(String venueId);

  Future<VerificationRequest?> verification(String venueId);
  Future<void> requestVerification(String venueId, String contact, {String? note});
  Future<void> withdrawVerification(String venueId);

  // ── team ──────────────────────────────────────────────────────────────────
  Future<List<StaffMember>> staff(String venueId);
  Future<List<ProfileHit>> searchPeople(String query);
  Future<void> addStaff(String venueId, String userId, StaffRole role);
  Future<void> setStaffRole(String venueId, String userId, StaffRole role);
  Future<void> removeStaff(String venueId, String userId);
  Future<void> setThankable(String venueId, bool thankable);
  Future<StaffInvite> createInvite(String venueId, StaffRole role);

  /// Join a team with an invite code; returns the venue's name.
  Future<String> acceptInvite(String code);

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

  // ── guest book ────────────────────────────────────────────────────────────
  Future<GuestCard?> guestCard(String venueId, String guestId);
  Future<void> setGuestNote(String venueId, String guestId, String body, List<String> tags);

  // ── Ninkasi for hosts ─────────────────────────────────────────────────────
  /// Streams Ninkasi's reply. [brief] holds only what this manager can already see.
  Stream<String> advise(Map<String, dynamic> brief, List<Map<String, String>> messages);
}
