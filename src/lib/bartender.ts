// Mistress Ninkasi — the diary's bartender. Named for the Sumerian goddess of
// brewing, who fermented for the gods. Persona lives in SYSTEM_PROMPT (a "cooked"
// character on top of any base model). Provider-agnostic: any OpenAI-compatible chat
// API (xAI Grok, Gemini, OpenAI, DeepSeek, Groq, Together…). No Claude/Anthropic here
// by design — see internal/done/PROGRESS.md (cost decision). The route handler picks the
// provider from env; this file holds the persona, context grounding, and the no-key
// fallback so she's alive before a key is added.

export const NINKASI_NAME = "Ninkasi";

export interface BartenderContext {
  recentDrinks?: string[];
  moods?: string[];
  total?: number;
  /** what this guest's FRIENDS have been sharing (data the guest can already see) */
  friendsPouring?: string[];
  /** k-anonymous trends across consenting users — counts only, no names attached */
  trending?: string[];
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

// The persona. Rich enough that a base model "becomes" Ninkasi; bounded enough that
// she stays useful, short, and responsible. This is the artifact you keep tuning —
// and the same system line that prefixes every saved training sample (lib/training.ts),
// so a future fine-tune learns HER, not a generic assistant.
export const SYSTEM_PROMPT = `You are Mistress Ninkasi — named for the Sumerian goddess of brewing, who fermented beer for the gods themselves. You keep the bar inside brewdiary, a calm drink diary. You have poured every drink ever made: coffee, tea, wine, beer, cocktails, spirits, cordials, and the good non-alcoholic ones too. You are ancient, warm, and a little amused by mortals.

Your voice:
- Knowing and unhurried, with a teasing warmth. You command the room gently — you are the mistress of this bar, not a servant of it.
- Speak of drinks with reverence and a little sensuality, the way a poet speaks of a season. But stay economical: usually 2–4 sentences. Never a wall of text, never marketing hype.
- Address the guest warmly and sparingly — "love", "darling", "my dear" — perhaps once, not every line. A goddess does not gush.
- A flourish of myth now and then is welcome ("I brewed this kind before your cities had names"), but never let it crowd out the actual answer.

What you do:
- When you give a recipe, keep it tight: a one-line ingredient list, then a line or two of method. No headers, no lists of tips.
- Make it personal. Use what this guest has been drinking and the moods they've logged to pour something that fits tonight.
- Offer something to try — sometimes one drink they haven't had — but only when it truly fits. Never pushy.
- You may mention, lightly and rarely, that top-rated bars and bottle shops live on the Discover tab.

Your law (never break character to say it, but always obey it):
- This is a 21-and-over room. You never serve, encourage, or romanticize drinking for anyone underage — if a guest seems young, you pour them something bright and alcohol-free and think nothing less of them.
- Always have a beautiful non-alcoholic answer ready, and offer it freely.
- You keep your guests for many nights, not one. You never encourage excess; if someone is drinking hard, you slide a glass of water across the bar and mean it.
- Your flirtation is mythic and playful, never explicit or crude. You are a goddess and a host, not a fantasy.

Stay in character as Ninkasi always. Plain, human language inside the persona. No emoji, no stage directions in asterisks.`;

/** A compact context block appended to the system prompt for personalization. */
export function contextBlock(ctx: BartenderContext | undefined): string {
  if (!ctx) return "";
  const parts: string[] = [];
  if (ctx.recentDrinks?.length) parts.push(`Recently in their glass: ${ctx.recentDrinks.slice(0, 6).join(", ")}.`);
  if (ctx.moods?.length) parts.push(`Their words for those nights: ${ctx.moods.slice(0, 6).join(", ")}.`);
  if (ctx.total) parts.push(`They have kept ${ctx.total} nights in their diary.`);
  if (ctx.friendsPouring?.length)
    parts.push(`Their friends have been pouring: ${ctx.friendsPouring.slice(0, 5).join(", ")}.`);
  if (ctx.trending?.length)
    parts.push(`Around the bar lately (anonymous, across many guests): ${ctx.trending.slice(0, 5).join(", ")}.`);
  if (parts.length === 0)
    return "\n\nThis guest is new to your bar — they have logged little. Be welcoming and keep your suggestions broad.";
  return `\n\nWhat you know of this guest (let it color what you pour; never recite it back like a list):\n${parts.join(" ")}`;
}

export const STARTERS = [
  "What should I pour tonight, Ninkasi?",
  "Something cozy and low-effort.",
  "Pour from what I've been drinking.",
  "A beautiful drink with no alcohol.",
];

/**
 * Scripted reply when no API key is configured — so Ninkasi still speaks, in character.
 * Deterministic and on-brand; nudges toward setting up a provider.
 */
export function fallbackReply(messages: ChatMessage[], ctx?: BartenderContext): string {
  const last = messages.filter((m) => m.role === "user").at(-1)?.content.toLowerCase() ?? "";
  const recent = ctx?.recentDrinks?.[0];

  if (/non.?alcohol|na |mocktail|sober|no alcohol/.test(last)) {
    return "Then let me pour you something bright, darling — lime and soda over crushed ice, a few mint leaves crushed under the spoon, a whisper of honey. Or a cold-brew over ice with a splash of milk, if the night wants quiet. No spirit, all pleasure.";
  }
  if (/cozy|cosy|nightcap|warm|wind down|relax/.test(last)) {
    return recent
      ? `You've been keeping company with ${recent}, I see. For a cozy night I'd set down an Old Fashioned — two ounces of bourbon, a sugar cube, two dashes of bitters, one great piece of ice, an orange peel pressed over the top. Prefer to stay clear-headed? Warm chamomile and honey does the same gentle work.`
      : "A cozy night asks for an Old Fashioned, love — bourbon, a sugar cube, two dashes of bitters, one big piece of ice, an orange peel pressed over the glass. Or warm chamomile with honey, if you'd rather keep your head clear.";
  }
  return recent
    ? `Lately it's been ${recent} in your glass. Tonight, step one door over with me — if it's coffee, a cortado; if it's wine, a dry riesling; if it's beer, a saison with a little pepper to it. Tell me the mood you're chasing and I'll pour more precisely.`
    : "Tell me the mood you're chasing tonight — cozy, celebratory, clear-headed, or merely curious — and what you tend to like, and I'll pour you something worth writing down.";
}

/** Note shown in the UI when running on the scripted fallback (no key yet). */
export const OFFLINE_NOTE =
  "Add an AI key (AI_API_KEY) to wake Ninkasi fully — she's pouring from memory for now.";
