"use client";

import { useState } from "react";
import Link from "next/link";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { countsByDate, memory, recentDrinks, recentMoods, stats } from "@/lib/derive";
import { addMonths, MONTH_NAMES, parseKey, todayKey } from "@/lib/date";
import { MonthCalendar } from "./MonthCalendar";
import { YearMosaic } from "./YearMosaic";
import { StreakStrip } from "./StreakStrip";
import { DayCounters } from "../ui/DayCounters";
import { LogSheet } from "../log/LogSheet";

export function CalendarHome() {
  const entries = useEntries();
  const counts = countsByDate(entries);
  const now = new Date();

  const [cursor, setCursor] = useState({ y: now.getFullYear(), m: now.getMonth() });
  const [view, setView] = useState<"month" | "year">("month");
  const [selected, setSelected] = useState<string | null>(null);

  const canNext =
    cursor.y < now.getFullYear() || (cursor.y === now.getFullYear() && cursor.m < now.getMonth());

  const s = stats(entries);
  const mem = memory(entries);
  const dayEntries = selected
    ? entries.filter((e) => e.date === selected).sort((a, b) => a.createdAt.localeCompare(b.createdAt))
    : [];

  function step(delta: number) {
    setCursor((c) => {
      const d = addMonths(new Date(c.y, c.m, 1), delta);
      return { y: d.getFullYear(), m: d.getMonth() };
    });
  }

  return (
    <>
      <div className="mb-5 flex justify-end">
        <div className="glass flex rounded-full p-1">
          <Toggle active={view === "month"} onClick={() => setView("month")}>
            Month
          </Toggle>
          <Toggle active={view === "year"} onClick={() => setView("year")}>
            Year
          </Toggle>
        </div>
      </div>

      <StreakStrip stats={s} />

      {mem && (
        <button
          onClick={() => setSelected(mem.date)}
          className="glass glass-press mt-4 flex w-full items-baseline gap-2 rounded-tile px-4 py-3 text-left text-sm text-muted"
        >
          <span className="label shrink-0">looking back</span>
          <span className="truncate">
            {mem.drink}
            {mem.mood && <span className="italic"> · {mem.mood}</span>}
          </span>
          <span className="tnum ml-auto shrink-0 text-xs text-faint">
            {MONTH_NAMES[parseKey(mem.date).getMonth()].slice(0, 3)} {parseKey(mem.date).getDate()}
          </span>
        </button>
      )}

      {/* optional quick-trackers (cigarettes, water…) for TODAY — sit above the calendar */}
      <DayCounters dateKey={todayKey()} className="mt-4" />

      <div className="mt-8">
        {view === "month" ? (
          <MonthCalendar
            year={cursor.y}
            month={cursor.m}
            counts={counts}
            onSelect={setSelected}
            onPrev={() => step(-1)}
            onNext={() => step(1)}
            canNext={canNext}
          />
        ) : (
          <YearMosaic year={now.getFullYear()} counts={counts} onSelect={setSelected} />
        )}
      </div>

      {entries.length === 0 && (
        <p className="mt-10 text-center text-sm text-faint">Tap a day to log your first drink.</p>
      )}

      <Link
        href="/bartender"
        className="glass glass-press mt-10 flex items-center justify-between gap-4 rounded-tile p-4"
      >
        <div className="min-w-0">
          <p className="label mb-1 text-faint">Ninkasi</p>
          <p className="text-[15px] text-ink">Not sure what to pour tonight?</p>
        </div>
        <span className="shrink-0 text-sm font-medium text-accent">Ask →</span>
      </Link>

      {selected && (
        <LogSheet
          dateKey={selected}
          dayEntries={dayEntries}
          recentDrinks={recentDrinks(entries)}
          recentMoods={recentMoods(entries)}
          onClose={() => setSelected(null)}
        />
      )}
    </>
  );
}

function Toggle({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={clsx(
        "rounded-full px-4 py-1.5 text-xs uppercase tracking-[0.14em] transition-all duration-200 ease-out",
        active ? "bg-ink text-paper shadow-sm" : "text-muted hover:text-ink",
      )}
    >
      {children}
    </button>
  );
}
