"use client";

// Plans — pre-plan a night, let people you're connected to ask to join.
//
// Same fetch-on-mount + shared version-bump pattern as parties.ts / venues.ts. The
// reads and the sensitive writes are all SECURITY DEFINER rpcs (upcoming_plans,
// request_join, respond_join…), so this file mostly just calls them and shapes the
// rows — the safety rules (join policy, blocks, "only the host decides") live in the
// database (031_plans.sql), never here.
//
// Two safety facts this file relies on and must not undermine:
//   • join_policy is only ever 'private' | 'invite' | 'friends' | 'fof' — there is
//     still NO stranger option; the DB CHECK refuses anything else, so a bug here
//     can't open a plan to the public. 'private' = only me, 'invite' = named guests.
//   • soft signals are COUNTS, never a rating — see PlanSignals.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

/** Who may see and ask to join. 'private' = only the host; 'invite' = specific people
 *  the host named; then the graph tiers. No public/stranger tier exists — deliberately. */
export type JoinPolicy = "private" | "invite" | "friends" | "fof";
export type PlanStatus = "open" | "closed" | "cancelled";
/** Where a join request stands. null = I haven't asked. */
export type JoinStatus = "requested" | "approved" | "declined" | "withdrawn";

/** A plan as it appears in the discover feed (someone else's, that I can see). */
export interface Plan {
  id: string;
  hostId: string;
  hostName: string;
  hostHandle: string;
  title: string;
  date: string;
  time?: string;
  city?: string;
  venueId?: string;
  note?: string;
  drinks: string[];
  vibeTags: string[];
  joinPolicy: JoinPolicy;
  capacity?: number;
  going: number;
  myStatus: JoinStatus | null;
}

/** A plan I'm hosting. */
export interface MyPlan {
  id: string;
  title: string;
  date: string;
  time?: string;
  city?: string;
  venueId?: string;
  note?: string;
  drinks: string[];
  vibeTags: string[];
  joinPolicy: JoinPolicy;
  capacity?: number;
  status: PlanStatus;
  going: number;
  pending: number;
}

export interface PlanRequest {
  joinId: string;
  userId: string;
  name: string;
  handle: string;
  message?: string;
  status: JoinStatus;
  askedAt: string;
}

