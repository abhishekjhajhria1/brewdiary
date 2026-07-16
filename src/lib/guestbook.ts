"use client";

// The venue guest book — a FIRST-PARTY CRM. Everything here is scoped to one venue
// and one guest who has actually been there; nothing reads the guest's diary or any
// other venue (the database enforces it — see 040_guest_book.sql). Staff keep notes
// and tags; the factual history (visits, tabs, perks) is derived live and read-only.
import { useCallback, useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export interface GuestCard {
  visits: number;
  firstSeen: string | null;
  lastSeen: string | null;
  tabs: number;
  totalSpend: number;
  perksClaimed: number;
  hasEarned: boolean;
  beenHere: boolean; // false ⇒ no book may be kept
  note: string;
  tags: string[];
  noteUpdatedAt: string | null;
}

function toCard(r: Record<string, unknown>): GuestCard {
  return {
    visits: Number(r.visits ?? 0),
    firstSeen: (r.first_seen as string) ?? null,
    lastSeen: (r.last_seen as string) ?? null,
    tabs: Number(r.tabs ?? 0),
    totalSpend: Number(r.total_spend ?? 0),
    perksClaimed: Number(r.perks_claimed ?? 0),
    hasEarned: Boolean(r.has_earned),
    beenHere: Boolean(r.been_here),
    note: (r.note as string) ?? "",
    tags: Array.isArray(r.tags) ? (r.tags as unknown[]).map(String) : [],
    noteUpdatedAt: (r.note_updated_at as string) ?? null,
  };
}

export function useGuestCard(
  venueId: string | null,
  guestId: string | null,
): { card: GuestCard | null; loading: boolean; reload: () => void } {
  const [card, setCard] = useState<GuestCard | null>(null);
  const [loading, setLoading] = useState(true);
  const [nonce, setNonce] = useState(0);
  const reload = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    if (!supabase || !venueId || !guestId) {
      setCard(null);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("venue_guest_card", { vid: venueId, uid: guestId });
      if (!active) return;
      const r = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
      setCard(r ? toCard(r) : null);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [venueId, guestId, nonce]);

  return { card, loading, reload };
}

/** Staff write a guest's note + tags. Server enforces staff + interaction gate. */
export async function setGuestNote(
  venueId: string,
  guestId: string,
  body: string,
  tags: string[],
): Promise<string | null> {
  if (!supabase) return "offline";
  const cleanTags = tags
    .map((t) => t.trim().slice(0, 24))
    .filter(Boolean)
    .slice(0, 12);
  const { error } = await supabase.rpc("set_guest_note", {
    vid: venueId,
    uid: guestId,
    in_body: body.slice(0, 2000),
    in_tags: cleanTags,
  });
  return error ? error.message : null;
}

// ── the guest's own transparency view ────────────────────────────────────────
export interface VenueBook {
  venueId: string;
  venueName: string;
  body: string;
  tags: string[];
  updatedAt: string;
}

export function useMyVenueBooks(): { books: VenueBook[]; loading: boolean; reload: () => void } {
  const me = useAuth().profile?.id;
  const [books, setBooks] = useState<VenueBook[]>([]);
  const [loading, setLoading] = useState(true);
  const [nonce, setNonce] = useState(0);
  const reload = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    if (!supabase || !me) {
      setBooks([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("my_venue_books");
      if (!active) return;
      setBooks(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          venueId: r.venue_id as string,
          venueName: (r.venue_name as string) ?? "a venue",
          body: (r.body as string) ?? "",
          tags: Array.isArray(r.tags) ? (r.tags as unknown[]).map(String) : [],
          updatedAt: r.updated_at as string,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, nonce]);

  return { books, loading, reload };
}

/** The guest erases a venue's note on them — RLS lets the subject delete their own row. */
export async function forgetVenueBook(meId: string, venueId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase
    .from("venue_guest_notes")
    .delete()
    .eq("venue_id", venueId)
    .eq("subject_id", meId);
  return error ? error.message : null;
}
