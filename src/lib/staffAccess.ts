// Staff access (supabase/053): the words and small rules around adding an employee with
// the owner's code, and a paused person. Twinned with mobile-bar/lib/logic/staff.dart —
// the same cases are tested on both sides (tests/staffAccess.test.ts, mobile-bar/test/
// staff_test.dart) — so the website and the venue app say the same thing. The DATABASE
// decides who may do what; this only says it plainly.

/** Waiting for a manager's yes, working, or paused. */
export type StaffStatus = "pending" | "active" | "locked";

/** Anything unknown reads as active: a database a migration behind has no status yet. */
export function parseStaffStatus(s: unknown): StaffStatus {
  return s === "pending" || s === "locked" ? s : "active";
}

/** Why the owner's code didn't let someone in (claim_staff_enrolment's `error`). */
export const CLAIM_ERRORS = ["not_found", "closed", "expired", "too_many", "wrong_code", "locked"] as const;
export type ClaimError = (typeof CLAIM_ERRORS)[number];

export function parseClaimError(s: unknown): ClaimError {
  return (CLAIM_ERRORS as readonly unknown[]).includes(s) ? (s as ClaimError) : "not_found";
}

/** The sentence for a code that didn't work. `left` is the tries left after a wrong one. */
export function claimMessage(e: ClaimError, left?: number | null, addedBy?: string | null): string {
  const who = addedBy && addedBy.trim() ? addedBy.trim() : "your manager";
  switch (e) {
    case "wrong_code":
      return left == null
        ? `That's not the code — check it with ${who}.`
        : `That's not the code — ${left === 1 ? "1 try" : `${left} tries`} left.`;
    case "too_many":
      return `Too many wrong tries — ask ${who} for a new code.`;
    case "expired":
      return `That code has run out — ask ${who} for a new one.`;
    case "closed":
      return `That code was replaced or cancelled — ask ${who} for the new one.`;
    case "not_found":
      return `That code isn't for this account — sign in with the email ${who} added.`;
    case "locked":
      return `Your access here is paused — talk to ${who}.`;
  }
}

/** The code as typed: digits only, at most six (a pasted "482 913" still works). */
export function codeDigits(typed: string): string {
  return typed.replace(/\D/g, "").slice(0, 6);
}

// The same shapes the database checks (enrol_staff, set_staff_details), so a form can say
// what's wrong before it asks.
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PHONE = /^\+?[0-9 ()-]{6,20}$/;
export function validStaffEmail(s: string): boolean {
  const t = s.trim();
  return t.length <= 254 && EMAIL.test(t);
}
export function validStaffPhone(s: string): boolean {
  return PHONE.test(s.trim());
}

/** "a server", "an owner", "kitchen staff" — a role word in a sentence. */
export function roleWithArticle(roleWord: string): string {
  const w = roleWord.trim().toLowerCase();
  if (w === "kitchen") return "kitchen staff";
  return `${/^[aeiou]/.test(w) ? "an" : "a"} ${w}`;
}

/** What the employee is sent, with the code in it. The code only works with `email`. */
export function enrolShareText(o: { venue: string; roleWord: string; email: string; code: string; hours?: number }): string {
  return (
    `You've been added to ${o.venue} on brewdiary bar as ${roleWithArticle(o.roleWord)}. ` +
    `Install brewdiary bar, sign in with ${o.email}, and type this code: ${o.code}. It works for ${o.hours ?? 48} hours, once.`
  );
}

/** "Please report to Arjun (manager)." — or a plain line when nobody was named. */
export function reportLine(reportTo?: string | null, reportToRole?: string | null): string {
  const who = reportTo?.trim() ?? "";
  if (!who) return "Please talk to the owner or a manager.";
  return `Please report to ${who}${reportToRole ? ` (${reportToRole})` : ""}.`;
}

/** "runs out in 31h" / "runs out in 40 min" / "ran out". */
export function codeLifeLeft(expiresAt: Date, now: Date): string {
  const mins = Math.floor((expiresAt.getTime() - now.getTime()) / 60_000);
  if (mins <= 0) return "ran out";
  if (mins < 60) return `runs out in ${mins} min`;
  return `runs out in ${Math.floor(mins / 60)}h`;
}
