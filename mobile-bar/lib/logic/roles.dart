// Who may do what at a venue. A MIRROR of public.role_capabilities (supabase/045): the
// database is the authority — every server function checks venue_can() — and this copy
// only decides what the app SHOWS, so a server never sees a button it can't press.
// src/lib/roles.ts is the same table for the website. Change one, change all three.

/// A person's role at ONE venue (a manager here can be a server somewhere else).
enum StaffRole {
  owner('owner'),
  manager('manager'),
  supervisor('supervisor'),
  bartender('bartender'),
  server('server'),
  host('host'),
  kitchen('kitchen');

  final String db;
  const StaffRole(this.db);

  static StaffRole parse(String? s) => StaffRole.values.firstWhere((r) => r.db == s, orElse: () => StaffRole.bartender);

  /// Lower is more senior. Supervisor sits above the floor, below management.
  int get rank => switch (this) {
        StaffRole.owner => 0,
        StaffRole.manager => 1,
        StaffRole.supervisor => 2,
        _ => 3,
      };

  bool get isManagement => this == StaffRole.owner || this == StaffRole.manager;
}

/// One thing a role may do. `db` is the key stored in public.role_capabilities.
enum Cap {
  // service
  floorView('floor.view'),
  seatGuests('guests.seat'),
  takeOrders('orders.take'),
  barStation('station.bar'),
  kitchenStation('station.kitchen'),
  voidOwn('orders.void_own'),
  approveVoids('orders.approve'),
  takePayment('payments.take'),
  refund('payments.refund'),
  cashUpOwn('cash.own'),
  closeDay('cash.close_day'),
  mark86('menu.86'),
  openRoom('rooms.open'),
  // guests
  guestsAtTables('guests.at_tables'),
  guestCard('guests.card'),
  tasteShare('guests.taste'),
  giveVibe('guests.vibe'),
  guestNotes('guests.notes'),
  redeemPerk('perks.redeem'),
  recordSpend('spend.record'),
  // back office
  editMenu('menu.edit'),
  editPerks('perks.edit'),
  countStock('stock.count'),
  receiveStock('stock.receive'),
  adjustStock('stock.adjust'),
  editRota('rota.edit'),
  ownShift('shift.own'),
  manageTips('tips.manage'),
  liveBoard('board.live'),
  reports('reports.view'),
  areaInsights('area.view'),
  advisor('ai.advisor'),
  guestTips('ai.guest_tips'),
  auditLog('audit.view'),
  manageTeam('team.manage'),
  editSettings('settings.edit'),
  requestVerification('venue.verify'),
  deleteVenue('venue.delete');

  final String db;
  const Cap(this.db);
}

const _floor = {
  Cap.floorView,
  Cap.takeOrders,
  Cap.voidOwn,
  Cap.takePayment,
  Cap.cashUpOwn,
  Cap.guestsAtTables,
  Cap.guestCard,
  Cap.tasteShare,
  Cap.giveVibe,
  Cap.guestNotes,
  Cap.redeemPerk,
  Cap.recordSpend,
  Cap.ownShift,
  Cap.guestTips,
};

/// The matrix (mobile-bar/PLAN.md §3.2). Owner can do everything; a manager everything
/// but delete the venue.
final Map<StaffRole, Set<Cap>> roleCaps = {
  StaffRole.owner: Cap.values.toSet(),
  StaffRole.manager: Cap.values.toSet()..remove(Cap.deleteVenue),
  StaffRole.supervisor: {
    ..._floor,
    Cap.seatGuests,
    Cap.barStation,
    Cap.kitchenStation,
    Cap.approveVoids,
    Cap.closeDay,
    Cap.mark86,
    Cap.openRoom,
    Cap.countStock,
    Cap.receiveStock,
    Cap.liveBoard,
  },
  StaffRole.bartender: {..._floor, Cap.barStation, Cap.mark86, Cap.openRoom, Cap.countStock, Cap.receiveStock},
  StaffRole.server: {..._floor, Cap.seatGuests},
  StaffRole.host: {Cap.floorView, Cap.seatGuests, Cap.openRoom, Cap.guestsAtTables, Cap.giveVibe, Cap.ownShift},
  StaffRole.kitchen: {Cap.kitchenStation, Cap.mark86, Cap.countStock, Cap.receiveStock, Cap.ownShift},
};

bool roleCan(StaffRole role, Cap cap) => roleCaps[role]!.contains(cap);

/// May [granter] give (or take away) [target]? Ownership is never granted from an app —
/// the creator is the owner, and a transfer goes through brewdiary. A manager manages
/// the floor, not other managers.
bool canGrant(StaffRole granter, StaffRole target) {
  if (target == StaffRole.owner) return false;
  if (granter == StaffRole.owner) return true;
  if (granter == StaffRole.manager) return target.rank > StaffRole.manager.rank;
  return false;
}

/// The roles [granter] may hand out, most senior first.
List<StaffRole> grantable(StaffRole granter) => StaffRole.values.where((r) => canGrant(granter, r)).toList();
