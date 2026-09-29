"use client";

// The menu on the table, opened by an NFC tag or QR (bwdy.site/m/<slug>).
// "You'd probably like" is worked out here, on this device, from this person's own
// diary — the venue never learns who looked or what they like. "Log it" writes the
// drink straight into the diary with the venue filled in.
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import clsx from "clsx";
import { fetchMenu, menuPicks, type Menu, type MenuItem } from "@/lib/menus";
import { addEntry, useEntries } from "@/lib/store";
import { todayKey } from "@/lib/date";
import { formatMoney } from "@/lib/money";

export function MenuView({ slug }: { slug: string }) {
  const entries = useEntries();
  const [menu, setMenu] = useState<Menu | null | "missing" | "error">(null);
  const [noAlcoholOnly, setNoAlcoholOnly] = useState(false);
  const [logged, setLogged] = useState<string | null>(null);

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
          {item.name}
          {item.noAlcohol && <span className="ml-2 align-middle text-[11px] uppercase tracking-[0.12em] text-accent">No alcohol</span>}
        </span>
        {item.description && <span className="mt-0.5 block text-sm leading-relaxed text-muted">{item.description}</span>}
      </span>
      <span className="flex shrink-0 flex-col items-end gap-1">
        {item.price != null && <span className="tnum text-[15px] text-ink">{formatMoney(item.price, (menu as Menu).currency)}</span>}
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
        <p className="label mb-1 text-faint">{menu.venueKind === "store" || menu.venueKind === "shop"
            ? "On the shelf"
            : menu.venueKind === "sweet_shop" || menu.venueKind === "bakery"
              ? "At the counter"
              : "The menu"}</p>
        <h1 className="font-display text-4xl leading-tight tracking-tight text-ink">{menu.venueName}</h1>
        {menu.venueCity && <p className="mt-1.5 text-sm text-faint">{menu.venueCity}</p>}
      </header>

      {menu.sections.length === 0 ? (
        <p className="mt-10 text-center text-sm text-faint">The menu isn&apos;t up yet — ask at the bar.</p>
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

      <p className="mt-8 border-t border-line pt-5 text-xs leading-relaxed text-faint">
        Opening a menu tells {menu.venueName} nothing about you. Prices are the venue&apos;s own.
      </p>
    </main>
  );
}
