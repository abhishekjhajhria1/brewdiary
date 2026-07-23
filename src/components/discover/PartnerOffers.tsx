"use client";

// Partner offers — browse verified bars, see the DINING deal they're running, book
// a table. The "Zomato Dineout" surface.
//
// ── THE ONE LINE THIS SECTION IS ALLOWED TO CROSS ───────────────────────────
// VenuesNearby shows a bar's NAME and CITY only — never its offer — because an
// ALCOHOL offer is surrogate alcohol advertising (illegal in India). This section
// DOES show an offer, and that is lawful for the same reason Dineout is: the offer
// is a DINING deal (a bill discount, a set menu, an experience), never the alcohol.
// The database guarantees it — discover_offers() only ever returns dining_offers,
// only for verified BARS, and never joins venue_perks (the private alcohol loyalty
// card). If a "free drink" ever needs showing, it does NOT belong here. See 050.
import { useMemo, useState } from "react";
import clsx from "clsx";
import { useDiscoverOffers, createReservation, type DiscoverOffer } from "@/lib/reservations";
import { useAuth } from "@/lib/profile";
import { savedCountry } from "@/lib/age";

export interface VenueGroup {
  venueId: string;
  name: string;
  city?: string;
  offers: DiscoverOffer[];
}

export function PartnerOffers() {
  const country = useMemo(() => savedCountry(), []);
  const { offers, loading } = useDiscoverOffers(country);
  const [booking, setBooking] = useState<VenueGroup | null>(null);

  // discover_offers returns one row per (venue, offer); fold them into one card per venue.
  const groups = useMemo(() => {
    const by = new Map<string, VenueGroup>();
    for (const o of offers) {
      const g = by.get(o.venueId) ?? { venueId: o.venueId, name: o.name, city: o.city, offers: [] };
      g.offers.push(o);
      by.set(o.venueId, g);
    }
    return [...by.values()];
  }, [offers]);

  if (loading || groups.length === 0) return null;

  return (
    <section className="mt-9">
      <p className="label mb-3 text-faint">Offers &amp; tables</p>
      <ul className="space-y-3">
        {groups.map((g) => (
          <li key={g.venueId} className="glass rounded-tile p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-[15px] text-ink">{g.name}</p>
                {g.city && <p className="text-xs text-muted">{g.city}</p>}
              </div>
              <button
                onClick={() => setBooking(g)}
                className="glass glass-press shrink-0 rounded-ctl px-3 py-1.5 text-xs uppercase tracking-[0.12em] text-muted transition-colors hover:text-ink"
              >
                Book a table
              </button>
            </div>
            <ul className="mt-3 space-y-2 border-t border-line pt-3">
              {g.offers.map((o) => (
                <li key={o.offerId}>
                  <p className="text-sm text-accent">{o.title}</p>
                  {o.detail && <p className="mt-0.5 text-xs text-faint">{o.detail}</p>}
                </li>
              ))}
            </ul>
          </li>
        ))}
      </ul>
      <p className="mt-3 text-xs leading-relaxed text-faint">
        Dining offers from verified bars — a table deal, never a drink deal. Booking asks the venue to
        hold a table; they confirm it. What you drink, and whether you drink, is always up to you.
      </p>

      {booking && <BookTable group={booking} onClose={() => setBooking(null)} />}
    </section>
  );
}

