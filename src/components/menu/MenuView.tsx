"use client";

// The menu on the table, opened by an NFC tag or QR (bwdy.site/m/<slug>), or by a
// table's own link (bwdy.site/t/<code>), which knows the table: there, if the venue
// switched it on, a guest can send an order and call staff (051). How it goes in is the
// venue's choice (059): a staff OK first, or straight to the bar and kitchen; at a
// counter (a pickup point) it gets a number, followed here until it's ready. A liquor
// store's bottles are never phone-ordered — its shelf makes a list for the till.
// "You'd probably like" is worked out here, on this device, from this person's own
// diary — the venue never learns who looked or what they like. "Log it" writes the
// drink straight into the diary with the venue filled in.
import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import clsx from "clsx";
import { fetchMenu, menuPicks, type Menu, type MenuItem } from "@/lib/menus";
import { addEntry, useEntries } from "@/lib/store";
import { todayKey } from "@/lib/date";
import { formatMoney } from "@/lib/money";
import { useAuth } from "@/lib/profile";
import {
  basketTotal,
  callStaff,
  isCounterKind,
  orderLive,
  orderStep,
  orderWords,
  placeOrder,
  useMyOrders,
  withdrawRequest,
  type CallKind,
  type OrderStatus,
  type TableInfo,
} from "@/lib/tableOrder";

const ALLERGEN_LABEL: Record<string, string> = {
  gluten: "gluten",
  crustaceans: "crustaceans",
  eggs: "eggs",
  fish: "fish",
  peanuts: "peanuts",
  soy: "soy",
  milk: "milk",
  nuts: "tree nuts",
  celery: "celery",
  mustard: "mustard",
  sesame: "sesame",
  sulphites: "sulphites",
  lupin: "lupin",
  molluscs: "molluscs",
};

/** India's menu mark: a square with a dot, green for veg, brown for non-veg — and a word for screen readers. */
function DietMark({ diet }: { diet: NonNullable<MenuItem["diet"]> }) {
  const color = diet === "veg" || diet === "vegan" ? "#2E7650" : diet === "egg" ? "#9A7A2A" : "#8B3A2A";
  const label = diet === "veg" ? "vegetarian" : diet === "vegan" ? "vegan" : diet === "egg" ? "contains egg" : "non-vegetarian";
  return (
    <span
      role="img"
      aria-label={label}
      title={label}
      className="mr-2 inline-flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-[2px] border-[1.5px] align-[-2px]"
      style={{ borderColor: color }}
    >
      <span className={clsx("h-1.5 w-1.5", diet === "non_veg" ? "" : "rounded-full")} style={{ background: color }} />
    </span>
  );
}

