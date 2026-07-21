"use client";

// Public profiles — the read side (usePublicProfile) + the owner's privacy
// controls (visibility + one social handle). The read goes through the
// public_profile() rpc, which honours the tier the OWNER picked — 'public'
// (anyone, including signed-out), 'fof' (my friends and their friends) or
// 'friends' — and returns only counts (a 12-week mosaic + totals), never notes,
// spend, or contacts. The rpc reads auth.uid(), so the fetch has to wait for the
// session: an anon call would wrongly read a friends-only profile as missing.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export type ProfileVisibility = "friends" | "fof" | "public";

export interface PublicProfile {
  displayName: string;
  handle: string;
  socialHandle?: string;
  counts: Map<string, number>; // day-key → logs that day (feeds the mosaic)
  total: number;
  kinds: number;
  // Lifetime aggregates (migration 046). Optional so the read still works before it's
  // applied — the score/stats just fall back to what the 12-week window can show.
  activeDays?: number; // distinct days logged, ALL-TIME
  longestStreak?: number;
  monthsActive?: number;
  firstDate?: string; // YYYY-MM-DD — "since …"
}

export function usePublicProfile(handle: string): { profile: PublicProfile | null; loading: boolean } {
  const { profile: me, status } = useAuth();
  const authLoading = status === "loading";
  const [profile, setProfile] = useState<PublicProfile | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !handle) {
      setProfile(null);
      setLoading(false);
      return;
    }
    if (authLoading) {
      setLoading(true); // re-run once the session lands — see the note above
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("public_profile", { h: handle });
      if (!active) return;
      const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
      if (!row) {
        setProfile(null);
        setLoading(false);
        return;
      }
      const dates = (row.dates as string[]) ?? [];
      const counts = new Map<string, number>();
      for (const d of dates) counts.set(d, (counts.get(d) ?? 0) + 1);
      const num = (v: unknown): number | undefined => (typeof v === "number" ? v : undefined);
      setProfile({
        displayName: row.display_name as string,
        handle: row.handle as string,
        socialHandle: (row.social_handle as string) ?? undefined,
        counts,
        total: (row.total as number) ?? 0,
        kinds: (row.kinds as number) ?? 0,
        activeDays: num(row.active_days),
        longestStreak: num(row.longest_streak),
        monthsActive: num(row.months_active),
        firstDate: (row.first_date as string) ?? undefined,
      });
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [handle, me?.id, authLoading]);

  return { profile, loading };
}

// ── my own privacy settings ──────────────────────────────────────────────────
export function useProfilePrivacy(): { visibility: ProfileVisibility; socialHandle: string; loaded: boolean } {
  const me = useAuth().profile?.id;
  const [state, setState] = useState<{ visibility: ProfileVisibility; socialHandle: string; loaded: boolean }>({
    visibility: "friends",
    socialHandle: "",
    loaded: false,
  });

  useEffect(() => {
    if (!supabase || !me) {
      setState({ visibility: "friends", socialHandle: "", loaded: true });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("profiles").select("profile_visibility, social_handle").eq("id", me).maybeSingle();
      if (active) {
        setState({
          visibility: (data?.profile_visibility as ProfileVisibility) ?? "friends",
          socialHandle: (data?.social_handle as string) ?? "",
          loaded: true,
        });
      }
    })();
    return () => {
      active = false;
    };
  }, [me]);

  return state;
}

export async function setProfileVisibility(meId: string, v: ProfileVisibility) {
  if (!supabase) return;
  await supabase.from("profiles").update({ profile_visibility: v }).eq("id", meId);
}

export async function setSocialHandle(meId: string, handle: string) {
  if (!supabase) return;
  await supabase.from("profiles").update({ social_handle: handle.trim() || null }).eq("id", meId);
}
