"use client";

import { useEffect, useRef, useState } from "react";
import clsx from "clsx";
import { useEntries } from "@/lib/store";
import { recentDrinks, recentMoods } from "@/lib/derive";
import {
  STARTERS,
  NINKASI_NAME,
  contextBlock,
  type BartenderContext,
  type ChatMessage,
} from "@/lib/bartender";
import { logExchange, isCollecting } from "@/lib/training";
import { useFeed } from "@/lib/friends";
import { useTasteTrends } from "@/lib/trends";
import { usePantry } from "@/lib/pantry";

/** Why Ninkasi couldn't answer, worded for the reader. */
class NinkasiUnavailable extends Error {}

export function Bartender() {
  const entries = useEntries();
  const { feed } = useFeed();
  const { trends } = useTasteTrends();
  const homeBar = usePantry();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [unavailable, setUnavailable] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages]);

  async function send(text: string) {
    const content = text.trim();
    if (!content || busy) return;
    const next: ChatMessage[] = [...messages, { role: "user", content }];
    setMessages(next);
    setInput("");
    setUnavailable(null);
    setBusy(true);
    // Optimistic empty assistant turn we stream into.
    setMessages((m) => [...m, { role: "assistant", content: "" }]);

    const context: BartenderContext = {
      recentDrinks: recentDrinks(entries, 6),
      moods: recentMoods(entries, 6),
      total: entries.length,
      friendsPouring: [...new Set(feed.map((f) => f.drink))].slice(0, 5),
      trending: trends.filter((t) => t.kind === "drink").map((t) => t.name).slice(0, 5),
      homeBar,
    };

    let acc = "";
    try {
      const res = await fetch("/api/bartender", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        // `collect` carries the user's "Help train Ninkasi" consent to the server,
        // which does the (pseudonymized) write into the separate AI database.
        body: JSON.stringify({ messages: next, context, collect: isCollecting() }),
      });
      // Off (503), busy (429) or failed: an honest line, never a scripted answer.
      if (!res.ok) {
        const why =
          res.status === 503
            ? "Ninkasi isn't switched on yet."
            : res.status === 429
              ? "Too many questions at once — ask again in a minute."
              : "Ninkasi couldn't answer just now — ask again.";
        throw new NinkasiUnavailable(why);
      }

      const reader = res.body?.getReader();
      const decoder = new TextDecoder();
      while (reader) {
        const { done, value } = await reader.read();
        if (done) break;
        acc += decoder.decode(value, { stream: true });
        setMessages((m) => {
          const copy = m.slice();
          copy[copy.length - 1] = { role: "assistant", content: acc };
          return copy;
        });
      }
      // Keep a LOCAL copy for the personal JSONL export (opt-out in You → Settings).
      // The central corpus write happens server-side, into the separate AI database —
      // /api/bartender records each consented, live exchange itself (see training.ts).
      logExchange({ user: content, assistant: acc, context: contextBlock(context) });
    } catch (e) {
      // Hand the question back to ask again; nothing she didn't say is kept.
      setMessages((m) => m.slice(0, -2));
      setInput(content);
      setUnavailable(e instanceof NinkasiUnavailable ? e.message : "Ninkasi can't be reached — check your connection.");
    } finally {
      setBusy(false);
    }
  }

  const empty = messages.length === 0;

  return (
    <div className="flex min-h-[calc(100dvh-12rem)] flex-col">
      <header className="mb-4">
        <h1 className="display text-ink">{NINKASI_NAME}</h1>
        <p className="mt-2 max-w-prose text-[15px] text-muted">
          Mistress of the bar, named for the goddess who brewed for the gods. Tell her the mood —
          she knows what you&apos;ve been pouring.
        </p>
      </header>

      <div ref={scrollRef} className="flex-1 space-y-4 overflow-y-auto py-2">
        {empty ? (
          <div className="flex flex-wrap gap-2 pt-2">
            {STARTERS.map((s) => (
              <button
                key={s}
                onClick={() => send(s)}
                className="glass glass-press rounded-ctl px-3.5 py-2 text-sm text-muted hover:text-ink"
              >
                {s}
              </button>
            ))}
          </div>
        ) : (
          messages.map((m, i) => (
            <div key={i} className={clsx("flex", m.role === "user" ? "justify-end" : "justify-start")}>
              {m.role === "user" ? (
                // Your message — the stronger, more opaque glass so "you" reads distinctly.
                <p className="glass-strong max-w-[85%] rounded-2xl rounded-br-md px-4 py-2.5 text-[15px] text-ink">
                  {m.content}
                </p>
              ) : (
                // Ninkasi's reply — the lighter glass, a different shade, left-aligned.
                <p className="glass max-w-[90%] whitespace-pre-wrap rounded-2xl rounded-bl-md px-4 py-2.5 text-[15px] leading-relaxed text-ink">
                  {m.content || <span className="text-faint">pouring…</span>}
                </p>
              )}
            </div>
          ))
        )}
      </div>

      {unavailable && (
        <p role="alert" className="mb-2 text-xs text-accent">
          {unavailable}
        </p>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          send(input);
        }}
        className="glass sticky bottom-0 mt-2 flex items-center gap-2 rounded-tile p-2 pl-4"
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="What are you in the mood for?"
          className="flex-1 bg-transparent py-1.5 outline-none placeholder:text-faint"
        />
        <button
          type="submit"
          disabled={busy || !input.trim()}
          className={clsx(
            "rounded-ctl px-4 py-2 text-sm font-medium transition-all active:scale-[0.98]",
            busy || !input.trim()
              ? "cursor-not-allowed bg-ink/10 text-faint"
              : "bg-accent text-accent-contrast hover:opacity-90",
          )}
        >
          {busy ? "…" : "Ask"}
        </button>
      </form>
    </div>
  );
}
