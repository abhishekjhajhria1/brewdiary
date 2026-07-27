"use client";

// Orders & bills — the client half of migration 051, the venue's till.
//
// ── WHY THIS FILE IS SHAPED LIKE THIS ────────────────────────────────────────
// A bar already had a "tab" here (points.ts / spend_events, 017) but only as a
// single typed NUMBER. That is enough to flex a room and nothing else. To take
// payment we need what's under the number — what was poured, at what price, for
// which table — and the moment we have that, we are one INSERT away from writing
// a guest's diary for them. 051's header explains why that INSERT can never
// exist. This file is the client that must never ask for it.
//
// So the shape here is deliberately lopsided:
//   • rich on the VENUE side (menu, open tickets, lines, attribution, totals)
//   • and on the guest side it does exactly one thing — assembles the drink lines
//     that will be OFFERED to them (drinkLinesFor), which a definer rpc turns into
//     a pending suggestion. Nothing in this file writes an entry. Nothing in this
//     file can.
//
// ── the rules that constrained it ───────────────────────────────────────────
// • Nothing rewards drinking more. There is no per-guest spend total in here, no
//   "who spent most at this table" helper, no ranking. `guestUserId` on a line
//   routes a suggestion; it is not the seed of a spender profile. If a component
//   ever wants a sorted-by-spend list of guests, the answer is no — see 051.
// • A guest can never write their own order. Every mutation below is staff-only
//   at the RLS layer; this module just doesn't offer guest writes at all.
// • Money is INTEGER MINOR UNITS (paise/cents), never a float, and always in the
//   VENUE's currency (022 / money.ts) — never the app's or the device's. The
//   conversion factor isn't always 100 (¥ has no minor unit), hence money.ts's
//   minorPerMajor rather than a hardcoded /100.
// • The DB is authoritative on PRICE and NAME. A line is inserted with placeholder
//   price/name and migration 051's order_items_snapshot() trigger overwrites both
//   from the menu row: a client-supplied price is a client-supplied discount.
// • Insert gotcha (repo-wide): every table in 051 has a SELECT policy calling a
//   SECURITY DEFINER helper, which trips PostgREST on INSERT..RETURNING. So: ids
//   are generated client-side and inserts go out WITHOUT .select(), reading back
//   separately — same discipline as parties.ts / expenses.ts / venues.ts.
//
// Same fetch-on-mount + shared version-bump pattern as venues.ts / points.ts;
// degrades to empty with no supabase/auth (there is no offline till).
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { DEFAULT_CURRENCY } from "./money";

// ── types ────────────────────────────────────────────────────────────────────

export type OrderStatus = "open" | "closed" | "void";
export type BillStatus = "unpaid" | "paid" | "refunded";

export interface MenuItem {
  id: string;
  venueId: string;
  name: string;
  category?: string;
  /** Integer minor units in `currency` (₹250.00 → 25000). */
  priceMinor: number;
  currency: string;
  /** The normalized canonical drink name (drinks.ts) when this item IS a drink.
   *  Undefined means food — and food never reaches anyone's diary. */
  drinkKey?: string;
  active: boolean;
  sortOrder: number;
}

export interface Order {
  id: string;
  venueId: string;
  /** The room this ticket belongs to, if any. Most tickets are just a table. */
  partyId?: string;
  tableLabel?: string;
  openedBy: string;
  openedAt: string;
  closedAt?: string;
  status: OrderStatus;
  /** The VENUE's currency (ISO-4217) — never assume the app's home one. */
  currency: string;
}

export interface OrderItem {
  id: string;
  orderId: string;
  menuItemId?: string;
  qty: number;
  unitPriceMinor: number;
  /** Snapshotted at insert, so last season's bill still says what it said. */
  name: string;
  drinkKey?: string;
  /** Who this line is FOR. Undefined is the normal case and a perfectly good bill. */
  guestUserId?: string;
}

export interface Bill {
  id: string;
  orderId: string;
  subtotalMinor: number;
  taxMinor: number;
  tipMinor: number;
  totalMinor: number;
  currency: string;
  status: BillStatus;
  paidAt?: string;
  paymentRef?: string;
}

/** One drink line as it will be OFFERED to a guest. snake_case because this is
 *  the exact jsonb payload stored in order_log_suggestions.items — no price, no
 *  venue's opinion, just what was in the glass. */
export interface DrinkLine {
  drink_key: string;
  name: string;
  qty: number;
}