export function MenuView({ slug, table }: { slug: string; table?: TableInfo }) {
  const entries = useEntries();
  const auth = useAuth();
  const [menu, setMenu] = useState<Menu | null | "missing" | "error">(null);
  const [noAlcoholOnly, setNoAlcoholOnly] = useState(false);
  const [logged, setLogged] = useState<string | null>(null);
  const [basket, setBasket] = useState<Map<string, number>>(new Map());
  const [orderNote, setOrderNote] = useState("");
  const [sending, setSending] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);
  const signedIn = auth.status === "authed";
  const takesOrders = Boolean(table?.tableService);
  // Signed in — or the venue takes orders without an account (this browser's secret).
  const ordering = takesOrders && (signedIn || Boolean(table?.ordersAnon));
  const atPickup = table?.pointKind === "pickup";
  const allOrders = useMyOrders(ordering, signedIn, nonce);
  const venueName = menu && typeof menu === "object" ? menu.venueName : "";
  const mine = allOrders.filter((o) => !o.venueName || o.venueName === venueName);
  const saidReady = useRef<Map<string, string>>(new Map());

  // An order turning ready: a buzz, a word on the page, and a notification if allowed.
  useEffect(() => {
    for (const o of mine) {
      const before = saidReady.current.get(o.id);
      saidReady.current.set(o.id, o.status);
      if (o.status !== "ready" || before === undefined || before === "ready") continue;
      const what = o.pickupNo != null ? `Number ${o.pickupNo} is ready` : "Your order is ready";
      const where = o.atPickup ? `collect it${o.point ? ` at ${o.point}` : ""}` : "it's on its way to you";
      setMsg(`${what} — ${where}.`);
      try {
        navigator.vibrate?.([120, 60, 120]);
        if (typeof Notification !== "undefined" && Notification.permission === "granted" && document.visibilityState !== "visible") {
          new Notification(`${what} · ${venueName}`, { body: where[0].toUpperCase() + where.slice(1) + "." });
        }
      } catch {
        /* the word on the page is enough */
      }
    }
  }, [mine, venueName]);

  useEffect(() => {
    let active = true;
    fetchMenu(slug)
      .then((m) => active && setMenu(m ?? "missing"))
      .catch(() => active && setMenu("error"));
    return () => {
      active = false;
    };
  }, [slug]);

  const picks = useMemo(() => (menu && typeof menu === "object" ? menuPicks(menu, entries) : []), [menu, entries]);

  if (menu === null) {
    return (
      <main className="flex-1" aria-hidden>
        <div className="glass mb-6 h-20 animate-pulse rounded-tile" />
        <div className="glass h-64 animate-pulse rounded-tile" />
      </main>
    );
  }
  if (menu === "missing" || menu === "error") {
    return (
      <main className="flex-1 text-center">
        <p className="mt-16 font-display text-2xl text-ink">{menu === "error" ? "Couldn't reach brewdiary." : "No menu here."}</p>
        <p className="mt-2 text-sm text-muted">
          {menu === "error" ? "Check your connection and try again." : "The tag may be old, or this place isn't on brewdiary yet — ask for a paper menu."}
        </p>
        <Link href="/" className="mt-6 inline-block text-sm font-medium text-accent hover:opacity-80">
          Go to brewdiary →
        </Link>
      </main>
    );
  }

  const byId = new Map(menu.sections.flatMap((s) => s.items.map((i) => [i.id, i] as const)));
  const pickItems = picks.map((id) => byId.get(id)).filter((x): x is MenuItem => !!x);
  const hasNoAlcohol = menu.sections.some((s) => s.items.some((i) => i.noAlcohol));
  const sections = menu.sections
    .map((s) => ({ ...s, items: noAlcoholOnly ? s.items.filter((i) => i.noAlcohol) : s.items }))
    .filter((s) => s.items.length > 0);

  const prices = new Map(menu.sections.flatMap((s) => s.items.map((i) => [i.id, i.price] as const)));
  const count = [...basket.values()].reduce((a, b) => a + b, 0);

  function add(item: MenuItem, d: number) {
    setBasket((b) => {
      const next = new Map(b);
      const q = Math.max(0, Math.min(20, (next.get(item.id) ?? 0) + d));
      if (q === 0) next.delete(item.id);
      else next.set(item.id, q);
      return next;
    });
  }

  async function send() {
    if (!table || count === 0) return;
    if (table.ordersPaused) return setMsg("The kitchen has paused phone orders for a few minutes — order at the bar.");
    setSending(true);
    setMsg(null);
    const { status, error } = await placeOrder(table.code, [...basket].map(([item, qty]) => ({ item, qty })), signedIn, orderNote.trim() || undefined);
    setSending(false);
    if (error) return setMsg(error[0].toUpperCase() + error.slice(1));
    setBasket(new Map());
    setOrderNote("");
    setMsg(
      status?.pickupNo != null
        ? `Ordered — your number is ${status.pickupNo}. Keep this page open; it says when it's ready.`
        : !status || status.status === "pending"
          ? "Sent — the staff will confirm it."
          : "Sent to the bar and the kitchen.",
    );
    // So "ready" can reach you when you look away: asked once, at the moment it matters.
    if (status?.pickupNo != null && typeof Notification !== "undefined" && Notification.permission === "default") {
      void Notification.requestPermission().catch(() => {});
    }
    setNonce((n) => n + 1);
  }

  async function call(kind: CallKind) {
    if (!table) return;
    const err = await callStaff(table.code, kind, signedIn);
    setMsg(err ?? (kind === "bill" ? "They're bringing the bill." : kind === "water" ? "Water's on its way." : "Someone's coming over."));
  }

  function logIt(item: MenuItem) {
    addEntry({
      date: todayKey(),
      drink: item.name,
      type: item.kind && item.kind !== "food" ? item.kind : undefined,
      venue: (menu as Menu).venueName,
    });
    setLogged(item.id);
    setTimeout(() => setLogged((cur) => (cur === item.id ? null : cur)), 1600);
  }

  const row = (item: MenuItem) => (
    <li key={item.id} className="flex items-start justify-between gap-4 py-3">
      <span className="min-w-0">
        <span className="block text-[15px] text-ink">
          {item.diet && <DietMark diet={item.diet} />}
          {item.name}
          {item.noAlcohol && <span className="ml-2 align-middle text-[11px] uppercase tracking-[0.12em] text-accent">No alcohol</span>}
        </span>
        {item.description && <span className="mt-0.5 block text-sm leading-relaxed text-muted">{item.description}</span>}
        {(item.allergens ?? []).length > 0 && (
          <span className="mt-0.5 block text-xs text-faint">Contains {(item.allergens ?? []).map((a) => ALLERGEN_LABEL[a] ?? a).join(", ")}</span>
        )}
      </span>
      <span className="flex shrink-0 flex-col items-end gap-1">
        {item.price != null && <span className="tnum text-[15px] text-ink">{formatMoney(item.price, (menu as Menu).currency)}</span>}
        {ordering && table?.legalClass === "off_trade" && !item.noAlcohol && <span className="text-xs text-faint">at the counter</span>}
        {ordering && !(table?.legalClass === "off_trade" && !item.noAlcohol) && (
          <span className="flex items-center gap-1">
            {(basket.get(item.id) ?? 0) > 0 && (
              <>
                <button onClick={() => add(item, -1)} aria-label={`One fewer ${item.name}`} className="glass glass-press h-9 w-9 rounded-ctl text-ink">
                  −
                </button>
                <span className="tnum w-5 text-center text-sm text-ink">{basket.get(item.id)}</span>
              </>
            )}
            <button
              onClick={() => add(item, 1)}
              aria-label={`Add ${item.name}`}
              className="h-9 rounded-ctl bg-accent px-3 text-xs font-semibold uppercase tracking-[0.1em] text-paper"
            >
              Add
            </button>
          </span>
        )}
        {item.kind !== "food" && (
          <button
            onClick={() => logIt(item)}
            className={clsx("text-xs transition-colors", logged === item.id ? "font-medium text-accent" : "text-faint hover:text-ink")}
          >
            {logged === item.id ? "Logged ✓" : "Log it"}
          </button>
        )}
      </span>
    </li>
  );

  return (
    <main className="flex-1">
      <header className="mb-6 border-b border-line pb-5">
        {table && <p className="label mb-1 text-accent">{atPickup ? table.tableLabel : `Table ${table.tableLabel}`}</p>}
        <p className="label mb-1 text-faint">{menu.venueKind === "store" || menu.venueKind === "shop"
            ? "On the shelf"
            : menu.venueKind === "sweet_shop" || menu.venueKind === "bakery"
              ? "At the counter"
              : "The menu"}</p>
        <h1 className="font-display text-4xl leading-tight tracking-tight text-ink">{menu.venueName}</h1>
        {menu.venueCity && <p className="mt-1.5 text-sm text-faint">{menu.venueCity}</p>}
      </header>

      {isCounterKind(menu.venueKind) && (
        <Link href={`/m/${slug}/shelf`} className="glass glass-press mb-6 flex items-center justify-between gap-4 rounded-tile p-5">
          <span>
            <span className="block text-[15px] text-ink">The shelf — make a list</span>
            <span className="mt-0.5 block text-sm text-muted">What&apos;s in stock, at its price. Show the list at the till and it&apos;s in their basket.</span>
          </span>
          <span aria-hidden className="text-faint">→</span>
        </Link>
      )}

      {ordering && table?.ordersPaused && (
        <p role="status" className="glass mb-6 rounded-tile p-5 text-[15px] text-ink">
          The kitchen has paused phone orders for a few minutes. Order at the bar, or try again shortly.
        </p>
      )}
      {ordering && atPickup && !table?.ordersPaused && mine.length === 0 && (
        <p className="mb-6 text-sm text-muted">Order here and get a number. This page says when it&apos;s ready — then collect it at {table?.tableLabel}.</p>
      )}
      {ordering && mine.filter((o) => orderLive(o) || Date.now() - Date.parse(o.createdAt) < 30 * 60_000).slice(0, 4).map((o) => (
        <OrderCard
          key={o.id}
          order={o}
          onCancel={
            o.status === "pending"
              ? async () => {
                  await withdrawRequest(o.id, signedIn);
                  setNonce((n) => n + 1);
                }
              : undefined
          }
        />
      ))}

      {menu.sections.length === 0 ? (
        isCounterKind(menu.venueKind) ? null : <p className="mt-10 text-center text-sm text-faint">The menu isn&apos;t up yet — ask at the bar.</p>
      ) : (
        <>
          {pickItems.length > 0 && !noAlcoholOnly && (
            <section className="glass mb-6 rounded-tile p-5">
              <p className="label mb-1 text-accent">You&apos;d probably like</p>
              <p className="mb-2 text-xs text-faint">From your own diary, worked out on this device. {menu.venueName} doesn&apos;t see it.</p>
              <ul className="divide-y divide-line">{pickItems.map(row)}</ul>
            </section>
          )}

          {hasNoAlcohol && (
            <button
              onClick={() => setNoAlcoholOnly((v) => !v)}
              aria-pressed={noAlcoholOnly}
              className={clsx(
                "mb-5 rounded-ctl px-3 py-1.5 text-xs transition-colors",
                noAlcoholOnly ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
              )}
            >
              No alcohol only
            </button>
          )}

          {sections.map((s) => (
            <section key={s.name} className="mb-6">
              <p className="label mb-1 text-faint">{s.name}</p>
              <ul className="divide-y divide-line border-y border-line">{s.items.map(row)}</ul>
            </section>
          ))}
        </>
      )}

      {table && takesOrders && !ordering && !signedIn && (
        <section className="glass mt-6 rounded-tile p-5">
          <p className="text-[15px] text-ink">{atPickup ? "Order here and collect by number" : "Order from your phone, or call staff"}</p>
          <p className="mt-1 text-sm text-muted">Sign in to brewdiary (it&apos;s free) and come back to this page. Or just wave — they&apos;ll see you.</p>
          <Link href="/" className="mt-3 inline-block text-sm font-medium text-accent hover:opacity-80">
            Sign in →
          </Link>
        </section>
      )}

      {table && ordering && !atPickup && (
        <section className="mt-6">
          <p className="label mb-2 text-faint">At table {table.tableLabel}</p>
          <div className="flex flex-wrap gap-2">
            {(
              [
                ["staff", "Call staff"],
                ["bill", "Bill please"],
                ["water", "Water"],
              ] as const
            ).map(([k, label]) => (
              <button key={k} onClick={() => call(k)} className="glass glass-press min-h-11 rounded-ctl px-4 text-sm text-ink">
                {label}
              </button>
            ))}
          </div>
        </section>
      )}

      {ordering && table?.legalClass === "off_trade" && menu.sections.some((sec) => sec.items.some((i) => !i.noAlcohol)) && (
        <p className="mt-6 text-sm text-muted">Bottles are bought at the counter — the law asks for an ID check there. Make a list from the shelf and show it at the till.</p>
      )}

      {msg && (
        <p role="status" className="mt-4 text-sm text-accent">
          {msg}
        </p>
      )}

      <p className="mt-8 border-t border-line pt-5 text-xs leading-relaxed text-faint">
        Opening a menu tells {menu.venueName} nothing about you. Prices are the venue&apos;s own.
        {ordering &&
          (table?.ordersDirect
            ? ` An order goes straight to the bar and the kitchen; they see ${atPickup ? "a number" : "the table"}, never your name.`
            : ` An order waits for the staff to confirm it; they see ${atPickup ? "a number" : "the table"}, never your name.`)}
      </p>

      {table && ordering && count > 0 && (
        <div className="sticky bottom-3 mt-6">
          <div className="glass-strong flex flex-col gap-3 rounded-tile p-4">
            <input
              value={orderNote}
              onChange={(e) => setOrderNote(e.target.value.slice(0, 200))}
              placeholder="A note for the staff (optional)"
              aria-label="A note for the staff"
              className="rounded-ctl border border-line bg-transparent px-3 py-2 text-sm text-ink placeholder:text-faint"
            />
            <button
              onClick={send}
              disabled={sending}
              className="min-h-12 rounded-ctl bg-ink px-4 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              {sending
                ? "Sending…"
                : `${atPickup ? "Order" : table.ordersDirect ? "Send to the bar" : "Send"} ${count} ${count === 1 ? "item" : "items"} · ${formatMoney(basketTotal(basket, prices), menu.currency)}`}
            </button>
          </div>
        </div>
      )}
    </main>

  );
}