/** Soft, factual comfort signals — NEVER a score on a person. */
export interface PlanSignals {
  mutualFriends: number;
  sharedDrinks: number;
  hostVerified: boolean;
  hostVouches: number;
  hostSince?: string;
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

// ── the discover feed: upcoming plans I'm allowed to see ─────────────────────
export function useUpcomingPlans(): { plans: Plan[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setPlans([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("upcoming_plans");
      if (!active) return;
      setPlans(((data as Record<string, unknown>[]) ?? []).map(toPlan));
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { plans, loading };
}

// ── my own plans (as host) ───────────────────────────────────────────────────
export function useMyPlans(): { plans: MyPlan[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [plans, setPlans] = useState<MyPlan[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setPlans([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("my_plans");
      if (!active) return;
      setPlans(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          id: r.id as string,
          title: r.title as string,
          date: r.plan_date as string,
          time: (r.plan_time as string) ?? undefined,
          city: (r.city as string) ?? undefined,
          venueId: (r.venue_id as string) ?? undefined,
          note: (r.note as string) ?? undefined,
          drinks: (r.drinks as string[]) ?? [],
          vibeTags: (r.vibe_tags as string[]) ?? [],
          joinPolicy: r.join_policy as JoinPolicy,
          capacity: (r.capacity as number) ?? undefined,
          status: r.status as PlanStatus,
          going: Number(r.going ?? 1),
          pending: Number(r.pending ?? 0),
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { plans, loading };
}

// ── the requests to one of my plans (host-only; the rpc enforces it) ─────────
export function usePlanRequests(planId: string | null): { requests: PlanRequest[]; loading: boolean } {
  const v = useVersion();
  const [requests, setRequests] = useState<PlanRequest[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !planId) {
      setRequests([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("plan_requests", { pid: planId });
      if (!active) return;
      setRequests(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          joinId: r.join_id as string,
          userId: r.user_id as string,
          name: (r.name as string) ?? (r.handle as string),
          handle: r.handle as string,
          message: (r.message as string) ?? undefined,
          status: r.status as JoinStatus,
          askedAt: r.asked_at as string,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [planId, v]);

  return { requests, loading };
}

// ── soft signals for one plan (comfort cues, never a rating) ─────────────────
export function usePlanSignals(planId: string | null): PlanSignals | null {
  const [signals, setSignals] = useState<PlanSignals | null>(null);
  useEffect(() => {
    if (!supabase || !planId) {
      setSignals(null);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("plan_signals", { pid: planId });
      if (!active) return;
      const r = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | undefined;
      setSignals(
        r
          ? {
              mutualFriends: Number(r.mutual_friends ?? 0),
              sharedDrinks: Number(r.shared_drinks ?? 0),
              hostVerified: Boolean(r.host_verified),
              hostVouches: Number(r.host_vouches ?? 0),
              hostSince: (r.host_since as string) ?? undefined,
            }
          : null,
      );
    })();
    return () => {
      active = false;
    };
  }, [planId]);
  return signals;
}

// ── the calendar overlay: which upcoming days have a plan I'm part of ─────────
export interface PlanDayItem {
  title: string;
  time?: string;
}
/** A plan on a given calendar day (host's own, or one I'm approved to join). */
export interface PlanDay {
  items: PlanDayItem[];
  /** true if I host at least one plan that day (vs. only joining). */
  mine: boolean;
}

/** Map of `YYYY-MM-DD` → the plan(s) I have that day. Powers the home calendar's
 *  plan markers. Only ever the caller's own plans/approved joins (the rpc enforces it). */
export function usePlanDays(): Map<string, PlanDay> {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [map, setMap] = useState<Map<string, PlanDay>>(() => new Map());

  useEffect(() => {
    if (!supabase || !me) {
      setMap(new Map());
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("my_plan_days");
      if (!active) return;
      const m = new Map<string, PlanDay>();
      for (const r of (data as Record<string, unknown>[]) ?? []) {
        const key = r.plan_date as string;
        const cur = m.get(key) ?? { items: [], mine: false };
        cur.items.push({ title: r.title as string, time: (r.plan_time as string) ?? undefined });
        if (r.host) cur.mine = true;
        m.set(key, cur);
      }
      setMap(m);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return map;
}

/** Block/sanction-aware people search — for the invite-by-username field. */
export async function searchUsers(q: string): Promise<{ id: string; handle: string; name: string }[]> {
  if (!supabase) return [];
  const query = q.trim().replace(/^@/, "");
  if (query.length < 2) return [];
  const { data } = await supabase.rpc("search_users", { q: query });
  return ((data as Record<string, unknown>[]) ?? []).map((r) => ({
    id: r.id as string,
    handle: r.handle as string,
    name: (r.display_name as string) ?? (r.handle as string),
  }));
}

/** An invited guest RSVPs directly — going or not — no host approval needed. */
export async function respondInvite(planId: string, going: boolean): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("respond_invite", { pid: planId, going });
  bump();
  if (!error) return null;
  if (/full/i.test(error.message)) return "This plan is full.";
  if (/taking people/i.test(error.message)) return "This plan isn't taking people right now.";
  return "Couldn't update that — try again.";
}

// ── invites (for 'invite' plans — the named-guest tier) ──────────────────────
export interface PlanInvitee {
  userId: string;
  name: string;
  handle: string;
}

/** The guest list for one of MY plans (host-only; the rpc enforces it). */
export function usePlanInvitees(planId: string | null): { invitees: PlanInvitee[]; loading: boolean } {
  const v = useVersion();
  const [invitees, setInvitees] = useState<PlanInvitee[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !planId) {
      setInvitees([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("plan_invitees", { pid: planId });
      if (!active) return;
      setInvitees(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          userId: r.user_id as string,
          name: (r.display_name as string) ?? (r.handle as string),
          handle: r.handle as string,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [planId, v]);

  return { invitees, loading };
}

/** Invite a specific person to an 'invite' plan. Host-only + block-aware server-side. */
export async function inviteToPlan(planId: string, userId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("invite_to_plan", { pid: planId, target: userId });
  bump();
  if (!error) return null;
  if (/can't invite|blocked/i.test(error.message)) return "You can't invite this person.";
  return "Couldn't send that invite — try again.";
}

/** Withdraw an invite (also pulls any join they started off it). */
export async function uninviteFromPlan(planId: string, userId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("uninvite_from_plan", { pid: planId, target: userId });
  bump();
  return error ? "Couldn't update the guest list — try again." : null;
}

function toPlan(r: Record<string, unknown>): Plan {
  return {
    id: r.id as string,
    hostId: r.host_id as string,
    hostName: (r.host_name as string) ?? (r.host_handle as string),
    hostHandle: r.host_handle as string,
    title: r.title as string,
    date: r.plan_date as string,
    time: (r.plan_time as string) ?? undefined,
    city: (r.city as string) ?? undefined,
    venueId: (r.venue_id as string) ?? undefined,
    note: (r.note as string) ?? undefined,
    drinks: (r.drinks as string[]) ?? [],
    vibeTags: (r.vibe_tags as string[]) ?? [],
    joinPolicy: r.join_policy as JoinPolicy,
    capacity: (r.capacity as number) ?? undefined,
    going: Number(r.going ?? 1),
    myStatus: (r.my_status as JoinStatus) ?? null,
  };
}

// ── mutations ────────────────────────────────────────────────────────────────

export interface NewPlan {
  title: string;
  date: string; // YYYY-MM-DD, today or later
  time?: string; // HH:MM, optional start time
  city?: string;
  venueId?: string;
  note?: string;
  drinks?: string[];
  vibeTags?: string[];
  joinPolicy?: JoinPolicy;
  capacity?: number;
}

/** Create a plan I host. Insert WITHOUT .select() — plans_read runs a definer fn, so
 *  PostgREST RETURNING trips (same gotcha as parties/venues); the id is client-made. */
export async function createPlan(meId: string, p: NewPlan): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const title = p.title.trim();
  if (!title) return { error: "Give your night a title." };
  if (!p.date) return { error: "Pick a date." };
  if (p.date < todayKey()) return { error: "A plan can't be in the past." };

  const id = crypto.randomUUID();
  const { error } = await supabase.from("plans").insert({
    id,
    host_id: meId,
    title,
    plan_date: p.date,
    plan_time: p.time || null,
    city: p.city?.trim() || null,
    venue_id: p.venueId || null,
    note: p.note?.trim() || null,
    drinks: dedupeTags(p.drinks),
    vibe_tags: dedupeTags(p.vibeTags),
    join_policy: p.joinPolicy ?? "friends",
    capacity: p.capacity && p.capacity > 0 ? p.capacity : null,
  });
  bump();
  if (error) return { error: error.message };
  return { id };
}

export async function updatePlan(
  planId: string,
  fields: Partial<Pick<NewPlan, "title" | "city" | "note" | "drinks" | "vibeTags" | "joinPolicy" | "capacity">>,
): Promise<string | null> {
  if (!supabase) return "offline";
  const patch: Record<string, unknown> = {};
  if (fields.title !== undefined) {
    const t = fields.title.trim();
    if (!t) return "Title can't be empty.";
    patch.title = t;
  }
  if (fields.city !== undefined) patch.city = fields.city.trim() || null;
  if (fields.note !== undefined) patch.note = fields.note.trim() || null;
  if (fields.drinks !== undefined) patch.drinks = dedupeTags(fields.drinks);
  if (fields.vibeTags !== undefined) patch.vibe_tags = dedupeTags(fields.vibeTags);
  if (fields.joinPolicy !== undefined) patch.join_policy = fields.joinPolicy;
  if (fields.capacity !== undefined) patch.capacity = fields.capacity && fields.capacity > 0 ? fields.capacity : null;
  const { error } = await supabase.from("plans").update(patch).eq("id", planId);
  bump();
  return error ? error.message : null;
}

/** Close (stop taking people) or cancel (call it off) or reopen. */
export async function setPlanStatus(planId: string, status: PlanStatus): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("plans").update({ status }).eq("id", planId);
  bump();
  return error ? error.message : null;
}

export async function deletePlan(planId: string) {
  if (!supabase) return;
  await supabase.from("plans").delete().eq("id", planId);
  bump();
}

/** Ask to join. The server re-checks the join policy AND blocks — this can't sneak
 *  someone into a plan they aren't allowed to see. */
export async function requestJoin(planId: string, message?: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("request_join", { pid: planId, msg: message?.trim() || null });
  bump();
  if (!error) return null;
  if (/full/i.test(error.message)) return "This plan is full.";
  if (/taking people/i.test(error.message)) return "This plan isn't taking people right now.";
  if (/can't join|allowed/i.test(error.message)) return "You can't join this plan.";
  return "Couldn't send that — try again.";
}

/** Host approves or declines a request. */
export async function respondJoin(joinId: string, approve: boolean): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("respond_join", { jid: joinId, approve });
  bump();
  if (!error) return null;
  if (/full/i.test(error.message)) return "The plan is full.";
  return "Couldn't record that — try again.";
}

/** Joiner backs out. */
export async function withdrawJoin(planId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("withdraw_join", { pid: planId });
  bump();
  return error ? "Couldn't update that — try again." : null;
}

// ── small helpers ────────────────────────────────────────────────────────────
function todayKey(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** Tidy a tag list: trimmed, lowercased, de-duped, capped in count and length. */
export function dedupeTags(tags?: string[]): string[] {
  if (!tags) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of tags) {
    const t = raw.trim().toLowerCase().slice(0, 24);
    if (t && !seen.has(t)) {
      seen.add(t);
      out.push(t);
      if (out.length >= 8) break; // a handful is plenty; a wall of tags is noise
    }
  }
  return out;
}
