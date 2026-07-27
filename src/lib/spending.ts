"use client";

// Spending — your own money, shown back to you. Nobody else's, and nobody else's
// business.
//
// ── WHY THIS EXISTS AND WHERE ITS LINE IS ────────────────────────────────────
// Prompt 3 of the dine-out work refused a per-guest spend view on the BAR's
// dashboard, and that refusal stands: a venue that can rank guests by money will
// work that list. But the harm in a spend number is always someone ELSE holding
// it, or you seeing yours beside theirs. Your own spending, private, is the same
// shape as goals.ts — a mirror, not a scoreboard — and if it moves behaviour at
// all it moves it down.
//
//   ✓ you see your own spend, across venues, over time
//   ✗ a venue sees a named guest's history          (no rpc takes a user id)
//   ✗ anyone is ranked, scored or rewarded by spend (see below)
//
// ⚠ THE LOAD-BEARING RULE: nothing here feeds the game. Sparks, palate score,
// passport, expeditions, streaks and every leaderboard are computed without ever
// reading this module, and that must stay true. Money buys no progress. If a
// future feature wants "spend" as an input to anything scored, that is rule #1
// and the answer is no — the game does not know money exists.
//
// ── the currency trap this module is built around ───────────────────────────
// A row's currency belongs to the VENUE, so a Goa weekend and a Berlin trip are
// in different money. There is deliberately NO function here that returns a
// single grand total: ₹ and € do not add, and a number that pretends they do is
// wrong in the most confident possible way. Every aggregate is keyed BY CURRENCY
// and the UI shows them as separate lines.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import { DEFAULT_CURRENCY } from "./money";

export type SpendSource = "order" | "tab";

export interface SpendRow {
  source: SpendSource;
  /** The order or spend_event this came from. */
  refId: string;
  /** YYYY-MM-DD. */
  date: string;
  venueId?: string;
  venueName: string;
  currency: string;
  /** Integer minor units, in `currency`. */
  amountMinor: number;
  /** Lines on an itemised order; undefined for a staff-typed tab total. */
  items?: number;
  /** False while a tab is still running tonight — not history yet. */
  settled: boolean;
}

// ── the read ─────────────────────────────────────────────────────────────────

/**
 * Your spend history. The rpc takes no user id — it is scoped to `auth.uid()` in
 * SQL — so there is no argument by which this becomes someone else's history.
 */
export function useMySpend(months = 12): { rows: SpendRow[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const [state, setState] = useState<{ rows: SpendRow[]; loading: boolean }>({ rows: [], loading: true });

  useEffect(() => {
    if (!supabase || !me) {
      setState({ rows: [], loading: false });
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("my_spend_history", { months });
      if (!active) return;
      setState({
        rows: ((data as Record<string, unknown>[]) ?? []).map((r) => ({
          source: ((r.source as string) ?? "tab") as SpendSource,
          refId: r.ref_id as string,
          date: r.on_date as string,
          venueId: (r.venue_id as string) ?? undefined,
          venueName: (r.venue_name as string) || "a venue",
          currency: (r.currency as string) || DEFAULT_CURRENCY,
          amountMinor: Number(r.amount_minor ?? 0),
          items: r.items == null ? undefined : Number(r.items),
          settled: Boolean(r.settled),
        })),
        loading: false,
      });
    })();
    return () => {
      active = false;
    };
  }, [me, months]);

  return state;
}

// ─────────────────────────────────────────────────────────────────────────────
// PURE DERIVES — no network, no React. Everything below is unit-tested.
//
// Every one of these is keyed by currency. None of them returns a grand total,
// because there isn't one.
// ─────────────────────────────────────────────────────────────────────────────

export interface CurrencyTotal {
  currency: string;
  totalMinor: number;
  count: number;
}

