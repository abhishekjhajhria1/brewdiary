"use client";

// Cups — user-made exploration competitions (Phase C-2). Supabase-backed, same
// fetch-on-mount + version-bump pattern as circles.ts / parties.ts.
//
// A cup is created, named, skinned and scored on ONE axis the maker picks. The
// leaderboard is NEVER stored — cup_board() (SECURITY DEFINER, counts-only)
// derives each member's score from their own entries in the window (044).
//
// THE AXIS PALETTE IS THE BOUNDARY. There is deliberately no "volume" or "spend"
// axis anywhere — only breadth/behaviour. A user gets total freedom over the
// name and the look, but "who drank most" is not an option they can pick,
// because it does not exist. That is CLAUDE.md rule #6, enforced in the DB CHECK
// (see 044) and mirrored here so the UI can only ever offer honest axes.
//
// Insert gotcha (as circles/expenses): cups_read calls a definer fn, so INSERT..
// RETURNING trips PostgREST — ids are client-generated, inserts carry no
// .select(), and the invite_code is read back separately.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

// The ONLY axes a cup can score on. Breadth & behaviour — never volume or spend.
// Kept in sync with the CHECK on cups.axis in 044 (a test asserts this list holds
// no volume/spend axis, so the boundary can't rot as the palette grows).
export const CUP_AXES = [
  { id: "drinks", label: "New drinks", blurb: "Most different drinks — variety, never how many." },
  { id: "venues", label: "New places", blurb: "Most different places you drank at." },
  { id: "varied", label: "Most varied", blurb: "Most different kinds — coffee through cocktails." },
  { id: "dry", label: "Easy nights", blurb: "Most dry days. A cup you win by pacing yourself." },
] as const;
export type CupAxis = (typeof CUP_AXES)[number]["id"];

// Cosmetic looks a maker can pick — "your cup, your colours". Constrained (the DB
// mirrors this set) so a skin is a theme name, never arbitrary markup.
export const CUP_SKINS = ["classic", "amber", "forest", "dusk", "rose", "mono"] as const;
export type CupSkin = (typeof CUP_SKINS)[number];

export type JoinPolicy = "friends" | "fof" | "invite";

export type CupSide = "a" | "b";

export interface Cup {
  id: string;
  name: string;
  skin: CupSkin;
  axis: CupAxis;
  joinPolicy: JoinPolicy;
  inviteCode: string;
  startsOn: string;
  endsOn: string;
  createdBy: string;
  /** Team battle (047): two named sides; members pick one; the board also sums per side. */
  teamMode: boolean;
  teamA: string | null;
  teamB: string | null;
}

/** One line of the board. Counts only — no entry content ever crosses this seam. */
export interface CupStanding {
  userId: string;
  name: string;
  handle: string;
  score: number;
}

// ── pure helpers (also unit-tested) ──────────────────────────────────────────
export function isValidCupName(name: string): boolean {
  const n = name.trim();
  return n.length >= 1 && n.length <= 40;
}

/** Day-keys sort lexicographically, so a string compare is the date compare. */
export function isValidWindow(startsOn: string, endsOn: string): boolean {
  return !!startsOn && !!endsOn && endsOn >= startsOn;
}

