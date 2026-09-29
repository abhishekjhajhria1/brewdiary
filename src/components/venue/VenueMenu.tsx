"use client";

// The venue's menu, and the tags that open it.
//
// Guests tap an NFC sticker (or scan the QR) on the table; it holds one plain link,
// bwdy.site/m/<slug>. Phones with the app open the menu in the app, everyone else
// gets the website — so one ₹20 sticker works for every guest. On Android Chrome
// the dashboard can write the sticker itself (Web NFC); elsewhere, any NFC-writer
// app does it with the copied link.
//
// A menu is NOT an offer: name, section, description, price. No discount field,
// no "tonight only" — see supabase/042_menus.sql. And it is only served once the
// venue is verified.
import { useMemo, useState } from "react";
import clsx from "clsx";
import {
  MENU_KINDS,
  addMenuItem,
  checkMenuItem,
  menuUrl,
  removeMenuItem,
  updateMenuItem,
  useMenuItems,
  type EditableMenuItem,
  type MenuItemInput,
  type MenuKind,
} from "@/lib/menus";
import { currencyForCountry, currencySymbol, formatMoney } from "@/lib/money";
import type { Venue } from "@/lib/venues";
import { RoomQr } from "./RoomQr";

const KIND_LABEL: Record<MenuKind, string> = {
  cocktail: "Cocktail",
  beer: "Beer",
  wine: "Wine",
  spirit: "Spirit",
  coffee: "Coffee",
  tea: "Tea",
  soft: "Soft drink",
  food: "Food",
  other: "Other",
};

const EMPTY: MenuItemInput = { section: "", name: "", description: "", noAlcohol: false };

// Web NFC (Chrome on Android). Typed loosely: it isn't in the DOM lib yet.
type NdefWriter = { write: (msg: { records: { recordType: string; data: string }[] }) => Promise<void> };
function ndefWriter(): NdefWriter | null {
  if (typeof window === "undefined" || !("NDEFReader" in window)) return null;
  const Ctor = (window as unknown as { NDEFReader: new () => NdefWriter }).NDEFReader;
  return new Ctor();
}

