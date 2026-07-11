import { milestoneProgress } from "@/lib/derive";

/** Quiet game layer — progress toward the next logging milestone. Derived, never stored. */
export function MilestoneMeter({ total }: { total: number }) {
  const { reached, next } = milestoneProgress(total);
  if (!next) {
    return (
      <p className="label text-accent">All milestones reached — {total} logged</p>
    );
  }
  const from = reached ?? 0;
  const pct = Math.max(4, Math.round(((total - from) / (next - from)) * 100));

  return (
    <div>
      <div className="mb-1.5 flex items-baseline justify-between">
        <span className="label">to {next} logs</span>
        <span className="tnum text-sm font-medium text-ink">
          {total}
          <span className="text-faint">/{next}</span>
        </span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-ink/10">
        <div
          className="h-full rounded-full bg-accent transition-[width] duration-500"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  );
}
