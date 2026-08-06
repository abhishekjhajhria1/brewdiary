"use client";

// Nights — ONE object for "a night out".
//
// ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
// `plans.ts` and `parties.ts` modelled the same thing twice: a date, a place,
// people, who may come, who's approved. The user had to choose between two
// near-identical forms BEFORE they knew what they wanted, and nothing converted
// one into the other — a plan that actually happened had no room to log into,
// and a party had no private/invite tier.
//
// So the app now has one noun. A NIGHT is a `plans` row (the spine: the richer
// fields plus the audited approval/block/sanction machinery). Its ROOM is a
// `parties` row, created LAZILY by `open_night_room` (migration 053) the first
// time the night needs one — a shareable link for people off the app, or the
// live log on the night itself. Most nights never allocate one.
//
// The lifecycle is TIME, never a mode the user picks:
//   upcoming → the invitation    tonight → the live room    past → the recap
// That's the same "the content is the state" rule PartyRoom already follows,
// extended backwards over the invitation.
//
// ── REFRESH ─────────────────────────────────────────────────────────────────
// This file has NO version bus of its own — it borrows `plans.ts`'s, because it
// reads the same rows through different rpcs. A write here calls
// notifyPlansChanged() so both sides refetch.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import { notifyPlansChanged, subscribePlans, plansVersion, type JoinPolicy, type PlanStatus } from "./plans";
import { todayKey } from "./date";

/** Who can see a night and ask in. Private → open, and it STOPS at friends-of-friends:
 *  there is deliberately no stranger tier (the DB CHECK refuses one). "Anyone with the
 *  link" is not a fifth value — it's a room's invite code, a link you hand out yourself. */
export type Audience = JoinPolicy;

/** Where a night is in its own life. Derived from the date, never stored. */
export type NightPhase = "upcoming" | "tonight" | "past";

export interface Night {
  /** The plan id — the canonical id of a night, room or no room. */
  id: string;
  hostId: string;
  hostName: string;
  title: string;
  /** YYYY-MM-DD */
  date: string;
  /** HH:MM(:SS) from postgres `time`, when the host set one. */
  time?: string;
  city?: string;
  venueId?: string;
  audience: Audience;
  status: PlanStatus;
  /** Approved heads, host included. Never a volume or spend figure. */
  going: number;
  /** Waiting on the host. Always 0 for a night I merely attend. */
  pending: number;
  /** Set once the night has a room. Undefined = no room yet. */
  partyId?: string;
  /** Do I host this one (→ approve, invite, share, call off). */
  host: boolean;
}

export const AUDIENCES: { id: Audience; label: string; hint: string }[] = [
  { id: "private", label: "Only me", hint: "A private note on your calendar. Nobody else sees it." },
  { id: "invite", label: "People I pick", hint: "Only the friends you name — they answer you directly, no queue." },
  { id: "friends", label: "My friends", hint: "Any friend can see it and ask to come." },
  { id: "fof", label: "Friends of friends", hint: "Friends, and their friends, can ask to come." },
];

export const AUDIENCE_LABEL: Record<Audience, string> = {
  private: "just you",
  invite: "people you pick",
  friends: "friends",
  fof: "friends of friends",
};

/** Upcoming / tonight / past, from the date alone. */
export function nightPhase(date: string, today: string = todayKey()): NightPhase {
  if (date === today) return "tonight";
  return date > today ? "upcoming" : "past";
}

