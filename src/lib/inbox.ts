"use client";

// The Together inbox — everything waiting on YOU, in one place.
//
// ── WHY ─────────────────────────────────────────────────────────────────────
// Every social feature here grew its own pending queue and kept it inside its own
// room: friend requests under Feed, join requests inside a plan, guests at the door
// inside a party. So nothing ever TOLD you that you were needed — you had to go
// looking, in four places, on the off chance. That is most of why Together had no
// reason to be opened.
//
// One rpc (`together_inbox`, migration 053) unions those queues. It is deliberately
// not a new read surface: every branch is scoped to auth.uid() server-side and
// returns only rows the caller's existing RLS already permits.
//
// ── WHAT IT IS NOT ──────────────────────────────────────────────────────────
// Not a notification feed, and not a growth lever. It holds only things that need a
// DECISION from you and that disappear once you make it. No likes, no "someone
// viewed your profile", no manufactured urgency, no unread state that never
// resolves. When it's empty it says so plainly and stays quiet.
//
// ── REFRESH ─────────────────────────────────────────────────────────────────
// The four queues live behind three different libraries with three different
// refresh buses. Rather than teach the inbox about all three, every action here is
// a thin wrapper that runs the real one and then pokes the shared plans bus, which
// this file listens to. One signal, one refetch, no stale rows.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import { notifyPlansChanged, subscribePlans, respondJoin, respondInvite } from "./plans";
import { acceptRequest, declineRequest } from "./friends";
import { approveGuest, declineGuest } from "./parties";

export type InboxKind = "friend_request" | "night_request" | "night_invite" | "room_request";

export interface InboxItem {
  kind: InboxKind;
  /** The row to act on: a friendship id, a join id, else the night/room it concerns. */
  refId: string;
  /** The night or room this is about, when it is about one. */
  subjectId?: string;
  actorId: string;
  actorName: string;
  actorHandle: string;
  /** The night's title, for the kinds that have one. */
  title?: string;
  createdAt: string;
}

export function useInbox(): { items: InboxItem[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const [items, setItems] = useState<InboxItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);

  useEffect(() => subscribePlans(() => setTick((n) => n + 1)), []);

  useEffect(() => {
    if (!supabase || !me) {
      setItems([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("together_inbox");
      if (!active) return;
      setItems(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          kind: r.kind as InboxKind,
          refId: r.ref_id as string,
          subjectId: (r.subject_id as string) ?? undefined,
          actorId: r.actor_id as string,
          actorName: (r.actor_name as string) ?? (r.actor_handle as string),
          actorHandle: r.actor_handle as string,
          title: (r.title as string) ?? undefined,
          createdAt: r.created_at as string,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, tick]);

  return { items, loading };
}

/** Just how many things are waiting — for the tab badge. */
export function useInboxCount(): number {
  return useInbox().items.length;
}

// ── the four decisions ───────────────────────────────────────────────────────
// Yes/no for each kind, wrapped so the inbox refetches afterwards. The underlying
// call is unchanged in every case — the server still re-derives who may do what.

/** Say yes. What that means depends on the kind, which is the whole point of one list. */
export async function acceptItem(item: InboxItem): Promise<string | null> {
  let err: string | null = null;
  switch (item.kind) {
    case "friend_request":
      await acceptRequest(item.refId);
      break;
    case "night_request":
      err = await respondJoin(item.refId, true);
      break;
    case "night_invite":
      err = await respondInvite(item.refId, true);
      break;
    case "room_request":
      if (!item.subjectId) return "Missing the room.";
      await approveGuest(item.subjectId, item.actorId);
      break;
  }
  notifyPlansChanged();
  return err;
}

/** Say no. Declining is always quiet — the other person is never told they were turned down. */
export async function dismissItem(item: InboxItem): Promise<string | null> {
  let err: string | null = null;
  switch (item.kind) {
    case "friend_request":
      await declineRequest(item.refId);
      break;
    case "night_request":
      err = await respondJoin(item.refId, false);
      break;
    case "night_invite":
      err = await respondInvite(item.refId, false);
      break;
    case "room_request":
      if (!item.subjectId) return "Missing the room.";
      await declineGuest(item.subjectId, item.actorId);
      break;
  }
  notifyPlansChanged();
  return err;
}

/** What the two buttons say for each kind — plain words, not one generic pair. */
export const INBOX_VERBS: Record<InboxKind, { yes: string; no: string }> = {
  friend_request: { yes: "Accept", no: "Ignore" },
  night_request: { yes: "Let in", no: "Not this time" },
  night_invite: { yes: "I'm in", no: "Can't" },
  room_request: { yes: "Let in", no: "Not this time" },
};

/** One line saying what this actually is. The kind alone means nothing to a person. */
export function inboxLine(item: InboxItem): string {
  switch (item.kind) {
    case "friend_request":
      return "wants to be friends";
    case "night_request":
      return item.title ? `asked to come to ${item.title}` : "asked to come along";
    case "night_invite":
      return item.title ? `invited you to ${item.title}` : "invited you out";
    case "room_request":
      return item.title ? `is at the door of ${item.title}` : "is at the door";
  }
}
