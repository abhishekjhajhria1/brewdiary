"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import clsx from "clsx";
import { addEntry, deleteEntry, updateEntry } from "@/lib/store";
import { useProfile } from "@/lib/profile";
import { useCircles, useEntryCircleShares, shareToCircle, unshareFromCircle } from "@/lib/circles";
import {
  useParties,
  useEntryPartyShares,
  shareToParty,
  unshareFromParty,
} from "@/lib/parties";
import type { DrinkType, Entry, Photo } from "@/lib/types";
import { DRINK_TYPES } from "@/lib/types";
import { addDays, formatDayLong, parseKey, timeOfDayLabel, toKey } from "@/lib/date";
import { canonicalize, suggestDrinks } from "@/lib/drinks";
import { useEntries } from "@/lib/store";
import { Chip } from "../ui/Chip";
import { ShareCard } from "../share/ShareCard";

const WEEKDAY_LONG = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

export function LogSheet({
  dateKey,
  dayEntries,
  recentDrinks,
  recentMoods,
  onClose,
}: {
  dateKey: string;
  dayEntries: Entry[];
  recentDrinks: string[];
  recentMoods: string[];
  onClose: () => void;
}) {
  const [drink, setDrink] = useState("");
  const [drinkFocused, setDrinkFocused] = useState(false);
  const [picked, setPicked] = useState(false); // just accepted a name → hush suggestions till they type again
  const [mood, setMood] = useState("");
  const [showMore, setShowMore] = useState(false);
  const [note, setNote] = useState("");
  const [venue, setVenue] = useState("");
  const [who, setWho] = useState("");
  const [type, setType] = useState<DrinkType | undefined>(undefined);
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [justLogged, setJustLogged] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [sharing, setSharing] = useState<Entry | null>(null);
  const [shareFor, setShareFor] = useState<string | null>(null);
  const profile = useProfile();
  const { circles } = useCircles();
  const { parties } = useParties();
  // parties worth offering a share to: upcoming, or recently past (late shares
  // still land on the recap page)
  const shareableParties = parties.filter((p) => p.date >= toKey(addDays(parseKey(dateKey), -14)));

  // Your full drink vocabulary (distinct, most-recent-first) powers autocomplete.
  const allEntries = useEntries();
  const history = useMemo(() => {
    const seen = new Set<string>();
    const out: string[] = [];
    for (const e of [...allEntries].sort((a, b) => b.createdAt.localeCompare(a.createdAt))) {
      const name = e.drink.trim();
      const key = name.toLowerCase();
      if (name && !seen.has(key)) {
        seen.add(key);
        out.push(name);
      }
    }
    return out;
  }, [allEntries]);

  const drinkRef = useRef<HTMLInputElement>(null);
  const d = parseKey(dateKey);
  const weekdayIdx = (d.getDay() + 6) % 7;

  useEffect(() => {
    drinkRef.current?.focus();
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [onClose]);

  function reset() {
    setDrink("");
    setMood("");
    setNote("");
    setVenue("");
    setWho("");
    setType(undefined);
    setPhotos([]);
    setShowMore(false);
    setEditingId(null);
  }

  function loadForEdit(e: Entry) {
    setEditingId(e.id);
    setDrink(e.drink);
    setPicked(true); // don't pop suggestions over a loaded entry
    setMood(e.mood ?? "");
    setNote(e.note ?? "");
    setVenue(e.venue ?? "");
    setWho(e.whoWith?.join(", ") ?? "");
    setType(e.type);
    setPhotos(e.photos ?? []);
    setShowMore(Boolean(e.note || e.venue || e.whoWith?.length || e.type || e.photos?.length));
    drinkRef.current?.focus();
  }

  // Accept a suggestion / canonical name — fills the field and pre-picks the Kind.
  function pick(name: string) {
    setDrink(name);
    setPicked(true);
    if (!type) {
      const c = canonicalize(name);
      if (c.type) setType(c.type);
    }
    drinkRef.current?.focus();
  }

  function submit() {
    if (!drink.trim()) return;
    const payload = {
      date: dateKey,
      drink,
      mood: mood || undefined,
      note: note.trim() || undefined,
      venue: venue.trim() || undefined,
      type,
      whoWith: who.trim() ? who.split(",").map((s) => s.trim()).filter(Boolean) : undefined,
      photos: photos.length ? photos : undefined,
    };
    if (editingId) updateEntry(editingId, payload);
    else addEntry(payload);
    reset();
    setJustLogged(true);
    setTimeout(() => setJustLogged(false), 1400);
    drinkRef.current?.focus();
  }

  async function onFiles(list: FileList | null) {
    if (!list) return;
    const files = Array.from(list).slice(0, 4 - photos.length);
    const read = await Promise.all(
      files.map(
        (f) =>
          new Promise<Photo>((resolve) => {
            const r = new FileReader();
            r.onload = () => resolve({ id: `${Date.now()}_${Math.random().toString(36).slice(2)}`, url: String(r.result) });
            r.readAsDataURL(f);
          }),
      ),
    );
    setPhotos((p) => [...p, ...read].slice(0, 4));
  }

  // live autocomplete + a gentle "we know the tidy name for this" nudge
  const typing = drink.trim();
  const suggestions = typing && !picked ? suggestDrinks(drink, history, 6) : [];
  const showSuggestions = drinkFocused && !picked && suggestions.length > 0;
  const canon = typing ? canonicalize(drink) : null;
  const showCanonHint = Boolean(!picked && canon?.matched && canon.canonical.toLowerCase() !== typing.toLowerCase());

  return (
    <div className="fixed inset-0 z-50 flex flex-col justify-end">
      <button
        aria-label="Close"
        onClick={onClose}
        className="animate-fade absolute inset-0 bg-black/50 backdrop-blur-[3px]"
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Log for ${formatDayLong(dateKey)}`}
        className="glass-strong animate-sheet relative mx-auto flex max-h-[88dvh] w-full max-w-lg flex-col overflow-y-auto rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4"
      >
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong" />

        <header className="mb-5 flex items-baseline justify-between">
          <div>
            <h2 className="font-display text-3xl leading-none">{formatDayLong(dateKey)}</h2>
            <span className="label mt-1 block">{WEEKDAY_LONG[weekdayIdx]}</span>
          </div>
          <button
            onClick={onClose}
            className="rounded-ctl px-2 py-1 text-sm text-muted transition-colors hover:text-ink"
          >
            Done
          </button>
        </header>

        {dayEntries.length > 0 && (
          <ul className="mb-5 divide-y divide-line border-y border-line">
            {dayEntries.map((e) => (
              <li key={e.id} className="py-2.5">
                <div className="flex items-center justify-between gap-3">
                <button
                  onClick={() => loadForEdit(e)}
                  className="min-w-0 flex-1 text-left"
                  aria-label={`Edit ${e.drink}`}
                >
                  <p
                    className={clsx(
                      "truncate text-[15px]",
                      editingId === e.id ? "text-accent" : "text-ink",
                    )}
                  >
                    {e.drink}
                    {editingId === e.id && <span className="label ml-2">editing</span>}
                  </p>
                  <p className="text-xs text-muted">
                    {e.mood ? <span className="italic">{e.mood}</span> : null}
                    {e.mood ? " · " : null}
                    {timeOfDayLabel(e.createdAt)}
                  </p>
                </button>
                <div className="flex shrink-0 items-center gap-3 text-sm">
                  {profile && (
                    <button
                      onClick={() => setShareFor(shareFor === e.id ? null : e.id)}
                      aria-expanded={shareFor === e.id}
                      aria-label={`Share ${e.drink}`}
                      className={clsx(
                        "transition-colors",
                        shareFor === e.id || e.visibility === "friends"
                          ? "font-medium text-accent"
                          : "text-muted hover:text-ink",
                      )}
                    >
                      {e.visibility === "friends" ? "Shared" : "Share"}
                    </button>
                  )}
                  <button
                    onClick={() => setSharing(e)}
                    aria-label={`Share ${e.drink} as an image`}
                    className="text-muted transition-colors hover:text-ink"
                  >
                    Card
                  </button>
                  <button
                    onClick={() => deleteEntry(e.id)}
                    aria-label={`Delete ${e.drink}`}
                    className="text-faint transition-colors hover:text-ink"
                  >
                    Remove
                  </button>
                </div>
                </div>
                {shareFor === e.id && profile && (
                  <ShareRow entry={e} meId={profile.id} circles={circles} parties={shareableParties} />
                )}
              </li>
            ))}
          </ul>
        )}

        {/* What */}
        <label className="label mb-1.5 block" htmlFor="drink">
          What did you drink?
        </label>
        <input
          id="drink"
          ref={drinkRef}
          value={drink}
          onChange={(e) => {
            setDrink(e.target.value);
            setPicked(false); // typing again → suggestions may return
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter") submit();
            else if (e.key === "Escape" && showSuggestions) {
              e.stopPropagation(); // close the dropdown, not the whole sheet
              setPicked(true);
            }
          }}
          onFocus={() => setDrinkFocused(true)}
          onBlur={() => setTimeout(() => setDrinkFocused(false), 120)}
          autoComplete="off"
          placeholder="A flat white, a negroni, a homebrew…"
          className="w-full border-b border-line-strong bg-transparent pb-2 text-lg outline-none placeholder:text-faint focus:border-ink"
        />

        {/* you typed a variant — offer the tidy family name (one tap to adopt) */}
        {showCanonHint && canon && (
          <button
            type="button"
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => pick(canon.canonical)}
            className="mt-2 self-start text-xs text-muted transition-colors hover:text-ink"
          >
            ≈ <span className="text-ink">{canon.canonical}</span> · tap to use
          </button>
        )}

        {/* typing → live suggestions; empty field → your usuals as chips */}
        {showSuggestions ? (
          <ul className="mt-2 overflow-hidden rounded-ctl border border-line">
            {suggestions.map((sug) => (
              <li key={sug} className="border-b border-line last:border-b-0">
                <button
                  type="button"
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => pick(sug)}
                  className="block w-full px-3 py-2 text-left text-[15px] text-ink transition-colors hover:bg-ink/5"
                >
                  {sug}
                </button>
              </li>
            ))}
          </ul>
        ) : (
          !typing &&
          recentDrinks.length > 0 && (
            <div className="mt-2.5 flex flex-wrap gap-1.5">
              {recentDrinks.map((r) => (
                <Chip key={r} active={drink === r} onClick={() => pick(r)}>
                  {r}
                </Chip>
              ))}
            </div>
          )
        )}

        {/* Mood */}
        <label className="label mb-1.5 mt-6 block" htmlFor="mood">
          A word for it?
        </label>
        <input
          id="mood"
          value={mood}
          onChange={(e) => setMood(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && submit()}
          placeholder="cozy, celebratory, ordinary…"
          className="w-full border-b border-line-strong bg-transparent pb-2 text-lg italic outline-none placeholder:not-italic placeholder:text-faint focus:border-ink"
        />
        {recentMoods.length > 0 && (
          <div className="mt-2.5 flex flex-wrap gap-1.5">
            {recentMoods.map((r) => (
              <Chip key={r} active={mood === r} onClick={() => setMood(r)}>
                {r}
              </Chip>
            ))}
          </div>
        )}

        {/* Expand-on-tap optionals */}
        {!showMore ? (
          <button
            onClick={() => setShowMore(true)}
            className="mt-6 self-start text-sm text-muted underline-offset-4 transition-colors hover:text-ink hover:underline"
          >
            add note · photo · place · who · kind
          </button>
        ) : (
          <div className="mt-6 space-y-5 border-t border-line pt-5">
            <Field label="Note">
              <textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                rows={2}
                placeholder="A line about the moment…"
                className="w-full resize-none rounded-ctl border border-line-strong bg-transparent px-3 py-2 text-sm outline-none placeholder:text-faint focus:border-ink"
              />
            </Field>

            <Field label="Photos">
              <div className="flex flex-wrap items-center gap-2">
                {photos.map((p) => (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    key={p.id}
                    src={p.url}
                    alt=""
                    className="h-14 w-14 rounded-ctl object-cover"
                  />
                ))}
                {photos.length < 4 && (
                  <label className="flex h-14 w-14 cursor-pointer items-center justify-center rounded-ctl border border-dashed border-line-strong text-xl text-faint transition-colors hover:border-ink hover:text-ink">
                    +
                    <input
                      type="file"
                      accept="image/*"
                      multiple
                      className="hidden"
                      onChange={(e) => onFiles(e.target.files)}
                    />
                  </label>
                )}
              </div>
            </Field>

            <Field label="Where">
              <input
                value={venue}
                onChange={(e) => setVenue(e.target.value)}
                placeholder="Home, a bar, a city…"
                className="w-full rounded-ctl border border-line-strong bg-transparent px-3 py-2 text-sm outline-none placeholder:text-faint focus:border-ink"
              />
            </Field>

            <Field label="Who with">
              <input
                value={who}
                onChange={(e) => setWho(e.target.value)}
                placeholder="Comma-separated names"
                className="w-full rounded-ctl border border-line-strong bg-transparent px-3 py-2 text-sm outline-none placeholder:text-faint focus:border-ink"
              />
            </Field>

            <Field label="Kind">
              <div className="flex flex-wrap gap-1.5">
                {DRINK_TYPES.map((t) => (
                  <Chip
                    key={t.value}
                    active={type === t.value}
                    onClick={() => setType(type === t.value ? undefined : t.value)}
                  >
                    {t.label}
                  </Chip>
                ))}
              </div>
            </Field>
          </div>
        )}

        {/* Log / Save */}
        {editingId && (
          <button
            onClick={reset}
            className="mt-6 self-start text-sm text-muted underline-offset-4 transition-colors hover:text-ink hover:underline"
          >
            cancel edit
          </button>
        )}
        <button
          onClick={submit}
          disabled={!drink.trim()}
          className={clsx(
            "mt-3 flex h-12 w-full items-center justify-center rounded-ctl text-base font-medium transition-all active:scale-[0.99]",
            drink.trim()
              ? "bg-ink text-paper hover:bg-ink/90"
              : "cursor-not-allowed bg-ink/10 text-faint",
          )}
        >
          {editingId ? "Save changes" : justLogged ? "Logged ✓" : "Log"}
        </button>
      </div>

      {sharing && <ShareCard entry={sharing} onClose={() => setSharing(null)} />}
    </div>
  );
}

/** Sharing is a deliberate act, separate from logging: one row of audiences —
 *  all friends, each circle, each (recent) party. Logging itself never shares. */
function ShareRow({
  entry,
  meId,
  circles,
  parties,
}: {
  entry: Entry;
  meId: string;
  circles: { id: string; name: string }[];
  parties: { id: string; name: string }[];
}) {
  const inCircles = useEntryCircleShares(entry.id);
  const inParties = useEntryPartyShares(entry.id);
  const [pending, setPending] = useState(false);

  async function run(fn: () => Promise<unknown>) {
    if (pending) return;
    setPending(true);
    await fn();
    setPending(false);
  }

  const friendsOn = entry.visibility === "friends";

  return (
    <div className="mt-2 flex flex-wrap items-center gap-1.5">
      <span className="label mr-1">to</span>
      <Chip
        active={friendsOn}
        onClick={() => updateEntry(entry.id, { visibility: friendsOn ? "private" : "friends" })}
      >
        {friendsOn ? "Friends ✓" : "Friends"}
      </Chip>
      {circles.map((c) => (
        <Chip
          key={c.id}
          active={inCircles.has(c.id)}
          onClick={() =>
            run(() => (inCircles.has(c.id) ? unshareFromCircle(entry.id, c.id) : shareToCircle(entry.id, c.id, meId)))
          }
        >
          {inCircles.has(c.id) ? `${c.name} ✓` : c.name}
        </Chip>
      ))}
      {parties.map((p) => (
        <Chip
          key={p.id}
          active={inParties.has(p.id)}
          onClick={() =>
            run(() => (inParties.has(p.id) ? unshareFromParty(entry.id, p.id) : shareToParty(entry.id, p.id, meId)))
          }
        >
          {inParties.has(p.id) ? `${p.name} ✓` : p.name}
        </Chip>
      ))}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <span className="label mb-1.5 block">{label}</span>
      {children}
    </div>
  );
}
