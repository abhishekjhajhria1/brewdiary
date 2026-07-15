import { MONTH_NAMES, WEEKDAYS, monthGrid } from "@/lib/date";
import { DayCell } from "./DayCell";

export function MonthCalendar({
  year,
  month,
  counts,
  planKeys,
  onSelect,
  onPrev,
  onNext,
  canNext,
}: {
  year: number;
  month: number;
  counts: Map<string, number>;
  /** Days with an upcoming plan I'm part of — marked, and tappable even in the future. */
  planKeys?: Set<string>;
  onSelect: (key: string) => void;
  onPrev: () => void;
  onNext: () => void;
  canNext: boolean;
}) {
  const grid = monthGrid(year, month);

  return (
    <section>
      <header className="mb-7 flex items-end justify-between">
        <h1 className="flex items-baseline gap-3">
          <span className="display text-ink">{MONTH_NAMES[month]}</span>
          <span className="label tnum">{year}</span>
        </h1>
        <nav className="flex items-center gap-1" aria-label="Change month">
          <NavButton label="Previous month" onClick={onPrev}>
            ‹
          </NavButton>
          <NavButton label="Next month" onClick={onNext} disabled={!canNext}>
            ›
          </NavButton>
        </nav>
      </header>

      <div className="glass rounded-tile p-4">
        <div className="mb-2 grid grid-cols-7 gap-1.5">
          {WEEKDAYS.map((w) => (
            <div key={w} className="label text-center">
              {w}
            </div>
          ))}
        </div>

        <div className="grid grid-cols-7 gap-1.5">
          {grid.map((day) => (
            <DayCell
              key={day.key}
              day={day}
              count={counts.get(day.key) ?? 0}
              hasPlan={planKeys?.has(day.key) ?? false}
              onSelect={onSelect}
            />
          ))}
        </div>
      </div>
    </section>
  );
}

function NavButton({
  label,
  onClick,
  disabled,
  children,
}: {
  label: string;
  onClick: () => void;
  disabled?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      disabled={disabled}
      className="flex h-11 w-11 items-center justify-center rounded-ctl text-xl leading-none text-muted transition-colors hover:bg-ink/5 hover:text-ink disabled:pointer-events-none disabled:opacity-30"
    >
      {children}
    </button>
  );
}
