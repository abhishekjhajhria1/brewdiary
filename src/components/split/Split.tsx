"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import clsx from "clsx";
import { useAuth } from "@/lib/profile";
import { useFriends, type SocialProfile } from "@/lib/friends";
import {
  useSplitData,
  computeBalances,
  addExpense,
  deleteExpense,
  settleUp,
  type Expense,
} from "@/lib/expenses";
import { MONTH_NAMES, parseKey, toKey } from "@/lib/date";
import { currencySymbol, formatMoney, savedCurrency } from "@/lib/money";

// A split has no venue, so it uses the person's OWN currency (set at the age gate
// from where they said they are; changeable in You → settings). Formatting goes
// through Intl, so a German user gets 1.234,56 € and an Indian user ₹1,23,456.
function money(n: number): string {
  return formatMoney(Math.round(Math.abs(n) * 100) / 100, savedCurrency());
}

export function Split() {
  const me = useAuth().profile;
  const { friends } = useFriends();
  const { expenses, settlements, loading } = useSplitData();
  const [adding, setAdding] = useState(false);

  const nameOf = useMemo(() => {
    const map = new Map<string, string>();
    if (me) map.set(me.id, "You");
    for (const f of friends) map.set(f.id, f.name);
    return (id: string) => map.get(id) ?? "friend";
  }, [me, friends]);

  const balances = useMemo(
    () => (me ? computeBalances(expenses, settlements, me.id) : new Map<string, number>()),
    [expenses, settlements, me],
  );

  const owedToMe = [...balances.values()].filter((v) => v > 0).reduce((a, b) => a + b, 0);
  const iOwe = [...balances.values()].filter((v) => v < 0).reduce((a, b) => a - b, 0);

  return (
    <>
      <header className="mb-6 flex items-end justify-between border-b border-line pb-4">
        <h1 className="font-display text-5xl leading-none tracking-tight">Split</h1>
        <Link href="/together" className="label text-faint transition-colors hover:text-ink">
          ← Together
        </Link>
      </header>

      <p className="max-w-prose text-[15px] leading-relaxed text-muted">
        Who bought which round. Split a tab with friends, and keep the tally quiet until someone settles up.
      </p>

      {/* summary */}
      <div className="mt-6 grid grid-cols-2 gap-3">
        <div className="glass rounded-tile p-4">
          <p className="label text-faint">You&apos;re owed</p>
          <p className="tnum mt-1 font-display text-2xl text-accent">{money(owedToMe)}</p>
        </div>
        <div className="glass rounded-tile p-4">
          <p className="label text-faint">You owe</p>
          <p className="tnum mt-1 font-display text-2xl text-ink">{money(iOwe)}</p>
        </div>
      </div>

      <button
        onClick={() => setAdding(true)}
        disabled={friends.length === 0}
        className="mt-4 w-full rounded-ctl bg-accent py-3 text-sm font-medium uppercase tracking-[0.12em] text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-40"
      >
        Add an expense
      </button>

      {friends.length === 0 && (
        <p className="mt-4 text-center text-sm text-faint">
          Add a friend in{" "}
          <Link href="/together" className="text-accent hover:underline">
            Together
          </Link>{" "}
          first — splitting takes two.
        </p>
      )}

      {/* balances */}
      {balances.size > 0 && (
        <section className="mt-8">
          <p className="label mb-3 text-faint">Balances</p>
          <ul className="divide-y divide-line border-y border-line">
            {[...balances.entries()].map(([id, v]) => {
              const friendOwesMe = v > 0;
              return (
                <li key={id} className="flex items-center justify-between gap-3 py-3">
                  <span className="min-w-0 text-[15px]">
                    <span className="text-ink">{nameOf(id)}</span>{" "}
                    <span className="text-muted">{friendOwesMe ? "owes you" : "— you owe"}</span>{" "}
                    <span className={clsx("tnum font-medium", friendOwesMe ? "text-accent" : "text-ink")}>{money(v)}</span>
                  </span>
                  <button
                    onClick={() => me && settleUp(me.id, id, Math.abs(v), friendOwesMe)}
                    className="shrink-0 text-sm text-muted transition-colors hover:text-ink"
                  >
                    Settle up
                  </button>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {/* history */}
      <section className="mt-8">
        <p className="label mb-3 text-faint">Recent</p>
        {loading ? (
          <ul className="space-y-2" aria-hidden>
            {[0, 1, 2].map((i) => (
              <li key={i} className="glass h-16 animate-pulse rounded-tile" />
            ))}
          </ul>
        ) : expenses.length === 0 ? (
          <p className="text-sm text-faint">No rounds split yet.</p>
        ) : (
          <ul className="space-y-2">
            {expenses.map((e) => (
              <ExpenseRow key={e.id} expense={e} meId={me?.id} nameOf={nameOf} />
            ))}
          </ul>
        )}
      </section>

      {adding && me && (
        <AddExpenseSheet me={me.id} meName={me.name} friends={friends} onClose={() => setAdding(false)} />
      )}
    </>
  );
}

function ExpenseRow({
  expense,
  meId,
  nameOf,
}: {
  expense: Expense;
  meId?: string;
  nameOf: (id: string) => string;
}) {
  const d = parseKey(toKey(new Date(expense.createdAt)));
  const payer = expense.payerId === meId ? "You" : nameOf(expense.payerId);
  const n = expense.shares.length || 1;
  return (
    <li className="glass flex items-center justify-between gap-3 rounded-tile px-4 py-3">
      <div className="min-w-0">
        <p className="truncate text-[15px] text-ink">{expense.description}</p>
        <p className="text-xs text-faint">
          {payer} paid · split {n} {n === 1 ? "way" : "ways"} · {MONTH_NAMES[d.getMonth()].slice(0, 3)} {d.getDate()}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-3">
        <span className="tnum text-[15px] text-ink">{money(expense.amount)}</span>
        {expense.payerId === meId && (
          <button
            onClick={() => deleteExpense(expense.id)}
            aria-label="Delete expense"
            className="text-xs text-faint transition-colors hover:text-ink"
          >
            Remove
          </button>
        )}
      </div>
    </li>
  );
}

function AddExpenseSheet({
  me,
  meName,
  friends,
  onClose,
}: {
  me: string;
  meName: string;
  friends: SocialProfile[];
  onClose: () => void;
}) {
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [payer, setPayer] = useState(me);
  const [participants, setParticipants] = useState<Set<string>>(new Set([me]));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const people: { id: string; name: string }[] = [{ id: me, name: meName }, ...friends.map((f) => ({ id: f.id, name: f.name }))];

  function toggle(id: string) {
    setParticipants((s) => {
      const next = new Set(s);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const amt = parseFloat(amount);
  const valid = description.trim().length > 0 && amt > 0 && participants.size >= 2;
  const each = valid ? amt / participants.size : 0;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!valid || busy) return;
    setBusy(true);
    setError(null);
    const err = await addExpense({
      meId: me,
      payerId: payer,
      description,
      amount: amt,
      participantIds: [...participants],
    });
    if (err) {
      setError(err);
      setBusy(false);
      return;
    }
    onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <button aria-label="Close" className="absolute inset-0 bg-ink/40 backdrop-blur-sm" onClick={onClose} />
      <div className="glass-strong animate-sheet relative max-h-[88dvh] w-full max-w-md overflow-y-auto rounded-t-[28px] p-6 sm:rounded-[28px] sm:p-8">
        <h2 className="font-display text-2xl text-ink">Split a tab</h2>

        <form onSubmit={submit} className="mt-5 space-y-5">
          <label className="block">
            <span className="label mb-1.5 block text-faint">What was it</span>
            <input
              autoFocus
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Round at The Kernel"
              className="w-full border-b border-line-strong bg-transparent pb-2 text-[15px] outline-none placeholder:text-faint focus:border-ink"
            />
          </label>

          <label className="block">
            <span className="label mb-1.5 block text-faint">Total ({currencySymbol(savedCurrency())})</span>
            <input
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              inputMode="decimal"
              placeholder="0"
              className="tnum w-full border-b border-line-strong bg-transparent pb-2 text-[15px] outline-none placeholder:text-faint focus:border-ink"
            />
          </label>

          <div>
            <span className="label mb-2 block text-faint">Who paid</span>
            <div className="flex flex-wrap gap-2">
              {people.map((p) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => setPayer(p.id)}
                  className={clsx(
                    "rounded-ctl border px-3 py-1.5 text-sm transition-colors",
                    payer === p.id ? "border-ink bg-ink text-paper" : "border-line-strong text-muted hover:border-ink hover:text-ink",
                  )}
                >
                  {p.id === me ? "You" : p.name}
                </button>
              ))}
            </div>
          </div>

          <div>
            <span className="label mb-2 block text-faint">Split between</span>
            <div className="flex flex-wrap gap-2">
              {people.map((p) => {
                const on = participants.has(p.id);
                return (
                  <button
                    key={p.id}
                    type="button"
                    onClick={() => toggle(p.id)}
                    aria-pressed={on}
                    className={clsx(
                      "rounded-ctl border px-3 py-1.5 text-sm transition-colors",
                      on ? "border-accent bg-accent text-accent-contrast" : "border-line-strong text-muted hover:border-ink hover:text-ink",
                    )}
                  >
                    {p.id === me ? "You" : p.name}
                  </button>
                );
              })}
            </div>
            {valid && (
              <p className="mt-2 text-xs text-faint">
                <span className="tnum">{money(each)}</span> each · {participants.size} people
              </p>
            )}
          </div>

          {error && <p className="text-sm text-accent">{error}</p>}

          <button
            type="submit"
            disabled={!valid || busy}
            className="w-full rounded-ctl bg-ink py-3 text-sm font-medium uppercase tracking-[0.12em] text-paper transition-opacity hover:opacity-90 disabled:opacity-40"
          >
            {busy ? "…" : "Add expense"}
          </button>
        </form>
      </div>
    </div>
  );
}
