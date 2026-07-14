"use client";

// Points — Phase 1 of Rooms/Points/Venues (Together's loud, opt-in corner; the
// Calendar never shows a score). Two POSITIVE-ONLY currencies earned inside a
// PARTY (the existing "room"): spark (public fun/variety/games) and vibe
// (positive recognition your group gives you). The board is DERIVED — the
// party_points_board() rpc SUMS an append-only ledger and returns counts only,
// members-only. No balance is ever stored (same discipline as challenge_board).
//
// Same fetch-on-mount + version-bump pattern as challenges.ts/parties.ts, and it
// degrades to an empty board with no supabase/auth (no fake offline multiplayer).
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import { DEFAULT_CURRENCY } from "./money";

export type Currency = "spark" | "vibe";

export interface PointRow {
  userId: string;
  name: string;
  sparks: number;
  vibe: number;
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

// A DB unique-index violation just means "already earned/awarded" — a harmless
// no-op we swallow rather than surface as an error.
function isDuplicate(message: string): boolean {
  return /duplicate|unique|23505/i.test(message);
}

// ── the party's board (sparks + vibe per member) ─────────────────────────────
export function usePointsBoard(partyId: string | null): { board: PointRow[]; loading: boolean } {
  const v = useVersion();
  const [board, setBoard] = useState<PointRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !partyId) {
      setBoard([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("party_points_board", { pid: partyId });
      if (!active) return;
      const rows: PointRow[] = ((data as Record<string, unknown>[]) ?? []).map((r) => ({
        userId: r.user_id as string,
        name: r.display_name as string,
        sparks: (r.sparks as number) ?? 0,
        vibe: (r.vibe as number) ?? 0,
      }));
      rows.sort((a, b) => b.sparks - a.sparks || b.vibe - a.vibe || a.name.localeCompare(b.name));
      setBoard(rows);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [partyId, v]);

  return { board, loading };
}

// ── mutations ────────────────────────────────────────────────────────────────

/** Check in. SERVER-AUTHORITATIVE (see 016_staff_awards.sql): the client can no
 *  longer insert sparks at all — award_checkin decides the reason, so nobody can
 *  mint sparks with invented ones. Returns true when this was a NEW check-in. */
export async function awardCheckin(partyId: string): Promise<boolean> {
  if (!supabase) return false;
  const { data, error } = await supabase.rpc("award_checkin", { pid: partyId });
  bump();
  return error ? false : Boolean(data);
}

/** Have I already checked into this room? (Read straight off the ledger, so it
 *  survives a reload and isn't confused by sparks earned from the quiz.) */
export function useHasCheckedIn(partyId: string | null, meId?: string): boolean {
  const v = useVersion();
  const [yes, setYes] = useState(false);

  useEffect(() => {
    if (!supabase || !partyId || !meId) {
      setYes(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("point_events")
        .select("id")
        .eq("party_id", partyId)
        .eq("subject_user_id", meId)
        .eq("currency", "spark")
        .eq("reason", "checkin")
        .limit(1);
      if (active) setYes((data ?? []).length > 0);
    })();
    return () => {
      active = false;
    };
  }, [partyId, meId, v]);

  return yes;
}

/** Give another guest a positive vibe. Positive-only + one-per-reason are
 *  enforced in the DB; a repeat is a harmless no-op. */
export async function awardVibe(partyId: string, meId: string, subjectId: string, reason: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("point_events").insert({
    party_id: partyId,
    subject_user_id: subjectId,
    awarder_id: meId,
    currency: "vibe",
    reason,
    value: 1,
  });
  bump();
  if (error && isDuplicate(error.message)) return null;
  return error ? error.message : null;
}

/** Take back a vibe you gave (matches the exact award). */
export async function undoVibe(partyId: string, meId: string, subjectId: string, reason: string) {
  if (!supabase) return;
  await supabase
    .from("point_events")
    .delete()
    .eq("party_id", partyId)
    .eq("awarder_id", meId)
    .eq("subject_user_id", subjectId)
    .eq("reason", reason)
    .eq("currency", "vibe");
  bump();
}

// ── the bar's people hand out vibe ───────────────────────────────────────────
// The other half of the locked model: vibe comes from your GROUP (above) *and*
// from BAR STAFF. Staff aren't party members, so both of these go through
// definer rpcs. Positive-only — there is no way to dock anyone.
export const STAFF_VIBE_REASONS = [
  "great vibe",
  "kept it classy",
  "a pleasure to serve",
  "looked after the table",
] as const;

export interface RoomGuest {
  id: string;
  name: string;
}

/** Who's in a room — visible to fellow guests OR to the venue's staff. */
export function useRoomGuests(partyId: string | null): { guests: RoomGuest[]; loading: boolean } {
  const v = useVersion();
  const [guests, setGuests] = useState<RoomGuest[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !partyId) {
      setGuests([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("room_guests", { pid: partyId });
      if (!active) return;
      setGuests(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({ id: r.id as string, name: r.name as string })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [partyId, v]);

  return { guests, loading };
}

/** A waiter/bartender/manager gives a guest vibe. Verified venues only (the DB
 *  enforces it); a repeat of the same reason is a harmless no-op. */
export async function staffAwardVibe(partyId: string, subjectId: string, reason: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("staff_award", { pid: partyId, uid: subjectId, reason });
  bump();
  if (!error) return null;
  return /verified/i.test(error.message)
    ? "Only a verified venue can hand out vibe."
    : "Couldn't give that — try again.";
}

// ── spend: recorded ONLY by the bar, never by the guest ──────────────────────
// spend_events has NO insert policy — a guest physically cannot write their own
// tab from the client. record_spend() is a definer fn that demands the caller be
// staff of that room's VERIFIED venue. This is what makes a spend-based perk
// ("order above ₹X → a free drink next visit") trustworthy.
export async function recordSpend(partyId: string, subjectId: string, amount: number): Promise<string | null> {
  if (!supabase) return "offline";
  if (!Number.isFinite(amount) || amount <= 0) return "Enter an amount above zero.";
  const { error } = await supabase.rpc("record_spend", { pid: partyId, uid: subjectId, amt: amount });
  bump();
  if (!error) return null;
  return /verified/i.test(error.message)
    ? "Only a verified venue can record a tab."
    : "Couldn't record that — try again.";
}

// ── the Together leaderboard — opt-in on BOTH sides ──────────────────────────
// friends_board() only returns people who switched compete_visible ON, so nobody
// is ranked in front of their friends without having asked to be.
export function useFriendsBoard(enabled: boolean): { board: PointRow[]; loading: boolean } {
  const v = useVersion();
  const [board, setBoard] = useState<PointRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !enabled) {
      setBoard([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("friends_board");
      if (!active) return;
      const rows: PointRow[] = ((data as Record<string, unknown>[]) ?? []).map((r) => ({
        userId: r.user_id as string,
        name: r.display_name as string,
        sparks: (r.sparks as number) ?? 0,
        vibe: (r.vibe as number) ?? 0,
      }));
      rows.sort((a, b) => b.sparks - a.sparks || b.vibe - a.vibe || a.name.localeCompare(b.name));
      setBoard(rows);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [enabled, v]);

  return { board, loading };
}

/** Show me on the Together leaderboard (and let me see it). Default OFF. */
export function useCompeteVisible(): { competeVisible: boolean; loaded: boolean } {
  const me = useAuth().profile?.id;
  const [state, setState] = useState({ competeVisible: false, loaded: false });
  useEffect(() => {
    if (!supabase || !me) {
      setState({ competeVisible: false, loaded: true });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("profiles").select("compete_visible").eq("id", me).maybeSingle();
      if (active) setState({ competeVisible: Boolean(data?.compete_visible), loaded: true });
    })();
    return () => {
      active = false;
    };
  }, [me]);
  return state;
}

export async function setCompeteVisible(meId: string, value: boolean) {
  if (!supabase) return;
  await supabase.from("profiles").update({ compete_visible: value }).eq("id", meId);
  bump();
}

// ── kiosk: the public wall board (anon), by room invite code ─────────────────
export interface KioskRow {
  name: string;
  sparks: number;
  vibe: number;
}

/** The public leaderboard for a room, polled. Uses the anon-callable room_board
 *  rpc, which returns ONLY guests who opted into kiosk visibility, counts only. */
export function useKioskBoard(code: string, pollMs = 5000): { rows: KioskRow[]; loading: boolean } {
  const [rows, setRows] = useState<KioskRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !code) {
      setRows([]);
      setLoading(false);
      return;
    }
    let active = true;
    async function load() {
      const { data } = await supabase!.rpc("room_board", { code });
      if (!active) return;
      setRows(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          name: r.display_name as string,
          sparks: (r.sparks as number) ?? 0,
          vibe: (r.vibe as number) ?? 0,
        })),
      );
      setLoading(false);
    }
    load();
    const t = setInterval(load, pollMs);
    return () => {
      active = false;
      clearInterval(t);
    };
  }, [code, pollMs]);

  return { rows, loading };
}

