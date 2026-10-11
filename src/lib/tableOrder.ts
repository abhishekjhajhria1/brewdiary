"use client";

// The table's own link — bwdy.site/t/<code> (051, 059). What a table's or a counter's QR
// or NFC tag opens: the venue's menu with the place already known, and — if the venue
// switched it on — ordering from the phone and "call staff / bill please / water".
//
// How an order goes in is the venue's choice (059): a request the staff accept onto the
// table's tab, or straight onto the bar's and kitchen's screens and printers (priced by
// the server either way). At a PICKUP POINT — a bar counter, a café's or a shop's — it
// gets a number to collect, and the guest follows it here. Staff never learn who asked;
// the guest sees only their own orders. Some venues take orders without an account:
// then this browser keeps a secret (localStorage) and the server keeps only its hash.
// The twin of test_m_app/lib/data/table_order.dart.
import { useCallback, useEffect, useState } from "react";
import { supabase } from "./supabase";

export interface TableInfo {
  code: string;
  venueSlug: string;
  venueName: string;
  venueKind: string;
  currency: string;
  tableLabel: string;
  /** The venue takes orders and calls from phones at this table. */
  tableService: boolean;
  /** "table", or "pickup" — a counter: an order gets a number to collect (059). */
  pointKind?: "table" | "pickup";
  /** Orders go straight to the bar and kitchen, no staff OK first. */
  ordersDirect?: boolean;
  /** The kitchen has paused phone orders for a while. */
  ordersPaused?: boolean;
  /** Orders without an account are welcome here. */
  ordersAnon?: boolean;
  /** on_trade | off_trade | no_alcohol — a liquor store's bottles are never phone-ordered. */
  legalClass?: string;
}

/** One of your orders, as you follow it (order_status_json, 059). */
export interface OrderStatus {
  id: string;
  /** pending (waiting for an OK) | sent | making | ready | served | declined | withdrawn */
  status: string;
  createdAt: string;
  venueName: string;
  point: string;
  atPickup: boolean;
  pickupNo: number | null;
  declineReason?: string;
  lines: { name: string; qty: number; status: string }[];
}

export function parseOrderStatus(j: Record<string, unknown>): OrderStatus {
  return {
    id: String(j.id),
    status: String(j.status ?? "pending"),
    createdAt: String(j.created_at ?? ""),
    venueName: String(j.venue_name ?? ""),
    point: String(j.point ?? ""),
    atPickup: j.point_kind === "pickup",
    pickupNo: typeof j.pickup_no === "number" ? j.pickup_no : null,
    declineReason: (j.decline_reason as string) || undefined,
    lines: ((j.lines as Record<string, unknown>[]) ?? []).map((l) => ({ name: String(l.name), qty: Number(l.qty ?? 1), status: String(l.status ?? "sent") })),
  };
}

/** Still on its way: worth asking about again. */
export function orderLive(o: OrderStatus): boolean {
  return ["pending", "sent", "making", "ready"].includes(o.status);
}

/** Which of the four steps (Sent, Making, Ready, Served/Collected) it's on; -1 for none. */
export function orderStep(o: OrderStatus): number {
  return ({ pending: 0, sent: 0, making: 1, ready: 2, served: 3 } as Record<string, number>)[o.status] ?? -1;
}

/** The same words as the app's OrderStatus.words. */
export function orderWords(o: OrderStatus): string {
  switch (o.status) {
    case "pending":
      return "waiting for the staff to confirm";
    case "sent":
      return o.atPickup ? "sent — they'll start on it" : "sent to the bar and kitchen";
    case "making":
      return "being made";
    case "ready":
      return o.atPickup ? `ready — collect it${o.point ? ` at ${o.point}` : ""}` : "ready — on its way to you";
    case "served":
      return o.atPickup ? "collected" : "served";
    case "declined":
      return `declined${o.declineReason ? ` — ${o.declineReason}` : ""}`;
    default:
      return "cancelled";
  }
}

