"use client";

import { useState } from "react";
import Link from "next/link";
import { useEntries } from "@/lib/store";
import { countsByDate, memory, recentDrinks, recentMoods, stats } from "@/lib/derive";
import { addMonths, MONTH_NAMES, parseKey, todayKey } from "@/lib/date";
import { useCalendarView } from "@/lib/calendarView";
import { usePlanDays } from "@/lib/plans";
import { MonthCalendar } from "./MonthCalendar";
import { YearMosaic } from "./YearMosaic";
import { StreakStrip } from "./StreakStrip";
import { DayCounters } from "../ui/DayCounters";
import { AchievementTile } from "./AchievementTile";
import { LogSheet } from "../log/LogSheet";
import { Passport } from "../passport/Passport";
import { Expeditions } from "../expeditions/Expeditions";

export function CalendarHome() {
  const entries = useEntries();
  const counts = countsByDate(entries);
  const now = new Date();

  const [cursor, setCursor] = useState({ y: now.getFullYear(), m: now.getMonth() });
  // View is shared with the TopBar's squircle toggle (see lib/calendarView).
  const view = useCalendarView();
  const [selected, setSelected] = useState<string | null>(null);

  // Upcoming plans I'm part of, keyed by day — the home marks these on the grid.
  const planDays = usePlanDays();
  const planKeys = new Set(planDays.keys());

  // You can page FORWARD as far as your furthest plan (past that is empty diary, so
  // there's no reason to). Normally that's just the current month.
  const nowYM = now.getFullYear() * 12 + now.getMonth();
  const curYM = cursor.y * 12 + cursor.m;
  let lastYM = nowYM;
  for (const k of planKeys) {
    const d = parseKey(k);
    lastYM = Math.max(lastYM, d.getFullYear() * 12 + d.getMonth());
  }
  const canNext = curYM < lastYM;

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

      {/* Month view: the per-day quick-trackers (cigarettes, water…) for TODAY.
          Year view: a collectible tracker made no sense there, so it becomes the
          rotating achievement tile instead (item 8). */}
      {view === "month" ? (
        <DayCounters dateKey={todayKey()} className="mt-4" />
      ) : (
        <AchievementTile className="mt-4" />
      )}

      <div className="mt-8">
        {view === "month" ? (
          <MonthCalendar
            year={cursor.y}
            month={cursor.m}
            counts={counts}
            planKeys={planKeys}
            onSelect={setSelected}
            onPrev={() => step(-1)}
            onNext={() => step(1)}
            canNext={canNext}
          />
        ) : (
          <YearMosaic year={now.getFullYear()} counts={counts} onSelect={setSelected} />
        )}
      </div>

      {/* The collectible layer lives WITH the year mosaic (its companion, per the Passport's
          own intent): the palate map + its trophies, then tonight's expedition hand — the
          "explore" block, on the most-visible page. Month view stays the lean daily ritual. */}
      {view === "year" && (
        <>
          <Passport />
          <Expeditions />
        </>
      )}

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
          plans={planDays.get(selected)?.items ?? []}
          recentDrinks={recentDrinks(entries)}
          recentMoods={recentMoods(entries)}
          onClose={() => setSelected(null)}
        />
      )}
    </>
  );
}
