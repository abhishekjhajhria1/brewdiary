"use client";

// "Split" — Splitwise-style shared drink tabs among friends. Supabase-backed.
// Expenses + shares + settlements are stored; each PAIR's balance is DERIVED
// (positive = they owe you). Same fetch-on-mount + bump-to-refresh pattern as friends.ts.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export interface ExpenseShare {
  userId: string;
  amount: number;
}
export interface Expense {
  id: string;
  payerId: string;
  description: string;
  amount: number;
  createdAt: string;
  shares: ExpenseShare[];
}
export interface Settlement {
  id: string;
  fromId: string;
  toId: string;
  amount: number;
  createdAt: string;
}

const subs = new Set<() => void>();
function bump() {
  subs.forEach((s) => s());
}

export function useSplitData(): { expenses: Expense[]; settlements: Settlement[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [settlements, setSettlements] = useState<Settlement[]>([]);
  const [loading, setLoading] = useState(true);
  const [v, setV] = useState(0);

  useEffect(() => {
    const cb = () => setV((n) => n + 1);
    subs.add(cb);
    return () => {
      subs.delete(cb);
    };
  }, []);

  useEffect(() => {
    if (!supabase || !me) {
      setExpenses([]);
      setSettlements([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const [exp, set] = await Promise.all([
        supabase!
          .from("expenses")
          .select("id, payer_id, description, amount, created_at, expense_shares(user_id, amount)")
          .order("created_at", { ascending: false }),
        supabase!.from("settlements").select("id, from_id, to_id, amount, created_at").order("created_at", { ascending: false }),
      ]);
      if (!active) return;
      setExpenses(
        (exp.data ?? []).map((r: Record<string, unknown>) => ({
          id: r.id as string,
          payerId: r.payer_id as string,
          description: r.description as string,
          amount: Number(r.amount),
          createdAt: r.created_at as string,
          shares: ((r.expense_shares as Record<string, unknown>[]) ?? []).map((s) => ({
            userId: s.user_id as string,
            amount: Number(s.amount),
          })),
        })),
      );
      setSettlements(
        (set.data ?? []).map((r: Record<string, unknown>) => ({
          id: r.id as string,
          fromId: r.from_id as string,
          toId: r.to_id as string,
          amount: Number(r.amount),
          createdAt: r.created_at as string,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { expenses, settlements, loading };
}

/** Net balance per other-user id. Positive = they owe you; negative = you owe them. */
export function computeBalances(expenses: Expense[], settlements: Settlement[], me: string): Map<string, number> {
  const bal = new Map<string, number>();
  const add = (id: string, delta: number) => bal.set(id, (bal.get(id) ?? 0) + delta);

  for (const e of expenses) {
    for (const s of e.shares) {
      if (s.userId === e.payerId) continue; // payer doesn't owe themselves
      if (e.payerId === me) add(s.userId, s.amount); // they owe me
      else if (s.userId === me) add(e.payerId, -s.amount); // I owe the payer
    }
  }
  for (const st of settlements) {
    if (st.fromId === me) add(st.toId, st.amount); // I paid them back → my debt shrinks
    else if (st.toId === me) add(st.fromId, -st.amount); // they paid me back → their debt shrinks
  }

  // drop ~zero balances (rounding)
  for (const [id, v] of bal) if (Math.abs(v) < 0.005) bal.delete(id);
  return bal;
}

// ── mutations ────────────────────────────────────────────────────────────────
/** Split `amount` evenly among participantIds; `payerId` paid the whole thing. */
export async function addExpense(input: {
  meId: string;
  payerId: string;
  description: string;
  amount: number;
  participantIds: string[]; // who the cost is split among (usually incl. payer)
}): Promise<string | null> {
  if (!supabase) return "offline";
  const parts = Array.from(new Set(input.participantIds));
  if (parts.length === 0 || input.amount <= 0 || !input.description.trim()) return "invalid";

  // Generate the id client-side and insert WITHOUT a re-select: the expenses read
  // policy runs a SECURITY DEFINER function, which trips PostgREST's INSERT..RETURNING
  // path (return=representation). return=minimal avoids it. Reads still work fine.
  const id =
    typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `x_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  const { error } = await supabase
    .from("expenses")
    .insert({ id, created_by: input.meId, payer_id: input.payerId, description: input.description.trim(), amount: input.amount });
  if (error) return error.message;

  const each = Math.round((input.amount / parts.length) * 100) / 100;
  const shares = parts.map((uid, i) => ({
    expense_id: id,
    user_id: uid,
    // last participant absorbs the rounding remainder so shares sum to the total
    amount: i === parts.length - 1 ? Math.round((input.amount - each * (parts.length - 1)) * 100) / 100 : each,
  }));
  const { error: sErr } = await supabase.from("expense_shares").insert(shares);
  bump();
  return sErr ? sErr.message : null;
}

export async function deleteExpense(id: string) {
  if (!supabase) return;
  await supabase.from("expenses").delete().eq("id", id); // cascade removes shares
  bump();
}

/** Record a payback that zeroes (or reduces) a balance. `friendOwesMe` sets the direction. */
export async function settleUp(meId: string, friendId: string, amount: number, friendOwesMe: boolean) {
  if (!supabase || amount <= 0) return;
  const from = friendOwesMe ? friendId : meId;
  const to = friendOwesMe ? meId : friendId;
  await supabase.from("settlements").insert({ from_id: from, to_id: to, amount, created_by: meId });
  bump();
}
