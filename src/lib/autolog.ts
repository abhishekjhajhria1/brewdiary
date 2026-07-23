"use client";

// Party catch-up auto-log — "once you're a few in, you stop logging".
//
// ── WHAT THIS IS, AND THE HONEST LIMITS OF IT ───────────────────────────────
// A real thing happens on a good night: you tap the beer/peg counter for the
// first few, then — a few drinks in — you stop, and the rest of the night never
// lands on your diary. This closes that gap: if a party's tally goes QUIET for two
// hours after you'd been counting, the app adds ONE more of what you were drinking,
// so the day isn't left blank.
//
// It is deliberately conservative and transparent, because the app CANNOT know how
// many you actually had once you stopped tapping (and can't tell "still out" from
// "went home and slept"). So:
//   • it only ever fires if you'd ALREADY logged ≥1 beer/peg that day — it invents
//     a night from nothing, never;
//   • it adds exactly ONE entry, clearly marked, and shows a notice with a one-tap
//     Remove — an approximate record you can correct, not a fabricated tally;
//   • it fires at most ONCE per party per day (no beer-every-2-hours loop);
//   • the entry is an ordinary repeat, so it earns no spark and moves no board
//     (rule #6: variety only) — it just keeps your own private count honest-ish.
//
// This trades a little accuracy for not losing the night, which is the maintainer's
// explicit call ("once a man is drunk enough he'll never log anything for that day").
import { useCallback, useEffect, useState } from "react";
import { useEntries, addEntry, deleteEntry } from "./store";
import { useExtras } from "./features";
import { normalize } from "./drinks";

const GAP_MS = 2 * 60 * 60 * 1000; // two hours of quiet
const POLL_MS = 5 * 60 * 1000; // re-check every 5 min while the app is open
const LKEY = "brewdiary.autolog.v1";

// `${partyId}:${date}` → what we did, so it fires once and the notice survives a reload.
interface DoneRec {
  entryId: string | null;
  ack: boolean; // the guest has kept or removed it — don't resurface
}
type DoneMap = Record<string, DoneRec>;

function readDone(): DoneMap {
  if (typeof window === "undefined") return {};
  try {
    const raw = window.localStorage.getItem(LKEY);
    return raw ? (JSON.parse(raw) as DoneMap) : {};
  } catch {
    return {};
  }
}
function writeDone(d: DoneMap) {
  try {
    window.localStorage.setItem(LKEY, JSON.stringify(d));
  } catch {
    /* quota / private mode — the once-guard is best-effort */
  }
}

export interface CatchUp {
  entryId: string;
  drink: string;
}

/** Watches one party-day; auto-adds a single catch-up drink after a 2h lull and
 *  hands back a notice the room can show (with Keep / Remove). Pass `enabled` false
 *  to arm nothing (e.g. an old party, or a solo one). */
export function usePartyCatchUp(
  partyId: string | null,
  dateKey: string,
  enabled: boolean,
): { pending: CatchUp | null; keep: () => void; remove: () => void } {
  const entries = useEntries();
  const extras = useExtras();
  const [pending, setPending] = useState<CatchUp | null>(null);
  const [tick, setTick] = useState(0);

  const key = partyId ? `${partyId}:${dateKey}` : null;

  // The 2h mark can pass while the app is simply left open — re-check on a timer.
  useEffect(() => {
    if (!enabled) return;
    const t = setInterval(() => setTick((n) => n + 1), POLL_MS);
    return () => clearInterval(t);
  }, [enabled]);

  useEffect(() => {
    if (!enabled || !key) return;
    if (!(extras.beers || extras.pegs)) return; // the counter isn't even on

    const done = readDone();
    const rec = done[key];

    // Already handled for this party+day: keep the notice up until kept/removed.
    if (rec) {
      if (rec.ack) {
        setPending(null);
        return;
      }
      const existing = rec.entryId ? entries.find((e) => e.id === rec.entryId) : null;
      setPending(existing ? { entryId: existing.id, drink: existing.drink } : null);
      return;
    }

    // The party-day's counter taps, oldest → newest.
    const taps = entries
      .filter((e) => e.date === dateKey && (normalize(e.drink) === "beer" || normalize(e.drink) === "peg"))
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    if (taps.length === 0) return; // never started counting → invent nothing

    const last = taps[taps.length - 1];
    if (Date.now() - new Date(last.createdAt).getTime() < GAP_MS) return; // still going

    // One conservative catch-up of whatever they were drinking. Marked + undoable.
    const added = addEntry({
      date: dateKey,
      drink: last.drink,
      type: last.type,
      note: "Added automatically — your night went quiet after this. Remove it if that's not right.",
    });
    writeDone({ ...readDone(), [key]: { entryId: added.id, ack: false } });
    setPending({ entryId: added.id, drink: added.drink });
  }, [enabled, key, dateKey, entries, extras.beers, extras.pegs, tick]);

  const ack = useCallback(() => {
    if (!key) return;
    const done = readDone();
    if (done[key]) writeDone({ ...done, [key]: { ...done[key], ack: true } });
  }, [key]);

  const keep = useCallback(() => {
    ack();
    setPending(null);
  }, [ack]);

  const remove = useCallback(() => {
    if (pending) deleteEntry(pending.entryId);
    setPending(null);
    if (key) writeDone({ ...readDone(), [key]: { entryId: null, ack: true } });
  }, [pending, key]);

  return { pending, keep, remove };
}
