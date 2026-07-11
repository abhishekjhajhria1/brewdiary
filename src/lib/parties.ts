"use client";

// Parties — events inside Together. Supabase-backed, same fetch-on-mount +
// version-bump pattern as friends.ts/circles.ts. A party_shares row exposes one
// entry to one party (entries.visibility untouched). The party page derives its
// recap (drink grid, attributed list, mood cloud, photo wall) from whatever
// guests shared in — nothing is stored.
//
// Invite links: /p/<code> works for non-users via the anon-callable
// party_preview() rpc; a code seen while signed out is stashed locally and
// auto-joined after sign-in (rememberPartyCode / consumePendingPartyCode).
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export type Rsvp = "going" | "maybe" | "no";

export interface Party {
  id: string;
  name: string;
  hostId: string;
  venue?: string;
  date: string;
  inviteCode: string;
  going: number;
}
export type MemberStatus = "pending" | "approved";
export interface PartyGuest {
  id: string;
  handle: string;
  name: string;
  rsvp: Rsvp;
  status: MemberStatus;
}
export interface PartyEntry {
  id: string;
  userId: string;
  authorName: string;
  date: string;
  createdAt: string;
  drink: string;
  mood?: string;
  note?: string;
  venue?: string;
  photos: { id: string; url: string }[];
}
export interface PartyPreview {
  name: string;
  date: string;
  venue?: string;
  hostName: string;
  going: number;
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

// ── my parties ───────────────────────────────────────────────────────────────
export function useParties(): { parties: Party[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [parties, setParties] = useState<Party[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setParties([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("parties")
        .select("id, name, host_id, venue, date, invite_code, party_members(user_id, rsvp, status)")
        .order("date", { ascending: false });
      if (!active) return;
      setParties(
        (data ?? []).map((r: Record<string, unknown>) => ({
          id: r.id as string,
          name: r.name as string,
          hostId: r.host_id as string,
          venue: (r.venue as string) ?? undefined,
          date: r.date as string,
          inviteCode: r.invite_code as string,
          going: (((r.party_members as { rsvp: string; status: string }[]) ?? []).filter(
            (m) => m.rsvp === "going" && m.status === "approved",
          )).length,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { parties, loading };
}

// ── one party: guest list + everything shared in (feeds the recap) ───────────
export function usePartyDetail(partyId: string | null): {
  party: Party | null;
  guests: PartyGuest[];
  entries: PartyEntry[];
  loading: boolean;
} {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [party, setParty] = useState<Party | null>(null);
  const [guests, setGuests] = useState<PartyGuest[]>([]);
  const [entries, setEntries] = useState<PartyEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !partyId || !me) {
      setParty(null);
      setGuests([]);
      setEntries([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const [p, m, s] = await Promise.all([
        supabase!
          .from("parties")
          .select("id, name, host_id, venue, date, invite_code")
          .eq("id", partyId)
          .maybeSingle(),
        supabase!
          .from("party_members")
          .select("user_id, rsvp, status, member:profiles(id, handle, display_name)")
          .eq("party_id", partyId),
        supabase!
          .from("party_shares")
          .select(
            "entry_id, entry:entries(id, user_id, date, drink, mood, note, venue, created_at, author:profiles(display_name, handle), entry_photos(id, url, sort_order))",
          )
          .eq("party_id", partyId),
      ]);
      if (!active) return;
      const gs: PartyGuest[] = (m.data ?? []).map((r: Record<string, unknown>) => {
        const prof = r.member as { id: string; handle: string; display_name: string | null };
        return {
          id: prof.id,
          handle: prof.handle,
          name: prof.display_name ?? prof.handle,
          rsvp: r.rsvp as Rsvp,
          status: (r.status as MemberStatus) ?? "approved",
        };
      });
      setParty(
        p.data
          ? {
              id: p.data.id,
              name: p.data.name,
              hostId: p.data.host_id,
              venue: p.data.venue ?? undefined,
              date: p.data.date,
              inviteCode: p.data.invite_code,
              going: gs.filter((g) => g.rsvp === "going" && g.status === "approved").length,
            }
          : null,
      );
      setGuests(gs);
      setEntries(
        (s.data ?? [])
          .map((r: Record<string, unknown>) => r.entry as Record<string, unknown> | null)
          .filter((e): e is Record<string, unknown> => !!e)
          .map((e) => ({
            id: e.id as string,
            userId: e.user_id as string,
            authorName:
              ((e.author as { display_name?: string; handle?: string } | null)?.display_name ??
                (e.author as { handle?: string } | null)?.handle) ||
              "guest",
            date: e.date as string,
            createdAt: e.created_at as string,
            drink: e.drink as string,
            mood: (e.mood as string) ?? undefined,
            note: (e.note as string) ?? undefined,
            venue: (e.venue as string) ?? undefined,
            photos: (((e.entry_photos as { id: string; url: string; sort_order: number }[]) ?? []) as {
              id: string;
              url: string;
              sort_order: number;
            }[])
              .sort((a, b) => a.sort_order - b.sort_order)
              .map((ph) => ({ id: ph.id, url: ph.url })),
          }))
          .sort((a, b) => a.createdAt.localeCompare(b.createdAt)),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [partyId, me, v]);

  return { party, guests, entries, loading };
}

// ── which parties is one of MY entries shared to? ────────────────────────────
export function useEntryPartyShares(entryId: string | null): Set<string> {
  const v = useVersion();
  const [ids, setIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    if (!supabase || !entryId) {
      setIds(new Set());
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("party_shares").select("party_id").eq("entry_id", entryId);
      if (active) setIds(new Set((data ?? []).map((r) => r.party_id as string)));
    })();
    return () => {
      active = false;
    };
  }, [entryId, v]);
  return ids;
}

// ── invite preview (works signed OUT — anon-callable rpc) ────────────────────
export async function fetchPartyPreview(code: string): Promise<PartyPreview | null> {
  if (!supabase) return null;
  const { data } = await supabase.rpc("party_preview", { code: code.trim() });
  const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
  if (!row) return null;
  return {
    name: row.name as string,
    date: row.date as string,
    venue: (row.venue as string) ?? undefined,
    hostName: row.host_name as string,
    going: row.going as number,
  };
}

// a code opened while signed out is remembered and joined after sign-in
const PENDING_KEY = "brewdiary.pendingParty.v1";
export function rememberPartyCode(code: string) {
  try {
    localStorage.setItem(PENDING_KEY, code.trim());
  } catch {}
}
export function consumePendingPartyCode(): string | null {
  try {
    const c = localStorage.getItem(PENDING_KEY);
    if (c) localStorage.removeItem(PENDING_KEY);
    return c;
  } catch {
    return null;
  }
}

// ── mutations ────────────────────────────────────────────────────────────────
export async function createParty(
  meId: string,
  fields: { name: string; date: string; venue?: string },
): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const name = fields.name.trim();
  if (!name) return { error: "name required" };
  const id = crypto.randomUUID();
  // no .select(): parties_read calls a definer fn (PostgREST RETURNING gotcha)
  const { error } = await supabase
    .from("parties")
    .insert({ id, name, host_id: meId, date: fields.date, venue: fields.venue?.trim() || null });
  if (error) return { error: error.message };
  const { error: mErr } = await supabase.from("party_members").insert({ party_id: id, user_id: meId });
  bump();
  return mErr ? { error: mErr.message } : { id };
}

export async function joinParty(
  code: string,
): Promise<{ id: string; name: string; status: MemberStatus } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const { data, error } = await supabase.rpc("join_party", { code: code.trim() });
  bump();
  if (error) return { error: error.message.includes("invalid code") ? "No party with that code." : error.message };
  const row = (Array.isArray(data) ? data[0] : data) as { id: string; name: string; status: MemberStatus } | null;
  return row ? { id: row.id, name: row.name, status: row.status ?? "pending" } : { error: "No party with that code." };
}

export async function setRsvp(partyId: string, meId: string, rsvp: Rsvp) {
  if (!supabase) return;
  await supabase.from("party_members").update({ rsvp }).eq("party_id", partyId).eq("user_id", meId);
  bump();
}

/** Host lets a pending requester in. */
export async function approveGuest(partyId: string, userId: string) {
  if (!supabase) return;
  await supabase.rpc("approve_party_member", { pid: partyId, uid: userId });
  bump();
}

/** Host turns a request down (removes the pending member row). */
export async function declineGuest(partyId: string, userId: string) {
  if (!supabase) return;
  await supabase.from("party_members").delete().eq("party_id", partyId).eq("user_id", userId);
  bump();
}

export async function leaveParty(partyId: string, meId: string) {
  if (!supabase) return;
  await supabase.from("party_members").delete().eq("party_id", partyId).eq("user_id", meId);
  bump();
}

export async function deleteParty(partyId: string) {
  if (!supabase) return;
  await supabase.from("parties").delete().eq("id", partyId);
  bump();
}

export async function shareToParty(entryId: string, partyId: string, meId: string) {
  if (!supabase) return;
  await supabase.from("party_shares").insert({ entry_id: entryId, party_id: partyId, user_id: meId });
  bump();
}

export async function unshareFromParty(entryId: string, partyId: string) {
  if (!supabase) return;
  await supabase.from("party_shares").delete().eq("entry_id", entryId).eq("party_id", partyId);
  bump();
}
