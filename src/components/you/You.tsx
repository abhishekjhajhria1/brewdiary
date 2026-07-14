"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import clsx from "clsx";
import { useEntries, reseed, resetAll, replaceAll, snapshot } from "@/lib/store";
import { lexicon, stats, yearReview, weekBalance } from "@/lib/derive";
import { useGoals, setGoal, anyGoalSet, GOAL_MAX, type GoalKey } from "@/lib/goals";
import { MilestoneMeter } from "../ui/MilestoneMeter";
import { MONTH_NAMES, parseKey } from "@/lib/date";
import type { Entry } from "@/lib/types";
import { useWishlist, addWish, removeWish, toggleWish } from "@/lib/wishlist";
import { useProfile, signOut } from "@/lib/profile";
import { isCollecting, setCollecting, clearTraining, useTrainingCount } from "@/lib/training";
import { useShareTrends, setShareTrends } from "@/lib/trends";
import { useCompeteVisible, setCompeteVisible } from "@/lib/points";
import { useProfilePrivacy, setProfileVisibility, setSocialHandle, type ProfileVisibility } from "@/lib/publicProfile";
import { useExtras, setExtra, EXTRAS, type ExtraKey } from "@/lib/features";
import { exportEverything, deleteAccount } from "@/lib/dataRights";
import { savedCountry, moveTo, confirmAge, legalAgeFor } from "@/lib/age";
import { KNOWN_COUNTRIES } from "@/lib/jurisdiction";
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

      {/* Balance — only ever appears once you've asked for it (You → Settings) */}
      <BalanceCard entries={entries} />

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

      {profile && <CompeteOptIn meId={profile.id} />}

      {profile && <VenueScreenNote />}

      {profile && <ProfilePrivacy meId={profile.id} handle={profile.handle} />}

      <WhereYouAre />

      <GoalsSettings />

      <ExtrasSettings />

      {profile && <DataRights />}

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
        <Link href="/privacy" className="transition-colors hover:text-ink">
          privacy
        </Link>
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

/** Your data, and the right to take it or destroy it. Not decoration: GDPR gives an
 *  enforceable right of access and erasure, India's DPDP Act gives erasure, and both
 *  app stores require an in-app account-deletion route. Deletion is real — the auth
 *  user is destroyed and every table cascades from it. */
