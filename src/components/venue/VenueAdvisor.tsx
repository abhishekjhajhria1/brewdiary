"use client";

// "Ninkasi's read" — the AI advisor that sits under the Insights numbers. She is
// handed ONLY this venue's aggregate totals (the very numbers already on screen) plus
// the owner's own perk/quiet-night settings, and turns them into a couple of plain,
// actionable sentences. No individual guest is ever described to the model — see
// lib/venueAdvisor.ts for the privacy line. Streams like the bartender; works on a
// scripted fallback before an AI key exists.
import { useMemo, useState } from "react";
import type { Venue } from "@/lib/venues";
import { useVenuePerks } from "@/lib/perks";
import { useAreaTrends } from "@/lib/trends";
import { currencyForCountry, formatMoney } from "@/lib/money";
import {
  ADVISOR_STARTERS,
  ADVISOR_OFFLINE_NOTE,
  type AdvisorInsights,
  type InsightBrief,
  type ChatMessage,
} from "@/lib/venueAdvisor";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function VenueAdvisor({
  venue,
  insights,
  days,
}: {
  venue: Venue;
  insights: AdvisorInsights;
  days: number;
}) {
  const { perks } = useVenuePerks(venue.id);
  // The neighbourhood's anonymous taste, scoped to this venue's coarse cell (k-anon ≥5).
  // Empty until the owner sets the venue's location (Setup) and ≥5 locals opt in.
  const { trends: areaTrends } = useAreaTrends(venue.geohash, days);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [offline, setOffline] = useState(false);
  const started = messages.length > 0;

  // The brief is assembled ONLY from data this manager already holds: the aggregate
  // numbers above and the venue's own settings. Nothing about any individual guest.
  const brief: InsightBrief = useMemo(() => {
    const currency = currencyForCountry(venue.country);
    return {
      venueName: venue.name,
      kind: venue.kind,
      days,
      currency,
      quietNightLabels: (venue.quietNights ?? []).map((d) => WEEKDAYS[d]).filter(Boolean),
      perks: perks.map((p) => ({
        reward: p.reward,
        at: p.kind === "spend" ? formatMoney(p.threshold, currency, { round: true }) : `${p.threshold} visits`,
      })),
      insights,
      areaLabel: venue.city || undefined,
      areaTrends: areaTrends.map((t) => ({ kind: t.kind, name: t.name, users: t.users })),
    };
  }, [venue, days, perks, insights, areaTrends]);

  async function ask(question?: string) {
    if (busy) return;
    // A follow-up appears as its own turn; the opening "read" sends no user message.
    const next: ChatMessage[] = question ? [...messages, { role: "user", content: question }] : messages;
    setMessages([...next, { role: "assistant", content: "" }]);
    setBusy(true);

    let acc = "";
    try {
      const res = await fetch("/api/venue-ai", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ brief, messages: next }),
      });
      setOffline(res.headers.get("x-advisor-mode") === "fallback");
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
    } catch {
      setMessages((m) => {
        const copy = m.slice();
        copy[copy.length - 1] = { role: "assistant", content: "The ledger slipped away for a moment — ask me again." };
        return copy;
      });
    } finally {
      setBusy(false);
    }
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const q = input.trim();
    if (!q) return;
    setInput("");
    void ask(q);
  }

  return (
    <div className="glass mt-4 rounded-tile p-5">
      <div className="mb-1 flex items-baseline justify-between gap-3">
        <p className="label text-faint">Ninkasi&apos;s read</p>
        <span className="font-display text-sm italic text-faint">for bars</span>
      </div>
      <p className="mb-3 max-w-prose text-xs leading-relaxed text-faint">
        She sees only the totals above — never a guest, a name, or what one person spent — and tells you what to do
        next.
      </p>

      {!started ? (
        <button
          onClick={() => ask()}
          disabled={busy}
          className="rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "Reading…" : "Read my numbers"}
        </button>
      ) : (
        <>
          <div className="space-y-2.5" aria-live="polite">
            {messages.map((m, idx) =>
              m.role === "user" ? (
                <p
                  key={idx}
                  className="glass-strong ml-auto max-w-[85%] rounded-2xl rounded-br-md px-4 py-2.5 text-[15px] leading-relaxed text-ink"
                >
                  {m.content}
                </p>
              ) : (
                <p
                  key={idx}
                  className="glass mr-auto max-w-[92%] rounded-2xl rounded-bl-md px-4 py-2.5 text-[15px] leading-relaxed text-ink"
                >
                  {m.content || <span className="text-faint">Reading the books…</span>}
                </p>
              ),
            )}
          </div>

          {/* Follow-up — grounded on the same aggregate brief, never on a person. */}
          <div className="mt-3">
            {!busy && (
              <div className="mb-2 flex flex-wrap gap-1.5">
                {ADVISOR_STARTERS.slice(1).map((s) => (
                  <button
                    key={s}
                    onClick={() => ask(s)}
                    className="glass glass-press rounded-ctl px-3 py-1.5 text-xs text-muted transition-colors hover:text-accent"
                  >
                    {s}
                  </button>
                ))}
              </div>
            )}
            <form onSubmit={submit} className="flex items-center gap-2">
              <label htmlFor={`advisor-${venue.id}`} className="sr-only">
                Ask Ninkasi about your numbers
              </label>
              <input
                id={`advisor-${venue.id}`}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Ask about your numbers…"
                className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint"
              />
              <button
                type="submit"
                disabled={busy || !input.trim()}
                className="shrink-0 rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                Ask
              </button>
            </form>
          </div>
        </>
      )}

      {offline && <p className="mt-2.5 text-xs leading-relaxed text-faint">{ADVISOR_OFFLINE_NOTE}</p>}
    </div>
  );
}
