import type { Stats } from "@/lib/derive";
import { MilestoneMeter } from "../ui/MilestoneMeter";

export function StreakStrip({ stats }: { stats: Stats }) {
  return (
    <div className="glass rounded-tile p-5">
      <div className="grid grid-cols-3 gap-2">
        <Stat value={stats.current} label="night streak" accent />
        <Stat value={stats.total} label="logged" />
        <Stat value={stats.kinds} label="kinds" />
      </div>
      {stats.total > 0 && (
        <div className="mt-4 border-t border-line pt-4">
          <MilestoneMeter total={stats.total} />
        </div>
      )}
    </div>
  );
}

function Stat({ value, label, accent }: { value: number; label: string; accent?: boolean }) {
  return (
    <div className="flex flex-col items-center gap-1 py-1">
      <span
        className={`tnum text-3xl font-semibold leading-none ${accent ? "text-accent" : "text-ink"}`}
      >
        {value}
      </span>
      <span className="label text-center">{label}</span>
    </div>
  );
}
