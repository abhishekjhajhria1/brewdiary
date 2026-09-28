"use client";

// Challenges — opt-in competitions INSIDE circles only (the locked rule: the
// Calendar never shows a score; this is Together's loud corner). Everything on
// the board is DERIVED from counts returned by the challenge_board() rpc —
// distinct dates, totals, distinct-drink counts. No entry content ever.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";

// Auto-scored kinds + 'freeform' = a manually-judged competition. The 043 kinds
// (days_kept … hydration) are for variety or consistency — none can be won by
// drinking more — and read challenge_board_v2().
export type ChallengeKind =
  | "most_logged"
  | "most_kinds"
  | "longest_streak"
  | "freeform"
  | "days_kept"
  | "dry_nights"
  | "new_drinks"
  | "new_places"
  | "hydration";

/** Kinds scored by challenge_board_v2() (migration 043). */
export const V2_KINDS: ChallengeKind[] = ["days_kept", "dry_nights", "new_drinks", "new_places", "hydration"];

/** The auto-scored kinds offered when creating a plain challenge, gentlest first.
 *  "Most logged" is last: it counts every entry, so it's the one a round can win. */
export const SCORED_KINDS: ChallengeKind[] = [
  "days_kept",
  "new_drinks",
  "new_places",
  "dry_nights",
  "hydration",
  "most_kinds",
  "longest_streak",
  "most_logged",
];

export const KIND_LABEL: Record<ChallengeKind, string> = {
  most_logged: "Most logged",
  most_kinds: "Most kinds",
  longest_streak: "Longest run",
  freeform: "Competition",
  days_kept: "Nights kept",
  dry_nights: "Dry nights",
  new_drinks: "New drinks",
  new_places: "New places",
  hydration: "Water nights",
};
export const KIND_UNIT: Record<ChallengeKind, string> = {
  most_logged: "logged",
  most_kinds: "kinds",
  longest_streak: "nights running",
  freeform: "",
  days_kept: "nights kept",
  dry_nights: "dry nights",
  new_drinks: "new drinks",
  new_places: "new places",
  hydration: "water nights",
};

/** One-tap starting points for a circle challenge. */
export interface ChallengePreset {
  kind: ChallengeKind;
  title: string;
  days: number;
  blurb: string;
}
export const CHALLENGE_PRESETS: ChallengePreset[] = [
  { kind: "dry_nights", title: "Dry week", days: 7, blurb: "Most dry nights in seven days." },
  { kind: "new_drinks", title: "Five new pours", days: 14, blurb: "Drinks none of you have logged before." },
  { kind: "new_places", title: "New places month", days: 30, blurb: "Somewhere you've never logged." },
  { kind: "hydration", title: "Water every night", days: 7, blurb: "A water logged each night." },
  { kind: "days_kept", title: "Keep the diary", days: 30, blurb: "Write every night — dry ones count." },
  { kind: "freeform", title: "Best homebrew", days: 14, blurb: "A rule you write, a winner you pick." },
];

/** The value a board row scores for a kind (v2 rows carry their own counts). */
export function scoreRow(kind: ChallengeKind, r: Record<string, unknown>): number {
  switch (kind) {
    case "most_logged":
      return Number(r.total ?? 0);
    case "most_kinds":
      return Number(r.kinds ?? 0);
    case "longest_streak":
      return longestRun((r.dates as string[]) ?? []);
    case "days_kept":
      return Number(r.days_kept ?? 0);
    case "dry_nights":
      return Number(r.dry_nights ?? 0);
    case "new_drinks":
      return Number(r.new_drinks ?? 0);
    case "new_places":
      return Number(r.new_places ?? 0);
    case "hydration":
      return Number(r.water_days ?? 0);
    default:
      return 0; // freeform — not auto-scored; ordered by name instead
  }
}

export function isFreeform(kind: ChallengeKind): boolean {
  return kind === "freeform";
}

