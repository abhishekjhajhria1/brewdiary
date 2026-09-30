"use client";

// The table's own link — bwdy.site/t/<code> (051). What a table's QR or NFC tag opens:
// the venue's menu with the table already known, and — if the venue switched it on —
// ordering from the phone and "call staff / bill please / water".
//
// A guest only ASKS: an order is a request the staff accept onto the table's tab (priced
// by the server as if they'd keyed it) or decline with a reason the guest sees. Staff
// never learn who asked; the guest sees only their own requests. Signing in is needed
// to ask (so a request can be rate-limited and answered), not to read the menu.
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
}

export type CallKind = "staff" | "bill" | "water";

export interface MyRequest {
  id: string;
  status: "pending" | "accepted" | "declined" | "withdrawn";
  lines: { name: string; qty: number; note?: string }[];
  declineReason?: string;
  createdAt: string;
}

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
  };
}

/** Send an order to the staff. `lines`: what and how many — never a price. */
export async function requestOrder(code: string, lines: { item: string; qty: number; note?: string }[], note?: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("request_order", { in_code: code, req: crypto.randomUUID(), lines, req_note: note ?? null });
  return error ? error.message : null;
}

export async function callStaff(code: string, kind: CallKind): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("call_table_staff", { in_code: code, call_kind: kind });
  return error ? error.message : null;
}

export async function withdrawRequest(id: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("withdraw_request", { req: id });
  return error ? error.message : null;
}

/** My own requests at this venue tonight (RLS returns only mine), newest first. Polls. */
export function useMyRequests(enabled: boolean, nonce: number): MyRequest[] {
  const [rows, setRows] = useState<MyRequest[]>([]);
  const load = useCallback(async () => {
    if (!supabase || !enabled) return;
    const since = new Date(Date.now() - 12 * 3600_000).toISOString();
    const { data } = await supabase
      .from("order_requests")
      .select("id, status, lines, decline_reason, created_at")
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(10);
    setRows(
      ((data ?? []) as Record<string, unknown>[]).map((r) => ({
        id: String(r.id),
        status: r.status as MyRequest["status"],
        lines: ((r.lines as { name: string; qty: number; note?: string }[]) ?? []).map((l) => ({ name: l.name, qty: l.qty, note: l.note ?? undefined })),
        declineReason: (r.decline_reason as string) || undefined,
        createdAt: String(r.created_at),
      })),
    );
  }, [enabled]);

  useEffect(() => {
    void load();
    if (!enabled) return;
    const t = setInterval(() => void load(), 15_000);
    return () => clearInterval(t);
  }, [load, enabled, nonce]);

  return rows;
}

/** What a basket comes to, from the menu's own prices (the staff's price is final). */
export function basketTotal(basket: Map<string, number>, prices: Map<string, number | undefined>): number {
  let t = 0;
  for (const [id, qty] of basket) t += (prices.get(id) ?? 0) * qty;
  return t;
}
