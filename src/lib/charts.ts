"use client";

// The Cartographer's store seam — proposing charts and reading the shared map back.
//
// The judgment lives in lib/cartography.ts (pure, tested); this file only moves rows.
// Two-mode like store.ts: signed out, every read is empty and proposing is a no-op —
// charting is inherently a shared act, so there is nothing sensible to do locally, and
// a silent local queue that never reaches anyone would be a lie.
//
// The database is the wall, not this file (042_cartography.sql): status is pinned to
// 'pending' by a trigger, there is no client UPDATE policy, and acceptance runs only
// through the moderator-gated rpc. Nothing here can grant anyone a byline.
import { useCallback, useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import type { ChartProposal } from "./cartography";
import type { DrinkType } from "./types";

/** A family somebody drew, and the handle to credit. The entire public reward. */
export interface ChartedFamily {
  family: string;
  handle: string;
  chartedAt: string;
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

function toProposal(r: Record<string, unknown>): ChartProposal {
  return {
    id: r.id as string,
    author: r.author as string,
    rawName: r.raw_name as string,
    canonical: r.canonical as string,
    family: r.family as string,
    type: (r.type as DrinkType) ?? "other",
    status: r.status as ChartProposal["status"],
    createdAt: r.created_at as string,
  };
}

/** Your own proposals, any status — so the UI can say "sent in" instead of nagging. */
export function useMyProposals(): ChartProposal[] {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [rows, setRows] = useState<ChartProposal[]>([]);

  useEffect(() => {
    if (!supabase || !me) {
      setRows([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("chart_proposals")
        .select("id, author, raw_name, canonical, family, type, status, created_at")
        .eq("author", me)
        .order("created_at", { ascending: false });
      if (!active) return;
      setRows(((data as Record<string, unknown>[]) ?? []).map(toProposal));
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return rows;
}

/**
 * Every family a drinker charted, with the handle to credit. Readable signed-out too —
 * an accepted chart IS the dictionary, and the dictionary was never private.
 */
export function useChartedFamilies(): ChartedFamily[] {
  const v = useVersion();
  const [rows, setRows] = useState<ChartedFamily[]>([]);

  useEffect(() => {
    if (!supabase) {
      setRows([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("charted_families");
      if (!active) return;
      setRows(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          family: r.family as string,
          handle: r.handle as string,
          chartedAt: r.charted_at as string,
        })),
      );
    })();
    return () => {
      active = false;
    };
  }, [v]);

  return rows;
}

/**
 * Send a proposal. Insert with a client-generated id and NO .select() — our
 * SECURITY DEFINER read policy makes PostgREST's INSERT … RETURNING fail (CLAUDE.md).
 * Status is not passed at all: the server pins it, and sending one would be theatre.
 */
export async function proposeChart(input: {
  rawName: string;
  canonical: string;
  family: string;
  type: DrinkType;
}): Promise<{ ok: boolean; error?: string }> {
  const me = (await supabase?.auth.getUser())?.data.user?.id;
  if (!supabase || !me) return { ok: false, error: "Sign in to chart a drink." };

  const { error } = await supabase.from("chart_proposals").insert({
    id: crypto.randomUUID(),
    author: me,
    raw_name: input.rawName,
    canonical: input.canonical,
    family: input.family,
    type: input.type,
  });
  if (error) {
    // The partial unique index on (author, lower(canonical)) where pending — you already sent it.
    if (error.code === "23505") return { ok: false, error: "You've already sent this one in." };
    return { ok: false, error: error.message };
  }
  bump();
  return { ok: true };
}

/** Withdraw your own proposal while it's still unreviewed. RLS refuses anything else. */
export async function withdrawChart(id: string): Promise<void> {
  if (!supabase) return;
  await supabase.from("chart_proposals").delete().eq("id", id);
  bump();
}

// ── the moderator side ───────────────────────────────────────────────────────

export interface PendingProposal {
  id: string;
  rawName: string;
  canonical: string;
  family: string;
  type: string | null;
  createdAt: string;
}

/**
 * The review queue. The rpc re-derives is_moderator() server-side and raises for anyone
 * else, so a non-moderator gets an empty list rather than a leak.
 */
export function usePendingProposals(): { rows: PendingProposal[]; loading: boolean; refresh: () => void } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [rows, setRows] = useState<PendingProposal[]>([]);
  const [loading, setLoading] = useState(true);
  const refresh = useCallback(() => bump(), []);

  useEffect(() => {
    if (!supabase || !me) {
      setRows([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      setLoading(true);
      const { data } = await supabase!.rpc("pending_chart_proposals");
      if (!active) return;
      setRows(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          id: r.id as string,
          rawName: r.raw_name as string,
          canonical: r.canonical as string,
          family: r.family as string,
          type: (r.type as string) ?? null,
          createdAt: r.created_at as string,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { rows, loading, refresh };
}

/** Accept or reject. Moderator-only — the rpc raises for anyone else. */
export async function reviewChart(id: string, decision: "accepted" | "rejected"): Promise<void> {
  if (!supabase) return;
  await supabase.rpc("review_chart_proposal", { pid: id, decision });
  bump();
}
