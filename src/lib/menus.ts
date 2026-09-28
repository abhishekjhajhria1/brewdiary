"use client";

// Menus — the paper menu on the table, opened by tapping an NFC tag (or scanning
// the QR) that holds bwdy.site/m/<slug>. With the app installed the phone opens
// the menu in the app; without it, /m/<slug> on the website shows the same menu.
//
// The lines (see supabase/042_menus.sql): a menu is NOT an offer (no discount
// column exists), it is reached from the table and never from Discover, a guest
// reading it tells the venue nothing, and only verified venues are served.
//
// "You'd probably like" (menuPicks) is worked out HERE, on the guest's device,
// from their own diary. The diary never goes anywhere.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { canonicalize, normalize } from "./drinks";
import type { DrinkType, Entry } from "./types";

export type MenuKind = Exclude<DrinkType, "none"> | "food";
export const MENU_KINDS: MenuKind[] = ["cocktail", "beer", "wine", "spirit", "coffee", "tea", "soft", "food", "other"];

export interface MenuItem {
  id: string;
  section: string;
  name: string;
  description?: string;
  price?: number;
  kind?: MenuKind;
  noAlcohol: boolean;
}
export interface MenuSection {
  name: string;
  items: MenuItem[];
}
export interface Menu {
  venueName: string;
  venueCity?: string;
  venueKind: "bar" | "store";
  currency: string;
  sections: MenuSection[];
}

/** The URL to write onto a table's NFC tag / print as its QR. */
export function menuUrl(slug: string, origin = "https://bwdy.site"): string {
  return `${origin.replace(/\/$/, "")}/m/${slug}`;
}

/** Rows from venue_menu() → a menu, sections in first-seen order (the rpc sorts by position). */
export function groupMenu(rows: Record<string, unknown>[]): Menu | null {
  if (rows.length === 0) return null;
  const first = rows[0];
  const sections: MenuSection[] = [];
  const bySection = new Map<string, MenuSection>();
  for (const r of rows) {
    if (!r.item_id) continue; // a verified venue with an empty menu
    const name = String(r.section ?? "Menu");
    let s = bySection.get(name);
    if (!s) {
      s = { name, items: [] };
      bySection.set(name, s);
      sections.push(s);
    }
    s.items.push({
      id: String(r.item_id),
      section: name,
      name: String(r.name),
      description: (r.description as string) || undefined,
      price: r.price == null ? undefined : Number(r.price),
      kind: (r.kind as MenuKind) || undefined,
      noAlcohol: Boolean(r.no_alcohol),
    });
  }
  return {
    venueName: String(first.venue_name),
    venueCity: (first.venue_city as string) || undefined,
    venueKind: first.venue_kind === "store" ? "store" : "bar",
    currency: String(first.currency ?? "INR"),
    sections,
  };
}

/** Public read by slug (works signed out). null = no such verified venue. */
export async function fetchMenu(slug: string): Promise<Menu | null> {
  if (!supabase) return null;
  const { data, error } = await supabase.rpc("venue_menu", { in_slug: slug });
  if (error) throw error;
  return groupMenu((data ?? []) as Record<string, unknown>[]);
}

/**
 * "You'd probably like" — up to `n` item ids, from the guest's OWN diary, on their
 * device. An item scores for sharing a drink family with something they've logged
 * (by how often), then for sharing a kind. Food never scores (the diary is drinks).
 * Items they've already had by name are skipped: this is for choosing, not repeating.
 */
export function menuPicks(menu: Menu, entries: Entry[], n = 3): string[] {
  const family = new Map<string, number>();
  const kind = new Map<string, number>();
  const had = new Set<string>();
  for (const e of entries) {
    if (e.type === "none") continue;
    const c = canonicalize(e.drink);
    family.set(c.family, (family.get(c.family) ?? 0) + 1);
    const t = e.type ?? c.type;
    if (t) kind.set(t, (kind.get(t) ?? 0) + 1);
    had.add(normalize(e.drink));
  }
  if (family.size === 0) return [];
  const scored: { id: string; score: number }[] = [];
  for (const s of menu.sections) {
    for (const it of s.items) {
      if (it.kind === "food" || had.has(normalize(it.name))) continue;
      const c = canonicalize(it.name);
      const score = (c.matched ? (family.get(c.family) ?? 0) * 3 : 0) + (it.kind ? (kind.get(it.kind) ?? 0) : 0);
      if (score > 0) scored.push({ id: it.id, score });
    }
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, n).map((x) => x.id);
}

