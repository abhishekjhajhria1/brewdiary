import OpenAI from "openai";
import {
  ADVISOR_SYSTEM_PROMPT,
  summarizeInsights,
  fallbackAdvice,
  type InsightBrief,
  type ChatMessage,
} from "@/lib/venueAdvisor";
import { rateLimit, clientKey } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Ninkasi's back-office read. Same guards as the bartender route (this is the paid,
// live path), but deliberately NOT wired to the AI data plane: business advice for an
// owner is not consumer diary data and never joins the pseudonymized training corpus.
//
// The whole payload is the venue's OWN aggregate numbers — the totals a manager can
// already see on the Insights panel — plus optional follow-up questions. No individual
// guest is ever described to the model, so there is nothing here to look up server-side:
// the model stays a stateless text function over numbers the caller already holds.
const MAX_MSGS = 10;
const MAX_MSG_CHARS = 1_000;
const MAX_TOTAL_CHARS = 6_000;
const RATE_LIMIT = 15;
const RATE_WINDOW_MS = 60_000;

const BASE_URL = process.env.AI_BASE_URL || "https://api.groq.com/openai/v1";
const MODEL = process.env.AI_MODEL || "llama-3.3-70b-versatile";

function isChatMessage(m: unknown): m is ChatMessage {
  if (typeof m !== "object" || m === null) return false;
  const { role, content } = m as ChatMessage;
  return (role === "user" || role === "assistant") && typeof content === "string";
}

// Trust nothing from the wire: coerce the brief into a shape summarizeInsights can
// read, dropping anything unexpected. A malformed brief becomes conservative zeros.
function coerceBrief(raw: unknown): InsightBrief | null {
  if (typeof raw !== "object" || raw === null) return null;
  const b = raw as Record<string, unknown>;
  const ins = (b.insights ?? {}) as Record<string, unknown>;
  const num = (x: unknown) => (typeof x === "number" && Number.isFinite(x) ? x : 0);
  const numOrNull = (x: unknown) => (x === null ? null : typeof x === "number" && Number.isFinite(x) ? x : 0);
  const str = (x: unknown, cap = 80) => (typeof x === "string" ? x.slice(0, cap) : "");
  return {
    venueName: str(b.venueName) || "this venue",
    kind: b.kind === "store" ? "store" : "bar",
    days: num(b.days) || 30,
    currency: (str(b.currency, 3) || "USD").toUpperCase(),
    quietNightLabels: Array.isArray(b.quietNightLabels)
      ? b.quietNightLabels.filter((x) => typeof x === "string").slice(0, 7).map((x) => (x as string).slice(0, 3))
      : [],
    perks: Array.isArray(b.perks)
      ? b.perks
          .filter((p): p is Record<string, unknown> => typeof p === "object" && p !== null)
          .slice(0, 3)
          .map((p) => ({ reward: str(p.reward, 60), at: str(p.at, 40) }))
      : [],
    insights: {
      rooms: num(ins.rooms),
      guests: num(ins.guests),
      newGuests: numOrNull(ins.newGuests),
      returningGuests: numOrNull(ins.returningGuests),
      quietVisits: num(ins.quietVisits),
      otherVisits: num(ins.otherVisits),
      perksEarned: numOrNull(ins.perksEarned),
      perksClaimed: num(ins.perksClaimed),
      tabs: num(ins.tabs),
      takings: num(ins.takings),
      kudos: num(ins.kudos),
    },
  };
}

function streamText(text: string): Response {
  const encoder = new TextEncoder();
  const words = text.split(/(\s+)/);
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      for (const w of words) {
        controller.enqueue(encoder.encode(w));
        await new Promise((r) => setTimeout(r, 12));
      }
      controller.close();
    },
  });
  return new Response(body, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
      "x-advisor-mode": "fallback",
    },
  });
}

export async function POST(req: Request) {
  const gate = rateLimit(`venue-ai:${clientKey(req)}`, RATE_LIMIT, RATE_WINDOW_MS);
  if (!gate.ok) {
    return new Response("Give me a moment with the last set of books, then ask again.", {
      status: 429,
      headers: { "Retry-After": String(gate.retryAfter), "Cache-Control": "no-store" },
    });
  }

  const declaredLen = Number(req.headers.get("content-length") || 0);
  if (declaredLen > 32_000) return new Response("Payload too large", { status: 413 });

  let brief: InsightBrief | null = null;
  let messages: ChatMessage[] = [];
  try {
    const body = await req.json();
    brief = coerceBrief(body.brief);
    messages = (Array.isArray(body.messages) ? body.messages : [])
      .filter(isChatMessage)
      .slice(-MAX_MSGS)
      .map((m: ChatMessage) => ({ role: m.role, content: m.content.slice(0, MAX_MSG_CHARS) }));
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  if (!brief) return new Response("No numbers to read", { status: 400 });
  const totalChars = messages.reduce((n, m) => n + m.content.length, 0);
  if (totalChars > MAX_TOTAL_CHARS) return new Response("Message too long", { status: 413 });

  const key = process.env.AI_API_KEY;
  if (!key) return streamText(fallbackAdvice(brief));

  // No follow-up question means "read my numbers" — the opening briefing.
  const turns: ChatMessage[] =
    messages.length > 0 ? messages : [{ role: "user", content: "Read my numbers and tell me what to do next." }];

  const client = new OpenAI({ apiKey: key, baseURL: BASE_URL });
  try {
    const completion = await client.chat.completions.create({
      model: MODEL,
      stream: true,
      temperature: 0.7,
      max_tokens: 420,
      messages: [
        { role: "system", content: ADVISOR_SYSTEM_PROMPT + summarizeInsights(brief) },
        ...turns.map((m) => ({ role: m.role, content: m.content })),
      ],
    });

    const encoder = new TextEncoder();
    const body = new ReadableStream<Uint8Array>({
      async start(controller) {
        try {
          for await (const chunk of completion) {
            const delta = chunk.choices?.[0]?.delta?.content;
            if (delta) controller.enqueue(encoder.encode(delta));
          }
        } catch {
          controller.enqueue(encoder.encode("\n\n(Lost my place in the ledger for a second — ask again.)"));
        } finally {
          controller.close();
        }
      },
    });

    return new Response(body, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
        "x-advisor-mode": "live",
        "x-advisor-model": MODEL,
      },
    });
  } catch {
    return streamText(fallbackAdvice(brief));
  }
}
