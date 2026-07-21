"use client";

// "Chart this" — the one action that turns a private off-map drink into part of the
// shared map. See internal/phase-b-cartographer.md.
//
// The whole reward for charting is one quiet line of attribution on the family, later,
// if a moderator accepts it. There is deliberately no count, no rank, no badge and no
// progress bar here — not an oversight. Visible contribution status is exactly what
// would make it rational to log drinks you never had, and honest logs are the one thing
// this app can't do without. So the form is calm, the payout is small, and nothing about
// it is worth gaming.
import { useState } from "react";
import clsx from "clsx";
import { checkProposal, suggestFamilies, type ChartProposal } from "@/lib/cartography";
import { proposeChart } from "@/lib/charts";
import { canonicalize } from "@/lib/drinks";
import { DRINK_TYPES, type DrinkType } from "@/lib/types";

export function ChartThis({ rawName, mine }: { rawName: string; mine: ChartProposal[] }) {
  const [open, setOpen] = useState(false);
  const [canonical, setCanonical] = useState(rawName.trim());
  const [family, setFamily] = useState(rawName.trim());
  const [type, setType] = useState<DrinkType>(canonicalize(rawName).type ?? "other");
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);

  const already = mine.find(
    (p) => p.rawName.trim().toLowerCase() === rawName.trim().toLowerCase() && p.status !== "rejected",
  );

  if (sent || already?.status === "pending") {
    return (
      <p className="mt-5 border-t border-line pt-4 text-sm text-muted">
        Sent in — a moderator will take a look. Your drink stays in your diary either way.
      </p>
    );
  }
  if (already?.status === "accepted") {
    return (
      <p className="mt-5 border-t border-line pt-4 text-sm text-muted">
        You charted this one. It&apos;s part of the map now.
      </p>
    );
  }

  if (!open) {
    return (
      <div className="mt-5 border-t border-line pt-4">
        <p className="text-sm text-muted">
          The map doesn&apos;t know this one yet. Chart it and everyone&apos;s passport can light it.
        </p>
        <button
          onClick={() => setOpen(true)}
          className="mt-3 min-h-11 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90"
        >
          Chart this
        </button>
      </div>
    );
  }

  async function send() {
    const check = checkProposal(canonical, mine);
    if (!check.ok) {
      setError(check.message);
      return;
    }
    if (!family.trim()) {
      setError("Give it a family, or let it found its own.");
      return;
    }
    setSending(true);
    setError(null);
    const res = await proposeChart({
      rawName: rawName.trim(),
      canonical: canonical.trim(),
      family: family.trim(),
      type,
    });
    setSending(false);
    if (res.ok) setSent(true);
    else setError(res.error ?? "Couldn't send that. Try again in a moment.");
  }

  const nearby = suggestFamilies(canonical || rawName);

  return (
    <div className="mt-5 border-t border-line pt-4">
      <p className="label mb-3 text-faint">Chart it</p>

      <label htmlFor="chart-canonical" className="mb-1 block text-xs text-muted">
        Tidy spelling
      </label>
      <input
        id="chart-canonical"
        value={canonical}
        onChange={(e) => {
          setCanonical(e.target.value);
          setError(null);
        }}
        maxLength={60}
        className="w-full border-b border-line-strong bg-transparent pb-2 text-sm outline-none placeholder:text-faint focus:border-ink"
      />

      <label htmlFor="chart-family" className="mb-1 mt-4 block text-xs text-muted">
        Family it joins
      </label>
      <input
        id="chart-family"
        value={family}
        onChange={(e) => {
          setFamily(e.target.value);
          setError(null);
        }}
        maxLength={60}
        className="w-full border-b border-line-strong bg-transparent pb-2 text-sm outline-none placeholder:text-faint focus:border-ink"
      />
      {nearby.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {/* Nearby families, so filing it is a choice — founding its own is a fine answer too. */}
          {nearby.map((f) => (
            <button
              key={f}
              onClick={() => setFamily(f)}
              className={clsx(
                "min-h-11 rounded-ctl border px-2.5 py-1 text-xs transition-colors",
                family === f ? "border-transparent bg-accent/8 text-ink" : "border-line text-faint hover:text-ink",
              )}
            >
              {f}
            </button>
          ))}
        </div>
      )}

      <fieldset className="mt-4">
        <legend className="mb-2 text-xs text-muted">Which world</legend>
        <div className="flex flex-wrap gap-1.5">
          {DRINK_TYPES.map((t) => (
            <button
              key={t.value}
              onClick={() => setType(t.value)}
              aria-pressed={type === t.value}
              className={clsx(
                "min-h-11 rounded-ctl border px-2.5 py-1 text-xs transition-colors",
                type === t.value ? "border-transparent bg-accent/8 text-ink" : "border-line text-faint hover:text-ink",
              )}
            >
              {t.label}
            </button>
          ))}
        </div>
      </fieldset>

      {error && (
        <p role="alert" className="mt-3 text-xs text-ink">
          {error}
        </p>
      )}

      <div className="mt-5 flex gap-2">
        <button
          onClick={send}
          disabled={sending}
          className="min-h-11 flex-1 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-60"
        >
          {sending ? "Sending…" : "Send it in"}
        </button>
        <button
          onClick={() => setOpen(false)}
          className="min-h-11 rounded-ctl px-4 py-2 text-sm text-faint transition-colors hover:text-ink"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