// ── the opt-in tab board (flexing, double-gated) ─────────────────────────────
// Your tab only ever reaches the wall when BOTH switches are on: kiosk_visible
// ("I'll be on the screen") AND flex_receipts ("my tab can show there"). The
// number itself was recorded by the BAR — you can't flex a tab you invented.
export interface TabRow {
  name: string;
  spend: number;
  /** The VENUE's currency (ISO-4217) — never assume the app's home one. */
  currency: string;
}

export function useRoomTabs(code: string, pollMs = 5000): TabRow[] {
  const [rows, setRows] = useState<TabRow[]>([]);

  useEffect(() => {
    if (!supabase || !code) {
      setRows([]);
      return;
    }
    let active = true;
    async function load() {
      const { data } = await supabase!.rpc("room_tabs", { code });
      if (!active) return;
      setRows(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          name: r.display_name as string,
          spend: Number(r.spend) || 0,
          currency: (r.currency as string) || DEFAULT_CURRENCY,
        })),
      );
    }
    load();
    const t = setInterval(load, pollMs);
    return () => {
      active = false;
      clearInterval(t);
    };
  }, [code, pollMs]);

  return rows;
}

// ── consent to a bar's screen: PER ROOM, and it expires ──────────────────────
// This used to be a permanent global flag on your profile — flip it once for a
// fun night and your name was on every venue's TV forever. Consent to be on a
// screen TONIGHT is not consent to be on screens ALWAYS. So it now lives on the
// room (room_consent), and the bar sets how long its board runs (board_until).
// When the night is over, everyone is off the wall automatically.
export interface RoomConsent {
  onBoard: boolean;
  showTab: boolean;
}

