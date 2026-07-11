"use client";

// Circles — private groups inside Together. Supabase-backed, same fetch-on-mount
// + shared version-bump pattern as friends.ts.
//
// Sharing model: a circle_shares row exposes ONE entry to ONE circle without
// touching entries.visibility (diary stays private by default; sharing is a
// separate deliberate act). The circle mosaic is DERIVED here from whatever
// members have shared in — never stored.
//
// Insert gotcha (learned on expenses): tables whose select policy calls a
// SECURITY DEFINER fn trip PostgREST on INSERT..RETURNING — so ids are
// generated client-side and inserts go out without .select().
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export interface Circle {
  id: string;
  name: string;
  createdBy: string;
  inviteCode: string;
  memberCount: number;
}
export interface CircleMember {
  id: string;
  handle: string;
  name: string;
}
export interface CircleEntry {
  id: string;
  userId: string;
  authorName: string;
  date: string;
  createdAt: string;
  drink: string;
  mood?: string;
  note?: string;
  venue?: string;
}
export interface CircleDetail {
  members: CircleMember[];
  entries: CircleEntry[];
  loading: boolean;
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

// ── my circles ───────────────────────────────────────────────────────────────
export function useCircles(): { circles: Circle[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [circles, setCircles] = useState<Circle[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setCircles([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("circles")
        .select("id, name, created_by, invite_code, circle_members(user_id)")
        .order("created_at", { ascending: true });
      if (!active) return;
      setCircles(
        (data ?? []).map((r: Record<string, unknown>) => ({
          id: r.id as string,
          name: r.name as string,
          createdBy: r.created_by as string,
          inviteCode: r.invite_code as string,
          memberCount: ((r.circle_members as unknown[]) ?? []).length,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { circles, loading };
}

// ── one circle: roster + shared entries (feeds the combined mosaic) ──────────
export function useCircleDetail(circleId: string | null): CircleDetail {
  const v = useVersion();
  const [members, setMembers] = useState<CircleMember[]>([]);
  const [entries, setEntries] = useState<CircleEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !circleId) {
      setMembers([]);
      setEntries([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const [m, s] = await Promise.all([
        supabase!
          .from("circle_members")
          .select("user_id, member:profiles(id, handle, display_name)")
          .eq("circle_id", circleId),
        supabase!
          .from("circle_shares")
          .select(
            "entry_id, entry:entries(id, user_id, date, drink, mood, note, venue, created_at, author:profiles(display_name, handle))",
          )
          .eq("circle_id", circleId),
      ]);
      if (!active) return;
      setMembers(
        (m.data ?? []).map((r: Record<string, unknown>) => {
          const p = r.member as { id: string; handle: string; display_name: string | null };
          return { id: p.id, handle: p.handle, name: p.display_name ?? p.handle };
        }),
      );
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
              "member",
            date: e.date as string,
            createdAt: e.created_at as string,
            drink: e.drink as string,
            mood: (e.mood as string) ?? undefined,
            note: (e.note as string) ?? undefined,
            venue: (e.venue as string) ?? undefined,
          }))
          .sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [circleId, v]);

  return { members, entries, loading };
}

// ── which circles is one of MY entries shared to? (for the log-sheet toggles) ─
export function useEntryCircleShares(entryId: string | null): Set<string> {
  const v = useVersion();
  const [ids, setIds] = useState<Set<string>>(new Set());
  useEffect(() => {
    if (!supabase || !entryId) {
      setIds(new Set());
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("circle_shares").select("circle_id").eq("entry_id", entryId);
      if (active) setIds(new Set((data ?? []).map((r) => r.circle_id as string)));
    })();
    return () => {
      active = false;
    };
  }, [entryId, v]);
  return ids;
}

// ── mutations ────────────────────────────────────────────────────────────────
export async function createCircle(meId: string, name: string): Promise<string | null> {
  if (!supabase) return "offline";
  const clean = name.trim();
  if (!clean) return "name required";
  const id = crypto.randomUUID();
  // no .select(): circles_read calls a definer fn (PostgREST RETURNING gotcha)
  const { error } = await supabase.from("circles").insert({ id, name: clean, created_by: meId });
  if (error) return error.message;
  const { error: mErr } = await supabase.from("circle_members").insert({ circle_id: id, user_id: meId });
  bump();
  return mErr ? mErr.message : null;
}

export async function joinCircle(code: string): Promise<{ name: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const { data, error } = await supabase.rpc("join_circle", { code: code.trim() });
  bump();
  if (error) return { error: error.message.includes("invalid code") ? "No circle with that code." : error.message };
  const row = Array.isArray(data) ? data[0] : data;
  return { name: (row as { name?: string } | null)?.name ?? "circle" };
}

export async function leaveCircle(circleId: string, meId: string) {
  if (!supabase) return;
  await supabase.from("circle_members").delete().eq("circle_id", circleId).eq("user_id", meId);
  bump();
}

export async function deleteCircle(circleId: string) {
  if (!supabase) return;
  await supabase.from("circles").delete().eq("id", circleId);
  bump();
}

export async function shareToCircle(entryId: string, circleId: string, meId: string) {
  if (!supabase) return;
  await supabase.from("circle_shares").insert({ entry_id: entryId, circle_id: circleId, user_id: meId });
  bump();
}

export async function unshareFromCircle(entryId: string, circleId: string) {
  if (!supabase) return;
  await supabase.from("circle_shares").delete().eq("entry_id", entryId).eq("circle_id", circleId);
  bump();
}
