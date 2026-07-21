"use client";

// Safety — block and report. Small surface, load-bearing.
//
// BLOCK is mutual invisibility: once you block someone, neither of you sees the
// other's plans, can join, or shows up in the other's signals — and they can't tell
// they were blocked. It's an rpc (block_user) because blocking also tears down any
// live join between you, both directions, in one step.
//
// REPORT is a one-way message to us. The reports table has NO select policy, so a
// report can't be read back by the reporter and is invisible to the person reported.
// Nothing here is a rating — a block is private and symmetric, a report goes to a
// human, and neither produces a public mark on anyone.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export type ReportReason = "harassment" | "spam" | "fake" | "unsafe" | "other";

export const REPORT_REASONS: { id: ReportReason; label: string }[] = [
  { id: "harassment", label: "Harassing or abusive" },
  { id: "unsafe", label: "Made me feel unsafe" },
  { id: "fake", label: "Fake or impersonating" },
  { id: "spam", label: "Spam or scam" },
  { id: "other", label: "Something else" },
];

export interface BlockedPerson {
  id: string;
  handle: string;
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

/** My block list, for a manage screen. Only ever my own side (RLS enforces it). */
export function useBlocks(): { blocked: BlockedPerson[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [blocked, setBlocked] = useState<BlockedPerson[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setBlocked([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("blocks")
        .select("blocked:profiles!blocks_blocked_id_fkey(id, handle, display_name)")
        .eq("blocker_id", me);
      if (!active) return;
      setBlocked(
        ((data as Record<string, unknown>[]) ?? [])
          .map((r) => {
            const p = r.blocked as { id: string; handle: string; display_name: string | null } | null;
            return p ? { id: p.id, handle: p.handle, name: p.display_name ?? p.handle } : null;
          })
          .filter((x): x is BlockedPerson => x !== null),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { blocked, loading };
}

/** Block someone. Also withdraws/declines any live join between you (server-side). */
export async function blockUser(otherId: string): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("block_user", { other: otherId });
  bump();
  return error ? "Couldn't block — try again." : null;
}

export async function unblockUser(otherId: string): Promise<void> {
  if (!supabase) return;
  const me = (await supabase.auth.getUser()).data.user?.id;
  if (!me) return;
  await supabase.from("blocks").delete().eq("blocker_id", me).eq("blocked_id", otherId);
  bump();
}

/** File a report. Write-only — it goes to the safety team, never back to anyone.
 *  Reporting the same person twice is a silent no-op, so one person counts once and
 *  can't inflate anyone's report tally into a harassment tool (the unique
 *  reporter+subject index from 035 enforces it). The reporter always gets the same
 *  calm reply — dedup is never revealed.
 *
 *  Plain INSERT, with the duplicate swallowed here. This used to be an upsert with
 *  ignoreDuplicates (ON CONFLICT DO NOTHING), which LOOKS right and is what 035
 *  describes — but it fails against this table: DO NOTHING has to read the conflicting
 *  row to know to skip it, and `reports` deliberately has NO select policy, so Postgres
 *  refuses the whole statement with "new row violates row-level security policy". The
 *  effect was that reporting a repeat offender a second time told the reporter their
 *  report had failed. Giving reports a select policy would fix the SQL and break the
 *  design (a report must not be readable, by anyone, including its author), so the
 *  dedup is absorbed here instead and the table stays insert-only. */
export async function reportUser(
  meId: string,
  subjectUserId: string,
  reason: ReportReason,
  opts?: { note?: string; planId?: string },
): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.from("reports").insert({
    reporter_id: meId,
    subject_user_id: subjectUserId,
    plan_id: opts?.planId || null,
    reason,
    note: opts?.note?.trim() || null,
  });
  // 23505 = unique violation: they've already reported this person. That's the dedup
  // working, not a failure — same calm reply as a first-time report.
  if (error && error.code !== "23505") return "Couldn't send the report — try again.";
  return null;
}
