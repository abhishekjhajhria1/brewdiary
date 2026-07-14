"use client";

// The kiosk wall board — a venue casts bwdy.site/kiosk/<code> to a screen. It's
// a full-bleed dark board (fixed inset-0 so it escapes the app's centered column)
// that polls the anon room_board rpc. Only guests who opted into kiosk visibility
// appear; nobody is ranked by spend. The consumer TopBar/TabBar hide on /kiosk.
import clsx from "clsx";
import { useKioskBoard, useRoomTabs } from "@/lib/points";
import { formatMoney } from "@/lib/money";

export function KioskBoard({ code }: { code: string }) {
  const { rows, loading } = useKioskBoard(code);
  const tabs = useRoomTabs(code);
  const top = rows[0]?.sparks ?? 0;

  return (
    <div className="fixed inset-0 z-60 overflow-hidden bg-[#0b0c12] text-white">
      <div className="mx-auto flex h-full max-w-4xl flex-col px-8 py-10 sm:px-14 sm:py-14">
        <header className="flex items-baseline justify-between gap-4 border-b border-white/20 pb-5">
          <h1 className="font-display text-4xl tracking-tight sm:text-5xl">Tonight&apos;s sparks</h1>
          <span className="text-[11px] uppercase tracking-[0.16em] text-white/55">bar.bwdy.site</span>
        </header>

        {loading ? (
          <p className="mt-20 text-center text-white/60">Warming up…</p>
        ) : rows.length === 0 ? (
          <div className="flex flex-1 flex-col items-center justify-center text-center">
            <p className="font-display text-2xl text-white/85">No one on the board yet.</p>
            <p className="mt-2 max-w-sm text-sm leading-relaxed text-white/60">
              Join the room, earn a spark, and switch on kiosk visibility (You → settings) to appear up here.
            </p>
          </div>
        ) : (
          <ol className="mt-4 flex-1 overflow-hidden">
            {rows.map((r, i) => (
              <li key={`${r.name}-${i}`} className="flex items-center justify-between gap-6 border-b border-white/10 py-4">
                <span className="flex min-w-0 items-center gap-5">
                  <span className="tnum w-8 shrink-0 text-2xl text-white/30">{i + 1}</span>
                  <span className="truncate text-2xl sm:text-3xl">{r.name}</span>
                </span>
                <span className="flex shrink-0 items-baseline gap-4">
                  {r.vibe > 0 && <span className="tnum text-base text-white/40">{r.vibe} vibe</span>}
                  <span className={clsx("tnum text-3xl sm:text-4xl", r.sparks === top ? "text-accent" : "text-white")}>{r.sparks}</span>
                </span>
              </li>
            ))}
          </ol>
        )}

        {/* Flexing — deliberately the SMALL print, under the board that matters.
            Only guests who switched on BOTH kiosk visibility and receipt-flexing
            are here, and the figure is one the bar itself recorded. */}
        {tabs.length > 0 && (
          <section className="mt-6 border-t border-white/15 pt-4">
            <p className="text-[11px] uppercase tracking-[0.16em] text-white/40">Flexing tonight · they asked for this</p>
            <ul className="mt-2 flex flex-wrap gap-x-8 gap-y-1">
              {tabs.map((t, i) => (
                <li key={`${t.name}-${i}`} className="flex items-baseline gap-2 text-base text-white/55">
                  <span className="truncate">{t.name}</span>
                  <span className="tnum text-white/80">{formatMoney(t.spend, t.currency, { round: true })}</span>
                </li>
              ))}
            </ul>
          </section>
        )}

        <footer className="mt-6 border-t border-white/15 pt-4 text-center text-xs text-white/35">
          Sparks are for trying something new — never for how much you drank, or what you spent.
        </footer>
      </div>
    </div>
  );
}