/** This browser's own order secret (48 hex characters), made once. */
let memorySecret: string | null = null;
export function deviceSecret(): string {
  const key = "brewdiary.order.device";
  try {
    const have = localStorage.getItem(key);
    if (have && /^[0-9a-f]{32,64}$/.test(have)) return have;
  } catch {
    /* private window: one for this visit */
  }
  if (memorySecret) return memorySecret;
  const b = new Uint8Array(24);
  crypto.getRandomValues(b);
  memorySecret = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  try {
    localStorage.setItem(key, memorySecret);
  } catch {
    /* kept in memory instead */
  }
  return memorySecret;
}

/** The database hasn't had 059 yet: the 051 calls still work. */
function behind(e: { code?: string } | null): boolean {
  return !!e && (e.code === "PGRST202" || e.code === "42883");
}

export type CallKind = "staff" | "bill" | "water";

/** The URL a table's QR / NFC tag carries. */
export function tableUrl(code: string, origin = "https://bwdy.site"): string {
  return `${origin.replace(/\/$/, "")}/t/${code}`;
}

/** An 8-character table code, or null for anything else (a typo, a stale tag). */
export function parseTableCode(raw: string): string | null {
  const c = raw.trim().toLowerCase();
  return /^[0-9a-z]{8}$/.test(c) ? c : null;
}

/** Public read (works signed out). null = no such active table at a verified venue. */
export async function fetchTable(code: string): Promise<TableInfo | null> {
  const c = parseTableCode(code);
  if (!supabase || !c) return null;
  const { data, error } = await supabase.rpc("table_info", { in_code: c });
  if (error) throw error;
  const r = (data as Record<string, unknown>[] | null)?.[0];
  if (!r) return null;
  return {
    code: c,
    venueSlug: String(r.venue_slug),
    venueName: String(r.venue_name),
    venueKind: String(r.venue_kind ?? "bar"),
    currency: String(r.currency ?? "INR"),
    tableLabel: String(r.table_label),
    tableService: r.table_service === true,
    pointKind: r.point_kind === "pickup" ? "pickup" : "table",
    ordersDirect: r.orders_direct === true,
    ordersPaused: r.orders_paused === true,
    ordersAnon: r.orders_anon === true,
    legalClass: typeof r.legal_class === "string" ? r.legal_class : "on_trade",
  };
}

/** Send an order. `lines`: what and how many — never a price. Signed out, the venue must
 *  take orders without an account (this browser's secret stands in). */
export async function placeOrder(
  code: string,
  lines: { item: string; qty: number; note?: string }[],
  signedIn: boolean,
  note?: string,
): Promise<{ status: OrderStatus | null; error: string | null }> {
  if (!supabase) return { status: null, error: "offline" };
  const req = crypto.randomUUID();
  const { data, error } = signedIn
    ? await supabase.rpc("place_order", { in_code: code, req, lines, req_note: note ?? null })
    : await supabase.rpc("place_order_guest", { in_code: code, req, device: deviceSecret(), lines, req_note: note ?? null });
  if (behind(error) && signedIn) {
    const old = await supabase.rpc("request_order", { in_code: code, req, lines, req_note: note ?? null }); // before 059
    return { status: null, error: old.error ? old.error.message : null };
  }
  if (error) return { status: null, error: error.message };
  return { status: data && typeof data === "object" ? parseOrderStatus(data as Record<string, unknown>) : null, error: null };
}

export async function callStaff(code: string, kind: CallKind, signedIn = true): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = signedIn
    ? await supabase.rpc("call_table_staff", { in_code: code, call_kind: kind })
    : await supabase.rpc("call_table_staff_guest", { in_code: code, device: deviceSecret(), call_kind: kind });
  return error ? error.message : null;
}

export async function withdrawRequest(id: string, signedIn = true): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = signedIn ? await supabase.rpc("withdraw_request", { req: id }) : await supabase.rpc("withdraw_guest_order", { req: id, device: deviceSecret() });
  return error ? error.message : null;
}