export function VenueMenu({ venue }: { venue: Venue }) {
  const { items, loading } = useMenuItems(venue.id);
  const currency = currencyForCountry(venue.country);
  const origin =
    typeof window !== "undefined" ? `${location.protocol}//${location.host.replace(/^bar\./, "")}` : "https://bwdy.site";
  const url = menuUrl(venue.slug, origin);

  const [form, setForm] = useState<MenuItemInput>(EMPTY);
  const [priceText, setPriceText] = useState("");
  const [editing, setEditing] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [qr, setQr] = useState(false);
  const [copied, setCopied] = useState(false);
  const [nfc, setNfc] = useState<"idle" | "waiting" | "done" | "failed">("idle");
  const canWriteNfc = typeof window !== "undefined" && "NDEFReader" in window;

  const sections = useMemo(() => {
    const order: string[] = [];
    const by = new Map<string, EditableMenuItem[]>();
    for (const it of items) {
      if (!by.has(it.section)) {
        by.set(it.section, []);
        order.push(it.section);
      }
      by.get(it.section)!.push(it);
    }
    return order.map((name) => ({ name, items: by.get(name)! }));
  }, [items]);

  function startEdit(it: EditableMenuItem) {
    setEditing(it.id);
    setForm({ section: it.section, name: it.name, description: it.description ?? "", kind: it.kind, noAlcohol: it.noAlcohol });
    setPriceText(it.price == null ? "" : String(it.price));
    setError(null);
  }

  function reset() {
    setEditing(null);
    setForm((f) => ({ ...EMPTY, section: f.section })); // keep the section: items come in runs
    setPriceText("");
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    const price = priceText.trim() === "" ? undefined : Number(priceText.replace(/,/g, ""));
    const input = { ...form, price };
    const bad = checkMenuItem(input);
    if (bad) return setError(bad);
    setBusy(true);
    const err = editing ? await updateMenuItem(editing, input) : await addMenuItem(venue.id, input, items.length);
    setBusy(false);
    if (err) return setError(err);
    setError(null);
    reset();
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {}
  }

  async function writeTag() {
    const w = ndefWriter();
    if (!w) return;
    setNfc("waiting");
    try {
      await w.write({ records: [{ recordType: "url", data: url }] });
      setNfc("done");
      setTimeout(() => setNfc("idle"), 2500);
    } catch {
      setNfc("failed");
    }
  }

  return (
    <div>
      {/* ── the tag ─────────────────────────────────────────────────────── */}
      <div className="glass mb-5 rounded-tile p-4">
        <p className="label mb-1 text-faint">Tap to open the menu</p>
        <p className="mb-3 text-xs leading-relaxed text-faint">
          Stick an NFC tag (NTAG213 or better) on each table with this link. Guests hold their phone near it and
          the menu opens — in the app if they have it, in the browser if they don&apos;t. The QR does the same for
          phones without NFC.
        </p>
        <p className="tnum mb-3 truncate rounded-ctl bg-ink/5 px-3 py-2 text-sm text-ink">{url}</p>
        <div className="flex flex-wrap gap-2 text-sm">
          {canWriteNfc && (
            <button
              onClick={writeTag}
              disabled={nfc === "waiting"}
              className="rounded-ctl bg-accent px-3 py-2 font-medium text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-60"
            >
              {nfc === "waiting" ? "Hold a tag to the phone…" : nfc === "done" ? "Tag written ✓" : "Write an NFC tag"}
            </button>
          )}
          <button onClick={copy} className={clsx("glass glass-press rounded-ctl px-3 py-2", copied ? "font-medium text-accent" : "text-muted")}>
            {copied ? "Copied" : "Copy link"}
          </button>
          <button onClick={() => setQr(true)} className="glass glass-press rounded-ctl px-3 py-2 text-muted">
            QR to print
          </button>
        </div>
        {nfc === "failed" && <p className="mt-2 text-xs text-accent">That tag didn&apos;t take — try another, or an NFC writer app with the link.</p>}
        {!canWriteNfc && (
          <p className="mt-2 text-xs text-faint">To write tags from here, open this page in Chrome on an Android phone. Any NFC writer app works too.</p>
        )}
        {!venue.verified && (
          <p className="mt-2 text-xs text-faint">Guests see the menu once the venue is verified. You can build it now.</p>
        )}
      </div>

      {/* ── the items ───────────────────────────────────────────────────── */}
      {loading ? (
        <div className="glass h-24 animate-pulse rounded-ctl" />
      ) : sections.length === 0 ? (
        <p className="mb-4 text-sm text-faint">No items yet. Add your first below — start with what people order most.</p>
      ) : (
        sections.map((s) => (
          <div key={s.name} className="mb-4">
            <p className="label mb-1 text-faint">{s.name}</p>
            <ul className="divide-y divide-line border-y border-line">
              {s.items.map((it) => (
                <li key={it.id} className="flex items-center justify-between gap-3 py-2.5">
                  <span className={clsx("min-w-0", !it.available && "opacity-50")}>
                    <span className="block truncate text-[15px] text-ink">
                      {it.name}
                      {it.noAlcohol && <span className="ml-2 text-[11px] uppercase tracking-[0.12em] text-accent">No alcohol</span>}
                    </span>
                    <span className="tnum text-xs text-faint">
                      {it.price != null ? formatMoney(it.price, currency) : "No price"}
                      {it.kind && <> · {KIND_LABEL[it.kind]}</>}
                      {!it.available && <> · off tonight</>}
                    </span>
                  </span>
                  <span className="flex shrink-0 items-center gap-3 text-sm">
                    <button
                      onClick={() => updateMenuItem(it.id, { available: !it.available })}
                      className="text-faint transition-colors hover:text-ink"
                    >
                      {it.available ? "Off tonight" : "Back on"}
                    </button>
                    <button onClick={() => startEdit(it)} className="text-faint transition-colors hover:text-ink">
                      Edit
                    </button>
                    <button onClick={() => removeMenuItem(it.id)} className="text-faint transition-colors hover:text-ink">
                      Remove
                    </button>
                  </span>
                </li>
              ))}
            </ul>
          </div>
        ))
      )}

      <form onSubmit={save} className="glass mt-5 space-y-3 rounded-tile p-4">
        <p className="label text-faint">{editing ? "Edit item" : "Add an item"}</p>
        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <span className="mb-1 block text-xs text-faint">Section</span>
            <input
              list="menu-sections"
              value={form.section}
              onChange={(e) => setForm({ ...form, section: e.target.value })}
              placeholder="Cocktails"
              className="w-full rounded-ctl border border-line bg-transparent px-3 py-2 text-[15px] text-ink outline-none focus:border-accent"
            />
            <datalist id="menu-sections">
              {sections.map((s) => (
                <option key={s.name} value={s.name} />
              ))}
            </datalist>
          </label>
          <label className="block">
            <span className="mb-1 block text-xs text-faint">Price ({currencySymbol(currency)})</span>
            <input
              inputMode="decimal"
              value={priceText}
              onChange={(e) => setPriceText(e.target.value)}
              placeholder="Optional"
              className="tnum w-full rounded-ctl border border-line bg-transparent px-3 py-2 text-[15px] text-ink outline-none focus:border-accent"
            />
          </label>
        </div>
        <label className="block">
          <span className="mb-1 block text-xs text-faint">Name</span>
          <input
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            placeholder="Mezcal Negroni"
            className="w-full rounded-ctl border border-line bg-transparent px-3 py-2 text-[15px] text-ink outline-none focus:border-accent"
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-xs text-faint">Description</span>
          <input
            value={form.description ?? ""}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
            placeholder="Optional — what's in it, where it's from"
            className="w-full rounded-ctl border border-line bg-transparent px-3 py-2 text-[15px] text-ink outline-none focus:border-accent"
          />
        </label>
        <div className="flex flex-wrap items-center gap-3">
          <select
            value={form.kind ?? ""}
            onChange={(e) => setForm({ ...form, kind: (e.target.value || undefined) as MenuKind | undefined })}
            className="rounded-ctl border border-line bg-transparent px-3 py-2 text-sm text-ink outline-none focus:border-accent"
            aria-label="Kind"
          >
            <option value="">Kind (optional)</option>
            {MENU_KINDS.map((k) => (
              <option key={k} value={k}>
                {KIND_LABEL[k]}
              </option>
            ))}
          </select>
          <label className="flex items-center gap-2 text-sm text-muted">
            <input type="checkbox" checked={form.noAlcohol} onChange={(e) => setForm({ ...form, noAlcohol: e.target.checked })} />
            No alcohol
          </label>
        </div>
        {error && <p className="text-sm text-accent">{error}</p>}
        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={busy}
            className="rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {busy ? "Saving…" : editing ? "Save" : "Add to menu"}
          </button>
          {editing && (
            <button type="button" onClick={reset} className="text-sm text-faint hover:text-ink">
              Cancel
            </button>
          )}
        </div>
        <p className="text-xs leading-relaxed text-faint">
          A menu, not an offer: there&apos;s no discount or &ldquo;tonight only&rdquo; here, by design — that would be
          alcohol advertising in most of the places we operate.
        </p>
      </form>

      {qr && (
        <RoomQr
          url={url}
          code={venue.slug}
          caption="Tap or scan for the menu"
          hint="Print this for the tables, next to the NFC tag. It opens the same menu."
          fileName={`brewdiary-menu-${venue.slug}.png`}
          onClose={() => setQr(false)}
        />
      )}
    </div>
  );
}
