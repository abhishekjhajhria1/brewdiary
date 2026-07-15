"use client";

// Vouches — a friend stakes their word that you're a real person. The last of the
// FREE trust signals (tenure + diary use + liveness + this — see verify.ts).
//
// A vouch is directional and OTHER-only: you vouch FOR a friend, never for yourself
// (the DB forbids it), so no one can inflate their own standing. It's friend-gated in
// the database (are_friends in the insert policy), so the button here is just the happy
// path — a forged insert for a non-friend is rejected server-side. What anyone else can
// ever see is a COUNT, never who vouched — there is no ranking of people.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

// ── shared refresh signal (same tiny pattern as friends.ts / safety.ts) ───────
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

/** How many people vouch for ME — the count that feeds my own trust level. Read
 *  straight off the table (RLS lets me see rows where I'm the vouchee). */
export function useMyVouchCount(): number {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (!supabase || !me) {
      setCount(0);
      return;
    }
    let active = true;
    (async () => {
      const { count: n } = await supabase!
        .from("vouches")
        .select("*", { count: "exact", head: true })
        .eq("vouchee_id", me);
      if (active) setCount(n ?? 0);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return count;
}

/** The set of friends I've vouched for — so a Vouch button can show its on/off state. */
export function useVouchedByMe(): Set<string> {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [ids, setIds] = useState<Set<string>>(() => new Set());

  useEffect(() => {
    if (!supabase || !me) {
      setIds(new Set());
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("vouches").select("vouchee_id").eq("voucher_id", me);
      if (active) setIds(new Set(((data as { vouchee_id: string }[]) ?? []).map((r) => r.vouchee_id)));
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return ids;
}

/** Vouch for a friend. The friend-gate + no-self-vouch live in the DB policy; a plain
 *  insert either lands or is rejected there. */
export async function vouchFor(meId: string, voucheeId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("vouches").insert({ voucher_id: meId, vouchee_id: voucheeId });
  bump();
  return error ? "Couldn't vouch — you can only vouch for a friend." : null;
}

/** Withdraw a vouch you gave. */
export async function unvouch(meId: string, voucheeId: string): Promise<void> {
  if (!supabase) return;
  await supabase.from("vouches").delete().eq("voucher_id", meId).eq("vouchee_id", voucheeId);
  bump();
}
