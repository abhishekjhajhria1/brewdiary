"use client";

// The moderator's screen: the report queue, and the two actions with teeth — suspend
// (a temporary freeze) and ban (indefinite). It's offered only to moderators, but the
// gate that matters is server-side: every action goes through a definer rpc that checks
// is_moderator() and re-derives the target, so this screen is UX, never authority.
//
// Deliberately calm and factual. A report shows who was reported, why, the free-text
// note, how many times they've been reported (the repeat-offender signal), and whether
// they're already sanctioned. No rating, no scores — just the facts a human needs to act.
import { useState } from "react";
import Link from "next/link";
import { REPORT_REASONS } from "@/lib/safety";
import {
  useIsModerator,
  useOpenReports,
  suspendUser,
  banUser,
  liftSanction,
  type OpenReport,
} from "@/lib/moderation";
import { ChartQueue } from "./ChartQueue";
import { RecipeQueue } from "./RecipeQueue";

const REASON_LABEL: Record<string, string> = Object.fromEntries(REPORT_REASONS.map((r) => [r.id, r.label]));

const DURATIONS: { label: string; days: number }[] = [
  { label: "1 day", days: 1 },
  { label: "7 days", days: 7 },
  { label: "30 days", days: 30 },
];

export function Moderation() {
  const isMod = useIsModerator();
  const { reports, loading, refresh } = useOpenReports();

  return (
    <>
      <header className="mb-6 flex items-end justify-between border-b border-line pb-4">
        <h1 className="font-display text-5xl leading-none tracking-tight">Moderation</h1>
        <Link href="/" className="label transition-colors hover:text-ink">
          Home
        </Link>
      </header>

      {!isMod ? (
        <div className="glass rounded-tile p-6">
          <p className="text-[15px] text-ink">This area is for moderators.</p>
          <p className="mt-1 text-sm text-faint">If you reached it by accident, nothing here will work — every action is checked again on the server.</p>
        </div>
      ) : loading ? (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => (
            <div key={i} className="glass h-28 animate-pulse rounded-tile" />
          ))}
        </div>
      ) : reports.length === 0 ? (
        <div className="glass rounded-tile p-6">
          <p className="text-[15px] text-ink">Nothing to review.</p>
          <p className="mt-1 text-sm text-faint">Reports land here as they come in. A quiet queue is a good sign.</p>
        </div>
      ) : (
        <ul className="space-y-3">
          {reports.map((r) => (
            <ReportCard key={r.id} report={r} onDone={refresh} />
          ))}
        </ul>
      )}

      {/* The other queue: drinks offered to the shared dictionary (042). Same gate,
          different job — this one grows the map rather than policing people. */}
      {isMod && (
        <section className="mt-10">
          <h2 className="label mb-3">Chart proposals</h2>
          <ChartQueue />
        </section>
      )}

      {/* The third queue: community recipes that earned their friends' backing and now
          await the human gate to public (045). */}
      {isMod && (
        <section className="mt-10">
          <h2 className="label mb-3">Recipes in review</h2>
          <RecipeQueue />
        </section>
      )}
    </>
  );
}

function ReportCard({ report: r, onDone }: { report: OpenReport; onDone: () => void }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [confirming, setConfirming] = useState<null | "ban">(null);

  async function run(fn: () => Promise<string | null>) {
    if (busy || !r.subjectId) return;
    setBusy(true);
    setErr(null);
    const e = await fn();
    setBusy(false);
    if (e) setErr(e);
    else onDone();
  }

  const when = new Date(r.createdAt);
  const whenText = Number.isNaN(when.getTime()) ? "" : when.toLocaleDateString(undefined, { month: "short", day: "numeric" });

  return (
    <li className="glass rounded-tile p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-[15px] text-ink">
            {r.subjectName ?? "someone"} {r.subjectHandle && <span className="text-faint">@{r.subjectHandle}</span>}
          </p>
          <p className="mt-0.5 text-sm text-muted">
            {REASON_LABEL[r.reason] ?? r.reason}
            {r.reporterName && <span className="text-faint"> · reported by {r.reporterName}</span>}
            {whenText && <span className="text-faint"> · {whenText}</span>}
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-1">
          {r.subjectReportCount > 1 && (
            <span className="glass rounded-ctl px-2 py-0.5 text-xs text-muted">{r.subjectReportCount} reports</span>
          )}
          {r.subjectSanctioned && <span className="text-xs text-accent">already limited</span>}
        </div>
      </div>

      {r.note && <p className="mt-3 rounded-ctl bg-ink/[0.03] px-3 py-2 text-sm leading-relaxed text-muted">{r.note}</p>}

      <div className="mt-4 flex flex-wrap items-center gap-2">
        {r.subjectSanctioned ? (
          <button
            onClick={() => run(() => liftSanction(r.subjectId!))}
            disabled={busy}
            className="rounded-ctl glass px-3.5 py-1.5 text-sm font-medium text-muted transition-opacity hover:opacity-80 disabled:opacity-50"
          >
            Lift limit
          </button>
        ) : (
          <>
            <span className="text-xs text-faint">Suspend:</span>
            {DURATIONS.map((d) => (
              <button
                key={d.days}
                onClick={() =>
                  run(() => suspendUser(r.subjectId!, new Date(Date.now() + d.days * 86_400_000), REASON_LABEL[r.reason]))
                }
                disabled={busy}
                className="rounded-ctl glass px-3 py-1.5 text-sm text-ink transition-opacity hover:opacity-80 disabled:opacity-50"
              >
                {d.label}
              </button>
            ))}
            {confirming === "ban" ? (
              <span className="flex items-center gap-2 text-sm">
                <span className="text-faint">Ban for good?</span>
                <button
                  onClick={() => run(() => banUser(r.subjectId!, REASON_LABEL[r.reason]))}
                  disabled={busy}
                  className="rounded-ctl bg-ink px-3 py-1.5 font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
                >
                  Ban
                </button>
                <button onClick={() => setConfirming(null)} className="text-faint hover:text-ink">
                  No
                </button>
              </span>
            ) : (
              <button
                onClick={() => setConfirming("ban")}
                disabled={busy}
                className="ml-auto text-sm text-faint transition-colors hover:text-ink"
              >
                Ban
              </button>
            )}
          </>
        )}
      </div>
      {err && <p className="mt-2 text-xs text-accent">{err}</p>}
    </li>
  );
}