function DataRights() {
  const [busy, setBusy] = useState(false);
  const [asking, setAsking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  async function doExport() {
    setBusy(true);
    setError(await exportEverything());
    setBusy(false);
  }

  async function doDelete() {
    setBusy(true);
    const err = await deleteAccount();
    setBusy(false);
    if (err) {
      setError(err);
      return;
    }
    router.push("/");
  }

  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Your data</p>
      <p className="mb-3 text-xs leading-relaxed text-faint">
        Take a copy of everything we hold about you, or delete your account outright. Deleting is
        immediate and permanent — the diary, the photos, the points, all of it.
      </p>

      <div className="flex flex-wrap gap-2">
        <button
          onClick={doExport}
          disabled={busy}
          className="glass glass-press rounded-ctl px-3.5 py-2 text-sm text-muted transition-colors hover:text-ink disabled:opacity-50"
        >
          Download my data
        </button>
        <button
          onClick={() => setAsking(true)}
          disabled={busy}
          className="rounded-ctl border border-line px-3.5 py-2 text-sm text-muted transition-colors hover:text-accent disabled:opacity-50"
        >
          Delete my account
        </button>
      </div>

      {asking && (
        <div className="glass mt-3 rounded-tile p-4">
          <p className="text-sm text-ink">Delete everything?</p>
          <p className="mt-1 text-xs leading-relaxed text-muted">
            Every entry, photo, friendship and point is destroyed. This cannot be undone, and we can&apos;t
            get it back for you. Download your data first if you want to keep it.
          </p>
          <div className="mt-3 flex gap-2">
            <button
              onClick={doDelete}
              disabled={busy}
              className="rounded-ctl bg-accent px-4 py-2 text-sm font-medium text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              {busy ? "Deleting…" : "Yes, delete it all"}
            </button>
            <button
              onClick={() => setAsking(false)}
              className="rounded-ctl border border-line px-4 py-2 text-sm text-muted transition-colors hover:text-ink"
            >
              Keep my account
            </button>
          </div>
        </div>
      )}

      {error && <p className="mt-2 text-sm text-accent">{error}</p>}
    </div>
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

/** Opt-in (default OFF) to the Together leaderboard. Flipping this ON is what
 *  makes the "Board" appear in Together — and it's also what puts you ON it.
 *  Friends who haven't opted in never show, so nobody is ranked unasked. */
function CompeteOptIn({ meId }: { meId: string }) {
  const { competeVisible, loaded } = useCompeteVisible();
  const [on, setOn] = useState(false);
  useEffect(() => {
    if (loaded) setOn(competeVisible);
  }, [loaded, competeVisible]);

  function toggle() {
    const next = !on;
    setOn(next);
    setCompeteVisible(meId, next);
  }

  return (
    <div className="mt-4 flex items-center justify-between gap-4 border-t border-line py-3">
      <div>
        <p className="text-sm text-ink">Leaderboard in Together</p>
        <p className="text-xs text-faint">
          Show the board — and put me on it, next to friends who also opted in. Off by default; never your spend.
        </p>
      </div>
      <Toggle on={on} label="Leaderboard in Together" onToggle={toggle} />
    </div>
  );
}

/** Consent to a bar's PHYSICAL screen is no longer a setting here — and that is
 *  the point. It used to be a permanent global switch: flip it on for one fun
 *  night and your name sat on every venue's TV forever. Consent to be on a screen
 *  TONIGHT is not consent to be on screens ALWAYS. So you now grant it inside the
 *  room you're actually in, and it dies with that night. */
function VenueScreenNote() {
  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Venue screens</p>
      <p className="text-xs leading-relaxed text-faint">
        There is no always-on switch for this. When you are in a bar&apos;s room, you can choose — for that night only —
        to appear on its screen, and whether your tab shows. It clears when the night ends.
      </p>
    </div>
  );
}

/** Balance — the counterweight to Together's loud corner. Shows ONLY once you've
 *  set a goal. The tone is a mirror, never a scold: it states the number and stops. */
function BalanceCard({ entries }: { entries: Entry[] }) {
  const goals = useGoals();
  if (!anyGoalSet(goals)) return null;

  const b = weekBalance(entries);
  const overLimit = goals.weeklyLimit !== undefined && b.drinks > goals.weeklyLimit;
  const dryMet = goals.dryDays !== undefined && b.dryDays >= goals.dryDays;

  return (
    <section className="mt-10">
      <h2 className="label mb-3">Your balance</h2>
      <div className="glass rounded-tile p-5">
        <div className="grid grid-cols-2 gap-4">
          {goals.weeklyLimit !== undefined && (
            <div>
              <p className={clsx("tnum font-display text-3xl", overLimit ? "text-accent" : "text-ink")}>
                {b.drinks}
                <span className="text-lg text-faint"> / {goals.weeklyLimit}</span>
              </p>
              <p className="mt-0.5 text-xs text-faint">drinks this week</p>
            </div>
          )}
          {goals.dryDays !== undefined && (
            <div>
              <p className={clsx("tnum font-display text-3xl", dryMet ? "text-accent" : "text-ink")}>
                {b.dryDays}
                <span className="text-lg text-faint"> / {goals.dryDays}</span>
              </p>
              <p className="mt-0.5 text-xs text-faint">dry days</p>
            </div>
          )}
        </div>
        <p className="mt-4 text-xs leading-relaxed text-faint">
          A rolling seven days. Yours alone — never shared, never shown to a bar, never on a board.
        </p>
      </div>
    </section>
  );
}

/** Where you are — the TRAVELLER's switch. Two rules, and they point in opposite
 *  directions on purpose:
 *
 *  • What YOU can do follows where you ARE, not your passport. Drinking age is
 *    territorial — a 20-year-old American is legal in Berlin and illegal in New
 *    York. So moving somewhere with a higher bar than you've cleared means we ask
 *    your age again. We can do that without ever having stored your date of birth,
 *    because we keep only which bar you cleared (see lib/age.ts).
 *
 *  • What a BAR can offer follows where the BAR is. A perk given in Dublin is an
 *    Irish promotion no matter whose phone receives it — a traveller does NOT
 *    bring their home country's rules with them. That would be the exact loophole
 *    these laws exist to close, and it could cost a partner bar its licence.
 *    (Enforced in the database: venue perks key off venues.country, never yours.) */
function WhereYouAre() {
  const [country, setCountry] = useState<string>("IN");
  const [needsAge, setNeedsAge] = useState<number | null>(null);
  const [dob, setDob] = useState("");
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    setCountry(savedCountry() ?? "IN");
  }, []);

  function pick(next: string) {
    setNeedsAge(null);
    const res = moveTo(next);
    if (!res.ok) {
      // The new country's legal age is higher than the bar this person cleared.
      setCountry(next);
      setNeedsAge(res.needsAge);
      return;
    }
    setCountry(next);
    setSaved(true);
    setTimeout(() => setSaved(false), 1600);
  }

  function reconfirm() {
    if (!dob) return;
    if (confirmAge(new Date(dob + "T00:00:00"), country)) {
      setNeedsAge(null);
      setDob("");
      setSaved(true);
      setTimeout(() => setSaved(false), 1600);
    } else {
      setNeedsAge(legalAgeFor(country));
    }
  }

  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Where you are</p>
      <p className="mb-2 text-xs leading-relaxed text-faint">
        Travelling? Set this to the country you&apos;re in. It sets your currency, and the legal drinking age
        we hold you to — that follows where you are, not where you&apos;re from.
      </p>

      <select
        value={country}
        onChange={(e) => pick(e.target.value)}
        aria-label="Country you are in"
        className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink"
      >
        {KNOWN_COUNTRIES.map((c) => (
          <option key={c.code} value={c.code}>
            {c.label}
          </option>
        ))}
        <option value="ZZ">Somewhere else</option>
      </select>

      {needsAge !== null && (
        <div className="glass mt-3 rounded-tile p-4">
          <p className="text-xs leading-relaxed text-muted">
            The legal drinking age there is {needsAge}+, which is higher than the one you confirmed. Confirm
            your date of birth again and we&apos;ll move you.
          </p>
          <div className="mt-2.5 flex items-center gap-2">
            <input
              type="date"
              value={dob}
              onChange={(e) => setDob(e.target.value)}
              aria-label="Date of birth"
              className="tnum glass rounded-ctl px-3 py-2 text-[15px] text-ink"
            />
            <button
              onClick={reconfirm}
              disabled={!dob}
              className="rounded-ctl bg-ink px-3.5 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              Confirm
            </button>
          </div>
        </div>
      )}

      {saved && <p className="mt-2 text-xs text-accent">Saved.</p>}
    </div>
  );
}