/** One of your orders: its number (at a counter), what's on it, and the four steps. */
function OrderCard({ order: o, onCancel }: { order: OrderStatus; onCancel?: () => void }) {
  const step = orderStep(o);
  const ready = o.status === "ready";
  const steps = o.atPickup ? ["Sent", "Making", "Ready", "Collected"] : ["Sent", "Making", "Ready", "Served"];
  return (
    <section className={clsx("glass mb-4 rounded-tile p-5", ready && "ring-1 ring-accent")} aria-live="polite">
      <div className="flex items-start gap-5">
        {o.pickupNo != null && (
          <div aria-label={`Your number is ${o.pickupNo}`}>
            <p className={clsx("label", ready ? "text-accent" : "text-faint")}>Your number</p>
            <p className={clsx("tnum font-display text-5xl leading-none", ready ? "text-accent" : "text-ink")}>{o.pickupNo}</p>
          </div>
        )}
        <div className="min-w-0 flex-1">
          <p className="text-[15px] text-ink">{o.lines.map((l) => `${l.qty} × ${l.name}`).join(", ")}</p>
          <p className={clsx("mt-0.5 text-sm", ready ? "text-accent" : "text-muted")}>{orderWords(o)}</p>
        </div>
        {onCancel && (
          <button onClick={onCancel} className="shrink-0 text-xs text-faint hover:text-ink">
            Cancel
          </button>
        )}
      </div>
      {step >= 0 && (
        <ol className="mt-4 grid grid-cols-4 gap-1.5" aria-label={`Step ${step + 1} of 4: ${steps[step]}`}>
          {steps.map((label, i) => (
            <li key={label}>
              <span className={clsx("block h-1 rounded-full transition-colors", i <= step ? "bg-accent" : "bg-line")} />
              <span className={clsx("mt-1 block text-[11px]", i === step ? "text-ink" : "text-faint")}>{label}</span>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
