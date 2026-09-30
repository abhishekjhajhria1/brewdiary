// Who may do what at a venue. A MIRROR of public.role_capabilities (supabase/045): the
// database is the authority — every server function asks venue_can() — and this copy
// only decides what the dashboard SHOWS. mobile-bar/lib/logic/roles.dart is the same
// table for the venue app; tests/roles.test.ts checks both against the migration.
import type { StaffRole } from "./venues";

export const STAFF_ROLES: StaffRole[] = ["owner", "manager", "supervisor", "bartender", "server", "host", "kitchen"];

/** Lower is more senior. */
export function roleRank(role: StaffRole): number {
  return role === "owner" ? 0 : role === "manager" ? 1 : role === "supervisor" ? 2 : 3;
}

export const CAPABILITIES = [
  "floor.view", "guests.seat", "orders.take", "station.bar", "station.kitchen", "orders.void_own",
  "orders.approve", "payments.take", "payments.refund", "cash.own", "cash.close_day", "menu.86",
  "rooms.open", "guests.at_tables", "guests.card", "guests.taste", "guests.vibe", "guests.notes",
  "perks.redeem", "spend.record", "menu.edit", "perks.edit", "stock.count", "stock.receive",
  "stock.adjust", "rota.edit", "shift.own", "tips.manage", "board.live", "reports.view", "area.view",
  "ai.advisor", "ai.guest_tips", "audit.view", "team.manage", "settings.edit", "venue.verify",
  "venue.delete",
] as const;
export type Capability = (typeof CAPABILITIES)[number];

const FLOOR: Capability[] = [
  "floor.view", "orders.take", "orders.void_own", "payments.take", "cash.own", "guests.at_tables",
  "guests.card", "guests.taste", "guests.vibe", "guests.notes", "perks.redeem", "spend.record",
  "shift.own", "ai.guest_tips",
];

export const ROLE_CAPS: Record<StaffRole, ReadonlySet<Capability>> = {
  owner: new Set(CAPABILITIES),
  manager: new Set(CAPABILITIES.filter((c) => c !== "venue.delete")),
  supervisor: new Set<Capability>([
    ...FLOOR, "guests.seat", "station.bar", "station.kitchen", "orders.approve", "cash.close_day",
    "menu.86", "rooms.open", "stock.count", "stock.receive", "board.live",
  ]),
  bartender: new Set<Capability>([...FLOOR, "station.bar", "menu.86", "rooms.open", "stock.count", "stock.receive"]),
  server: new Set<Capability>([...FLOOR, "guests.seat"]),
  host: new Set<Capability>(["floor.view", "guests.seat", "rooms.open", "guests.at_tables", "guests.vibe", "shift.own"]),
  kitchen: new Set<Capability>(["station.kitchen", "menu.86", "stock.count", "stock.receive", "shift.own"]),
};

export function roleCan(role: StaffRole | undefined | null, cap: Capability): boolean {
  return !!role && (ROLE_CAPS[role]?.has(cap) ?? false);
}

/** May `granter` hand out (or take away) `target`? Never 'owner'; a manager manages the
 *  floor, never another manager. Mirrors can_grant_role() in 045. */
export function canGrant(granter: StaffRole, target: StaffRole): boolean {
  if (target === "owner") return false;
  if (granter === "owner") return true;
  if (granter === "manager") return roleRank(target) > roleRank("manager");
  return false;
}

export const ROLE_LABEL: Record<StaffRole, string> = {
  owner: "Owner",
  manager: "Manager",
  supervisor: "Shift lead",
  bartender: "Bartender",
  server: "Server",
  host: "Host",
  kitchen: "Kitchen",
};
