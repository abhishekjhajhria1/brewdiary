"use client";

// The shelf, and a list for the till (059). Nothing is ordered or paid here: at a liquor
// store the law puts an ID check on every bottle at the counter, and a list keeps that
// where it belongs. The list stays in this browser, one per shop (localStorage), and is
// shown as a QR the till scans (the same code the app makes — src/lib/scanCodes.ts).
import Link from "next/link";
import { useEffect, useState } from "react";
import { formatMoney } from "@/lib/money";
import { shopListQr } from "@/lib/scanCodes";
import { fetchShelf, type ShelfItem } from "@/lib/tableOrder";
import { QrSvg } from "@/components/ui/QrSvg";

const CATEGORY: Record<string, string> = {
  spirit: "Spirits",
  beer: "Beer",
  wine: "Wine",
  other_alcohol: "Other alcohol",
  soft: "Soft drinks",
  food: "Food",
  sweet: "Sweets",
  other: "Other",
};

function readList(slug: string): Record<string, number> {
  try {
    const raw = JSON.parse(localStorage.getItem(`brewdiary.list.${slug}`) ?? "{}") as Record<string, unknown>;
    return Object.fromEntries(Object.entries(raw).filter(([, v]) => typeof v === "number" && v > 0).map(([k, v]) => [k, Math.min(99, v as number)]));
  } catch {
    return {};
  }
}

function saveList(slug: string, list: Record<string, number>) {
  try {
    if (Object.keys(list).length === 0) localStorage.removeItem(`brewdiary.list.${slug}`);
    else localStorage.setItem(`brewdiary.list.${slug}`, JSON.stringify(list));
  } catch {
    /* private window: the list lasts this visit */
  }
}

const title = (i: ShelfItem) => (i.brand ? `${i.brand} ${i.name}` : i.name);
const pack = (i: ShelfItem) => (i.size == null ? "" : `${i.size % 1 === 0 ? i.size : i.size.toFixed(1)} ${i.unit ?? ""}`.trim());

