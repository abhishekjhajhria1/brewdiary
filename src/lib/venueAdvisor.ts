// Ninkasi, keeping the books. The SAME goddess who tends the bar inside the diary
// (see lib/bartender.ts), but here she is talking shop with the publican — plain,
// practical, entirely on the owner's side.
//
// THE PRIVACY LINE (this is the whole point): she is only ever handed the AGGREGATE
// totals a manager can already read on the Insights panel — counts, one takings
// figure, the venue's own perk/quiet-night settings. No guest list, no name, no
// individual's spend or drink EVER reaches this model. A hidden split arrives as
// null (rendered "—") and stays unknown. So "AI insights on customers" here means
// "read my numbers and tell me what to do", never "profile a person" — the latter
// is a thing this product refuses to build (see the Insights note in VenueApp).
//
// Like bartender.ts this file is provider-agnostic and framework-free: persona +
// grounding. Without an AI key the route says so — there is no scripted stand-in.
import type { ChatMessage } from "./bartender";

export type { ChatMessage };

// Mirrors VenueInsights (lib/venues.ts) — nulls preserved, because a null is "hidden
// to protect an individual", which is NOT the same fact as 0.
export interface AdvisorInsights {
  rooms: number;
  guests: number;
  newGuests: number | null;
  returningGuests: number | null;
  quietVisits: number;
  otherVisits: number;
  perksEarned: number | null;
  perksClaimed: number;
  tabs: number;
  takings: number;
  kudos: number;
  visitsByDow: number[]; // index 0 = Sunday … 6 = Saturday (visit volume)
  prevGuests: number; // guests in the previous equal-length window
  prevTakings: number; // takings in the previous equal-length window
}

// The brief the client assembles from data it already holds. Everything here is the
// venue's OWN aggregate/config data — nothing about any individual guest.
export interface InsightBrief {
  venueName: string;
  kind: "bar" | "store";
  days: number;
  currency: string; // ISO code, for Intl formatting of the takings figure
  quietNightLabels: string[]; // e.g. ["Tue", "Wed"] — the owner's own setting
  perks: { reward: string; at: string }[]; // the venue's own live tiers, pre-labelled
  insights: AdvisorInsights;
  // The market layer: what CONSENTING drinkers in the venue's area log (k-anon ≥5,
  // counts only, no individuals). Optional — absent until there's a local pool.
  areaLabel?: string;
  areaTrends?: { kind: "drink" | "mood"; name: string; users: number }[];
}

// The persona. Bounded hard: read the given totals, advise inside the product's
// ethics, refuse to invent per-guest knowledge she was never given.
export const ADVISOR_SYSTEM_PROMPT = `You are Ninkasi, keeping the books for a publican — the same goddess who tends the bar inside the brewdiary diary, but here you are talking shop with the owner: plain, unhurried, without flourish. You have watched ten thousand houses open and close, and you know what actually brings people back.

You are handed ONLY the totals for this one venue over a chosen window — counts, a single takings figure, and the owner's own perk and quiet-night settings. You may ALSO be given a short list of what consenting drinkers in the venue's wider area have been logging lately: anonymous, counts only, with at least five different people behind every item. You never see a guest list, a name, or what any one person spent or drank, and you must never pretend to. If asked about a particular customer, say plainly that you only ever see totals, never individuals — that is how this app is built on purpose, and it is a feature, not a shortcoming.

How you advise:
- Read the numbers you were given and say, in 2 to 4 short sentences, what they mean and the ONE or TWO things worth doing next. Be specific to THESE numbers. No preamble, no headers, no bulleted essays.
- A number shown as "—" was hidden because too few people came to split it without pointing at an individual. Treat it as unknown; never guess what it hides.
- Your counsel lives inside this house's rules. You NEVER advise anything that rewards drinking more or faster: no pushing a second round, no volume targets, and no discounting drink (it is often unlawful and never your advice). What you DO reach for: mark a dead night as a quiet night so a visit there counts double toward the house perk; set or tune a loyalty tier to turn a new face into a regular; make sure the staff are being thanked; give people a reason to try something new; and when you're shown the area's taste, suggest what to feature, pour or stock to match the neighbourhood — an anonymous crowd's leaning, never a person's.
- Speak of the takings as a rough total for the window, never a per-head figure.
- Plain, warm, direct — a wise landlord, not a consultant. No emoji, no asterisks, none of the empty words ("elevate", "seamless", "unlock").

Stay Ninkasi: ancient, calm, and on the owner's side.`;

const WEEKDAY_ORDER = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const WEEKDAY_FULL = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const K_ANON = 5; // mirror public.k_anon() — below this, an average tab would leak one person

// Busiest / deadest weekday from the 7-slot visit-volume array. Deadest is the
// lowest weekday that saw ANY visit — a weekday with zero visits is "never open",
// a different story from "open but dead", and not what the quiet-night lever fixes.
export function peakDays(visitsByDow: number[]): { busiest: number | null; deadest: number | null } {
  if (!visitsByDow || visitsByDow.length < 7) return { busiest: null, deadest: null };
  let busiest: number | null = null;
  let deadest: number | null = null;
  for (let i = 0; i < 7; i++) {
    const v = visitsByDow[i] ?? 0;
    if (busiest === null || v > (visitsByDow[busiest] ?? 0)) busiest = i;
    if (v > 0 && (deadest === null || v < (visitsByDow[deadest] ?? 0))) deadest = i;
  }
  // If nothing was logged, there's no busiest either.
  if (busiest !== null && (visitsByDow[busiest] ?? 0) === 0) busiest = null;
  return { busiest, deadest };
}

