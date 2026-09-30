import OpenAI from "openai";
import { HOST_SYSTEM_PROMPT, coerceHostBrief, hostBriefing, hostFallbackAnswer, summarizeHostBrief, type ChatMessage } from "@/lib/hostAdvisor";
import { rateLimit, clientKey } from "@/lib/ratelimit";
import { getServerUser } from "@/lib/supabase-server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Ninkasi for hosts: the shift companion for every role on a venue's team. The same
// guards as the other AI routes, plus a signed-in person (the venue app sends its
// bearer token; the web dashboard its cookie) — this is staff tooling, not a public toy.
//
// The payload is the brief the app built from what THIS person's role can already see,
// counts only: tonight's state, the menu, the card, public facts about the area. No
// guest is ever described, so there is nothing to look up here, and it never joins the
// training corpus. With no AI key it answers from the same rules the app uses offline.
const MAX_MSGS = 10;
const MAX_MSG_CHARS = 800;
const MAX_TOTAL_CHARS = 5_000;

const BASE_URL = process.env.AI_BASE_URL || "https://api.groq.com/openai/v1";
const MODEL = process.env.AI_MODEL || "llama-3.3-70b-versatile";

function isChatMessage(m: unknown): m is ChatMessage {
  if (typeof m !== "object" || m === null) return false;
  const { role, content } = m as ChatMessage;
  return (role === "user" || role === "assistant") && typeof content === "string";
}

function streamText(text: string): Response {
  const encoder = new TextEncoder();
  const words = text.split(/(\s+)/);
  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      for (const w of words) {
        controller.enqueue(encoder.encode(w));
        await new Promise((r) => setTimeout(r, 10));
      }
      controller.close();
    },
  });
  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "x-host-mode": "fallback" } });
}

export async function POST(req: Request) {
  const user = await getServerUser(req);
  if (!user) return new Response("Sign in to ask Ninkasi.", { status: 401 });

  const gate = rateLimit(`host-ai:${user.id}:${clientKey(req)}`, 20, 60_000);
  if (!gate.ok) {
    return new Response("Give me a moment — ask again shortly.", { status: 429, headers: { "Retry-After": String(gate.retryAfter), "Cache-Control": "no-store" } });
  }
  if (Number(req.headers.get("content-length") || 0) > 24_000) return new Response("Payload too large", { status: 413 });

  let body: { brief?: unknown; messages?: unknown };
  try {
    body = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }
  const brief = coerceHostBrief(body.brief);
  if (!brief) return new Response("No briefing to read", { status: 400 });
  const messages: ChatMessage[] = (Array.isArray(body.messages) ? body.messages : [])
    .filter(isChatMessage)
    .slice(-MAX_MSGS)
    .map((m) => ({ role: m.role, content: m.content.slice(0, MAX_MSG_CHARS) }));
  if (messages.reduce((n, m) => n + m.content.length, 0) > MAX_TOTAL_CHARS) return new Response("Message too long", { status: 413 });

  const lastQuestion = [...messages].reverse().find((m) => m.role === "user")?.content;
  const fallback = () => streamText(lastQuestion ? hostFallbackAnswer(brief, lastQuestion) : hostBriefing(brief).join("\n"));

  const key = process.env.AI_API_KEY;
  if (!key) return fallback();

  const turns: ChatMessage[] = messages.length ? messages : [{ role: "user", content: "Brief me for this shift: the few things I need to know, most important first." }];
  try {
    const completion = await new OpenAI({ apiKey: key, baseURL: BASE_URL }).chat.completions.create({
      model: MODEL,
      stream: true,
      temperature: 0.5,
      max_tokens: 360,
      messages: [{ role: "system", content: HOST_SYSTEM_PROMPT + summarizeHostBrief(brief) }, ...turns],
    });
    const encoder = new TextEncoder();
    const stream = new ReadableStream<Uint8Array>({
      async start(controller) {
        try {
          for await (const chunk of completion) {
            const delta = chunk.choices?.[0]?.delta?.content;
            if (delta) controller.enqueue(encoder.encode(delta));
          }
        } catch {
          controller.enqueue(encoder.encode("\n\n(Lost my place for a second — ask again.)"));
        } finally {
          controller.close();
        }
      },
    });
    return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "x-host-mode": "live", "x-host-model": MODEL } });
  } catch {
    return fallback();
  }
}
