"use client";

// Moderation — the operator side of the safety layer. A moderator (seeded into the
// `moderators` table by hand, never grantable from the app) can read the report queue
// and suspend or ban an account. Everything here is gated server-side by is_moderator();
// these hooks only decide what to SHOW — the database is the wall, not this file.
//
// The flip side lives on every user: useMySanction tells someone plainly when their
// account is limited, so a suspended person sees an honest banner instead of a silent
// failure when a write is refused by RLS.
import { useCallback, useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export type SanctionKind = "suspend" | "ban";

export interface OpenReport {
  id: string;
  reporterName: string | null;
  subjectId: string | null;
  subjectName: string | null;
  subjectHandle: string | null;
  reason: string;
  note: string | null;
  createdAt: string;
  subjectReportCount: number;
  subjectSanctioned: boolean;
}

export interface MySanction {
  banned: boolean;
  suspendedUntil: string | null;
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

/** Am I a moderator? Reads my own row (RLS shows me only mine). Decides whether the
 *  moderation screen is offered — the rpcs enforce it for real regardless. */
export function useIsModerator(): boolean {
  const me = useAuth().profile?.id;
  const [isMod, setIsMod] = useState(false);

  useEffect(() => {
    if (!supabase || !me) {
      setIsMod(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("moderators").select("user_id").eq("user_id", me).maybeSingle();
      if (active) setIsMod(Boolean(data));
    })();
    return () => {
      active = false;
    };
  }, [me]);

  return isMod;
}

/** My own sanction, if any — so we can tell me honestly rather than fail silently. */
export function useMySanction(): MySanction | null {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [s, setS] = useState<MySanction | null>(null);

  useEffect(() => {
    if (!supabase || !me) {
      setS(null);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("user_sanctions")
        .select("banned, suspended_until")
        .eq("user_id", me)
        .maybeSingle();
      if (!active) return;
      const row = data as { banned: boolean; suspended_until: string | null } | null;
      // A suspension that has run out is no sanction at all.
      if (!row || (!row.banned && (!row.suspended_until || new Date(row.suspended_until) <= new Date()))) {
        setS(null);
      } else {
        setS({ banned: row.banned, suspendedUntil: row.suspended_until });
      }
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return s;
}

/** The report queue — moderator-only (the rpc raises otherwise). */
export function useOpenReports(): { reports: OpenReport[]; loading: boolean; refresh: () => void } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [reports, setReports] = useState<OpenReport[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setReports([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      setLoading(true);
      const { data } = await supabase!.rpc("open_reports");
      if (!active) return;
      setReports(
        ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          id: r.id as string,
          reporterName: (r.reporter_name as string) ?? null,
          subjectId: (r.subject_id as string) ?? null,
          subjectName: (r.subject_name as string) ?? null,
          subjectHandle: (r.subject_handle as string) ?? null,
          reason: r.reason as string,
          note: (r.note as string) ?? null,
          createdAt: r.created_at as string,
          subjectReportCount: Number(r.subject_report_count ?? 0),
          subjectSanctioned: Boolean(r.subject_sanctioned),
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { reports, loading, refresh: useCallback(() => bump(), []) };
}

// ── mutations (all moderator-only, enforced in the rpc) ──────────────────────
export async function suspendUser(target: string, until: Date, reason?: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("suspend_user", { target, until: until.toISOString(), reason: reason?.trim() || null });
  bump();
  return error ? "Couldn't apply the suspension." : null;
}

export async function banUser(target: string, reason?: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("ban_user", { target, reason: reason?.trim() || null });
  bump();
  return error ? "Couldn't apply the ban." : null;
}

export async function liftSanction(target: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("lift_sanction", { target });
  bump();
  return error ? "Couldn't lift the sanction." : null;
}