/** "9:30 pm" from a postgres time, or undefined. Display-only. */
export function prettyTime(t?: string): string | undefined {
  if (!t) return undefined;
  const [hRaw, m] = t.split(":");
  const h = Number(hRaw);
  if (Number.isNaN(h)) return undefined;
  const suffix = h < 12 ? "am" : "pm";
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}${m && m !== "00" ? `:${m}` : ""} ${suffix}`;
}

function toNight(r: Record<string, unknown>): Night {
  return {
    id: r.id as string,
    hostId: r.host_id as string,
    hostName: (r.host_name as string) ?? "someone",
    title: r.title as string,
    date: r.plan_date as string,
    time: (r.plan_time as string) ?? undefined,
    city: (r.city as string) ?? undefined,
    venueId: (r.venue_id as string) ?? undefined,
    audience: r.join_policy as Audience,
    status: r.status as PlanStatus,
    going: Number(r.going ?? 1),
    pending: Number(r.pending ?? 0),
    partyId: (r.party_id as string) ?? undefined,
    host: Boolean(r.host),
  };
}

// ── the shared refresh signal (plans's bus — see the header) ─────────────────
function useVersion(): number {
  const [, set] = useState(0);
  useEffect(() => subscribePlans(() => set((n) => n + 1)), []);
  return plansVersion();
}

// ── every night that's mine: hosted or joined, past included ─────────────────
// `my_plans` was hosted-only and `my_plan_days` upcoming-only, so neither could
// back a list that shows a friend's night last Friday beside yours on Saturday.
export function useMyNights(): { nights: Night[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [nights, setNights] = useState<Night[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setNights([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("my_nights");
      if (!active) return;
      setNights(((data as Record<string, unknown>[]) ?? []).map(toNight));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { nights, loading };
}

/** One night by id, from the same list — so the page and the list can never disagree. */
export function useNight(id: string | null): { night: Night | null; loading: boolean } {
  const { nights, loading } = useMyNights();
  return { night: id ? (nights.find((n) => n.id === id) ?? null) : null, loading };
}

/** Split a list into the three phases, each already in the order it wants to be read:
 *  tonight first, then what's coming (soonest first), then recaps (newest first). */
export function groupNights(nights: Night[], today: string = todayKey()) {
  const tonight: Night[] = [];
  const upcoming: Night[] = [];
  const past: Night[] = [];
  for (const n of nights) {
    if (n.status === "cancelled") continue;
    const phase = nightPhase(n.date, today);
    (phase === "tonight" ? tonight : phase === "upcoming" ? upcoming : past).push(n);
  }
  upcoming.sort((a, b) => a.date.localeCompare(b.date));
  past.sort((a, b) => b.date.localeCompare(a.date));
  return { tonight, upcoming, past };
}

// ── the room ─────────────────────────────────────────────────────────────────

/** Give a night its room (idempotent, host-only — the rpc re-checks, not this file).
 *  Everyone already approved on the night walks straight in; they were vetted once. */
export async function openNightRoom(planId: string): Promise<{ partyId: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const { data, error } = await supabase.rpc("open_night_room", { pid: planId });
  notifyPlansChanged();
  if (error) {
    if (/only the host/i.test(error.message)) return { error: "Only the host can open the room." };
    if (/called off/i.test(error.message)) return { error: "This night was called off." };
    return { error: "Couldn't open the room — try again." };
  }
  return { partyId: data as string };
}

/** One-shot read of a room's invite code — for the moment right after creating a
 *  night, where there's no hook mounted yet to watch for it. */
export async function fetchNightCode(partyId: string): Promise<string | null> {
  if (!supabase) return null;
  const { data } = await supabase.from("parties").select("invite_code").eq("id", partyId).maybeSingle();
  return (data?.invite_code as string) ?? null;
}

/** The room's invite code — the thing behind the shareable /p/<code> link.
 *  Readable by the host and by members (parties_read), nobody else. */
export function useNightCode(partyId?: string): string | null {
  const v = useVersion();
  const [code, setCode] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase || !partyId) {
      setCode(null);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("parties").select("invite_code").eq("id", partyId).maybeSingle();
      if (active) setCode((data?.invite_code as string) ?? null);
    })();
    return () => {
      active = false;
    };
  }, [partyId, v]);

  return code;
}

/** The link you actually paste into a chat. Works for people with no account —
 *  /p/<code> renders an anon-callable preview (party_preview). */
export function nightShareUrl(code: string): string {
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  return `${origin}/p/${code}`;
}
