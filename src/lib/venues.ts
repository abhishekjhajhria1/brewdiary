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
import type { VenueKind } from "./perks";

export type StaffRole = "owner" | "manager" | "bartender";

export interface Venue {
  id: string;
  name: string;
  slug: string;
  createdBy: string;
  city?: string;
  /** on-trade (drink here) or off-trade (carry out). A store is NOT a quieter bar:
   *  it runs no rooms, and its loyalty card needs a separate legal permission,
   *  because at a shop the visit IS the purchase. See perks.ts / 030. */
  kind: VenueKind;
  /** ISO-3166 alpha-2. Decides what kind of perk is LAWFUL here — see perks.ts. */
  country: string;
  /** Sub-national code where it matters (US states 'MA'/'UT'; 'NIR'/'SCT' in GB). */
  region?: string;
  /** Weekdays this bar calls quiet (0 = Sun … 6 = Sat). A visit on one counts
   *  double toward the house perk — never a drink discount. */
  quietNights: number[];
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
        .select("role, venue:venues(id, name, slug, created_by, city, kind, country, region, quiet_nights, verified)")
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
              kind: ((vv.kind as string) ?? "bar") as VenueKind,
              country: (vv.country as string) ?? "IN",
              region: (vv.region as string) ?? undefined,
              quietNights: (vv.quiet_nights as number[]) ?? [],
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
  fields: { name: string; slug?: string; city?: string; kind?: VenueKind; country?: string; region?: string },
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
      // Bar or bottle shop. A store runs no rooms and needs its own legal permission
      // for a loyalty card — the DB refuses one where it isn't allowed (030).
      kind: fields.kind ?? "bar",
      // Where the venue is decides what kind of perk it may lawfully offer (020).
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

export async function updateVenue(
  venueId: string,
  fields: { name?: string; city?: string; quietNights?: number[] },
): Promise<string | null> {
  if (!supabase) return "offline";
  const patch: Record<string, string | number[] | null> = {};
  if (fields.name !== undefined) {
    const n = fields.name.trim();
    if (!n) return "Name can't be empty.";
    patch.name = n;
  }
  if (fields.city !== undefined) patch.city = fields.city.trim() || null;
  // Quiet nights (Postgres dow: 0 = Sunday … 6 = Saturday). A visit on one of these
  // counts DOUBLE toward this venue's perk — private loyalty, never a public score,
  // and never a drink discount. See 024_quiet_nights.sql.
  if (fields.quietNights !== undefined) {
    patch.quiet_nights = [...new Set(fields.quietNights)].filter((d) => d >= 0 && d <= 6).sort();
  }
  const { error } = await supabase.from("venues").update(patch).eq("id", venueId);
  bump();
  return error ? error.message : null;
}

// ── Discover: list the BAR, never the OFFER ──────────────────────────────────
// A listing is a directory entry (Google Maps lists bars). An OFFER is alcohol
// advertising — specifically illegal in India, and banned outright in Thailand,
// Norway, Lithuania, Türkiye and Poland. So this carries a name, a city, and
// whether a room is running. Never a perk, a reward, a price or a drink. If you
// are ever tempted to add "and here's what they're offering tonight" — that is the
// line, and it's the one that turns a diary into an advertising platform.
export interface DiscoverVenue {
  name: string;
  slug: string;
  city?: string;
  country: string;
  kind: VenueKind;
  openTonight: boolean;
}

export function useDiscoverVenues(country?: string | null): { venues: DiscoverVenue[]; loading: boolean } {
  const [state, setState] = useState<{ venues: DiscoverVenue[]; loading: boolean }>({ venues: [], loading: true });

  useEffect(() => {
    if (!supabase) {
      setState({ venues: [], loading: false });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("discover_venues", { in_country: country ?? null, lim: 30 });
      if (!active) return;
      setState({
        venues: ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          name: r.name as string,
          slug: r.slug as string,
          city: (r.city as string) ?? undefined,
          country: r.country as string,
          kind: ((r.kind as string) ?? "bar") as VenueKind,
          openTonight: Boolean(r.open_tonight),
        })),
        loading: false,
      });
    })();
    return () => {
      active = false;
    };
  }, [country]);

  return state;
}

// ── insights: counts a bar can act on, and never a profile of anyone ─────────
// A manager already sees the names of guests in their own room (they need them to
// record a tab). So counts over that same population are not new personal data.
// What WOULD be: a small-group split ("1 new guest" = that named person has never
// been here), a profile built over time, or anything about another venue. Hence:
//   • splits are NULL below k=5 (see k_anon() — 5, not 3, because a 2/1 split in a
//     group of 3 is deducible by subtraction: a differencing attack),
//   • no per-guest rows, ever,
//   • every query is hard-scoped to one venue.
// A NULL means "hidden", which is NOT the same fact as 0 — render it as "—".
export interface VenueInsights {
  rooms: number;
  guests: number;
  newGuests: number | null;
  returningGuests: number | null;
  quietVisits: number;
  otherVisits: number;
  perksEarned: number | null;
  perksClaimed: number;
  tabs: number;
  takings: number;
  kudos: number;
}

export function useVenueInsights(venueId: string | null, days = 30): { data: VenueInsights | null; loading: boolean } {
  const v = useVersion();
  const [state, setState] = useState<{ data: VenueInsights | null; loading: boolean }>({ data: null, loading: true });

  useEffect(() => {
    if (!supabase || !venueId) {
      setState({ data: null, loading: false });
      return;
    }
    let active = true;
    setState({ data: null, loading: true });
    (async () => {
      const { data } = await supabase!.rpc("venue_insights", { vid: venueId, days });
      if (!active) return;
      const r = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
      if (!r) {
        setState({ data: null, loading: false });
        return;
      }
      const num = (x: unknown) => (x === null || x === undefined ? null : Number(x));
      setState({
        data: {
          rooms: Number(r.rooms ?? 0),
          guests: Number(r.guests ?? 0),
          newGuests: num(r.new_guests),
          returningGuests: num(r.returning_guests),
          quietVisits: Number(r.quiet_visits ?? 0),
          otherVisits: Number(r.other_visits ?? 0),
          perksEarned: num(r.perks_earned),
          perksClaimed: Number(r.perks_claimed ?? 0),
          tabs: Number(r.tabs ?? 0),
          takings: Number(r.takings ?? 0),
          kudos: Number(r.kudos ?? 0),
        },
        loading: false,
      });
    })();
    return () => {
      active = false;
    };
  }, [venueId, days, v]);

  return state;
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
