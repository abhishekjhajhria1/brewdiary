import OpenAI from "openai";
import {
  SYSTEM_PROMPT,
  contextBlock,
  fallbackReply,
  type BartenderContext,
  type ChatMessage,
} from "@/lib/bartender";
import { rateLimit, clientKey } from "@/lib/ratelimit";
import { recordExchange, aiDbEnabled } from "@/lib/aidb";
import { getServerUser } from "@/lib/supabase-server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Abuse / cost guards for the live path. A chat turn never needs more than this, and
// capping it stops a bad actor (or a runaway client loop) from running up the AI bill.
const MAX_MSGS = 12; // only the last N turns are sent as context anyway
const MAX_MSG_CHARS = 2_000; // one message
const MAX_TOTAL_CHARS = 8_000; // whole conversation payload
const RATE_LIMIT = 20; // requests…
const RATE_WINDOW_MS = 60_000; // …per minute, per client

// Provider-agnostic: any OpenAI-compatible endpoint. Configure via env —
//   AI_API_KEY   (required to go live)
//   AI_BASE_URL  (default Groq — the chosen TEACHER while we distill our own
//                 Ninkasi; later this points at our self-hosted fine-tune)
//   AI_MODEL     (e.g. llama-3.3-70b-versatile, grok-4-fast, gemini-2.0-flash)
const BASE_URL = process.env.AI_BASE_URL || "https://api.groq.com/openai/v1";
const MODEL = process.env.AI_MODEL || "llama-3.3-70b-versatile";

/** Accept only well-formed chat turns from the request body. */
function isChatMessage(m: unknown): m is ChatMessage {
  if (typeof m !== "object" || m === null) return false;
  const { role, content } = m as ChatMessage;
  return (role === "user" || role === "assistant") && typeof content === "string";
}

function streamText(text: string): Response {
  // Stream a fixed string token-ish so the client renders identically to a live model.
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
      "x-bartender-mode": "fallback",
    },
  });
}

export async function POST(req: Request) {
  // 1) Rate limit per client — the first guard on the (paid) live path.
  const gate = rateLimit(`bartender:${clientKey(req)}`, RATE_LIMIT, RATE_WINDOW_MS);
  if (!gate.ok) {
    return new Response("Slow down, love — the bar's busy. Try again in a moment.", {
      status: 429,
      headers: { "Retry-After": String(gate.retryAfter), "Cache-Control": "no-store" },
    });
  }

  // 1b) Reject an absurdly large body before we spend effort parsing it.
  const declaredLen = Number(req.headers.get("content-length") || 0);
  if (declaredLen > 64_000) return new Response("Payload too large", { status: 413 });

  let messages: ChatMessage[] = [];
  let context: BartenderContext | undefined;
  let collect = false; // client's consent flag ("Help train Ninkasi")
  try {
    const body = await req.json();
    collect = body.collect === true;
    // 2) Validate + cap the input so a huge payload can't inflate token cost.
    messages = (Array.isArray(body.messages) ? body.messages : [])
      .filter(isChatMessage)
      .slice(-MAX_MSGS)
      .map((m: ChatMessage) => ({ role: m.role, content: m.content.slice(0, MAX_MSG_CHARS) }));
    context = body.context;
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  if (messages.length === 0) return new Response("No message", { status: 400 });
  const totalChars = messages.reduce((n, m) => n + m.content.length, 0);
  if (totalChars > MAX_TOTAL_CHARS) return new Response("Message too long", { status: 413 });

  const key = process.env.AI_API_KEY;
  if (!key) {
    // No provider configured yet — keep the feature usable with scripted replies.
    return streamText(fallbackReply(messages, context));
  }

  const client = new OpenAI({ apiKey: key, baseURL: BASE_URL });

  try {
    const completion = await client.chat.completions.create({
      model: MODEL,
      stream: true,
      temperature: 0.8,
      max_tokens: 500,
      messages: [
        { role: "system", content: SYSTEM_PROMPT + contextBlock(context) },
        ...messages.map((m) => ({ role: m.role, content: m.content })),
      ],
    });

    // If the user consented, resolve WHO they are concurrently with streaming (server-
    // trusted, from the session cookie — not a client-supplied id) so we can record the
    // finished exchange into the SEPARATE AI database. Started now, awaited at close, so
    // it adds zero latency to the first token.
    const willCollect = collect && aiDbEnabled;
    const userPromise = willCollect ? getServerUser() : Promise.resolve(null);
    const lastUser = messages.filter((m) => m.role === "user").at(-1)?.content ?? "";
    const ctxText = contextBlock(context);

    const encoder = new TextEncoder();
    let full = "";
    const body = new ReadableStream<Uint8Array>({
      async start(controller) {
        try {
          for await (const chunk of completion) {
            const delta = chunk.choices?.[0]?.delta?.content;
            if (delta) {
              full += delta;
              controller.enqueue(encoder.encode(delta));
            }
          }
        } catch {
          controller.enqueue(encoder.encode("\n\n(The bartender stepped away for a second — try again.)"));
        } finally {
          controller.close();
          // After the response is delivered, mirror the consented exchange into the AI
          // data plane (pseudonymized, server-side). Best-effort; never blocks the user.
          if (willCollect && full.trim()) {
            const u = await userPromise.catch(() => null);
            if (u) void recordExchange({ userId: u.id, prompt: lastUser, reply: full, context: ctxText, model: MODEL });
          }
        }
      },
    });

    return new Response(body, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
        "x-bartender-mode": "live",
        // which teacher answered — stored with each consented exchange so the
        // training corpus knows its provenance
        "x-bartender-model": MODEL,
      },
    });
  } catch {
    // Provider/auth/network error → graceful scripted fallback rather than a hard 500.
    return streamText(fallbackReply(messages, context));
  }
}
