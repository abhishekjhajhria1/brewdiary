"use client";

// Venues — the bar/venue side (served on bar.bwdy.site, which the middleware
// rewrites onto /venue). A venue is OWNED by a profile (created_by) and STAFFED
// by profiles via venue_staff (owner/manager/bartender). `verified` is our gate
// and cannot be self-set (a DB trigger + RLS enforce it).
//
// Same fetch-on-mount + shared version-bump pattern as circles.ts; degrades to
// empty with no supabase/auth (no fake offline venue).
//
// Insert gotcha (same as circles/parties): venues_read calls a SECURITY DEFINER
// fn, so PostgREST trips on INSERT..RETURNING — ids are generated client-side and
// inserts go out WITHOUT .select().
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export type StaffRole = "owner" | "manager" | "bartender";

export interface Venue {
  id: string;
  name: string;
  slug: string;
  createdBy: string;
  city?: string;
  /** ISO-3166 alpha-2. Decides what kind of perk is LAWFUL here — see perks.ts. */
  country: string;
  /** Sub-national code where it matters (US states 'MA'/'UT'). */
  region?: string;
  verified: boolean;
  myRole: StaffRole;
}
export interface VenueStaff {
  id: string;
  handle: string;
  name: string;
  role: StaffRole;
}
export type VerificationStatus = "pending" | "approved" | "rejected";
export interface VerificationRequest {
  status: VerificationStatus;
  contact: string;
  note?: string;
  createdAt: string;
}

