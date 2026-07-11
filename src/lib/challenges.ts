"use client";

// Challenges — opt-in competitions INSIDE circles only (the locked rule: the
// Calendar never shows a score; this is Together's loud corner). Everything on
// the board is DERIVED from counts returned by the challenge_board() rpc —
// distinct dates, totals, distinct-drink counts. No entry content ever.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";

// The three auto-scored kinds + 'freeform' = a manually-judged competition.
export type ChallengeKind = "most_logged" | "most_kinds" | "longest_streak" | "freeform";

/** The auto-scored kinds offered when creating a plain challenge. */
export const SCORED_KINDS: ChallengeKind[] = ["most_logged", "most_kinds", "longest_streak"];

export const KIND_LABEL: Record<ChallengeKind, string> = {
  most_logged: "Most logged",
  most_kinds: "Most kinds",
  longest_streak: "Longest run",
  freeform: "Competition",
};
export const KIND_UNIT: Record<ChallengeKind, string> = {
  most_logged: "logged",
  most_kinds: "kinds",
  longest_streak: "nights running",
  freeform: "",
};

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
      const { data } = await supabase!.rpc("challenge_board", { cid: id });
      if (!active) return;
      const rows: BoardRow[] = ((data as Record<string, unknown>[]) ?? []).map((r) => {
        const dates = (r.dates as string[]) ?? [];
        const value =
          kind === "most_logged"
            ? (r.total as number)
            : kind === "most_kinds"
              ? (r.kinds as number)
              : kind === "longest_streak"
                ? longestRun(dates)
                : 0; // freeform — not auto-scored; ordered by name instead
        return { userId: r.user_id as string, name: r.display_name as string, value };
      });
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
