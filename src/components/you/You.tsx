"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import clsx from "clsx";
import { useEntries, reseed, resetAll, replaceAll, snapshot } from "@/lib/store";
import { lexicon, stats, yearReview } from "@/lib/derive";
import { MilestoneMeter } from "../ui/MilestoneMeter";
import { MONTH_NAMES, parseKey } from "@/lib/date";
import type { Entry } from "@/lib/types";
import { useWishlist, addWish, removeWish, toggleWish } from "@/lib/wishlist";
import { useProfile, signOut } from "@/lib/profile";
import { isCollecting, setCollecting, clearTraining, useTrainingCount } from "@/lib/training";
import { useShareTrends, setShareTrends } from "@/lib/trends";
import { useExtras, setExtra, EXTRAS, type ExtraKey } from "@/lib/features";
import { Chip } from "../ui/Chip";
import { VenueLink } from "../ui/VenueLink";

export function You() {
  const entries = useEntries();
  const s = stats(entries);
  const lex = lexicon(entries);
  const yr = yearReview(entries);
  const [query, setQuery] = useState("");
  const [mood, setMood] = useState<string | null>(null);

  const photos = useMemo(
    () => entries.flatMap((e) => (e.photos ?? []).map((p) => ({ p, e }))),
    [entries],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return entries
      .filter((e) => (mood ? e.mood?.toLowerCase() === mood : true))
      .filter((e) =>
        q
          ? [e.drink, e.mood, e.note, e.venue].some((f) => f?.toLowerCase().includes(q))
          : true,
      )
      .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
  }, [entries, query, mood]);

  return (
    <>
      <header className="mb-6 flex items-end justify-between border-b border-line pb-4">
        <h1 className="font-display text-5xl leading-none tracking-tight">You</h1>
        <span className="label">{s.longest} night best</span>
      </header>

      <div className="glass rounded-tile p-5">
        <div className="grid grid-cols-3">
          <Metric value={s.current} label="streak" />
          <Metric value={s.total} label="logged" />
          <Metric value={s.kinds} label="kinds" />
        </div>
        {s.total > 0 && (
          <div className="mt-4 border-t border-line pt-4">
            <MilestoneMeter total={s.total} />
          </div>
        )}
      </div>

      {/* Your year — a calm look-back, all derived */}
      {yr.total > 0 && (
        <section className="mt-10">
          <h2 className="label mb-3">Your year</h2>
          <dl className="glass divide-y divide-line rounded-tile px-5">
            {yr.topDrink && <ReviewRow label="Most poured" value={yr.topDrink} />}
            {yr.topMood && <ReviewRow label="Most-felt" value={yr.topMood} italic />}
            {yr.busiestMonth && <ReviewRow label="Busiest month" value={yr.busiestMonth} />}
            <ReviewRow label="Days logged" value={String(yr.days)} tnum />
          </dl>
        </section>
      )}

      <ToTry />

      {/* Mood lexicon */}
      {lex.length > 0 && (
        <section className="mt-10">
          <h2 className="label mb-3">Your words</h2>
          <div className="flex flex-wrap gap-1.5">
            {lex.map((m) => (
              <Chip
                key={m.word}
                active={mood === m.word}
                onClick={() => setMood(mood === m.word ? null : m.word)}
              >
                <span className="italic">{m.word}</span>
                <span className="tnum ml-1.5 text-xs opacity-60">{m.count}</span>
              </Chip>
            ))}
          </div>
        </section>
      )}

      {/* Photo wall */}
      {photos.length > 0 && (
        <section className="mt-10">
          <h2 className="label mb-3">Photos</h2>
          <div className="grid grid-cols-4 gap-1.5 sm:grid-cols-5">
            {photos.map(({ p }) => (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                key={p.id}
                src={p.url}
                alt=""
                className="aspect-square w-full rounded-cell object-cover"
              />
            ))}
          </div>
        </section>
      )}

      {/* Shelf */}
      <section className="mt-10">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="label">Shelf</h2>
          {(mood || query) && (
            <button
              onClick={() => {
                setMood(null);
                setQuery("");
              }}
              className="text-xs text-faint transition-colors hover:text-ink"
            >
              clear
            </button>
          )}
        </div>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search your drinks…"
          className="mb-3 w-full border-b border-line-strong bg-transparent pb-2 text-sm outline-none placeholder:text-faint focus:border-ink"
        />
        {filtered.length === 0 ? (
          <p className="py-6 text-center text-sm text-faint">Nothing here yet.</p>
        ) : (
          <ul className="glass divide-y divide-line rounded-tile px-5">
            {filtered.map((e) => (
              <ShelfRow key={e.id} entry={e} />
            ))}
          </ul>
        )}
      </section>

      <Settings />
    </>
  );
}