// ── the booking sheet (reused by the plan cards, hence exported) ─────────────
export function BookTable({ group, onClose }: { group: VenueGroup; onClose: () => void }) {
  const signedIn = Boolean(useAuth().profile?.id);
  const today = useMemo(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }, []);

  const [offerId, setOfferId] = useState<string | undefined>(group.offers[0]?.offerId);
  const [date, setDate] = useState(today);
  const [time, setTime] = useState("");
  const [size, setSize] = useState(2);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function submit() {
    setBusy(true);
    setErr(null);
    const res = await createReservation(group.venueId, {
      date,
      time: time || undefined,
      partySize: size,
      note,
      offerId,
    });
    setBusy(false);
    if ("error" in res) setErr(res.error);
    else setDone(true);
  }

  const inputClass =
    "w-full rounded-ctl border border-line-strong bg-transparent px-3 py-2 text-sm outline-none placeholder:text-faint focus:border-ink";

  return (
    <div className="fixed inset-0 z-50 flex flex-col justify-end">
      <button aria-label="Close" onClick={onClose} className="animate-fade absolute inset-0 bg-black/50 backdrop-blur-[3px]" />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Book a table at ${group.name}`}
        className="glass-strong animate-sheet relative mx-auto flex max-h-[88dvh] w-full max-w-lg flex-col overflow-y-auto rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4"
      >
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong" />
        <header className="mb-5 flex items-start justify-between">
          <div>
            <h2 className="font-display text-3xl leading-none">{group.name}</h2>
            <span className="label mt-1 block">Book a table</span>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="-mr-1.5 -mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-2xl leading-none text-muted transition-colors hover:bg-ink/5 hover:text-ink"
          >
            ×
          </button>
        </header>

        {done ? (
          <div className="py-6 text-center">
            <p className="text-[15px] text-ink">Booking sent to {group.name}.</p>
            <p className="mt-1 text-sm text-faint">They&apos;ll confirm your table — you&apos;ll see it under You.</p>
            <button
              onClick={onClose}
              className="mt-5 inline-flex h-11 items-center justify-center rounded-ctl bg-ink px-6 text-sm font-medium text-paper transition-opacity hover:opacity-90"
            >
              Done
            </button>
          </div>
        ) : !signedIn ? (
          <p className="py-6 text-center text-sm leading-relaxed text-faint">
            Sign in to book a table — your booking is tied to your account so the venue can confirm it.
          </p>
        ) : (
          <div className="space-y-5">
            {group.offers.length > 0 && (
              <div>
                <span className="label mb-1.5 block">The deal</span>
                <div className="flex flex-wrap gap-1.5">
                  {group.offers.map((o) => (
                    <button
                      key={o.offerId}
                      type="button"
                      onClick={() => setOfferId(offerId === o.offerId ? undefined : o.offerId)}
                      aria-pressed={offerId === o.offerId}
                      className={clsx(
                        "rounded-ctl border px-3 py-1.5 text-xs transition-colors",
                        offerId === o.offerId
                          ? "border-transparent bg-accent/10 text-ink"
                          : "border-line text-muted hover:border-line-strong hover:text-ink",
                      )}
                    >
                      {o.title}
                    </button>
                  ))}
                </div>
              </div>
            )}

            <div className="flex gap-2">
              <div className="flex-1">
                <label className="label mb-1.5 block" htmlFor="res-date">
                  Date
                </label>
                <input
                  id="res-date"
                  type="date"
                  value={date}
                  min={today}
                  onChange={(e) => setDate(e.target.value)}
                  className={inputClass}
                />
              </div>
              <div className="w-32">
                <label className="label mb-1.5 block" htmlFor="res-time">
                  Time
                </label>
                <input id="res-time" type="time" value={time} onChange={(e) => setTime(e.target.value)} className={inputClass} />
              </div>
            </div>

            <div>
              <label className="label mb-1.5 block" htmlFor="res-size">
                Party size
              </label>
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  aria-label="One fewer"
                  disabled={size <= 1}
                  onClick={() => setSize((n) => Math.max(1, n - 1))}
                  className="glass glass-press flex h-10 w-10 items-center justify-center rounded-full text-xl leading-none text-muted transition-colors hover:text-ink disabled:cursor-not-allowed disabled:text-faint/40"
                >
                  −
                </button>
                <span className="tnum w-8 text-center text-xl text-ink">{size}</span>
                <button
                  type="button"
                  aria-label="One more"
                  disabled={size >= 50}
                  onClick={() => setSize((n) => Math.min(50, n + 1))}
                  className="glass glass-press flex h-10 w-10 items-center justify-center rounded-full text-xl leading-none text-muted transition-colors hover:text-ink disabled:cursor-not-allowed disabled:text-faint/40"
                >
                  +
                </button>
              </div>
            </div>

            <div>
              <label className="label mb-1.5 block" htmlFor="res-note">
                Anything to add?
              </label>
              <textarea
                id="res-note"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                rows={2}
                placeholder="A window table, a birthday, a high chair…"
                className={clsx(inputClass, "resize-none")}
              />
            </div>

            {err && <p className="text-sm text-accent">{err}</p>}

            <button
              onClick={submit}
              disabled={busy || !date}
              className={clsx(
                "flex h-12 w-full items-center justify-center rounded-ctl text-base font-medium transition-all active:scale-[0.99]",
                !busy && date ? "bg-ink text-paper hover:bg-ink/90" : "cursor-not-allowed bg-ink/10 text-faint",
              )}
            >
              {busy ? "Sending…" : "Request the table"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