// ── shared refresh signal ────────────────────────────────────────────────────
let version = 0;
const subs = new Set<() => void>();
function bump() {
  version++;
  subs.forEach((s) => s());
}
function useVersion(): number {
  const [, set] = useState(0);
  useEffect(() => {
    const cb = () => set((n) => n + 1);
    subs.add(cb);
    return () => {
      subs.delete(cb);
    };
  }, []);
  return version;
}

// ─────────────────────────────────────────────────────────────────────────────
// PURE HELPERS — no network, no React, no Supabase. Everything below this line
// is unit-tested in tests/orders.test.ts, because it is the part that handles
// money and the part where an off-by-one is somebody's paise.
// ─────────────────────────────────────────────────────────────────────────────

/** The subset of a line the arithmetic actually needs. */
export interface PricedLine {
  qty: number;
  unitPriceMinor: number;
}

/**
 * Sum a ticket: subtotal from the lines, tax as a rate on the subtotal, tip flat.
 *
 * `taxRate` is a FRACTION (0.05 = 5%), because a percent-typed-as-5 that lands in
 * a rate slot multiplies a bill by six, and that bug should be impossible to
 * write rather than merely unlikely.
 *
 * Tax rounds to a whole minor unit (Math.round — half up). A venue's real filing
 * is its own accounting system's business; what matters here is that the three
 * numbers we store ADD UP, because 051 has a CHECK constraint saying they must.
 */
export function billTotals(
  items: PricedLine[],
  taxRate = 0,
  tipMinor = 0,
): { subtotalMinor: number; taxMinor: number; totalMinor: number } {
  const subtotalMinor = (items ?? []).reduce((sum, i) => {
    const qty = safeInt(i?.qty);
    const unit = safeInt(i?.unitPriceMinor);
    return sum + qty * unit;
  }, 0);

  const rate = Number.isFinite(taxRate) && taxRate > 0 ? taxRate : 0;
  const taxMinor = Math.round(subtotalMinor * rate);
  const tip = safeInt(tipMinor);

  return { subtotalMinor, taxMinor, totalMinor: subtotalMinor + taxMinor + tip };
}

/**
 * Divide a total between n payers, in whole minor units.
 *
 * The invariant that matters — and the one the tests hammer — is that the parts
 * sum to EXACTLY the total. ₹100 three ways is 3334 + 3333 + 3333 paise, not
 * 3333.33 each: a naive divide loses a paise, and a bill that doesn't reconcile
 * is a bill a venue stops trusting. The remainder goes to the FIRST payers,
 * deterministically, so the same split renders the same way every time rather
 * than shuffling under a re-render.
 */
export function splitEvenly(totalMinor: number, n: number): number[] {
  const parts = Math.floor(safeInt(n));
  if (parts <= 0) return [];
  // Never negative: a refund is its own flow, not a split with a minus sign.
  const total = Math.max(0, safeInt(totalMinor));
  const base = Math.floor(total / parts);
  const remainder = total - base * parts;
  return Array.from({ length: parts }, (_, i) => base + (i < remainder ? 1 : 0));
}

/**
 * The drink lines to OFFER one guest — the payload of order_log_suggestions.items.
 *
 * Two things happen here and both are the product, not an implementation detail:
 *
 *   1. FOOD IS DROPPED. A line with no drink_key never reaches a diary. The diary
 *      is a drink diary; a venue does not get to tell it about the calamari.
 *   2. Duplicates COLLAPSE by drink_key. Two separate "Negroni" lines rung up an
 *      hour apart are one drink family with qty 2, so the offer reads the way the
 *      night actually went instead of like a receipt.
 *
 * Passing a null/undefined guest returns nothing: unattributed lines belong to
 * nobody, and "nobody" is not a person we may offer a diary entry to.
 */
export function drinkLinesFor(items: OrderItem[], guestUserId: string | null | undefined): DrinkLine[] {
  if (!guestUserId) return [];
  const out = new Map<string, DrinkLine>();
  for (const item of items ?? []) {
    if (!item || item.guestUserId !== guestUserId) continue;
    const key = (item.drinkKey ?? "").trim();
    if (!key) continue; // food, cover charge, hookah — not a drink, not a diary line
    const qty = safeInt(item.qty);
    if (qty <= 0) continue;
    const existing = out.get(key);
    if (existing) existing.qty += qty;
    // first-seen name wins, so a menu rename mid-ticket doesn't rewrite history
    else out.set(key, { drink_key: key, name: item.name ?? key, qty });
  }
  return [...out.values()];
}