export function useRoomConsent(partyId: string | null): { consent: RoomConsent; loaded: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [state, setState] = useState<{ consent: RoomConsent; loaded: boolean }>({
    consent: { onBoard: false, showTab: false },
    loaded: false,
  });

  useEffect(() => {
    if (!supabase || !partyId || !me) {
      setState({ consent: { onBoard: false, showTab: false }, loaded: true });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("room_consent")
        .select("on_board, show_tab")
        .eq("party_id", partyId)
        .eq("user_id", me)
        .maybeSingle();
      if (active) {
        setState({
          consent: { onBoard: Boolean(data?.on_board), showTab: Boolean(data?.show_tab) },
          loaded: true,
        });
      }
    })();
    return () => {
      active = false;
    };
  }, [partyId, me, v]);

  return state;
}

/** Set my consent for THIS room only. Turning off the board turns off the tab
 *  with it — a tab can never show for someone who isn't on the board. */
export async function setRoomConsent(partyId: string, meId: string, next: RoomConsent) {
  if (!supabase) return;
  const showTab = next.onBoard && next.showTab;
  await supabase
    .from("room_consent")
    .upsert({ party_id: partyId, user_id: meId, on_board: next.onBoard, show_tab: showTab });
  bump();
}

// (The old global `kiosk_visible` / `flex_receipts` profile switches are gone —
//  see useRoomConsent above. A permanent, app-wide "yes, put me on bar TVs" flag
//  was the wrong shape for that consent.)
