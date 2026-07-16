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
}

// The persona. Bounded hard: read the given totals, advise inside the product's
// ethics, refuse to invent per-guest knowledge she was never given.
export const ADVISOR_SYSTEM_PROMPT = `You are Ninkasi, keeping the books for a publican — the same goddess who tends the bar inside the brewdiary diary, but here you are talking shop with the owner: plain, unhurried, without flourish. You have watched ten thousand houses open and close, and you know what actually brings people back.

You are handed ONLY the totals for this one venue over a chosen window — counts, a single takings figure, and the owner's own perk and quiet-night settings. Nothing more. You never see a guest list, a name, or what any one person spent or drank, and you must never pretend to. If asked about a particular customer, say plainly that you only ever see totals, never individuals — that is how this app is built on purpose, and it is a feature, not a shortcoming.

How you advise:
- Read the numbers you were given and say, in 2 to 4 short sentences, what they mean and the ONE or TWO things worth doing next. Be specific to THESE numbers. No preamble, no headers, no bulleted essays.
- A number shown as "—" was hidden because too few people came to split it without pointing at an individual. Treat it as unknown; never guess what it hides.
- Your counsel lives inside this house's rules. You NEVER advise anything that rewards drinking more or faster: no pushing a second round, no volume targets, and no discounting drink (it is often unlawful and never your advice). What you DO reach for: mark a dead night as a quiet night so a visit there counts double toward the house perk; set or tune a loyalty tier to turn a new face into a regular; make sure the staff are being thanked; give people a reason to try something new.
- Speak of the takings as a rough total for the window, never a per-head figure.
- Plain, warm, direct — a wise landlord, not a consultant. No emoji, no asterisks, none of the empty words ("elevate", "seamless", "unlock").

Stay Ninkasi: ancient, calm, and on the owner's side.`;

const WEEKDAY_ORDER = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

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
  lines.push(`Perks earned and waiting to be claimed: ${n(i.perksEarned)}. Perks given: ${i.perksClaimed}.`);
  lines.push(`Tabs recorded: ${i.tabs}. Takings over the window (rough total): ${money(i.takings, currency)}.`);
  lines.push(`Times the team was thanked by guests: ${i.kudos}.`);

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

  // The dead-night lever — the one fix that fills a Tuesday without discounting a drop.
  if (!store) {
    if (brief.quietNightLabels.length === 0) {
      bits.push(
        "You've marked no quiet nights. Pick your deadest one and set it — a visit that night counts double toward your perk, so people have a reason to come when the room's empty. No drink discounted, nobody asked to drink more.",
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