// ── the venue's editor ───────────────────────────────────────────────────────
export interface EditableMenuItem extends MenuItem {
  available: boolean;
  position: number;
}

let version = 0;
const subs = new Set<() => void>();
function bump() {
  version++;
  subs.forEach((s) => s());
}
function useVersion() {
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

export function useMenuItems(venueId: string | null): { items: EditableMenuItem[]; loading: boolean } {
  const v = useVersion();
  const [items, setItems] = useState<EditableMenuItem[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    if (!supabase || !venueId) {
      setItems([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("venue_menu_items")
        .select("id, section, name, description, price, kind, no_alcohol, available, position")
        .eq("venue_id", venueId)
        .order("position")
        .order("created_at");
      if (!active) return;
      setItems(
        (data ?? []).map((r: Record<string, unknown>) => ({
          id: r.id as string,
          section: r.section as string,
          name: r.name as string,
          description: (r.description as string) || undefined,
          price: r.price == null ? undefined : Number(r.price),
          kind: (r.kind as MenuKind) || undefined,
          noAlcohol: Boolean(r.no_alcohol),
          available: Boolean(r.available),
          position: Number(r.position ?? 0),
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);
  return { items, loading };
}

export interface MenuItemInput {
  section: string;
  name: string;
  description?: string;
  price?: number;
  kind?: MenuKind;
  noAlcohol: boolean;
}

/** Validate before it hits the DB checks, with a message a bar owner understands. */
export function checkMenuItem(i: MenuItemInput): string | null {
  if (!i.name.trim()) return "Give it a name.";
  if (i.name.trim().length > 80) return "Keep the name under 80 characters.";
  if (!i.section.trim()) return "Pick a section, like Cocktails or Food.";
  if (i.section.trim().length > 40) return "Keep the section under 40 characters.";
  if ((i.description ?? "").length > 240) return "Keep the description under 240 characters.";
  if (i.price != null && (!Number.isFinite(i.price) || i.price < 0)) return "The price should be a number, or left blank.";
  return null;
}

// Inserts carry a client-generated id and no .select() (the RLS read policy calls a
// SECURITY DEFINER fn — see venues.ts).
export async function addMenuItem(venueId: string, i: MenuItemInput, position: number): Promise<string | null> {
  if (!supabase) return "Not connected.";
  const bad = checkMenuItem(i);
  if (bad) return bad;
  const { error } = await supabase.from("venue_menu_items").insert({
    id: crypto.randomUUID(),
    venue_id: venueId,
    section: i.section.trim(),
    name: i.name.trim(),
    description: i.description?.trim() || null,
    price: i.price ?? null,
    kind: i.kind ?? null,
    no_alcohol: i.noAlcohol,
    position,
  });
  if (error) return "Couldn't add it — try again.";
  bump();
  return null;
}

export async function updateMenuItem(id: string, patch: Partial<MenuItemInput> & { available?: boolean }): Promise<string | null> {
  if (!supabase) return "Not connected.";
  const row: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (patch.section !== undefined) row.section = patch.section.trim();
  if (patch.name !== undefined) row.name = patch.name.trim();
  if (patch.description !== undefined) row.description = patch.description.trim() || null;
  if (patch.price !== undefined) row.price = patch.price ?? null;
  if (patch.kind !== undefined) row.kind = patch.kind ?? null;
  if (patch.noAlcohol !== undefined) row.no_alcohol = patch.noAlcohol;
  if (patch.available !== undefined) row.available = patch.available;
  const { error } = await supabase.from("venue_menu_items").update(row).eq("id", id);
  if (error) return "Couldn't save — try again.";
  bump();
  return null;
}

export async function removeMenuItem(id: string): Promise<void> {
  if (!supabase) return;
  await supabase.from("venue_menu_items").delete().eq("id", id);
  bump();
}
