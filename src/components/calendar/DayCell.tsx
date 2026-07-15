import clsx from "clsx";
import type { GridDay } from "@/lib/date";
import { intensityLevel } from "@/lib/derive";

const FILL = [
  "transparent",
  "var(--cell-1)",
  "var(--cell-2)",
  "var(--cell-3)",
  "var(--cell-4)",
] as const;

export function DayCell({
  day,
  count,
  hasPlan = false,
  onSelect,
}: {
  day: GridDay;
  count: number;
  /** An upcoming plan I'm part of sits on this day — mark it, and let it be tapped
   *  (plans are in the future, which is otherwise non-interactive). */
  hasPlan?: boolean;
  onSelect: (key: string) => void;
}) {
  const level = intensityLevel(count);
  const interactive = !day.isFuture || hasPlan;
  // The gentle month ramp (max ~33%) keeps the date number legible in BOTH themes,
  // so no theme-dependent text-colour flip is needed.

  return (
    <button
      type="button"
      disabled={!interactive}
      onClick={() => onSelect(day.key)}
      aria-label={`${day.key}${count ? `, ${count} logged` : ", nothing logged yet"}${hasPlan ? ", a plan" : ""}`}
      className={clsx(
        "relative flex aspect-square select-none items-start justify-start rounded-cell p-1.5 transition-[background,box-shadow] duration-200 sm:p-2",
        interactive
          ? "cursor-pointer hover:shadow-[inset_0_0_0_1px_var(--color-line-strong)]"
          : "cursor-default",
        level === 0 && day.inMonth && "shadow-[inset_0_0_0_1px_var(--color-line)]",
      )}
      style={{ background: FILL[level] }}
    >
      <span
        className={clsx(
          "tnum text-[11px] leading-none sm:text-xs",
          day.isToday && "font-semibold",
          day.inMonth ? "text-ink" : "text-faint",
          day.isFuture && "text-faint",
        )}
      >
        {day.date.getDate()}
      </span>

      {count > 1 && (
        <span
          className="tnum absolute bottom-1 right-1.5 text-[9px] leading-none text-muted"
          aria-hidden
        >
          {count}
        </span>
      )}

      {hasPlan && (
        <span aria-hidden className="absolute bottom-1 left-1.5 h-1.5 w-1.5 rounded-full bg-accent" />
      )}

      {day.isToday && (
        <span
          aria-hidden
          className="pointer-events-none absolute inset-0 rounded-cell shadow-[inset_0_0_0_1.5px_var(--color-accent)]"
        />
      )}
    </button>
  );
}
