"use client";

// The curation engine's public face: k-anonymous taste trends across CONSENTING
// users (profiles.share_trends, opt-in, default off). taste_trends() returns
// counts only — a drink/mood appears when ≥3 distinct people logged it in the
// window. Feeds the Discover "what's pouring" card and Ninkasi's context.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export interface Trend {
  kind: "drink" | "mood";
  name: string;
  users: number;
  logs: number;
}

export function useTasteTrends(daysBack = 14): { trends: Trend[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const [trends, setTrends] = useState<Trend[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setTrends([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("taste_trends", { days_back: daysBack });
      if (!active) return;
      setTrends(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          kind: r.kind as "drink" | "mood",
          name: r.name as string,
          users: r.users as number,
          logs: r.logs as number,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, daysBack]);

  return { trends, loading };
}

// ── the opt-in flag on my profile ────────────────────────────────────────────
export function useShareTrends(): { shareTrends: boolean; loaded: boolean } {
  const me = useAuth().profile?.id;
  const [state, setState] = useState({ shareTrends: false, loaded: false });

  useEffect(() => {
    if (!supabase || !me) {
      setState({ shareTrends: false, loaded: true });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("profiles").select("share_trends").eq("id", me).maybeSingle();
      if (active) setState({ shareTrends: Boolean(data?.share_trends), loaded: true });
    })();
    return () => {
      active = false;
    };
  }, [me]);

  return state;
}

export async function setShareTrends(meId: string, value: boolean) {
  if (!supabase) return;
  await supabase.from("profiles").update({ share_trends: value }).eq("id", meId);
}
