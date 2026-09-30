// Payroll (supabase/054): turn payroll_days() rows into the CSV an accountant opens, and
// the per-person totals. Twinned with mobile-bar/lib/logic/payroll.dart; both are held to
// one fixture (tests/fixtures/payroll.json), so the website and the venue app export the
// same file byte for byte.
//
// Money is added up in whole paise (cents), never as floating point. People are in NAME
// order — payroll is for pay, never a ranking. brewdiary reports hours and rates; overtime,
// tax and statutory deductions are the payroll provider's.

/** One person's day, as payroll_days() returns it. */
export interface PayrollDay {
  userId: string;
  name: string;
  /** 'left' for someone no longer on the team. */
  role: string;
  /** YYYY-MM-DD, in the venue's time zone. */
  day: string;
  shifts: number;
  firstIn: string | null;
  lastOut: string | null;
  workedMinutes: number;
  unpaidBreakMinutes: number;
  paidBreakMinutes: number;
  plannedMinutes: number;
  stillOn: boolean;
  corrected: boolean;
  hourlyRate: number | null;
  pay: number | null;
}

const num = (v: unknown): number => (typeof v === "number" ? v : Number(v ?? 0) || 0);
const numOrNull = (v: unknown): number | null => (v === null || v === undefined || v === "" ? null : num(v));

/** A payroll_days() row (snake_case, as PostgREST returns it). */
export function parsePayrollDay(r: Record<string, unknown>): PayrollDay {
  return {
    userId: String(r.user_id),
    name: (r.name as string) ?? "someone",
    role: (r.role as string) ?? "",
    day: String(r.day).slice(0, 10),
    shifts: num(r.shifts),
    firstIn: (r.first_in as string) ?? null,
    lastOut: (r.last_out as string) ?? null,
    workedMinutes: num(r.worked_minutes),
    unpaidBreakMinutes: num(r.unpaid_break_minutes),
    paidBreakMinutes: num(r.paid_break_minutes),
    plannedMinutes: num(r.planned_minutes),
    stillOn: r.still_on === true,
    corrected: r.corrected === true,
    hourlyRate: numOrNull(r.hourly_rate),
    pay: numOrNull(r.pay),
  };
}