export function axisLabel(axis: CupAxis): string {
  return CUP_AXES.find((a) => a.id === axis)?.label ?? axis;
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

function rowToCup(r: Record<string, unknown>): Cup {
  return {
    id: r.id as string,
    name: r.name as string,
    skin: (r.skin as CupSkin) ?? "classic",
    axis: r.axis as CupAxis,
    joinPolicy: (r.join_policy as JoinPolicy) ?? "invite",
    inviteCode: r.invite_code as string,
    startsOn: r.starts_on as string,
    endsOn: r.ends_on as string,
    createdBy: r.created_by as string,
    teamMode: (r.team_mode as boolean) ?? false,
    teamA: (r.team_a as string) ?? null,
    teamB: (r.team_b as string) ?? null,
  };
}

// ── the cups I'm in ──────────────────────────────────────────────────────────
export function useMyCups(): { cups: Cup[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [cups, setCups] = useState<Cup[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setCups([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("cup_members")
        // All columns, so the read keeps working across additive migrations (047 added
        // the team fields; naming them here would 400 until the migration lands).
        .select("cup:cups(*)")
        .eq("user_id", me);
      if (!active) return;
      setCups(
        (data ?? [])
          .map((r: Record<string, unknown>) => r.cup as Record<string, unknown> | null)
          .filter((c): c is Record<string, unknown> => !!c)
          .map(rowToCup)
          .sort((a, b) => b.endsOn.localeCompare(a.endsOn)),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { cups, loading };
}

// ── one cup's leaderboard (derived server-side, counts only) ─────────────────
export function useCupBoard(cupId: string | null): { standings: CupStanding[]; loading: boolean } {
  const v = useVersion();
  const [standings, setStandings] = useState<CupStanding[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !cupId) {
      setStandings([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("cup_board", { cup: cupId });
      if (!active) return;
      const rows = (data ?? []) as Record<string, unknown>[];
      setStandings(
        rows
          .map((r): CupStanding => ({
            userId: r.user_id as string,
            name: (r.display_name as string) || (r.handle as string) || "player",
            handle: (r.handle as string) ?? "",
            score: (r.score as number) ?? 0,
          }))
          // Leader first; ties broken by name so the order is stable, not a coin flip.
          .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name)),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [cupId, v]);

  return { standings, loading };
}

// ── the team board (047) ─────────────────────────────────────────────────────
/** One side's total: how many stand on it, and the SUM of their solo breadth scores.
 *  Derived server-side (cup_team_board wraps cup_board, so the anti-volume palette
 *  and the members-only gate are inherited, never re-implemented). */
export interface TeamStanding {
  team: CupSide;
  players: number;
  score: number;
}

export function useCupTeams(cup: Cup | null): {
  teams: TeamStanding[];
  mySide: CupSide | null;
  loading: boolean;
} {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [state, setState] = useState<{ teams: TeamStanding[]; mySide: CupSide | null; loading: boolean }>({
    teams: [],
    mySide: null,
    loading: true,
  });

  useEffect(() => {
    if (!supabase || !cup || !cup.teamMode || !me) {
      setState({ teams: [], mySide: null, loading: false });
      return;
    }
    let active = true;
    setState((s) => ({ ...s, loading: true }));
    (async () => {
      const [{ data: board }, { data: mine }] = await Promise.all([
        supabase!.rpc("cup_team_board", { cup: cup.id }),
        supabase!.from("cup_members").select("team").eq("cup_id", cup.id).eq("user_id", me).maybeSingle(),
      ]);
      if (!active) return;
      const rows = (board ?? []) as Record<string, unknown>[];
      setState({
        teams: rows.map((r) => ({
          team: r.team as CupSide,
          players: (r.players as number) ?? 0,
          score: (r.score as number) ?? 0,
        })),
        mySide: ((mine as { team?: CupSide | null } | null)?.team as CupSide) ?? null,
        loading: false,
      });
    })();
    return () => {
      active = false;
    };
  }, [cup, me, v]);

  return state;
}

/** Pick (or switch) my side in a team cup. Server re-checks everything (pick_team). */
export async function pickTeam(cupId: string, side: CupSide): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("pick_team", { cup: cupId, side });
  bump();
  return error ? error.message : null;
}

// ── mutations ────────────────────────────────────────────────────────────────
export interface NewCup {
  name: string;
  axis: CupAxis;
  skin?: CupSkin;
  joinPolicy?: JoinPolicy;
  startsOn: string;
  endsOn: string;
  /** Team battle: give both sides a name to switch it on. */
  teamA?: string;
  teamB?: string;
}

export async function createCup(meId: string, input: NewCup): Promise<{ id: string; inviteCode: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  if (!isValidCupName(input.name)) return { error: "Give the cup a name (up to 40 characters)." };
  if (!isValidWindow(input.startsOn, input.endsOn)) return { error: "The end date can't be before the start." };

  const id = crypto.randomUUID();
  const teamMode = !!(input.teamA?.trim() && input.teamB?.trim());
  // No .select(): cups_read calls a definer fn (PostgREST RETURNING gotcha). The
  // owner is added to cup_members by a DB trigger, not from here.
  const { error } = await supabase.from("cups").insert({
    id,
    created_by: meId,
    name: input.name.trim(),
    skin: input.skin ?? "classic",
    axis: input.axis,
    join_policy: input.joinPolicy ?? "invite",
    starts_on: input.startsOn,
    ends_on: input.endsOn,
    team_mode: teamMode,
    team_a: teamMode ? input.teamA!.trim().slice(0, 24) : null,
    team_b: teamMode ? input.teamB!.trim().slice(0, 24) : null,
  });
  if (error) return { error: error.message };

  const { data } = await supabase.from("cups").select("invite_code").eq("id", id).maybeSingle();
  bump();
  return { id, inviteCode: (data as { invite_code?: string } | null)?.invite_code ?? "" };
}

export async function joinCup(code: string): Promise<{ id: string } | { error: string }> {
  if (!supabase) return { error: "offline" };
  const { data, error } = await supabase.rpc("join_cup", { code: code.trim().toLowerCase() });
  bump();
  if (error) {
    const m = error.message;
    return {
      error: m.includes("no such cup")
        ? "No cup with that code."
        : m.includes("ended")
          ? "That cup has already ended."
          : m.includes("eligible")
            ? "This cup is only open to the host's friends."
            : m.includes("unavailable")
              ? "This cup isn't available to you."
              : m,
    };
  }
  return { id: typeof data === "string" ? data : "" };
}

export async function leaveCup(cupId: string, meId: string) {
  if (!supabase) return;
  await supabase.from("cup_members").delete().eq("cup_id", cupId).eq("user_id", meId);
  bump();
}

export async function deleteCup(cupId: string) {
  if (!supabase) return;
  await supabase.from("cups").delete().eq("id", cupId);
  bump();
}
