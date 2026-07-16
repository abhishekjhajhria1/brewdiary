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
// grounding + a scripted fallback so the feature is alive before an AI key exists.
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

/**
 * Scripted advice when no AI key is configured — deterministic, on-brand, and useful
 * on its own. Rule-based over the same aggregates; nudges toward the levers that don't
 * reward drinking more (quiet nights, a first perk tier, honouring earned perks, thanks).
 */
export function fallbackAdvice(brief: InsightBrief): string {
  const i = brief.insights;
  const store = brief.kind === "store";
  const bits: string[] = [];

  if (i.guests === 0) {
    return store
      ? "No card punches yet in this window, love. Once you're verified, find a regular at the till and punch their card — a visit a day, and the reward you promised does the rest."
      : "A quiet stretch — no guests logged in this window. Open a room, put the code on the tables, and let your bartenders hand out a good word as they serve. The numbers will come once the room does.";
  }

  // Trend first — "are we growing" is the question an owner opens the dashboard with.
  const gPct = pctChange(i.guests, i.prevGuests);
  if (gPct !== null && gPct <= -20) {
    bits.push(
      `Fewer people than the ${brief.days} days before — down about ${Math.abs(gPct)}%. Before anything fancy, lean on the regulars: make sure every earned perk gets honoured, and give a dead night a reason to fill.`,
    );
  } else if (gPct !== null && gPct >= 25) {
    bits.push(
      `Up about ${gPct}% on the previous ${brief.days} days — whatever you're doing, it's working. Lock it in with a perk so this month's new faces have a reason to make it three visits, not one.`,
    );
  }

  // The dead-night lever — now it can name the actual deadest weekday from the data.
  if (!store) {
    const { deadest } = peakDays(i.visitsByDow);
    const deadLabel = deadest !== null ? WEEKDAY_FULL[deadest] : null;
    const deadIsMarked = deadest !== null && brief.quietNightLabels.includes(WEEKDAY_ORDER[deadest]);

    if (deadLabel && !deadIsMarked) {
      bits.push(
        `${deadLabel} is your quietest night and it isn't marked quiet. Set it under Perks — a visit that ${deadLabel} then counts double toward the house perk, so people have a reason to come when the room's empty. No drink discounted, nobody asked to drink more.`,
      );
    } else if (brief.quietNightLabels.length === 0) {
      bits.push(
        "You've marked no quiet nights. Pick your deadest one and set it — a visit that night counts double toward your perk, so the empty nights have a pull. No drink discounted, nobody asked to drink more.",
      );
    } else if (i.quietVisits === 0 && i.otherVisits > 0) {
      bits.push(
        `Your quiet-night boost is on but nobody's used it yet. Say it out loud where they'll see it — "come ${brief.quietNightLabels.join(" or ")}, your visit counts double." A boost nobody knows about does nothing.`,
      );
    }
  }

  // Is there even a reason to come back?
  if (brief.perks.length === 0) {
    bits.push(
      "You've no house perk set. A small one — five visits, a free coffee — is the whole reason a face becomes a regular. Set one under Perks and give them something to chase.",
    );
  } else if (i.perksEarned !== null && i.perksEarned > 0) {
    bits.push(
      `${i.perksEarned} ${i.perksEarned === 1 ? "guest has" : "guests have"} earned a perk and not claimed it. Next time they're in, hand it over — a promise kept is what brings the third visit and the fourth.`,
    );
  }

  // Convert new faces into regulars, when the split is visible.
  if (i.newGuests !== null && i.returningGuests !== null && i.newGuests > i.returningGuests && i.newGuests >= 3) {
    bits.push(
      "Plenty of new faces, fewer coming back. That's a first-tier perk's job — make the reward for the second or third visit easy to reach, so the first visit isn't the last.",
    );
  }

  // The kindness lever.
  if (!store && i.kudos === 0 && i.guests >= 3) {
    bits.push(
      "Nobody's thanked your team yet. Remind the room they can — a guest tapping a bartender's name to say thanks costs you nothing and keeps good staff longer than a raise sometimes does.",
    );
  }

  // The neighbourhood nudge — only when there's a real local pool behind it.
  const areaDrinks = (brief.areaTrends ?? []).filter((t) => t.kind === "drink").map((t) => t.name).slice(0, 3);
  if (areaDrinks.length) {
    const where = brief.areaLabel ? `around ${brief.areaLabel}` : "around here";
    bits.push(
      `${areaDrinks.join(", ")} ${areaDrinks.length === 1 ? "is" : "are"} what drinkers ${where} have been logging lately. If it's not already on your list, a night built around one of those is an easy pull — the neighbourhood's already reaching for it.`,
    );
  }

  if (bits.length === 0) {
    bits.push(
      store
        ? "Steady numbers. Keep the card honest — one punch per person per day — and make sure the reward's worth the walk back. That's the whole game at a shop."
        : "Steady numbers, nothing crying out. Keep honouring the perks people earn, keep a dead night marked quiet, and let the staff be thanked. The regulars build themselves from there.",
    );
  }

  // Two nudges at most — a wall of advice is advice nobody acts on.
  return bits.slice(0, 2).join(" ");
}

/** Note shown in the UI when running on the scripted fallback (no key yet). */
export const ADVISOR_OFFLINE_NOTE =
  "Add an AI key (AI_API_KEY) and Ninkasi reads your numbers herself — she's advising from the ledger for now.";
