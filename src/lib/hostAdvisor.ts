// Ninkasi for hosts — the shift companion for a venue's team (/api/host-ai). The twin of
// mobile-bar/lib/logic/host_brief.dart: the same brief, the same briefing rules, the same
// scripted answers when the AI is off. tests/hostAdvisor.test.ts and the Dart logic tests
// check the same cases.
//
// The brief holds only what the person's own role can already see, and only counts:
// never a guest's name, never what one person had or spent. So the model stays a
// stateless text function, and nothing it says can be about a person.

export interface HostSignal {
  kind: string;
  title: string;
  startsOn?: string; // YYYY-MM-DD
  endsOn?: string;
  where: string;
}

export interface HostBrief {
  venueName: string;
  kind: string;
  role: string;
  sellsAlcohol: boolean;
  counter: boolean;
  today: string; // YYYY-MM-DD, the venue's day
  roomOpen: boolean;
  canOpenRoom: boolean;
  guestsIn: number | null;
  quietTonight: boolean;
  soldOut: string[];
  alcoholFree: string[];
  menuItems: number;
  perks: { reward: string; at: string }[];
  signals: HostSignal[];
  area: string[];
}

export type ChatMessage = { role: "user" | "assistant"; content: string };

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const ROLES = ["owner", "manager", "supervisor", "bartender", "server", "host", "kitchen"];

/** Trust nothing from the wire: keep the known shape, cap every list and string. */
export function coerceHostBrief(raw: unknown): HostBrief | null {
  if (typeof raw !== "object" || raw === null) return null;
  const b = raw as Record<string, unknown>;
  const str = (x: unknown, cap = 80) => (typeof x === "string" ? x.replace(/\s+/g, " ").trim().slice(0, cap) : "");
  const strs = (x: unknown, n: number, cap = 80) => (Array.isArray(x) ? x.map((s) => str(s, cap)).filter(Boolean).slice(0, n) : []);
  const today = str(b.today, 10);
  if (!DAY.test(today)) return null;
  const guests = typeof b.guestsIn === "number" && Number.isFinite(b.guestsIn) && b.guestsIn >= 0 ? Math.floor(b.guestsIn) : null;
  return {
    venueName: str(b.venueName) || "this venue",
    kind: str(b.kind, 20) || "bar",
    role: ROLES.includes(str(b.role, 20)) ? str(b.role, 20) : "server",
    sellsAlcohol: b.sellsAlcohol === true,
    counter: b.counter === true,
    today,
    roomOpen: b.roomOpen === true,
    canOpenRoom: b.canOpenRoom === true,
    guestsIn: guests,
    quietTonight: b.quietTonight === true,
    soldOut: strs(b.soldOut, 20, 60),
    alcoholFree: strs(b.alcoholFree, 10, 60),
    menuItems: typeof b.menuItems === "number" && Number.isFinite(b.menuItems) ? Math.max(0, Math.floor(b.menuItems)) : 0,
    perks: (Array.isArray(b.perks) ? b.perks : [])
      .filter((p): p is Record<string, unknown> => typeof p === "object" && p !== null)
      .slice(0, 3)
      .map((p) => ({ reward: str(p.reward, 60), at: str(p.at, 40) })),
    signals: (Array.isArray(b.signals) ? b.signals : [])
      .filter((s): s is Record<string, unknown> => typeof s === "object" && s !== null)
      .slice(0, 10)
      .map((s) => ({
        kind: str(s.kind, 20),
        title: str(s.title, 140),
        startsOn: DAY.test(str(s.startsOn, 10)) ? str(s.startsOn, 10) : undefined,
        endsOn: DAY.test(str(s.endsOn, 10)) ? str(s.endsOn, 10) : undefined,
        where: str(s.where, 40),
      }))
      .filter((s) => s.title),
    area: strs(b.area, 8, 200),
  };
}

const days = (from: string, to: string) => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
const isDryDay = (s: HostSignal) => s.kind === "holiday" && /\bdry\b/i.test(s.title);
const list = (xs: string[]) => (xs.length <= 1 ? xs.join("") : `${xs.slice(0, -1).join(", ")} and ${xs[xs.length - 1]}`);

function when(today: string, d?: string): string {
  if (!d) return "";
  const n = days(today, d);
  if (n <= 0) return "today";
  if (n === 1) return "tomorrow";
  const wd = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  return n < 7 ? `on ${wd[new Date(`${d}T00:00:00Z`).getUTCDay()]}` : `in ${n} days`;
}

