"use client";

// Staff kudos — a guest thanks the bartender, by name.
//
// People don't quit a bar because they lost a leaderboard; they quit because
// nobody ever noticed. So this is a THANK YOU, not a rating.
//
// The shape is dictated by law, not taste. Feedback attached to a named employee
// is *employee monitoring* under GDPR: lawful basis, a DPIA, and works-council
// consultation in DE/FR/PL/BE/NL/AT/SE. So:
//   • Positive-only. No stars, no score, no complaint path. Ever.
//   • The STAFF MEMBER sees their own thanks.
//   • A MANAGER SEES ONE NUMBER for the whole team — never a per-person ranking.
//     A bar will ask for the ranking. The answer is no; that's the line between a
//     thank-you box and a surveillance tool.
//   • Staff can opt out and then cannot be thanked at all.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";

/** Fixed and positive-only. A guest cannot write free text about a worker. */
export const KUDOS_REASONS = [
  "looked after us",
  "great recommendation",
  "made the night",
  "quick and kind",
] as const;

export interface RoomStaff {
  id: string;
  name: string;
}

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

/** Who's on tonight and taking thanks. Only opted-in staff; you must be in the room. */
export function useRoomStaff(partyId: string | null): RoomStaff[] {
  const [staff, setStaff] = useState<RoomStaff[]>([]);

  useEffect(() => {
    if (!supabase || !partyId) {
      setStaff([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("room_staff", { pid: partyId });
      if (active) {
        setStaff(((data as Record<string, unknown>[]) ?? []).map((r) => ({ id: r.id as string, name: r.name as string })));
      }
    })();
    return () => {
      active = false;
    };
  }, [partyId]);

  return staff;
}

/** Say thank you. Once per reason, per person, per night — a repeat is a no-op. */
export async function thankStaff(partyId: string, staffId: string, reason: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("thank_staff", { pid: partyId, sid: staffId, why: reason });
  bump();
  if (!error) return null;
  if (/not taking thanks/i.test(error.message)) return "They've turned thanks off.";
  return "Couldn't send that — try again.";
}

/** What a staff member sees: their OWN thanks, grouped by reason. */
export function useMyKudos(venueId: string | null): { reason: string; n: number }[] {
  const v = useVersion();
  const [rows, setRows] = useState<{ reason: string; n: number }[]>([]);

  useEffect(() => {
    if (!supabase || !venueId) {
      setRows([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("my_kudos", { vid: venueId });
      if (active) {
        setRows(((data as Record<string, unknown>[]) ?? []).map((r) => ({ reason: r.reason as string, n: Number(r.n) })));
      }
    })();
    return () => {
      active = false;
    };
  }, [venueId, v]);

  return rows;
}

/** What a MANAGER sees: one number for the whole team. Never a per-person table —
 *  see the note at the top of this file, and don't "improve" it. */
export function useVenueKudosTotal(venueId: string | null, days = 30): number {
  const v = useVersion();
  const [total, setTotal] = useState(0);

  useEffect(() => {
    if (!supabase || !venueId) {
      setTotal(0);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("venue_kudos_total", { vid: venueId, since_days: days });
      if (active) setTotal(Number(data ?? 0));
    })();
    return () => {
      active = false;
    };
  }, [venueId, days, v]);

  return total;
}

/** A staff member turns thanks off (or back on) for themselves. */
export async function setThankable(venueId: string, meId: string, value: boolean) {
  if (!supabase) return;
  await supabase.from("venue_staff").update({ thankable: value }).eq("venue_id", venueId).eq("user_id", meId);
  bump();
}
