"use client";

// The ready board on a wall: numbers being made on the left, numbers ready to collect
// big and amber on the right. It re-reads every 5 seconds and asks the browser to keep
// the screen awake. Full-bleed (fixed inset-0), dark, like the kiosk board; the consumer
// TopBar/TabBar hide on /ready.
import { useEffect, useRef, useState } from "react";
import clsx from "clsx";
import { fetchPickupBoard } from "@/lib/tableOrder";

type Board = { venueName: string; numbers: { no: number; ready: boolean; since: string }[] };

export function ReadyBoard({ code }: { code: string }) {
  const [board, setBoard] = useState<Board | null | "missing">(null);
  const [offline, setOffline] = useState(false);
  const [fresh, setFresh] = useState<Set<number>>(new Set());
  const seen = useRef<Set<number> | null>(null);

  useEffect(() => {
    let active = true;
    const read = async () => {
      try {
        const b = await fetchPickupBoard(code);
        if (!active) return;
        if (!b) return setBoard("missing");
        const ready = new Set(b.numbers.filter((n) => n.ready).map((n) => n.no));
        // A number that just turned ready glows for a moment.
        if (seen.current) setFresh(new Set([...ready].filter((n) => !seen.current!.has(n))));
        seen.current = ready;
        setBoard(b);
        setOffline(false);
      } catch {
        if (active) setOffline(true);
      }
    };
    void read();
    const t = setInterval(read, 5_000);
    return () => {
      active = false;
      clearInterval(t);
    };
  }, [code]);

  // A screen on the wall shouldn't dim mid-rush.
  useEffect(() => {
    let lock: { release: () => Promise<void> } | null = null;
    const take = async () => {
      try {
        lock = await (navigator as Navigator & { wakeLock?: { request: (t: "screen") => Promise<{ release: () => Promise<void> }> } }).wakeLock?.request("screen") ?? null;
      } catch {
        /* not allowed here: the screen sleeps on its own settings */
      }
    };
    void take();
    const again = () => document.visibilityState === "visible" && void take();
    document.addEventListener("visibilitychange", again);
    return () => {
      document.removeEventListener("visibilitychange", again);
      void lock?.release().catch(() => {});
    };
  }, []);

  const making = board && board !== "missing" ? board.numbers.filter((n) => !n.ready) : [];
  const ready = board && board !== "missing" ? board.numbers.filter((n) => n.ready).sort((a, b) => b.since.localeCompare(a.since)) : [];

  return (
    <div className="fixed inset-0 z-60 overflow-hidden bg-[#0b0c12] text-white">
      <div className="mx-auto flex h-full max-w-6xl flex-col px-8 py-10 sm:px-14 sm:py-12">
        <header className="flex items-baseline justify-between gap-4 border-b border-white/20 pb-5">
          <h1 className="font-display text-4xl tracking-tight sm:text-5xl">{board && board !== "missing" && board.venueName ? board.venueName : "Ready to collect"}</h1>
          <span className="text-[11px] uppercase tracking-[0.16em] text-white/55">{offline ? "reconnecting…" : "bwdy.site"}</span>
        </header>

        {board === null ? (
          <p className="mt-20 text-center text-white/60">Warming up…</p>
        ) : board === "missing" ? (
          <div className="flex flex-1 flex-col items-center justify-center text-center">
            <p className="font-display text-2xl text-white/85">This board&apos;s link isn&apos;t live.</p>
            <p className="mt-2 max-w-sm text-sm leading-relaxed text-white/60">Open it again from the venue app: Floor setup → the pickup point → share the ready board&apos;s link.</p>
          </div>
        ) : (
          <div className="mt-8 grid flex-1 grid-cols-1 gap-10 overflow-hidden sm:grid-cols-5">
            <section className="sm:col-span-2" aria-label="Being made">
              <p className="text-[11px] uppercase tracking-[0.16em] text-white/45">Being made</p>
              {making.length === 0 ? (
                <p className="mt-4 text-white/40">Nothing on the go.</p>
              ) : (
                <ul className="mt-4 flex flex-wrap gap-x-8 gap-y-3">
                  {making.map((n) => (
                    <li key={n.no} className="tnum font-display text-5xl text-white/55 sm:text-6xl">
                      <span className="sr-only">Number </span>
                      {n.no}
                    </li>
                  ))}
                </ul>
              )}
            </section>
            <section className="sm:col-span-3" aria-label="Ready — come and collect" aria-live="polite">
              <p className="text-[11px] uppercase tracking-[0.16em] text-accent">Ready — come and collect</p>
              {ready.length === 0 ? (
                <p className="mt-4 text-white/40">Nothing waiting.</p>
              ) : (
                <ul className="mt-4 flex flex-wrap gap-x-10 gap-y-4">
                  {ready.map((n) => (
                    <li key={n.no} className={clsx("tnum font-display text-7xl text-accent sm:text-8xl", fresh.has(n.no) && "motion-safe:animate-pulse")}>
                      <span className="sr-only">Number </span>
                      {n.no}
                      <span className="sr-only"> is ready</span>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          </div>
        )}

        <p className="mt-6 text-center text-base text-white/55">Order from your phone: scan the QR on the counter. Your number shows here when it&apos;s ready.</p>
      </div>
    </div>
  );
}