/** The briefing, most urgent first — the same rules as hostBriefing() in Dart. */
export function hostBriefing(b: HostBrief): string[] {
  const lines: string[] = [];

  for (const s of b.signals) {
    if (!isDryDay(s) || !s.startsOn) continue;
    const n = days(b.today, s.startsOn);
    const ongoing = n <= 0 && (!s.endsOn || days(b.today, s.endsOn) >= 0);
    if (ongoing && b.sellsAlcohol) lines.push(`Today is a dry day (${s.title}): no alcohol may be sold. Lead with the alcohol-free list.`);
    else if (n === 1 && b.sellsAlcohol) lines.push(`Tomorrow is a dry day (${s.title}) — let regulars know tonight.`);
  }

  if (b.counter) lines.push("The till is ready — punch cards once a day per guest.");
  else if (b.roomOpen) {
    const g = b.guestsIn;
    lines.push(`Tonight's room is open${g === null ? "" : g === 0 ? " — no one has joined yet" : `, ${g} ${g === 1 ? "guest" : "guests"} in`}.`);
  } else {
    lines.push(b.canOpenRoom ? "No room open yet — open tonight's room so guests can join from the table." : "No room open yet — ask a manager to open tonight's room.");
  }
  if (b.quietTonight && b.perks.length) {
    lines.push("It's a quiet night: a visit counts double toward the card. Worth a word to regulars — it's a visit, not a drink, that counts.");
  }

  if (b.soldOut.length) {
    lines.push(`86'd: ${list(b.soldOut.slice(0, 5))}${b.soldOut.length > 5 ? ` and ${b.soldOut.length - 5} more` : ""}. Say so before they order.`);
  }
  if (b.sellsAlcohol) {
    if (b.alcoholFree.length) lines.push(`Alcohol-free tonight: ${list(b.alcoholFree.slice(0, 3))}. Offer one with every recommendation.`);
    else if (b.menuItems > 0) lines.push("Nothing alcohol-free on the menu — add at least one (Menu).");
  }

  const soon = b.signals.filter(
    (s) => !isDryDay(s) && (s.startsOn ? days(b.today, s.startsOn) <= 3 : s.kind !== "price" && s.kind !== "venue"),
  );
  for (const s of soon.slice(0, 2)) {
    const w = when(b.today, s.startsOn);
    lines.push(`Around you: ${s.title}${w ? ` (${w}${s.where ? `, ${s.where}` : ""})` : ""}.`);
  }
  lines.push(...b.area.slice(0, 2));

  if (b.sellsAlcohol && !b.counter) {
    lines.push("Water is free and on every table. If someone's had enough, stop serving alcohol, offer water and food, and get the manager.");
  }
  return lines;
}

/** Scripted answers for when the AI is off — the same as hostFallbackAnswer() in Dart. */
export function hostFallbackAnswer(b: HostBrief, question: string): string {
  const q = question.toLowerCase();
  if (/enough|drunk|cut off/.test(q)) {
    return "Stop serving them alcohol — calmly, and without an audience. Offer water and something to eat, bring in the manager, and help them get home safely (a cab, a friend). Never argue, and never make it about them as a person. Nothing goes on their card.";
  }
  if (/alcohol-free|zero|mocktail/.test(q)) {
    return b.alcoholFree.length
      ? `Tonight: ${list(b.alcoholFree)}. Mention one with every recommendation — lots of people want one and don't ask.`
      : "There's nothing marked alcohol-free on the menu yet. Water is always free; ask a manager to add a proper zero-proof option.";
  }
  if (/around|event|nearby/.test(q)) {
    const s = b.signals.filter((x) => !isDryDay(x)).slice(0, 3);
    return s.length
      ? s.map((x) => `${x.title}${x.startsOn ? ` (${when(b.today, x.startsOn)})` : ""}`).join(". ")
      : "Nothing listed around you right now. Events, openings and dry days show here as they come in.";
  }
  if (/card|loyalty|perk|reward/.test(q)) {
    if (!b.perks.length) return "This venue doesn't run a loyalty card yet — a manager can set one up in More › Loyalty card.";
    const p = b.perks[0];
    return `Each visit counts toward the card: ${p.reward} after ${p.at}. Guests see their progress in their own app; staff hand the reward over from the guest's card. It's visits that count — never how much anyone drinks.`;
  }
  return `I can't reach the full Ninkasi right now. Here's the briefing: ${hostBriefing(b).slice(0, 3).join(" ")}`;
}

export const HOST_SYSTEM_PROMPT = `You are Ninkasi, the calm, experienced shift companion for the team at a venue on brewdiary. You talk to one member of staff at a time; their role is given below. Answer like a good shift lead: short, practical, kind, in plain words. Two to five sentences unless asked for more.

What you know is the briefing below: tonight's state, the menu, the loyalty card, public facts about the area, and (for managers) anonymous area trends. You know nothing about any individual guest and must never pretend to.

Rules you never break:
- Never suggest selling more alcohol, another round, upselling, bigger measures, happy hours, discounts on drinks or anything that rewards drinking more. Recommend what fits, and always offer an alcohol-free option next to any drink suggestion.
- Never comment on how much any guest has had, and never guess anyone's age, gender, religion, caste, origin or anything like it. If asked to profile a guest, decline and explain the venue only sees what guests choose to share.
- If someone has had enough: stop serving them alcohol calmly, offer water and food, involve the manager, help them get home safely. Never argue or shame.
- On a dry day, no alcohol may be sold at all — say so plainly.
- On law, licences, tax or safety specifics, give the general rule and say to check with the manager or local rules; don't invent regulations.
- If the question is outside the shift, the venue, the menu or the area, say briefly that you're here for the shift.

Today's briefing:
`;

/** The brief as plain lines for the system prompt. */
export function summarizeHostBrief(b: HostBrief): string {
  const role = b.role === "kitchen" ? "the kitchen" : `a ${b.role}`;
  const out = [
    `Venue: ${b.venueName} (${b.kind.replace("_", " ")}${b.sellsAlcohol ? ", sells alcohol" : ", sells no alcohol"}). Talking to ${role}. Today: ${b.today}.`,
    ...hostBriefing(b).map((l) => `- ${l}`),
  ];
  if (b.perks.length) out.push(`Loyalty card: ${b.perks.map((p) => `${p.reward} after ${p.at}`).join("; ")}.`);
  const later = b.signals.filter((s) => s.startsOn && days(b.today, s.startsOn) > 3).slice(0, 4);
  if (later.length) out.push(`Later: ${later.map((s) => `${s.title} (${s.startsOn})`).join("; ")}.`);
  return out.join("\n");
}