/** Minutes as h:mm — "7:05", "0:45". */
export function hm(minutes: number): string {
  const m = Math.max(0, Math.trunc(minutes));
  return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`;
}

/** Minutes as decimal hours with two places, rounded half up: 425 → "7.08". */
export function hoursDecimal(minutes: number): string {
  const m = Math.max(0, Math.trunc(minutes));
  return cents(Math.floor((m * 100 + 30) / 60));
}

const toCents = (v: number): number => Math.round(v * 100);

function cents(c: number): string {
  const a = Math.abs(c);
  return `${c < 0 ? "-" : ""}${Math.floor(a / 100)}.${String(a % 100).padStart(2, "0")}`;
}

/** Plain code-unit order on the lower-cased name (the Dart twin's compareTo), then id. */
function byName(a: { name: string; userId: string }, b: { name: string; userId: string }): number {
  const x = a.name.toLowerCase();
  const y = b.name.toLowerCase();
  if (x !== y) return x < y ? -1 : 1;
  return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
}

/** One CSV field: quoted when it holds a comma, quote or line break; text a spreadsheet
 *  would run as a formula (=, +, -, @) is defused with a leading apostrophe. */
export function csvField(v: string): string {
  let s = v;
  if (s.length > 0 && "=+-@\t\r".includes(s[0])) s = `'${s}`;
  if (/[,"\n\r]/.test(s)) s = `"${s.replace(/"/g, '""')}"`;
  return s;
}

const row = (fields: string[]) => fields.map(csvField).join(",");

function notes(r: PayrollDay): string {
  return [
    r.corrected && "corrected",
    r.stillOn && "still on",
    r.workedMinutes === 0 && r.plannedMinutes > 0 && "planned, not worked",
    r.workedMinutes > 0 && r.pay === null && "no rate",
  ]
    .filter(Boolean)
    .join("; ");
}

export interface PayrollPerson {
  userId: string;
  name: string;
  role: string;
  daysWorked: number;
  workedMinutes: number;
  plannedMinutes: number;
  /** null only when nothing worked had a rate */
  payCents: number | null;
  missingRate: boolean;
  rate: number | null;
}

/** Totals per person, in name order. */
export function payrollTotals(rows: PayrollDay[]): PayrollPerson[] {
  const by = new Map<string, PayrollDay[]>();
  for (const r of rows) by.set(r.userId, [...(by.get(r.userId) ?? []), r]);
  const out: PayrollPerson[] = [];
  for (const [userId, list] of by) {
    const days = [...list].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
    const worked = days.filter((d) => d.workedMinutes > 0);
    const paid = worked.filter((d) => d.pay !== null);
    const rated = days.filter((d) => d.hourlyRate !== null);
    out.push({
      userId,
      name: days[0].name,
      role: days[days.length - 1].role,
      daysWorked: worked.length,
      workedMinutes: days.reduce((n, d) => n + d.workedMinutes, 0),
      plannedMinutes: days.reduce((n, d) => n + d.plannedMinutes, 0),
      payCents: paid.length === 0 ? null : paid.reduce((n, d) => n + toCents(d.pay as number), 0),
      missingRate: worked.length !== paid.length,
      rate: rated.length === 0 ? null : (rated[rated.length - 1].hourlyRate as number),
    });
  }
  return out.sort(byName);
}

/** The whole period's pay, in paise, across everyone with a rate. */
export function payrollTotalCents(people: PayrollPerson[]): number {
  return people.reduce((n, p) => n + (p.payCents ?? 0), 0);
}

/** The CSV: a heading line, one row per person per day, then each person's totals and the
 *  team's. Numbers use a dot and two decimals so any spreadsheet reads them. */
export function payrollCsv(o: { venue: string; currency: string; from: string; to: string; rows: PayrollDay[] }): string {
  const sorted = [...o.rows].sort((a, b) => byName(a, b) || (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
  const lines: string[] = [
    row(["Payroll", o.venue, o.from, o.to, o.currency]),
    "",
    row(["Name", "Role", "Date", "Shifts", "First in", "Last out", "Worked (h:mm)", "Worked (hours)", "Unpaid breaks (min)",
      "Paid breaks (min)", "Planned (h:mm)", "Rate per hour", "Pay", "Notes"]),
    ...sorted.map((r) =>
      row([
        r.name,
        r.role,
        r.day,
        String(r.shifts),
        r.firstIn ?? "",
        r.lastOut ?? "",
        hm(r.workedMinutes),
        hoursDecimal(r.workedMinutes),
        String(r.unpaidBreakMinutes),
        String(r.paidBreakMinutes),
        hm(r.plannedMinutes),
        r.hourlyRate === null ? "" : cents(toCents(r.hourlyRate)),
        r.pay === null ? "" : cents(toCents(r.pay)),
        notes(r),
      ]),
    ),
    "",
    row(["Totals", "Role", "Days worked", "Worked (h:mm)", "Worked (hours)", "Planned (h:mm)", "Rate per hour", "Pay", "Notes"]),
  ];
  const people = payrollTotals(o.rows);
  for (const p of people) {
    lines.push(
      row([
        p.name,
        p.role,
        String(p.daysWorked),
        hm(p.workedMinutes),
        hoursDecimal(p.workedMinutes),
        hm(p.plannedMinutes),
        p.rate === null ? "" : cents(toCents(p.rate)),
        p.payCents === null ? "" : cents(p.payCents),
        p.payCents === null && p.workedMinutes > 0 ? "no rate set" : p.missingRate ? "no rate for some days" : "",
      ]),
    );
  }
  const worked = people.reduce((n, p) => n + p.workedMinutes, 0);
  const planned = people.reduce((n, p) => n + p.plannedMinutes, 0);
  lines.push(row(["Team", "", "", hm(worked), hoursDecimal(worked), hm(planned), "", cents(payrollTotalCents(people)), ""]));
  return `${lines.join("\n")}\n`;
}

// ── periods, the file, the venue's clock ─────────────────────────────────────

/** The periods offered. A current period stops at today: payroll pays for time worked, so
 *  days still to come aren't in it. (Twin of PayPeriod in payroll.dart.) */
export const PAY_PERIODS = [
  { id: "thisWeek", label: "This week" },
  { id: "lastWeek", label: "Last week" },
  { id: "thisMonth", label: "This month" },
  { id: "lastMonth", label: "Last month" },
] as const;
export type PayPeriod = (typeof PAY_PERIODS)[number]["id"];

const utc = (day: string): Date => new Date(`${day}T00:00:00Z`);
const iso = (d: Date): string => d.toISOString().slice(0, 10);
const addDays = (day: string, n: number): string => {
  const d = utc(day);
  d.setUTCDate(d.getUTCDate() + n);
  return iso(d);
};

/** [first, last] day of [p] (both included, YYYY-MM-DD) for a venue whose today is [today]. */
export function payPeriod(p: PayPeriod, today: string): [string, string] {
  const t = utc(today);
  const monday = addDays(today, -((t.getUTCDay() + 6) % 7));
  const y = t.getUTCFullYear();
  const m = t.getUTCMonth();
  switch (p) {
    case "thisWeek":
      return [monday, today];
    case "lastWeek":
      return [addDays(monday, -7), addDays(monday, -1)];
    case "thisMonth":
      return [iso(new Date(Date.UTC(y, m, 1))), today];
    case "lastMonth":
      return [iso(new Date(Date.UTC(y, m - 1, 1))), iso(new Date(Date.UTC(y, m, 0)))];
  }
}

/** Today's date where the venue is (the browser may be somewhere else). */
export function todayIn(tz: string, now: Date = new Date()): string {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
  } catch {
    return iso(now);
  }
}

/** "payroll-the-gin-room-2026-09-01-to-2026-09-30.csv" (twin of payrollFileName in Dart). */
export function payrollFileName(venue: string, from: string, to: string): string {
  let slug = venue.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  if (slug.length > 40) slug = slug.slice(0, 40).replace(/-+$/, "");
  return `payroll-${slug || "venue"}-${from}-to-${to}.csv`;
}

/** The file's text: a byte-order mark first, so Excel reads names in any script as UTF-8
 *  (without it, Excel on Windows guesses a legacy code page and mangles them). */
export const payrollFileText = (csv: string): string => `﻿${csv}`;

/** The time zone a venue's days are counted in — the venue's, not the viewer's. A country
 *  with one zone maps straight; a wide one by state where we know it; UTC otherwise (the
 *  database accepts only a real zone name). Twin of venueTimeZone in the venue app's
 *  logic/area.dart, held to the same cases. */
export function venueTimeZone(country: string, region?: string | null): string {
  const c = country.toUpperCase();
  if (c === "US") {
    const r = (region ?? "").toUpperCase();
    if (["NY", "MA", "NJ", "PA", "FL", "GA", "DC", "MD", "VA", "NC", "SC", "OH", "MI", "CT", "RI", "VT", "NH", "ME", "DE"].includes(r)) return "America/New_York";
    if (["IL", "TX", "MN", "WI", "MO", "LA", "TN", "AL", "MS", "IA", "OK", "KS", "AR", "NE"].includes(r)) return "America/Chicago";
    if (["CO", "UT", "NM", "MT", "WY", "ID"].includes(r)) return "America/Denver";
    if (r === "AZ") return "America/Phoenix";
    if (r === "HI") return "Pacific/Honolulu";
    if (r === "AK") return "America/Anchorage";
    return "America/Los_Angeles";
  }
  const zones: Record<string, string> = {
    IN: "Asia/Kolkata", GB: "Europe/London", IE: "Europe/Dublin", FR: "Europe/Paris",
    DE: "Europe/Berlin", ES: "Europe/Madrid", IT: "Europe/Rome", NL: "Europe/Amsterdam",
    PT: "Europe/Lisbon", BE: "Europe/Brussels", AT: "Europe/Vienna", PL: "Europe/Warsaw",
    SE: "Europe/Stockholm", NO: "Europe/Oslo", DK: "Europe/Copenhagen", FI: "Europe/Helsinki",
    CH: "Europe/Zurich", TR: "Europe/Istanbul", AE: "Asia/Dubai", SG: "Asia/Singapore",
    TH: "Asia/Bangkok", JP: "Asia/Tokyo", KR: "Asia/Seoul", ZA: "Africa/Johannesburg",
    NZ: "Pacific/Auckland", LK: "Asia/Colombo", NP: "Asia/Kathmandu", SA: "Asia/Riyadh",
  };
  return zones[c] ?? "UTC";
}

/** Minutes for the screen: "7h 05m", "45m", "0m" (twin of formatMinutes in the venue app). */
export function minutesWords(minutes: number): string {
  if (minutes <= 0) return "0m";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${String(m).padStart(2, "0")}m`;
}
