"use client";

// Real "Together" data — Supabase-backed. Replaces the demo social.ts.
// RLS already guarantees a feed query only returns friends' friends-visible entries
// (+ your own), so the feed is just `entries where visibility=friends and not me`.
//
// Hooks fetch on mount and re-run on a shared version bump after any mutation
// (send/accept request, cheers, comment). Keep it simple: fetch + refresh, no realtime yet.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export interface SocialProfile {
  id: string;
  handle: string;
  name: string;
}
export interface FeedComment {
  id: string;
  userId: string;
  body: string;
  createdAt: string;
  authorName: string;
}
export interface FeedEntry {
  id: string;
  userId: string;
  author: SocialProfile;
  date: string;
  createdAt: string;
  drink: string;
  mood?: string;
  note?: string;
  venue?: string;
  cheers: number;
  cheered: boolean;
  comments: FeedComment[];
}
export interface FriendRequest {
  friendshipId: string;
  profile: SocialProfile;
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

type ProfileRow = { id: string; handle: string; display_name: string | null };
function toProfile(r: ProfileRow): SocialProfile {
  return { id: r.id, handle: r.handle, name: r.display_name ?? r.handle };
}

// ── friends list ─────────────────────────────────────────────────────────────
export function useFriends(): { friends: SocialProfile[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [friends, setFriends] = useState<SocialProfile[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setFriends([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("friendships")
        .select(
          "requester_id, addressee_id, requester:profiles!friendships_requester_id_fkey(id,handle,display_name), addressee:profiles!friendships_addressee_id_fkey(id,handle,display_name)",
        )
        .eq("status", "accepted")
        .or(`requester_id.eq.${me},addressee_id.eq.${me}`);
      if (!active) return;
      const list = (data ?? []).map((row: Record<string, unknown>) => {
        const other = (row.requester_id === me ? row.addressee : row.requester) as ProfileRow;
        return toProfile(other);
      });
      setFriends(list);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { friends, loading };
}

// ── incoming requests ────────────────────────────────────────────────────────
export function useFriendRequests(): FriendRequest[] {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [reqs, setReqs] = useState<FriendRequest[]>([]);

  useEffect(() => {
    if (!supabase || !me) {
      setReqs([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("friendships")
        .select("id, requester:profiles!friendships_requester_id_fkey(id,handle,display_name)")
        .eq("addressee_id", me)
        .eq("status", "pending");
      if (!active) return;
      setReqs((data ?? []).map((r: Record<string, unknown>) => ({ friendshipId: r.id as string, profile: toProfile(r.requester as ProfileRow) })));
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return reqs;
}

// ── feed ─────────────────────────────────────────────────────────────────────
export function useFeed(): { feed: FeedEntry[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [feed, setFeed] = useState<FeedEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setFeed([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("entries")
        .select(
          "id,user_id,date,drink,mood,note,venue,created_at, author:profiles(id,handle,display_name), reactions(user_id), comments(id,user_id,body,created_at, author:profiles(display_name))",
        )
        .eq("visibility", "friends")
        .neq("user_id", me)
        .order("created_at", { ascending: false })
        .limit(50);
      if (!active) return;
      const items: FeedEntry[] = (data ?? []).map((r: Record<string, unknown>) => {
        const reactions = (r.reactions as { user_id: string }[]) ?? [];
        const comments = ((r.comments as Record<string, unknown>[]) ?? [])
          .map((c) => ({
            id: c.id as string,
            userId: c.user_id as string,
            body: c.body as string,
            createdAt: c.created_at as string,
            authorName: ((c.author as { display_name?: string } | null)?.display_name) ?? "friend",
          }))
          .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
        return {
          id: r.id as string,
          userId: r.user_id as string,
          author: toProfile(r.author as ProfileRow),
          date: r.date as string,
          createdAt: r.created_at as string,
          drink: r.drink as string,
          mood: (r.mood as string) ?? undefined,
          note: (r.note as string) ?? undefined,
          venue: (r.venue as string) ?? undefined,
          cheers: reactions.length,
          cheered: reactions.some((x) => x.user_id === me),
          comments,
        };
      });
      setFeed(items);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { feed, loading };
}

// ── a friend's entries (for their mosaic) ────────────────────────────────────
export function useFriendEntries(friendId: string | null): { id: string; date: string }[] {
  const v = useVersion();
  const [rows, setRows] = useState<{ id: string; date: string }[]>([]);
  useEffect(() => {
    if (!supabase || !friendId) {
      setRows([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("entries")
        .select("id, date")
        .eq("user_id", friendId)
        .eq("visibility", "friends");
      if (active) setRows((data ?? []) as { id: string; date: string }[]);
    })();
    return () => {
      active = false;
    };
  }, [friendId, v]);
  return rows;
}

// ── search ───────────────────────────────────────────────────────────────────
export async function searchUsers(query: string): Promise<SocialProfile[]> {
  if (!supabase) return [];
  // People type the leading "@" (the placeholder invites it) and often search by
  // NAME, not handle. Strip the wildcard/grouping chars so they can't smuggle an
  // ilike pattern through. The search runs as a SECURITY DEFINER rpc so it can drop
  // anyone on either side of a block — someone you blocked (or who blocked you) can't
  // be found here at all. (Self-exclusion + blocks are handled by the rpc via auth.uid.)
  const q = query
    .trim()
    .replace(/^@+/, "")
    .replace(/[%,()]/g, "");
  if (q.length < 2) return [];
  const { data } = await supabase.rpc("search_users", { q });
  return ((data as ProfileRow[]) ?? []).map((r) => toProfile(r));
}

// ── mutations ────────────────────────────────────────────────────────────────
export async function sendRequest(meId: string, addresseeId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("friendships").insert({ requester_id: meId, addressee_id: addresseeId, status: "pending" });
  bump();
  return error ? error.message : null;
}

export async function acceptRequest(friendshipId: string) {
  if (!supabase) return;
  await supabase.from("friendships").update({ status: "accepted", responded_at: new Date().toISOString() }).eq("id", friendshipId);
  bump();
}

export async function declineRequest(friendshipId: string) {
  if (!supabase) return;
  await supabase.from("friendships").delete().eq("id", friendshipId);
  bump();
}

export async function toggleCheers(entryId: string, meId: string, cheered: boolean) {
  if (!supabase) return;
  if (cheered) {
    await supabase.from("reactions").delete().eq("entry_id", entryId).eq("user_id", meId).eq("type", "cheers");
  } else {
    await supabase.from("reactions").insert({ entry_id: entryId, user_id: meId, type: "cheers" });
  }
  bump();
}

export async function addComment(entryId: string, meId: string, body: string) {
  if (!supabase) return;
  const text = body.trim();
  if (!text) return;
  await supabase.from("comments").insert({ entry_id: entryId, user_id: meId, body: text });
  bump();
}
