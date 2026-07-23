"use client";

// Reservations + dining offers — the "Dineout" layer.
//
// ── WHAT INSPIRED THIS, AND THE ONE LINE IT HOLDS ───────────────────────────
// Modelled on Zomato Dineout / EazyDiner: browse partner venues, see the DINING
// deal they're offering ("Flat 20% off the total bill", a set menu), and book a
// table. Those services operate lawfully in India because what they advertise is a
// DINING offer, never the alcohol itself. brewdiary keeps exactly that line:
//   • a DINING offer (percent off / flat deal / set menu / experience) is public
//     and advertisable — it is not surrogate alcohol advertising;
//   • an ALCOHOL offer (a free/discounted drink) stays the PRIVATE venue_perks
//     loyalty card (perks.ts) — earned after you're there, staff-recorded, never
//     advertised. There is deliberately no alcohol field here.
// The database enforces all of it (050): a dining offer can't exist at a bottle
// shop or an unverified venue, and a guest can only ever REQUEST a table for
// themselves — a booking is confirmed by staff, never self-confirmed.
//
// Same fetch-on-mount + shared version-bump pattern as venues.ts / plans.ts.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import type { VenueKind } from "./perks";

export type OfferKind = "percent_off" | "flat_deal" | "set_menu" | "experience";
export type ReservationStatus =
  | "requested"
  | "confirmed"
  | "declined"
  | "cancelled"
  | "seated"
  | "no_show";

/** A dining offer as shown to a guest in Discover (via discover_offers). */
export interface DiscoverOffer {
  venueId: string;
  name: string;
  slug: string;
  city?: string;
  country: string;
  offerId: string;
  title: string;
  detail?: string;
  kind: OfferKind;
  percentOff?: number;
}

/** A verified venue a guest can attach to a plan or book (via venue_directory). */
export interface DirectoryVenue {
  id: string;
  name: string;
  slug: string;
  city?: string;
  kind: VenueKind;
  country: string;
}

/** A booking as the GUEST sees it (their own). */
export interface MyReservation {
  id: string;
  venueId: string;
  venueName: string;
  venueSlug?: string;
  city?: string;
  date: string;
  time?: string;
  partySize: number;
  note?: string;
  status: ReservationStatus;
  createdAt: string;
}

/** A booking as the VENUE'S staff see it. */
export interface VenueReservation {
  id: string;
  guestName: string;
  guestHandle: string;
  offerTitle?: string;
  date: string;
  time?: string;
  partySize: number;
  note?: string;
  status: ReservationStatus;
  createdAt: string;
}

/** A dining offer as the venue's manager edits it. */
export interface DiningOffer {
  id: string;
  title: string;
  detail?: string;
  kind: OfferKind;
  percentOff?: number;
  active: boolean;
}

export interface NewOffer {
  title: string;
  detail?: string;
  kind: OfferKind;
  percentOff?: number;
}