export interface Challenge {
  id: string;
  circleId: string;
  createdBy: string;
  kind: ChallengeKind;
  /** Optional custom name (falls back to KIND_LABEL when absent). */
  title?: string;
  /** Free-form only: the written rule the creator sets. */
  rule?: string;
  /** Free-form only: the participant the creator declared the winner. */
  winnerId?: string;
  startsOn: string;
  endsOn: string;
  participantIds: string[];
}
export interface BoardRow {
  userId: string;
  name: string;
  value: number;
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

/** Longest consecutive-day run in a set of ISO dates. */
export function longestRun(dates: string[]): number {
  if (dates.length === 0) return 0;
  const days = [...new Set(dates)].sort();
  let best = 1;
  let run = 1;
  for (let i = 1; i < days.length; i++) {
    const prev = new Date(`${days[i - 1]}T00:00:00Z`).getTime();
    const cur = new Date(`${days[i]}T00:00:00Z`).getTime();
    if (cur - prev === 86_400_000) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  return best;
}

// ── a circle's challenges ────────────────────────────────────────────────────
export function useChallenges(circleId: string | null): { challenges: Challenge[]; loading: boolean } {
  const v = useVersion();
  const [challenges, setChallenges] = useState<Challenge[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !circleId) {
      setChallenges([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("challenges")
        .select("id, circle_id, created_by, kind, title, rule, winner_id, starts_on, ends_on, challenge_members(user_id)")
        .eq("circle_id", circleId)
        .order("created_at", { ascending: false });
      if (!active) return;
      setChallenges(
        (data ?? []).map((r: Record<string, unknown>) => ({
          id: r.id as string,
          circleId: r.circle_id as string,
          createdBy: r.created_by as string,
          kind: r.kind as ChallengeKind,
          title: (r.title as string) ?? undefined,
          rule: (r.rule as string) ?? undefined,
          winnerId: (r.winner_id as string) ?? undefined,
          startsOn: r.starts_on as string,
          endsOn: r.ends_on as string,
          participantIds: ((r.challenge_members as { user_id: string }[]) ?? []).map((m) => m.user_id),
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [circleId, v]);

  return { challenges, loading };
}

// ── the leaderboard (count-only rpc), scored client-side per kind ────────────
export function useChallengeBoard(challenge: Challenge | null): { board: BoardRow[]; loading: boolean } {
  const v = useVersion();
  const [board, setBoard] = useState<BoardRow[]>([]);
  const [loading, setLoading] = useState(true);
  const id = challenge?.id ?? null;
  const kind = challenge?.kind;

  useEffect(() => {
    if (!supabase || !id || !kind) {
      setBoard([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const fn = V2_KINDS.includes(kind) ? "challenge_board_v2" : "challenge_board";
      const { data } = await supabase!.rpc(fn, { cid: id });
      if (!active) return;
      const rows: BoardRow[] = ((data as Record<string, unknown>[]) ?? []).map((r) => ({
        userId: r.user_id as string,
        name: r.display_name as string,
        value: scoreRow(kind, r),
      }));
      rows.sort((a, b) => b.value - a.value || a.name.localeCompare(b.name));
      setBoard(rows);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [id, kind, v]);

  return { board, loading };
}

// ── mutations ────────────────────────────────────────────────────────────────
export async function createChallenge(
  meId: string,
  circleId: string,
  opts: { kind: ChallengeKind; startsOn: string; endsOn: string; title?: string; rule?: string },
): Promise<string | null> {
  if (!supabase) return "offline";
  const id = crypto.randomUUID();
  // no .select(): challenges_read calls a definer fn (PostgREST RETURNING gotcha)
  const { error } = await supabase.from("challenges").insert({
    id,
    circle_id: circleId,
    created_by: meId,
    kind: opts.kind,
    starts_on: opts.startsOn,
    ends_on: opts.endsOn,
    title: opts.title?.trim() || null,
    rule: opts.rule?.trim() || null,
  });
  if (error) return error.message;
  // starting one is opting in
  const { error: mErr } = await supabase.from("challenge_members").insert({ challenge_id: id, user_id: meId });
  bump();
  return mErr ? mErr.message : null;
}

/** Free-form competition: the creator declares (or clears, with null) the winner. */
export async function setChallengeWinner(challengeId: string, winnerId: string | null) {
  if (!supabase) return;
  await supabase.rpc("set_challenge_winner", { cid: challengeId, winner: winnerId });
  bump();
}

export async function joinChallenge(challengeId: string, meId: string) {
  if (!supabase) return;
  await supabase.from("challenge_members").insert({ challenge_id: challengeId, user_id: meId });
  bump();
}

export async function leaveChallenge(challengeId: string, meId: string) {
  if (!supabase) return;
  await supabase.from("challenge_members").delete().eq("challenge_id", challengeId).eq("user_id", meId);
  bump();
}

export async function deleteChallenge(challengeId: string) {
  if (!supabase) return;
  await supabase.from("challenges").delete().eq("id", challengeId);
  bump();
}