/** Non-finite / fractional input can't be trusted into money maths. Floor toward zero. */
function safeInt(n: unknown): number {
  const x = Number(n);
  return Number.isFinite(x) ? Math.trunc(x) : 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// HOOKS & MUTATIONS (network)
// ─────────────────────────────────────────────────────────────────────────────

// ── row mappers ──────────────────────────────────────────────────────────────
function toMenuItem(r: Record<string, unknown>): MenuItem {
  return {
    id: r.id as string,
    venueId: r.venue_id as string,
    name: r.name as string,
    category: (r.category as string) ?? undefined,
    priceMinor: Number(r.price_minor ?? 0),
    currency: (r.currency as string) || DEFAULT_CURRENCY,
    drinkKey: (r.drink_key as string) ?? undefined,
    active: Boolean(r.active),
    sortOrder: Number(r.sort_order ?? 0),
  };
}
function toOrder(r: Record<string, unknown>): Order {
  return {
    id: r.id as string,
    venueId: r.venue_id as string,
    partyId: (r.party_id as string) ?? undefined,
    tableLabel: (r.table_label as string) ?? undefined,
    openedBy: r.opened_by as string,
    openedAt: r.opened_at as string,
    closedAt: (r.closed_at as string) ?? undefined,
    status: ((r.status as string) ?? "open") as OrderStatus,
    currency: (r.currency as string) || DEFAULT_CURRENCY,
  };
}
function toOrderItem(r: Record<string, unknown>): OrderItem {
  return {
    id: r.id as string,
    orderId: r.order_id as string,
    menuItemId: (r.menu_item_id as string) ?? undefined,
    qty: Number(r.qty ?? 1),
    unitPriceMinor: Number(r.unit_price_minor ?? 0),
    name: (r.name_snapshot as string) ?? "",
    drinkKey: (r.drink_key as string) ?? undefined,
    guestUserId: (r.guest_user_id as string) ?? undefined,
  };
}
function toBill(r: Record<string, unknown>): Bill {
  return {
    id: r.id as string,
    orderId: r.order_id as string,
    subtotalMinor: Number(r.subtotal_minor ?? 0),
    taxMinor: Number(r.tax_minor ?? 0),
    tipMinor: Number(r.tip_minor ?? 0),
    totalMinor: Number(r.total_minor ?? 0),
    currency: (r.currency as string) || DEFAULT_CURRENCY,
    status: ((r.status as string) ?? "unpaid") as BillStatus,
    paidAt: (r.paid_at as string) ?? undefined,
    paymentRef: (r.payment_ref as string) ?? undefined,
  };
}

const MENU_COLS = "id, venue_id, name, category, price_minor, currency, drink_key, active, sort_order";
const ORDER_COLS = "id, venue_id, party_id, table_label, opened_by, opened_at, closed_at, status, currency";
const ITEM_COLS = "id, order_id, menu_item_id, qty, unit_price_minor, name_snapshot, drink_key, guest_user_id";
const BILL_COLS =
  "id, order_id, subtotal_minor, tax_minor, tip_minor, total_minor, currency, status, paid_at, payment_ref";

// ── the menu ─────────────────────────────────────────────────────────────────
/** A venue's live menu, in the venue's own order. Read by anyone who can see the
 *  venue; only a manager may edit it (RLS, 051). */
export function useMenu(venueId: string | null): { items: MenuItem[]; loading: boolean } {
  const v = useVersion();
  const [items, setItems] = useState<MenuItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setItems([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("menu_items")
        .select(MENU_COLS)
        .eq("venue_id", venueId)
        .eq("active", true)
        .order("sort_order")
        .order("name");
      if (!active) return;
      setItems(((data as Record<string, unknown>[]) ?? []).map(toMenuItem));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { items, loading };
}

// ── the floor ────────────────────────────────────────────────────────────────
/** Every ticket currently open at this venue, newest first. */
export function useOpenOrders(venueId: string | null): { orders: Order[]; loading: boolean } {
  const v = useVersion();
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setOrders([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("orders")
        .select(ORDER_COLS)
        .eq("venue_id", venueId)
        .eq("status", "open")
        .order("opened_at", { ascending: false });
      if (!active) return;
      setOrders(((data as Record<string, unknown>[]) ?? []).map(toOrder));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { orders, loading };
}

/** An open ticket with its lines already in hand. */
export interface Ticket extends Order {
  items: OrderItem[];
}

/**
 * The floor: every open ticket AND its lines, in two queries.
 *
 * The panel needs a running total and an item count on every card, so fetching
 * lines per-card would be an N+1 against a phone on bar wifi. One `.in()` over
 * the open order ids instead, and the expanded ticket reuses what's already here.
 */
export function useOpenTickets(venueId: string | null): { tickets: Ticket[]; loading: boolean } {
  const v = useVersion();
  const [state, setState] = useState<{ tickets: Ticket[]; loading: boolean }>({ tickets: [], loading: true });

  useEffect(() => {
    if (!supabase || !venueId) {
      setState({ tickets: [], loading: false });
      return;
    }
    let active = true;
    (async () => {
      const { data: orderRows } = await supabase!
        .from("orders")
        .select(ORDER_COLS)
        .eq("venue_id", venueId)
        .eq("status", "open")
        .order("opened_at", { ascending: false });
      if (!active) return;

      const orders = ((orderRows as Record<string, unknown>[]) ?? []).map(toOrder);
      if (orders.length === 0) {
        setState({ tickets: [], loading: false });
        return;
      }

      const { data: itemRows } = await supabase!
        .from("order_items")
        .select(ITEM_COLS)
        .in(
          "order_id",
          orders.map((o) => o.id),
        )
        .order("created_at");
      if (!active) return;

      const byOrder = new Map<string, OrderItem[]>();
      for (const r of ((itemRows as Record<string, unknown>[]) ?? []).map(toOrderItem)) {
        const list = byOrder.get(r.orderId);
        if (list) list.push(r);
        else byOrder.set(r.orderId, [r]);
      }
      setState({ tickets: orders.map((o) => ({ ...o, items: byOrder.get(o.id) ?? [] })), loading: false });
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return state;
}

/** One ticket, its lines, and its bill if one has been raised. */
export function useOrder(orderId: string | null): {
  order: Order | null;
  items: OrderItem[];
  bill: Bill | null;
  loading: boolean;
} {
  const v = useVersion();
  const [state, setState] = useState<{ order: Order | null; items: OrderItem[]; bill: Bill | null; loading: boolean }>({
    order: null,
    items: [],
    bill: null,
    loading: true,
  });

  useEffect(() => {
    if (!supabase || !orderId) {
      setState({ order: null, items: [], bill: null, loading: false });
      return;
    }
    let active = true;
    setState({ order: null, items: [], bill: null, loading: true });
    (async () => {
      const [o, i, b] = await Promise.all([
        supabase!.from("orders").select(ORDER_COLS).eq("id", orderId).maybeSingle(),
        supabase!.from("order_items").select(ITEM_COLS).eq("order_id", orderId).order("created_at"),
        supabase!.from("bills").select(BILL_COLS).eq("order_id", orderId).maybeSingle(),
      ]);
      if (!active) return;
      setState({
        order: o.data ? toOrder(o.data as Record<string, unknown>) : null,
        items: ((i.data as Record<string, unknown>[]) ?? []).map(toOrderItem),
        bill: b.data ? toBill(b.data as Record<string, unknown>) : null,
        loading: false,
      });
    })();
    return () => {
      active = false;
    };
  }, [orderId, v]);

  return state;
}

// ── mutations (staff only — RLS is the enforcement, this is just the client) ──

/** Open a ticket. Returns its id, generated here (no .select() — see the header). */
export async function openOrder(
  venueId: string,
  meId: string,
  tableLabel?: string,
  partyId?: string | null,
): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const id = crypto.randomUUID();
  const { error } = await supabase.from("orders").insert({
    id,
    venue_id: venueId,
    opened_by: meId,
    table_label: tableLabel?.trim() || null,
    party_id: partyId || null,
  });
  bump();
  return error ? { error: error.message } : { id };
}

/**
 * Put a line on a ticket.
 *
 * Note what is NOT sent: a price. `unit_price_minor` and `name_snapshot` go out as
 * placeholders and 051's trigger overwrites both from the menu row. The browser
 * does not get a vote on what a drink costs.
 */
export async function addOrderItem(
  orderId: string,
  menuItemId: string,
  qty = 1,
  guestUserId?: string | null,
): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const id = crypto.randomUUID();
  const { error } = await supabase.from("order_items").insert({
    id,
    order_id: orderId,
    menu_item_id: menuItemId,
    qty: Math.max(1, Math.min(99, Math.trunc(qty) || 1)),
    unit_price_minor: 0, // trigger sets it from the menu
    name_snapshot: "", // trigger sets it from the menu
    guest_user_id: guestUserId || null,
  });
  bump();
  return error ? { error: error.message } : { id };
}

export async function setOrderItemQty(itemId: string, qty: number): Promise<string | null> {
  if (!supabase) return "offline";
  const n = Math.max(1, Math.min(99, Math.trunc(qty) || 1));
  const { error } = await supabase.from("order_items").update({ qty: n }).eq("id", itemId);
  bump();
  return error ? error.message : null;
}

export async function removeOrderItem(itemId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("order_items").delete().eq("id", itemId);
  bump();
  return error ? error.message : null;
}

/**
 * Say who a line is for — or un-say it, with null.
 *
 * This is the ONLY thing that makes a later diary offer possible, and it is
 * optional on purpose. A bill with every line unattributed is a completely
 * normal bill; the UI must say so rather than nagging the floor to tag people.
 */
export async function attributeItem(orderItemId: string, guestUserId: string | null): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase
    .from("order_items")
    .update({ guest_user_id: guestUserId || null })
    .eq("id", orderItemId);
  bump();
  return error ? error.message : null;
}

/**
 * Raise the bill for a ticket. One bill per order (051 has a UNIQUE), so this
 * upserts on order_id: re-closing a ticket to add a tip amends rather than
 * duplicating.
 *
 * Only ever writes status 'unpaid'. A client that could write 'paid' is a
 * free-drinks bug — settlement is the payment webhook's job, through a definer
 * function, and RLS refuses anything else.
 */
export async function raiseBill(
  orderId: string,
  items: PricedLine[],
  taxRate = 0,
  tipMinor = 0,
): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const { subtotalMinor, taxMinor, totalMinor } = billTotals(items, taxRate, tipMinor);
  const id = crypto.randomUUID();
  const { error } = await supabase.from("bills").upsert(
    {
      id,
      order_id: orderId,
      subtotal_minor: subtotalMinor,
      tax_minor: taxMinor,
      tip_minor: Math.max(0, safeInt(tipMinor)),
      total_minor: totalMinor,
      status: "unpaid",
    },
    { onConflict: "order_id" },
  );
  bump();
  return error ? { error: error.message } : { id };
}

/** Close a ticket. Voids nothing, refunds nothing — just flips the status. */
export async function closeOrder(orderId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("orders").update({ status: "closed" }).eq("id", orderId);
  bump();
  return error ? error.message : null;
}

/** Abandon a ticket (walkout, mis-rung). Kept as a row — a till you can delete
 *  from is a till you can steal from. */
export async function voidOrder(orderId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("orders").update({ status: "void" }).eq("id", orderId);
  bump();
  return error ? error.message : null;
}

// ── the menu editor (manager/owner only — RLS enforces the rung) ─────────────
export async function addMenuItem(
  venueId: string,
  fields: { name: string; priceMinor: number; category?: string; drinkKey?: string | null; sortOrder?: number },
): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const name = fields.name.trim();
  if (!name) return { error: "Give the item a name." };
  const price = Math.max(0, safeInt(fields.priceMinor));
  const id = crypto.randomUUID();
  const { error } = await supabase.from("menu_items").insert({
    id,
    venue_id: venueId,
    name,
    category: fields.category?.trim() || null,
    price_minor: price,
    drink_key: fields.drinkKey?.trim() || null,
    sort_order: safeInt(fields.sortOrder),
  });
  bump();
  return error ? { error: error.message } : { id };
}

export async function updateMenuItem(
  itemId: string,
  fields: { name?: string; priceMinor?: number; category?: string; drinkKey?: string | null; active?: boolean },
): Promise<string | null> {
  if (!supabase) return "offline";
  const patch: Record<string, string | number | boolean | null> = {};
  if (fields.name !== undefined) {
    const n = fields.name.trim();
    if (!n) return "Name can't be empty.";
    patch.name = n;
  }
  if (fields.priceMinor !== undefined) patch.price_minor = Math.max(0, safeInt(fields.priceMinor));
  if (fields.category !== undefined) patch.category = fields.category.trim() || null;
  if (fields.drinkKey !== undefined) patch.drink_key = fields.drinkKey?.trim() || null;
  if (fields.active !== undefined) patch.active = fields.active;
  const { error } = await supabase.from("menu_items").update(patch).eq("id", itemId);
  bump();
  return error ? error.message : null;
}

/** Retire an item. Prefer `updateMenuItem(id, { active: false })` — a delete
 *  orphans the menu_item_id on old lines (they keep their name/price snapshot,
 *  but the link to the menu is gone for good). */
export async function deleteMenuItem(itemId: string) {
  if (!supabase) return;
  await supabase.from("menu_items").delete().eq("id", itemId);
  bump();
}