// The web-safe handle used at bar.bwdy.site. Must satisfy the DB check:
// ^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])$  (2..40 chars, alnum ends, hyphens inside).
const SLUG_RE = /^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])$/;
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "") // strip accents
    .replace(/[^a-z0-9]+/g, "-") // non-alnum → hyphen
    .replace(/^-+|-+$/g, "") // trim hyphens
    .slice(0, 40)
    .replace(/-+$/g, ""); // in case the 40-cut left a trailing hyphen
}
export function isValidSlug(slug: string): boolean {
  return SLUG_RE.test(slug);
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

// ── venues I'm on the team of ────────────────────────────────────────────────
export function useMyVenues(): { venues: Venue[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [venues, setVenues] = useState<Venue[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setVenues([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("venue_staff")
        .select("role, venue:venues(id, name, slug, created_by, city, country, region, verified)")
        .eq("user_id", me);
      if (!active) return;
      setVenues(
        (data ?? [])
          .map((r: Record<string, unknown>): Venue | null => {
            const vv = r.venue as Record<string, unknown> | null;
            if (!vv) return null;
            return {
              id: vv.id as string,
              name: vv.name as string,
              slug: vv.slug as string,
              createdBy: vv.created_by as string,
              city: (vv.city as string) ?? undefined,
              country: (vv.country as string) ?? "IN",
              region: (vv.region as string) ?? undefined,
              verified: Boolean(vv.verified),
              myRole: r.role as StaffRole,
            };
          })
          .filter((x): x is Venue => x !== null),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { venues, loading };
}

// ── one venue's roster ───────────────────────────────────────────────────────
export function useVenueStaff(venueId: string | null): { staff: VenueStaff[]; loading: boolean } {
  const v = useVersion();
  const [staff, setStaff] = useState<VenueStaff[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setStaff([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("venue_staff")
        .select("role, member:profiles(id, handle, display_name)")
        .eq("venue_id", venueId);
      if (!active) return;
      const ROLE_RANK: Record<StaffRole, number> = { owner: 0, manager: 1, bartender: 2 };
      setStaff(
        (data ?? [])
          .map((r: Record<string, unknown>) => {
            const p = r.member as { id: string; handle: string; display_name: string | null };
            return { id: p.id, handle: p.handle, name: p.display_name ?? p.handle, role: r.role as StaffRole };
          })
          .sort((a, b) => ROLE_RANK[a.role] - ROLE_RANK[b.role] || a.name.localeCompare(b.name)),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { staff, loading };
}

// ── verification: the venue's own request (they can never approve it) ────────
export function useVerification(venueId: string | null): { request: VerificationRequest | null; loading: boolean } {
  const v = useVersion();
  const [request, setRequest] = useState<VerificationRequest | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setRequest(null);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("venue_verifications")
        .select("status, contact, note, created_at")
        .eq("venue_id", venueId)
        .maybeSingle();
      if (!active) return;
      setRequest(
        data
          ? {
              status: data.status as VerificationStatus,
              contact: data.contact as string,
              note: (data.note as string) ?? undefined,
              createdAt: data.created_at as string,
            }
          : null,
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { request, loading };
}

/** Submit a verification request. RLS forces status='pending' — only the service
 *  role (scripts/verify-venue.mjs) can ever approve it. */
export async function requestVerification(
  venueId: string,
  meId: string,
  contact: string,
  note?: string,
): Promise<string | null> {
  if (!supabase) return "offline";
  const c = contact.trim();
  if (c.length < 3) return "Add a phone or email we can reach you on.";
  const { error } = await supabase
    .from("venue_verifications")
    .insert({ venue_id: venueId, requested_by: meId, contact: c, note: note?.trim() || null });
  bump();
  return error ? error.message : null;
}

/** Withdraw a pending (or rejected) request so it can be resubmitted. */
export async function withdrawVerification(venueId: string) {
  if (!supabase) return;
  await supabase.from("venue_verifications").delete().eq("venue_id", venueId);
  bump();
}

// ── mutations ────────────────────────────────────────────────────────────────
export async function createVenue(
  meId: string,
  fields: { name: string; slug?: string; city?: string; country?: string; region?: string },
): Promise<{ id: string; slug: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const name = fields.name.trim();
  if (!name) return { error: "Give your venue a name." };
  const slug = (fields.slug?.trim() || slugify(name)).toLowerCase();
  if (!isValidSlug(slug)) {
    return { error: "Pick a web-safe address: letters, numbers and hyphens, 2–40 characters." };
  }
  const id = crypto.randomUUID();
  // no .select(): venues_read calls a definer fn (PostgREST RETURNING gotcha)
  const { error } = await supabase
    .from("venues")
    .insert({
      id,
      name,
      slug,
      created_by: meId,
      city: fields.city?.trim() || null,
      // Where the bar is decides what kind of perk it may lawfully offer (020).
      country: (fields.country || "IN").toUpperCase(),
      region: fields.region?.trim().toUpperCase() || null,
    });
  if (error) {
    if (/duplicate|unique/i.test(error.message)) return { error: "That address is taken — try another." };
    return { error: error.message };
  }
  const { error: sErr } = await supabase.from("venue_staff").insert({ venue_id: id, user_id: meId, role: "owner" });
  bump();
  return sErr ? { error: sErr.message } : { id, slug };
}

export async function updateVenue(venueId: string, fields: { name?: string; city?: string }): Promise<string | null> {
  if (!supabase) return "offline";
  const patch: Record<string, string | null> = {};
  if (fields.name !== undefined) {
    const n = fields.name.trim();
    if (!n) return "Name can't be empty.";
    patch.name = n;
  }
  if (fields.city !== undefined) patch.city = fields.city.trim() || null;
  const { error } = await supabase.from("venues").update(patch).eq("id", venueId);
  bump();
  return error ? error.message : null;
}

/** Add a profile to the team. Managers/owner only (RLS enforces it). */
export async function addStaff(venueId: string, userId: string, role: StaffRole = "bartender"): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("venue_staff").insert({ venue_id: venueId, user_id: userId, role });
  bump();
  if (error && /duplicate|unique/i.test(error.message)) return null; // already on the team
  return error ? error.message : null;
}

export async function removeStaff(venueId: string, userId: string) {
  if (!supabase) return;
  await supabase.from("venue_staff").delete().eq("venue_id", venueId).eq("user_id", userId);
  bump();
}

export async function deleteVenue(venueId: string) {
  if (!supabase) return;
  await supabase.from("venues").delete().eq("id", venueId);
  bump();
}
