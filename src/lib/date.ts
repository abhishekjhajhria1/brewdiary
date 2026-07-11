// Date helpers. Keys are local-time YYYY-MM-DD so "the day it's for" matches the user's calendar.

export function toKey(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function parseKey(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function todayKey(): string {
  return toKey(new Date());
}

export function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

export function addMonths(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth() + n, 1);
}

export function isSameDay(a: Date, b: Date): boolean {
  return toKey(a) === toKey(b);
}

export const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

// Monday-first weekday labels (Swiss / ISO).
export const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export interface GridDay {
  date: Date;
  key: string;
  inMonth: boolean;
  isToday: boolean;
  isFuture: boolean;
}

/** A Monday-first 6-row grid covering the given month, padded with adjacent days. */
export function monthGrid(year: number, month: number): GridDay[] {
  const first = new Date(year, month, 1);
  // JS getDay: 0=Sun..6=Sat. Convert to Monday-first index 0=Mon..6=Sun.
  const lead = (first.getDay() + 6) % 7;
  const start = addDays(first, -lead);
  const todayK = todayKey();
  const todayDate = new Date();
  todayDate.setHours(0, 0, 0, 0);

  const days: GridDay[] = [];
  for (let i = 0; i < 42; i++) {
    const date = addDays(start, i);
    const key = toKey(date);
    days.push({
      date,
      key,
      inMonth: date.getMonth() === month,
      isToday: key === todayK,
      isFuture: date.getTime() > todayDate.getTime(),
    });
  }
  return days;
}

export function formatDayLong(key: string): string {
  const d = parseKey(key);
  return `${MONTH_NAMES[d.getMonth()]} ${d.getDate()}`;
}

export function timeOfDayLabel(iso: string): string {
  const h = new Date(iso).getHours();
  if (h < 5) return "Late night";
  if (h < 11) return "Morning";
  if (h < 15) return "Midday";
  if (h < 18) return "Afternoon";
  if (h < 22) return "Evening";
  return "Nightcap";
}