/** Whole-number percent change vs a previous value; null when there's no base to compare. */
export function pctChange(current: number, previous: number): number | null {
  if (!previous || previous <= 0) return null;
  return Math.round(((current - previous) / previous) * 100);
}

function money(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return String(Math.round(amount));
  }
}

function n(x: number | null): string {
  return x === null ? "—" : String(x);
}

/** The compact, PII-free numbers block appended to the system prompt for grounding. */
export function summarizeInsights(brief: InsightBrief): string {
  const { insights: i, currency } = brief;
  const lines: string[] = [];
  lines.push(`Venue: ${brief.venueName} (${brief.kind === "store" ? "bottle shop" : "bar"}). Window: last ${brief.days} days.`);

  const quiet = [...brief.quietNightLabels].sort(
    (a, b) => WEEKDAY_ORDER.indexOf(a) - WEEKDAY_ORDER.indexOf(b),
  );
  lines.push(quiet.length ? `Quiet nights set: ${quiet.join(", ")}.` : `Quiet nights set: none.`);

  lines.push(
    brief.perks.length
      ? `Live perks: ${brief.perks.map((p) => `"${p.reward}" at ${p.at}`).join("; ")}.`
      : `Live perks: none set.`,
  );

  lines.push(
    brief.kind === "store"
      ? `Card punches (visits): ${i.guests}. New faces: ${n(i.newGuests)}. Returning: ${n(i.returningGuests)}.`
      : `Nights open: ${i.rooms}. Guests: ${i.guests}. New faces: ${n(i.newGuests)}. Regulars: ${n(i.returningGuests)}.`,
  );
  lines.push(`Visits on a quiet night: ${i.quietVisits}; on other nights: ${i.otherVisits}.`);

  // Busiest / deadest weekday — the lever into quiet nights.
  const { busiest, deadest } = peakDays(i.visitsByDow);
  if (busiest !== null || deadest !== null) {
    const parts: string[] = [];
    if (busiest !== null) parts.push(`busiest ${WEEKDAY_FULL[busiest]} (${i.visitsByDow[busiest]} visits)`);
    if (deadest !== null && deadest !== busiest) {
      const isQuiet = brief.quietNightLabels.includes(WEEKDAY_ORDER[deadest]);
      parts.push(
        `deadest ${WEEKDAY_FULL[deadest]} (${i.visitsByDow[deadest]} visits${isQuiet ? ", already marked quiet" : ", NOT marked quiet"})`,
      );
    }
    lines.push(`By weekday: ${parts.join("; ")}.`);
  }

  // Growth trend vs the previous equal-length window.
  const gPct = pctChange(i.guests, brief.insights.prevGuests);
  const tPct = pctChange(i.takings, brief.insights.prevTakings);
  const trend: string[] = [];
  if (gPct !== null) trend.push(`guests ${gPct >= 0 ? "up" : "down"} ${Math.abs(gPct)}% (${brief.insights.prevGuests} before)`);
  if (tPct !== null) trend.push(`takings ${tPct >= 0 ? "up" : "down"} ${Math.abs(tPct)}%`);
  if (trend.length) lines.push(`Versus the previous ${brief.days} days: ${trend.join(", ")}.`);

  // Return rate — derived from the k-anon-suppressed split, so it's only present
  // when it's safe to show. Speak of it as retention.
  if (i.returningGuests !== null && i.guests > 0) {
    lines.push(`Return rate: ${Math.round((i.returningGuests / i.guests) * 100)}% of guests had been before.`);
  }

  lines.push(`Perks earned and waiting to be claimed: ${n(i.perksEarned)}. Perks given: ${i.perksClaimed}.`);

  // Average tab only when there are enough tabs that it can't point at one person.
  const avgTab = i.tabs >= K_ANON ? `; average tab about ${money(i.takings / i.tabs, currency)}` : "";
  lines.push(`Tabs recorded: ${i.tabs}. Takings over the window (rough total): ${money(i.takings, currency)}${avgTab}.`);
  lines.push(`Times the team was thanked by guests: ${i.kudos}.`);

  // The area layer — anonymous neighbourhood taste (≥5 people behind each item).
  if (brief.areaTrends && brief.areaTrends.length) {
    const where = brief.areaLabel ? `in ${brief.areaLabel}` : "in this area";
    const drinks = brief.areaTrends.filter((t) => t.kind === "drink").map((t) => t.name).slice(0, 5);
    const moods = brief.areaTrends.filter((t) => t.kind === "mood").map((t) => t.name).slice(0, 4);
    const parts: string[] = [];
    if (drinks.length) parts.push(`drinks: ${drinks.join(", ")}`);
    if (moods.length) parts.push(`moods: ${moods.join(", ")}`);
    if (parts.length)
      lines.push(`What consenting drinkers ${where} have been logging lately (anonymous, counts only): ${parts.join("; ")}.`);
  }

  return `\n\nThe numbers for this venue (aggregate totals only — no individual is described here):\n${lines.join("\n")}`;
}

export const ADVISOR_STARTERS = [
  "Read my numbers — what should I do?",
  "How do I fill my quiet nights?",
  "Is my loyalty perk working?",
  "How do I turn new faces into regulars?",
];