/** What you spent, per currency. The closest thing to a "total" that is honest. */
export function totalsByCurrency(rows: SpendRow[]): CurrencyTotal[] {
  const out = new Map<string, CurrencyTotal>();
  for (const r of rows ?? []) {
    if (!r) continue;
    const cur = out.get(r.currency);
    if (cur) {
      cur.totalMinor += clean(r.amountMinor);
      cur.count += 1;
    } else {
      out.set(r.currency, { currency: r.currency, totalMinor: clean(r.amountMinor), count: 1 });
    }
  }
  // biggest first, so the currency you actually live in leads
  return [...out.values()].sort((a, b) => b.totalMinor - a.totalMinor || a.currency.localeCompare(b.currency));
}

export interface MonthTotal {
  /** YYYY-MM. */
  month: string;
  currency: string;
  totalMinor: number;
  count: number;
}

/** Month by month, newest first. Split by currency: a month abroad is its own row. */
export function byMonth(rows: SpendRow[]): MonthTotal[] {
  const out = new Map<string, MonthTotal>();
  for (const r of rows ?? []) {
    if (!r?.date) continue;
    const month = r.date.slice(0, 7);
    if (month.length !== 7) continue;
    const key = `${month}|${r.currency}`;
    const cur = out.get(key);
    if (cur) {
      cur.totalMinor += clean(r.amountMinor);
      cur.count += 1;
    } else {
      out.set(key, { month, currency: r.currency, totalMinor: clean(r.amountMinor), count: 1 });
    }
  }
  return [...out.values()].sort((a, b) => b.month.localeCompare(a.month) || a.currency.localeCompare(b.currency));
}

export interface VenueTotal {
  venueName: string;
  currency: string;
  totalMinor: number;
  visits: number;
}

/**
 * Where it went, biggest first.
 *
 * This is a ranking of PLACES, which is fine — a place is not a person and
 * cannot be made to feel anything about its position. There is deliberately no
 * equivalent function ranking people, and there will not be one.
 */
export function byVenue(rows: SpendRow[]): VenueTotal[] {
  const out = new Map<string, VenueTotal>();
  for (const r of rows ?? []) {
    if (!r) continue;
    const key = `${r.venueName}|${r.currency}`;
    const cur = out.get(key);
    if (cur) {
      cur.totalMinor += clean(r.amountMinor);
      cur.visits += 1;
    } else {
      out.set(key, { venueName: r.venueName, currency: r.currency, totalMinor: clean(r.amountMinor), visits: 1 });
    }
  }
  return [...out.values()].sort((a, b) => b.totalMinor - a.totalMinor || a.venueName.localeCompare(b.venueName));
}

/**
 * A typical night out, per currency — the median, not the mean.
 *
 * The median on purpose: one anniversary dinner drags a mean somewhere that
 * describes no actual evening, and "your average night out is ₹4,200" when it's
 * really ₹900 is the kind of wrong number that makes someone distrust the whole
 * screen.
 */
export function typicalNight(rows: SpendRow[]): CurrencyTotal[] {
  const byCur = new Map<string, number[]>();
  for (const r of rows ?? []) {
    if (!r) continue;
    const list = byCur.get(r.currency);
    if (list) list.push(clean(r.amountMinor));
    else byCur.set(r.currency, [clean(r.amountMinor)]);
  }
  const out: CurrencyTotal[] = [];
  for (const [currency, amounts] of byCur) {
    amounts.sort((a, b) => a - b);
    const mid = Math.floor(amounts.length / 2);
    const median =
      amounts.length % 2 === 0 ? Math.round((amounts[mid - 1] + amounts[mid]) / 2) : amounts[mid];
    out.push({ currency, totalMinor: median, count: amounts.length });
  }
  return out.sort((a, b) => b.count - a.count || a.currency.localeCompare(b.currency));
}

/** A negative or non-finite amount is a bug upstream, not a credit. Floor at 0. */
function clean(n: unknown): number {
  const x = Number(n);
  return Number.isFinite(x) && x > 0 ? Math.trunc(x) : 0;
}
