"use client";

// The curation engine's public face: k-anonymous taste trends across CONSENTING
// users (profiles.share_trends, opt-in, default off). taste_trends() returns
// counts only — a drink/mood appears when ≥3 distinct people logged it in the
// window. Feeds the Discover "what's pouring" card and Ninkasi's context.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import { encodeGeohash, AREA_PRECISION } from "./geohash";

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

// ── AREA trends: what CONSENTING drinkers in one coarse cell are into ─────────
// Same k-anon/counts-only shape as taste_trends, matched by a coarse GEOHASH and
// backed by ≥5 distinct people (a city cell is a smaller crowd). Feeds the venue
// advisor — a bar learns its neighbourhood's taste, never an individual's. The arg
// is the venue's geohash (see venues.geohash).
export function useAreaTrends(geo: string | null | undefined, daysBack = 30): { trends: Trend[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const [trends, setTrends] = useState<Trend[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const g = (geo ?? "").trim();
    if (!supabase || !me || !g) {
      setTrends([]);
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("area_taste_trends", { in_geo: g, days_back: daysBack });
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
  }, [me, geo, daysBack]);

  return { trends, loading };
}

// ── the opt-in coarse cell on my profile (only meaningful with share_trends on) ──
export function useTrendsGeo(): { hasArea: boolean; loaded: boolean; reload: () => void } {
  const me = useAuth().profile?.id;
  const [state, setState] = useState({ hasArea: false, loaded: false });
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    if (!supabase || !me) {
      setState({ hasArea: false, loaded: true });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("profiles").select("trends_geo").eq("id", me).maybeSingle();
      if (active) setState({ hasArea: Boolean(data?.trends_geo), loaded: true });
    })();
    return () => {
      active = false;
    };
  }, [me, nonce]);

  return { ...state, reload: () => setNonce((n) => n + 1) };
}

/** Ask the browser for a one-time position and reduce it to a coarse cell ON DEVICE.
 *  Only the short geohash is ever returned/stored — raw coordinates never leave here. */
export function requestLocationGeohash(): Promise<{ geohash?: string; error?: string }> {
  if (typeof navigator === "undefined" || !navigator.geolocation) {
    return Promise.resolve({ error: "Your device can't share a location." });
  }
  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ geohash: encodeGeohash(pos.coords.latitude, pos.coords.longitude, AREA_PRECISION) }),
      (err) =>
        resolve({
          error:
            err.code === err.PERMISSION_DENIED
              ? "Location permission was declined — no worries, it stays off."
              : "Couldn't read a location just now. Try again.",
        }),
      { enableHighAccuracy: false, timeout: 10_000, maximumAge: 600_000 },
    );
  });
}

/** Store (or clear) my coarse cell. Pass null to leave the local map entirely. */
export async function setTrendsGeo(meId: string, geohash: string | null): Promise<string | null> {
  if (!supabase) return "offline";
  const v = geohash ? geohash.trim().slice(0, 12) : null;
  const { error } = await supabase.from("profiles").update({ trends_geo: v }).eq("id", meId);
  return error ? error.message : null;
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