export interface NewReservation {
  date: string; // YYYY-MM-DD, today or later
  time?: string; // HH:MM
  partySize: number;
  note?: string;
  offerId?: string;
  planId?: string;
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

// ── Discover: verified bars and the dining offer they're running ─────────────
export function useDiscoverOffers(country?: string | null): { offers: DiscoverOffer[]; loading: boolean } {
  const [state, setState] = useState<{ offers: DiscoverOffer[]; loading: boolean }>({ offers: [], loading: true });

  useEffect(() => {
    if (!supabase) {
      setState({ offers: [], loading: false });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("discover_offers", { in_country: country ?? null, lim: 40 });
      if (!active) return;
      setState({
        offers: ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          venueId: r.venue_id as string,
          name: r.name as string,
          slug: r.slug as string,
          city: (r.city as string) ?? undefined,
          country: r.country as string,
          offerId: r.offer_id as string,
          title: r.title as string,
          detail: (r.detail as string) ?? undefined,
          kind: (r.kind as OfferKind) ?? "flat_deal",
          percentOff: r.percent_off != null ? Number(r.percent_off) : undefined,
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

// ── the verified-venue directory (for the plan venue-picker + id→name lookup) ──
export function useVenueDirectory(q: string | null): { venues: DirectoryVenue[]; loading: boolean } {
  const [state, setState] = useState<{ venues: DirectoryVenue[]; loading: boolean }>({ venues: [], loading: false });

  useEffect(() => {
    if (!supabase || q === null) {
      setState({ venues: [], loading: false });
      return;
    }
    let active = true;
    setState((s) => ({ ...s, loading: true }));
    (async () => {
      const { data } = await supabase!.rpc("venue_directory", { q: q.trim() || null });
      if (!active) return;
      setState({
        venues: ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          id: r.id as string,
          name: r.name as string,
          slug: r.slug as string,
          city: (r.city as string) ?? undefined,
          kind: ((r.kind as string) ?? "bar") as VenueKind,
          country: r.country as string,
        })),
        loading: false,
      });
    })();
    return () => {
      active = false;
    };
  }, [q]);

  return state;
}

// Resolve an attached venue's name for DISPLAY (e.g. a plan card that stores only a
// venue_id). The verified-venue directory is small and public, so we load it once and
// cache it module-wide rather than fetch per card.
let directoryCache: DirectoryVenue[] | null = null;
let directoryPromise: Promise<DirectoryVenue[]> | null = null;
async function loadDirectory(): Promise<DirectoryVenue[]> {
  if (directoryCache) return directoryCache;
  if (!directoryPromise) {
    directoryPromise = (async () => {
      if (!supabase) return [];
      const { data } = await supabase.rpc("venue_directory", { q: null });
      directoryCache = ((data as Record<string, unknown>[]) ?? []).map((r) => ({
        id: r.id as string,
        name: r.name as string,
        slug: r.slug as string,
        city: (r.city as string) ?? undefined,
        kind: ((r.kind as string) ?? "bar") as VenueKind,
        country: r.country as string,
      }));
      return directoryCache;
    })();
  }
  return directoryPromise;
}

/** The display name of a venue by id (or null while loading / unknown). */
export function useVenueName(venueId?: string | null): string | null {
  const [name, setName] = useState<string | null>(null);
  useEffect(() => {
    if (!venueId) {
      setName(null);
      return;
    }
    let active = true;
    loadDirectory().then((list) => {
      if (active) setName(list.find((v) => v.id === venueId)?.name ?? null);
    });
    return () => {
      active = false;
    };
  }, [venueId]);
  return name;
}

// ── the guest's own bookings ─────────────────────────────────────────────────
export function useMyReservations(): { reservations: MyReservation[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [reservations, setReservations] = useState<MyReservation[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setReservations([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("reservations")
        .select("id, venue_id, res_date, res_time, party_size, note, status, created_at, venue:venues(name, slug, city)")
        .eq("user_id", me)
        .order("res_date", { ascending: false });
      if (!active) return;
      setReservations(
        ((data as Record<string, unknown>[]) ?? []).map((r) => {
          const venue = r.venue as { name?: string; slug?: string; city?: string } | null;
          return {
            id: r.id as string,
            venueId: r.venue_id as string,
            venueName: venue?.name ?? "a venue",
            venueSlug: venue?.slug ?? undefined,
            city: venue?.city ?? undefined,
            date: r.res_date as string,
            time: (r.res_time as string) ?? undefined,
            partySize: Number(r.party_size ?? 1),
            note: (r.note as string) ?? undefined,
            status: r.status as ReservationStatus,
            createdAt: r.created_at as string,
          };
        }),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { reservations, loading };
}

// ── the venue's incoming bookings (any staff) ────────────────────────────────
export function useVenueReservations(venueId: string | null): { reservations: VenueReservation[]; loading: boolean } {
  const v = useVersion();
  const [reservations, setReservations] = useState<VenueReservation[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setReservations([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("reservations")
        .select(
          "id, res_date, res_time, party_size, note, status, created_at, guest:profiles(display_name, handle), offer:dining_offers(title)",
        )
        .eq("venue_id", venueId)
        .order("res_date", { ascending: true });
      if (!active) return;
      setReservations(
        ((data as Record<string, unknown>[]) ?? []).map((r) => {
          const guest = r.guest as { display_name?: string; handle?: string } | null;
          const offer = r.offer as { title?: string } | null;
          return {
            id: r.id as string,
            guestName: guest?.display_name ?? guest?.handle ?? "a guest",
            guestHandle: guest?.handle ?? "",
            offerTitle: offer?.title ?? undefined,
            date: r.res_date as string,
            time: (r.res_time as string) ?? undefined,
            partySize: Number(r.party_size ?? 1),
            note: (r.note as string) ?? undefined,
            status: r.status as ReservationStatus,
            createdAt: r.created_at as string,
          };
        }),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { reservations, loading };
}

// ── mutations: bookings ──────────────────────────────────────────────────────

/** Ask for a table. Insert WITHOUT .select() — reservations_read gates on a definer
 *  fn (is_venue_staff), so PostgREST RETURNING trips (same gotcha as venues/plans);
 *  the id is client-made. The DB forces status='requested' and re-checks the venue. */
export async function createReservation(venueId: string, p: NewReservation): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const me = (await supabase.auth.getUser()).data.user?.id;
  if (!me) return { error: "Sign in to book a table." };
  if (!p.date) return { error: "Pick a date." };
  if (!Number.isFinite(p.partySize) || p.partySize < 1) return { error: "How many people?" };

  const id = crypto.randomUUID();
  const { error } = await supabase.from("reservations").insert({
    id,
    venue_id: venueId,
    user_id: me,
    offer_id: p.offerId || null,
    plan_id: p.planId || null,
    res_date: p.date,
    res_time: p.time || null,
    party_size: Math.min(Math.max(Math.round(p.partySize), 1), 50),
    note: p.note?.trim() || null,
  });
  bump();
  if (error) {
    if (/past/i.test(error.message)) return { error: "That date has passed — pick another." };
    if (/verified|off-licence|table/i.test(error.message)) return { error: "You can only book a table at a verified bar." };
    return { error: "Couldn't send that booking — try again." };
  }
  return { id };
}

/** The guest calls off their own booking. */
export async function cancelReservation(id: string): Promise<string | null> {
  return setReservationStatus(id, "cancelled");
}

/** Move a booking forward. A guest may only 'cancelled' their own; staff may
 *  confirm/decline/seat/no_show. The server (set_reservation_status) decides. */
export async function setReservationStatus(id: string, status: ReservationStatus): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("set_reservation_status", { rid: id, new_status: status });
  bump();
  if (!error) return null;
  if (/not allowed|staff/i.test(error.message)) return "You can't change this booking.";
  return "Couldn't update that — try again.";
}

// ── mutations: dining offers (venue managers of a verified bar) ──────────────

export function useVenueOffers(venueId: string | null): { offers: DiningOffer[]; loading: boolean } {
  const v = useVersion();
  const [offers, setOffers] = useState<DiningOffer[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !venueId) {
      setOffers([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!
        .from("dining_offers")
        .select("id, title, detail, kind, percent_off, active")
        .eq("venue_id", venueId)
        .order("created_at", { ascending: true });
      if (!active) return;
      setOffers(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          id: r.id as string,
          title: r.title as string,
          detail: (r.detail as string) ?? undefined,
          kind: (r.kind as OfferKind) ?? "flat_deal",
          percentOff: r.percent_off != null ? Number(r.percent_off) : undefined,
          active: Boolean(r.active),
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return { offers, loading };
}

/** How many dining offers a venue may run at once — a short, legible menu, same
 *  spirit as the 3-tier cap on perks. */
export const MAX_OFFERS = 4;

export async function addDiningOffer(venueId: string, meId: string, offer: NewOffer): Promise<string | null> {
  if (!supabase) return "offline";
  const title = offer.title.trim();
  if (!title) return "Describe the offer.";
  if (offer.kind === "percent_off" && (!offer.percentOff || offer.percentOff < 1 || offer.percentOff > 100)) {
    return "Set a percentage between 1 and 100.";
  }
  const { error } = await supabase.from("dining_offers").insert({
    venue_id: venueId,
    title,
    detail: offer.detail?.trim() || null,
    kind: offer.kind,
    percent_off: offer.kind === "percent_off" ? Math.round(offer.percentOff!) : null,
    created_by: meId,
    updated_at: new Date().toISOString(),
  });
  bump();
  if (!error) return null;
  // The DB is the authority on what's lawful where — surface its reason verbatim.
  if (/off-licence|verified|not permitted/i.test(error.message)) return error.message;
  return /row-level security|violates/i.test(error.message) ? "Only a manager of a verified venue can add an offer." : error.message;
}

export async function toggleDiningOffer(id: string, active: boolean): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("dining_offers").update({ active, updated_at: new Date().toISOString() }).eq("id", id);
  bump();
  return error ? "Couldn't update that offer." : null;
}

export async function removeDiningOffer(id: string) {
  if (!supabase) return;
  await supabase.from("dining_offers").delete().eq("id", id);
  bump();
}