/** My own orders from the last 12 hours, newest first — every 8 s while one is on its
 *  way, every 30 s otherwise. */
export function useMyOrders(enabled: boolean, signedIn: boolean, nonce: number): OrderStatus[] {
  const [rows, setRows] = useState<OrderStatus[]>([]);
  const load = useCallback(async () => {
    if (!supabase || !enabled) return;
    const { data, error } = signedIn ? await supabase.rpc("my_orders") : await supabase.rpc("guest_orders", { device: deviceSecret() });
    if (!error) return setRows(((data as Record<string, unknown>[] | null) ?? []).map(parseOrderStatus));
    if (!behind(error) || !signedIn) return;
    // Before 059: the requests themselves (RLS returns only mine).
    const since = new Date(Date.now() - 12 * 3600_000).toISOString();
    const old = await supabase
      .from("order_requests")
      .select("id, status, lines, decline_reason, created_at")
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(10);
    setRows(
      ((old.data ?? []) as Record<string, unknown>[]).map((r) =>
        parseOrderStatus({ ...r, status: r.status === "accepted" ? "sent" : r.status }),
      ),
    );
  }, [enabled, signedIn]);

  const busy = rows.some(orderLive);
  useEffect(() => {
    void load();
    if (!enabled) return;
    const t = setInterval(() => void load(), busy ? 8_000 : 30_000);
    return () => clearInterval(t);
  }, [load, enabled, nonce, busy]);

  return rows;
}

/** The ready board for a pickup point (pickup_board, 059): numbers and states, never who. */
export async function fetchPickupBoard(code: string): Promise<{ venueName: string; numbers: { no: number; ready: boolean; since: string }[] } | null> {
  const c = parseTableCode(code);
  if (!supabase || !c) return null;
  const { data, error } = await supabase.rpc("pickup_board", { in_code: c });
  if (error) throw error;
  const rows = (data as Record<string, unknown>[] | null) ?? [];
  return {
    venueName: rows[0] ? String(rows[0].venue_name) : "",
    numbers: rows.map((r) => ({ no: Number(r.pickup_no), ready: r.state === "ready", since: String(r.since) })),
  };
}

export interface ShelfItem {
  id: string;
  name: string;
  brand?: string;
  category: string;
  size?: number;
  unit?: string;
  byWeight: boolean;
  price: number;
  mrp?: number;
  alcohol: boolean;
}

/** A counter's shelf (store_shelf, 059): in stock, at its price — never how many are left. */
export async function fetchShelf(slug: string): Promise<{ venueName: string; currency: string; items: ShelfItem[] } | null> {
  if (!supabase) return null;
  const { data, error } = await supabase.rpc("store_shelf", { in_slug: slug.trim().toLowerCase() });
  if (error) throw error;
  const rows = (data as Record<string, unknown>[] | null) ?? [];
  if (!rows.length) return null;
  return {
    venueName: String(rows[0].venue_name),
    currency: String(rows[0].currency ?? "INR"),
    items: rows.map((r) => ({
      id: String(r.product_id),
      name: String(r.name),
      brand: (r.brand as string) || undefined,
      category: String(r.category ?? "other"),
      size: r.size == null ? undefined : Number(r.size),
      unit: (r.unit as string) || undefined,
      byWeight: r.sold_by === "weight",
      price: Number(r.price ?? 0),
      mrp: r.mrp == null ? undefined : Number(r.mrp),
      alcohol: r.is_alcohol === true,
    })),
  };
}

/** A counter: a liquor store, sweet shop, bakery or shop — it has a shelf. */
export function isCounterKind(kind: string | undefined): boolean {
  return ["store", "sweet_shop", "bakery", "shop"].includes(kind ?? "");
}

/** What a basket comes to, from the menu's own prices (the staff's price is final). */
export function basketTotal(basket: Map<string, number>, prices: Map<string, number | undefined>): number {
  let t = 0;
  for (const [id, qty] of basket) t += (prices.get(id) ?? 0) * qty;
  return t;
}