export function ShelfView({ slug }: { slug: string }) {
  const [shelf, setShelf] = useState<Awaited<ReturnType<typeof fetchShelf>> | "missing" | "error" | undefined>(undefined);
  const [list, setList] = useState<Record<string, number>>({});
  const [showQr, setShowQr] = useState(false);
  const [q, setQ] = useState("");

  useEffect(() => {
    setList(readList(slug));
    let active = true;
    fetchShelf(slug)
      .then((s) => active && setShelf(s ?? "missing"))
      .catch(() => active && setShelf("error"));
    return () => {
      active = false;
    };
  }, [slug]);

  if (shelf === undefined) {
    return (
      <main className="flex-1" aria-hidden>
        <div className="glass mb-6 h-20 animate-pulse rounded-tile" />
        <div className="glass h-64 animate-pulse rounded-tile" />
      </main>
    );
  }
  if (shelf === "missing" || shelf === "error" || shelf === null) {
    return (
      <main className="flex-1 text-center">
        <p className="mt-16 font-display text-2xl text-ink">{shelf === "error" ? "Couldn't reach brewdiary." : "Nothing on this shelf online yet."}</p>
        <p className="mt-2 text-sm text-muted">{shelf === "error" ? "Check your connection and try again." : "Ask at the counter."}</p>
        <Link href={`/m/${slug}`} className="mt-6 inline-block text-sm font-medium text-accent hover:opacity-80">
          ← The menu
        </Link>
      </main>
    );
  }

  const byId = new Map(shelf.items.map((i) => [i.id, i]));
  const onList = Object.entries(list).flatMap(([id, qty]) => (byId.get(id) ? [{ item: byId.get(id)!, qty }] : []));
  const total = onList.reduce((s, l) => s + l.item.price * l.qty, 0);
  const alcohol = onList.some((l) => l.item.alcohol);
  const shown = shelf.items.filter((i) => !q.trim() || title(i).toLowerCase().includes(q.trim().toLowerCase()));
  const cats = Object.keys(CATEGORY).filter((c) => shown.some((i) => i.category === c));
  for (const i of shown) if (!cats.includes(i.category)) cats.push(i.category);

  function set(i: ShelfItem, qty: number) {
    setList((cur) => {
      const next = { ...cur };
      if (qty <= 0) delete next[i.id];
      else next[i.id] = Math.min(99, qty);
      saveList(slug, next);
      return next;
    });
  }

  return (
    <main className="flex-1">
      <header className="mb-6 border-b border-line pb-5">
        <p className="label mb-1 text-faint">The shelf · a list for the till</p>
        <h1 className="font-display text-4xl leading-tight tracking-tight text-ink">{shelf.venueName}</h1>
      </header>

      {onList.length > 0 && (
        <section className="glass mb-6 rounded-tile p-5" aria-label="Your list">
          <p className="label mb-2 text-accent">Your list</p>
          <ul className="space-y-1 text-[15px] text-ink">
            {onList.map((l) => (
              <li key={l.item.id}>
                {l.qty} × {title(l.item)}
              </li>
            ))}
          </ul>
          <p className="tnum mt-2 text-xs text-faint">About {formatMoney(total, shelf.currency)} — the till has the final word.</p>
          {showQr ? (
            <div className="mt-4 flex flex-col items-center gap-2">
              <QrSvg data={shopListQr(slug, onList.map((l) => ({ productId: l.item.id, qty: l.qty })))} label="Your list as a code for the till" />
              <p className="text-sm text-muted">Show this at the till. They scan it, and it&apos;s in their basket.</p>
            </div>
          ) : (
            <button onClick={() => setShowQr(true)} className="mt-4 min-h-12 w-full rounded-ctl bg-accent px-4 text-sm font-semibold text-paper">
              Show it at the till
            </button>
          )}
          <button
            onClick={() => {
              setList({});
              saveList(slug, {});
              setShowQr(false);
            }}
            className="mt-2 text-xs text-faint hover:text-ink"
          >
            Clear the list
          </button>
        </section>
      )}

      <input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Find something"
        aria-label="Find something on the shelf"
        className="glass mb-5 w-full rounded-ctl px-4 py-3 text-sm text-ink placeholder:text-faint"
      />

      {cats.map((c) => (
        <section key={c} className="mb-6">
          <p className="label mb-1 text-faint">{CATEGORY[c] ?? c}</p>
          <ul className="divide-y divide-line border-y border-line">
            {shown
              .filter((i) => i.category === c)
              .map((i) => {
                const n = list[i.id] ?? 0;
                return (
                  <li key={i.id} className="flex items-center justify-between gap-4 py-3">
                    <span className="min-w-0">
                      <span className="block text-[15px] text-ink">{title(i)}</span>
                      <span className="tnum block text-xs text-faint">
                        {[pack(i), `${formatMoney(i.price, shelf.currency)}${i.byWeight ? " a kg" : ""}`, i.mrp && i.mrp > i.price ? `MRP ${formatMoney(i.mrp, shelf.currency)}` : ""].filter(Boolean).join(" · ")}
                      </span>
                    </span>
                    {i.byWeight ? (
                      <span className="shrink-0 text-right text-xs text-faint">weighed at the counter</span>
                    ) : (
                      <span className="flex shrink-0 items-center gap-1">
                        {n > 0 && (
                          <>
                            <button onClick={() => set(i, n - 1)} aria-label={`One fewer ${title(i)}`} className="glass glass-press h-9 w-9 rounded-ctl text-ink">
                              −
                            </button>
                            <span className="tnum w-5 text-center text-sm text-ink">{n}</span>
                          </>
                        )}
                        <button onClick={() => set(i, n + 1)} aria-label={`Add ${title(i)} to the list`} className="h-9 rounded-ctl bg-accent px-3 text-xs font-semibold uppercase tracking-[0.1em] text-paper">
                          Add
                        </button>
                      </span>
                    )}
                  </li>
                );
              })}
          </ul>
        </section>
      ))}

      <p className="mt-8 border-t border-line pt-5 text-xs leading-relaxed text-faint">
        {alcohol
          ? "Bottles are sold at the counter, where the law asks for an ID check. A list only saves you the hunt — nothing is ordered or paid here."
          : "A list only saves you the hunt — nothing is ordered or paid here. Opening the shelf tells the shop nothing about you."}
      </p>
    </main>
  );
}