function Settings() {
  const fileRef = useRef<HTMLInputElement>(null);
  const [reminder, setReminder] = useState(false);
  const [collect, setCollect] = useState(true);
  const trainingCount = useTrainingCount();
  const profile = useProfile();
  const router = useRouter();

  async function handleSignOut() {
    await signOut(); // wait for the session cookie to clear…
    router.push("/"); // …then the server gate renders the landing (not the app)
    router.refresh();
  }

  useEffect(() => {
    setReminder(localStorage.getItem("brewdiary.reminder") === "on");
    setCollect(isCollecting());
  }, []);

  function toggleCollect() {
    const next = !collect;
    setCollect(next);
    setCollecting(next);
  }

  function toggleReminder() {
    const next = !reminder;
    setReminder(next);
    localStorage.setItem("brewdiary.reminder", next ? "on" : "off");
    if (next && "Notification" in window && Notification.permission === "default") {
      Notification.requestPermission().catch(() => {});
    }
  }

  function exportJson() {
    const blob = new Blob([JSON.stringify(snapshot(), null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `brewdiary-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function importJson(file: File | undefined) {
    if (!file) return;
    try {
      const data = JSON.parse(await file.text());
      if (Array.isArray(data)) replaceAll(data);
    } catch {
      /* ignore malformed file */
    }
  }

  return (
    <footer className="glass mt-12 rounded-tile p-5">
      <h2 className="label mb-4">Settings</h2>
      {profile && (
        <p className="mb-5 text-sm text-muted">
          Signed in as <span className="text-ink">{profile.name}</span>
        </p>
      )}
      <div className="flex items-center justify-between gap-4 py-1">
        <div>
          <p className="text-sm text-ink">Nightly reminder</p>
          <p className="text-xs text-faint">A gentle nudge to log before bed.</p>
        </div>
        <Toggle on={reminder} label="Nightly reminder" onToggle={toggleReminder} />
      </div>

      <div className="mt-4 flex items-center justify-between gap-4 border-t border-line py-3">
        <div>
          <p className="text-sm text-ink">Help train Ninkasi</p>
          <p className="text-xs text-faint">
            Keep your chats with Ninkasi on this device to teach her your taste
            {trainingCount > 0 ? ` · ${trainingCount} saved` : ""}.
          </p>
        </div>
        <Toggle on={collect} label="Help train Ninkasi" onToggle={toggleCollect} />
      </div>

      {profile && <TrendsOptIn meId={profile.id} />}

      <ExtrasSettings />

      <div className="mt-5 flex flex-wrap items-center gap-x-5 gap-y-2 text-xs text-faint">
        <button onClick={exportJson} className="transition-colors hover:text-ink">
          export data
        </button>
        <button onClick={() => fileRef.current?.click()} className="transition-colors hover:text-ink">
          import data
        </button>
        <button onClick={reseed} className="transition-colors hover:text-ink">
          reseed demo
        </button>
        <button onClick={resetAll} className="transition-colors hover:text-ink">
          reset diary
        </button>
        {trainingCount > 0 && (
          <button onClick={clearTraining} className="transition-colors hover:text-ink">
            clear ninkasi data
          </button>
        )}
        {profile ? (
          <button onClick={handleSignOut} className="transition-colors hover:text-ink">
            sign out
          </button>
        ) : (
          <button onClick={() => router.push("/")} className="transition-colors hover:text-ink">
            sign in
          </button>
        )}
        <input
          ref={fileRef}
          type="file"
          accept="application/json"
          className="hidden"
          onChange={(e) => importJson(e.target.files?.[0])}
        />
      </div>
    </footer>
  );
}

/** Opt-in (default OFF) to counting this diary in the anonymous taste trends. */
function TrendsOptIn({ meId }: { meId: string }) {
  const { shareTrends, loaded } = useShareTrends();
  const [on, setOn] = useState(false);
  useEffect(() => {
    if (loaded) setOn(shareTrends);
  }, [loaded, shareTrends]);

  function toggle() {
    const next = !on;
    setOn(next);
    setShareTrends(meId, next);
  }

  return (
    <div className="mt-4 flex items-center justify-between gap-4 border-t border-line py-3">
      <div>
        <p className="text-sm text-ink">Anonymous taste trends</p>
        <p className="text-xs text-faint">
          Count my logs in the &quot;what&apos;s pouring&quot; trends — counts only, never my name or notes.
        </p>
      </div>
      <Toggle on={on} label="Anonymous taste trends" onToggle={toggle} />
    </div>
  );
}

/** Extras — optional trackers, off by default. Flip one on and its counter
 *  appears in the log window (see lib/features.ts). Keeps the app clean until asked. */
function ExtrasSettings() {
  const flags = useExtras();
  return (
    <div className="mt-4 border-t border-line pt-3">
      <p className="label mb-1">Extras</p>
      <p className="mb-1 text-xs text-faint">
        Optional trackers. Turn one on and a small counter shows up on each day in your log.
      </p>
      {EXTRAS.map((e) => (
        <div key={e.key} className="flex items-center justify-between gap-4 py-2">
          <div>
            <p className="text-sm text-ink">{e.label}</p>
            <p className="text-xs text-faint">{e.hint}</p>
          </div>
          <Toggle
            on={flags[e.key] ?? false}
            label={e.label}
            onToggle={(next) => setExtra(e.key as ExtraKey, next)}
          />
        </div>
      ))}
    </div>
  );
}

/** The pill switch used across Settings. */
function Toggle({ on, label, onToggle }: { on: boolean; label: string; onToggle: (next: boolean) => void }) {
  return (
    <button
      onClick={() => onToggle(!on)}
      role="switch"
      aria-checked={on}
      aria-label={label}
      className={clsx(
        // flex + p-0.5: the knob is exactly half the inner width, so translate-x-full
        // lands it flush against the right padding — it can never overhang the pill.
        "flex h-6 w-11 shrink-0 items-center rounded-full p-0.5 transition-colors duration-200 ease-out",
        on
          ? "bg-accent shadow-[inset_0_1px_1px_rgba(0,0,0,0.12)]"
          : "bg-ink/10 shadow-[inset_0_0_0_1px_var(--line-strong),inset_0_1px_2px_rgba(0,0,0,0.15)]",
      )}
    >
      <span
        className={clsx(
          "h-5 w-5 rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.35)] transition-transform duration-200 ease-out",
          on && "translate-x-full",
        )}
      />
    </button>
  );
}

function ToTry() {
  const items = useWishlist();
  const [draft, setDraft] = useState("");
  const active = items.filter((w) => !w.done);
  const done = items.filter((w) => w.done);

  return (
    <section className="mt-10">
      <h2 className="label mb-3">To try</h2>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          addWish(draft);
          setDraft("");
        }}
        className="mb-3 flex items-center gap-2"
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="A drink you want to get to…"
          className="flex-1 border-b border-line-strong bg-transparent pb-2 text-sm outline-none placeholder:text-faint focus:border-ink"
        />
        <button
          type="submit"
          disabled={!draft.trim()}
          className={clsx(
            "rounded-ctl px-3 py-1.5 text-xs uppercase tracking-[0.12em] transition-colors",
            draft.trim() ? "bg-ink text-paper hover:bg-ink/90" : "cursor-not-allowed bg-ink/10 text-faint",
          )}
        >
          Add
        </button>
      </form>

      {items.length === 0 ? (
        <p className="py-2 text-sm text-faint">Nothing on the list yet — add a drink you&apos;re curious about.</p>
      ) : (
        <ul className="glass divide-y divide-line rounded-tile px-5">
          {[...active, ...done].map((w) => (
            <li key={w.id} className="flex items-center justify-between gap-3 py-2.5">
              <button
                onClick={() => toggleWish(w.id)}
                className="flex min-w-0 flex-1 items-center gap-2.5 text-left"
                aria-label={w.done ? `Mark ${w.drink} not tried` : `Mark ${w.drink} tried`}
              >
                <span
                  aria-hidden
                  className={clsx(
                    "flex h-4 w-4 shrink-0 items-center justify-center rounded-[3px] border text-[10px] leading-none",
                    w.done ? "border-accent bg-accent text-accent-contrast" : "border-line-strong text-transparent",
                  )}
                >
                  ✓
                </span>
                <span className={clsx("truncate text-[15px]", w.done ? "text-faint line-through" : "text-ink")}>
                  {w.drink}
                </span>
              </button>
              <button
                onClick={() => removeWish(w.id)}
                aria-label={`Remove ${w.drink}`}
                className="shrink-0 text-sm text-faint transition-colors hover:text-ink"
              >
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function ReviewRow({
  label,
  value,
  italic,
  tnum,
}: {
  label: string;
  value: string;
  italic?: boolean;
  tnum?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between gap-3 py-3">
      <dt className="label">{label}</dt>
      <dd className={clsx("text-[15px] text-ink", italic && "italic", tnum && "tnum")}>{value}</dd>
    </div>
  );
}

function Metric({ value, label }: { value: number; label: string }) {
  return (
    <div className="flex flex-col items-center gap-1 py-3">
      <span className="tnum text-2xl font-semibold leading-none">{value}</span>
      <span className="label">{label}</span>
    </div>
  );
}

function ShelfRow({ entry }: { entry: Entry }) {
  const d = parseKey(entry.date);
  return (
    <li className="flex items-baseline justify-between gap-3 py-3">
      <div className="min-w-0">
        <p className="truncate text-[15px] text-ink">{entry.drink}</p>
        <p className="text-xs text-muted">
          {entry.mood && <span className="italic">{entry.mood}</span>}
          {entry.mood && entry.venue ? " · " : ""}
          {entry.venue && <VenueLink venue={entry.venue} />}
        </p>
      </div>
      <span className="tnum shrink-0 text-xs text-faint">
        {MONTH_NAMES[d.getMonth()].slice(0, 3)} {d.getDate()}
      </span>
    </li>
  );
}