/** Gentle limits — both OFF by default, both on-device only. */
function GoalsSettings() {
  const goals = useGoals();

  function edit(key: GoalKey, raw: string) {
    const n = Number(raw);
    setGoal(key, raw.trim() === "" || !Number.isFinite(n) || n <= 0 ? undefined : n);
  }

  const FIELDS: { key: GoalKey; label: string; hint: string }[] = [
    { key: "weeklyLimit", label: "Weekly limit", hint: "Alcoholic drinks in a rolling 7 days." },
    { key: "dryDays", label: "Dry days", hint: "Days with nothing alcoholic, per week." },
  ];

  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Gentle limits</p>
      <p className="mb-3 text-xs leading-relaxed text-faint">
        Optional, and off unless you set one. Stays on this device — a private intention never leaves it.
      </p>
      <div className="flex flex-wrap gap-4">
        {FIELDS.map((f) => (
          <label key={f.key} className="flex-1 min-w-130px">
            <span className="mb-1 block text-xs text-muted">{f.label}</span>
            <input
              type="number"
              inputMode="numeric"
              min={1}
              max={GOAL_MAX[f.key]}
              value={goals[f.key] ?? ""}
              onChange={(e) => edit(f.key, e.target.value)}
              placeholder="off"
              aria-label={f.label}
              className="glass w-full rounded-ctl px-3 py-2 text-[15px] text-ink placeholder:text-faint"
            />
            <span className="mt-1 block text-xs text-faint">{f.hint}</span>
          </label>
        ))}
      </div>
    </div>
  );
}

const VIS_LABEL: Record<ProfileVisibility, string> = {
  friends: "Friends only",
  fof: "Friends of friends",
  public: "Public",
};

function ProfilePrivacy({ meId, handle }: { meId: string; handle: string }) {
  const { visibility, socialHandle, loaded } = useProfilePrivacy();
  const [vis, setVis] = useState<ProfileVisibility>("friends");
  const [link, setLink] = useState("");
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    if (loaded) {
      setVis(visibility);
      setLink(socialHandle);
    }
  }, [loaded, visibility, socialHandle]);

  function pick(v: ProfileVisibility) {
    setVis(v);
    setProfileVisibility(meId, v);
  }
  function saveLink() {
    setSocialHandle(meId, link);
    setSaved(true);
    setTimeout(() => setSaved(false), 1600);
  }

  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Public profile</p>
      <p className="mb-3 text-xs text-faint">
        Who can open your profile at /u/{handle}. Any of these shows a streak mosaic and totals — never your notes,
        never your spend, never where you were.
      </p>
      <div className="flex flex-wrap gap-2">
        {(["friends", "fof", "public"] as ProfileVisibility[]).map((v) => (
          <button
            key={v}
            onClick={() => pick(v)}
            aria-pressed={vis === v}
            className={clsx(
              "rounded-ctl px-3.5 py-1.5 text-sm transition-colors",
              vis === v ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
            )}
          >
            {VIS_LABEL[v]}
          </button>
        ))}
      </div>
      {vis !== "friends" && (
        <p className="mt-2 text-xs text-faint">
          {vis === "public" ? "Live to anyone at " : "Open to your friends and their friends at "}
          <Link href={`/u/${handle}`} className="text-accent transition-opacity hover:opacity-80">
            /u/{handle}
          </Link>
        </p>
      )}

      <p className="label mb-1 mt-4 text-faint">One social link</p>
      <p className="mb-2 text-xs text-faint">
        Anyone who can see your profile will see this. Add only a handle you&apos;re fine with strangers finding — never your phone, email, or address.
      </p>
      <div className="flex items-center gap-2">
        <input
          value={link}
          onChange={(e) => setLink(e.target.value)}
          placeholder="@you or https://…"
          aria-label="Social link"
          className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint"
        />
        <button
          onClick={saveLink}
          className={clsx("shrink-0 text-sm transition-colors", saved ? "font-medium text-accent" : "text-muted hover:text-ink")}
        >
          {saved ? "Saved" : "Save"}
        </button>
      </div>
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
