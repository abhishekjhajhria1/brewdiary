"use client";

// The venue GUEST BOOK — a first-party CRM. Find a guest who's been to your venue,
// see the history YOUR venue generated (visits, tabs, perks), and keep your own
// notes and tags on them. It never shows their diary or anything from another bar —
// the database refuses (see 040_guest_book.sql). The guest can see and delete every
// note kept on them from You › Settings.
import { useEffect, useState } from "react";
import type { Venue } from "@/lib/venues";
import { searchUsers, type SocialProfile } from "@/lib/friends";
import { useGuestCard, setGuestNote } from "@/lib/guestbook";
import { currencyForCountry, formatMoney } from "@/lib/money";

const inputClass = "glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint";

function niceDate(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });
}

export function GuestBook({ venue }: { venue: Venue }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SocialProfile[]>([]);
  const [guest, setGuest] = useState<SocialProfile | null>(null);

  useEffect(() => {
    if (guest || query.trim().length < 2) {
      setResults([]);
      return;
    }
    const t = setTimeout(async () => setResults(await searchUsers(query)), 300);
    return () => clearTimeout(t);
  }, [query, guest]);

  return (
    <div className="mb-5">
      <p className="label mb-1.5 text-faint">Guest book</p>
      <p className="mb-3 text-xs leading-relaxed text-faint">
        Your own notes on the regulars you serve — what they like, what they&apos;ve had here. First-party only:
        never their diary, never another bar. They can see and erase anything you keep.
      </p>

      {guest ? (
        <GuestDetail venue={venue} guest={guest} onBack={() => setGuest(null)} />
      ) : (
        <>
          <label htmlFor={`gb-${venue.id}`} className="sr-only">
            Find a guest
          </label>
          <input
            id={`gb-${venue.id}`}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Find a guest by name or @handle"
            className={inputClass}
          />
          {query.trim().length >= 2 && (
            <ul className="mt-2 space-y-2">
              {results.length === 0 && <li className="px-1 text-sm text-faint">No one by that name or handle.</li>}
              {results.map((p) => (
                <li key={p.id} className="flex items-center justify-between gap-3 px-1">
                  <span className="min-w-0 truncate text-[15px] text-ink">
                    {p.name} <span className="text-faint">@{p.handle}</span>
                  </span>
                  <button
                    onClick={() => {
                      setGuest(p);
                      setQuery("");
                    }}
                    className="shrink-0 text-sm font-medium text-accent transition-opacity hover:opacity-80"
                  >
                    Open
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </div>
  );
}

function GuestDetail({ venue, guest, onBack }: { venue: Venue; guest: SocialProfile; onBack: () => void }) {
  const { card, loading, reload } = useGuestCard(venue.id, guest.id);
  const currency = currencyForCountry(venue.country);
  const money = (n: number) => formatMoney(n, currency, { round: true });

  const [body, setBody] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  const [tagInput, setTagInput] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hydrated, setHydrated] = useState(false);

  // Load the existing note once the card arrives.
  useEffect(() => {
    if (card && !hydrated) {
      setBody(card.note);
      setTags(card.tags);
      setHydrated(true);
    }
  }, [card, hydrated]);

  function addTag() {
    const t = tagInput.trim().slice(0, 24);
    if (t && !tags.includes(t) && tags.length < 12) setTags((s) => [...s, t]);
    setTagInput("");
  }

  async function save() {
    setSaving(true);
    setError(null);
    const err = await setGuestNote(venue.id, guest.id, body, tags);
    setSaving(false);
    if (err) {
      setError(err);
      return;
    }
    setSaved(true);
    setTimeout(() => setSaved(false), 1600);
    reload();
  }

  return (
    <div className="glass rounded-tile p-4">
      <div className="mb-3 flex items-center justify-between gap-3">
        <p className="min-w-0 truncate text-[15px] text-ink">
          {guest.name} <span className="text-faint">@{guest.handle}</span>
        </p>
        <button onClick={onBack} className="shrink-0 text-sm text-faint transition-colors hover:text-ink">
          ← Guests
        </button>
      </div>

      {loading ? (
        <div className="glass h-24 animate-pulse rounded-ctl" />
      ) : !card || !card.beenHere ? (
        <p className="text-sm leading-relaxed text-faint">
          {guest.name.split(" ")[0]} hasn&apos;t been to {venue.name} yet. You can keep a book once they visit — a
          room they join or a card you punch — so a book is only ever about your own guests.
        </p>
      ) : (
        <>
          {/* First-party history — what happened HERE. */}
          <dl className="grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
            <Fact label="visits" value={String(card.visits)} />
            <Fact label="tabs" value={String(card.tabs)} />
            <Fact label="spent here" value={money(card.totalSpend)} />
            <Fact label="perks given" value={String(card.perksClaimed)} />
          </dl>
          <p className="mt-2.5 text-xs text-faint">
            First seen {niceDate(card.firstSeen)} · last seen {niceDate(card.lastSeen)}
            {card.hasEarned && <span className="text-accent"> · has a perk waiting</span>}
          </p>

          {/* The subjective bit — your note + tags. */}
          <div className="mt-4 border-t border-line pt-4">
            <label htmlFor="gb-note" className="label mb-1.5 block text-faint">
              Your note
            </label>
            <textarea
              id="gb-note"
              value={body}
              onChange={(e) => setBody(e.target.value.slice(0, 2000))}
              rows={3}
              placeholder="Likes a smoky mezcal. In on Fridays with the football crowd. No nuts."
              className="glass w-full resize-none rounded-ctl px-4 py-2.5 text-[15px] leading-relaxed text-ink placeholder:text-faint"
            />

            <div className="mt-2 flex flex-wrap items-center gap-1.5">
              {tags.map((t) => (
                <button
                  key={t}
                  onClick={() => setTags((s) => s.filter((x) => x !== t))}
                  className="glass rounded-ctl px-2.5 py-1 text-xs text-muted transition-colors hover:text-ink"
                  title="Remove tag"
                >
                  {t} ×
                </button>
              ))}
              <input
                value={tagInput}
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === ",") {
                    e.preventDefault();
                    addTag();
                  }
                }}
                onBlur={addTag}
                placeholder="add a tag"
                aria-label="Add a tag"
                className="glass min-w-24 flex-1 rounded-ctl px-3 py-1 text-xs text-ink placeholder:text-faint"
              />
            </div>

            {error && <p className="mt-2 text-sm text-accent">{error}</p>}

            <button
              onClick={save}
              disabled={saving}
              className="mt-3 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              {saving ? "Saving…" : saved ? "Saved" : "Save note"}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dd className="tnum font-display text-xl leading-none text-ink">{value}</dd>
      <dt className="mt-1 text-xs text-faint">{label}</dt>
    </div>
  );
}
