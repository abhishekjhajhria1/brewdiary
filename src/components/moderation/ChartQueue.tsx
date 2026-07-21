"use client";

// The chart-proposal queue: drinks people have offered to the shared dictionary.
//
// Accepting one changes what EVERY user sees, which is why it's here behind the same
// moderator gate as the report queue and not an auto-accept. As always the gate that
// matters is server-side — review_chart_proposal() re-derives is_moderator() — so this
// screen is UX, never authority.
//
// What to look for: is it a real drink, is it already in the dictionary under another
// name (accepting a duplicate quietly forks everyone's passport), and is the family
// sensible. Rejection is silent and costs the author nothing — they can send it again.
import { useState } from "react";
import { usePendingProposals, reviewChart, type PendingProposal } from "@/lib/charts";
import { existingMatch } from "@/lib/cartography";

export function ChartQueue() {
  const { rows, loading, refresh } = usePendingProposals();

  if (loading) {
    return <div className="glass h-24 animate-pulse rounded-tile" />;
  }
  if (rows.length === 0) {
    return (
      <div className="glass rounded-tile p-6">
        <p className="text-[15px] text-ink">No drinks waiting to be charted.</p>
        <p className="mt-1 text-sm text-faint">
          These arrive when someone logs a drink the dictionary doesn&apos;t know and offers it up.
        </p>
      </div>
    );
  }

  return (
    <ul className="space-y-3">
      {rows.map((p) => (
        <ProposalCard key={p.id} proposal={p} onDone={refresh} />
      ))}
    </ul>
  );
}

function ProposalCard({ proposal: p, onDone }: { proposal: PendingProposal; onDone: () => void }) {
  const [busy, setBusy] = useState(false);

  // The one check a human is most likely to miss: the dictionary may already know this
  // under a different spelling, and accepting it would fork the family in two.
  const clash = existingMatch(p.canonical);

  async function decide(decision: "accepted" | "rejected") {
    setBusy(true);
    await reviewChart(p.id, decision);
    setBusy(false);
    onDone();
  }

  return (
    <li className="glass rounded-tile p-5">
      <p className="font-display text-2xl leading-none text-ink">{p.canonical}</p>
      <p className="mt-2 text-sm text-muted">
        Logged as <span className="italic">{p.rawName}</span> · joins {p.family}
        {p.type ? ` · ${p.type}` : ""}
      </p>

      {clash && (
        <p role="alert" className="mt-3 rounded-ctl bg-accent/8 px-3 py-2 text-xs text-ink">
          The dictionary may already have this as <strong>{clash}</strong>. Accepting a duplicate
          splits the family in two on everyone&apos;s map.
        </p>
      )}

      <div className="mt-4 flex gap-2">
        <button
          onClick={() => decide("accepted")}
          disabled={busy}
          className="min-h-11 flex-1 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-60"
        >
          Add to the map
        </button>
        <button
          onClick={() => decide("rejected")}
          disabled={busy}
          className="min-h-11 rounded-ctl border border-line px-4 py-2 text-sm text-muted transition-colors hover:border-line-strong hover:text-ink disabled:opacity-60"
        >
          Not this one
        </button>
      </div>
    </li>
  );
}
