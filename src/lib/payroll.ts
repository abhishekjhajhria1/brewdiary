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
