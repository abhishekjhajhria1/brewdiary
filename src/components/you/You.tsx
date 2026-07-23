"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import clsx from "clsx";
import { useEntries, reseed, resetAll, replaceAll, snapshot } from "@/lib/store";
import { countsByDate, lexicon, stats, yearReview, weekBalance, type Stats } from "@/lib/derive";
import { useGoals, setGoal, anyGoalSet, GOAL_MAX, type GoalKey } from "@/lib/goals";
import { MilestoneMeter } from "../ui/MilestoneMeter";
import { ScoreBanner } from "../ui/ScoreBanner";
import { scoreFromEntries } from "@/lib/score";
import { ProfileCard } from "../share/ProfileCard";
import { MONTH_NAMES, addDays, parseKey, toKey, todayKey } from "@/lib/date";
import type { Entry } from "@/lib/types";
import { usePantry, addIngredient, removeIngredient } from "@/lib/pantry";
import { makeable, commonStaples } from "@/lib/recipes";
import { useProfile, signOut, updateHandle } from "@/lib/profile";
import { reroll } from "@/lib/handles";
import { WeeklyRecap } from "../passport/WeeklyRecap";
import { useRecap, setRecap } from "@/lib/recap";
import { TrustCard } from "../verify/TrustCard";
import { useIsModerator } from "@/lib/moderation";
import { useBlocks, unblockUser } from "@/lib/safety";
import { isCollecting, setCollecting, clearTraining, useTrainingCount } from "@/lib/training";
import { useShareTrends, setShareTrends, useTrendsGeo, requestLocationGeohash, setTrendsGeo } from "@/lib/trends";
import { useMyVenueBooks, forgetVenueBook } from "@/lib/guestbook";
import { useMyReservations, cancelReservation, type ReservationStatus } from "@/lib/reservations";
import { useCompeteVisible, setCompeteVisible } from "@/lib/points";
import { useProfilePrivacy, setProfileVisibility, setSocialHandle, type ProfileVisibility } from "@/lib/publicProfile";
import { useExtras, setExtra, EXTRAS, type ExtraKey } from "@/lib/features";
import { useWaterMl, setWaterMl, formatVolume } from "@/lib/waterPref";
import { exportEverything, deleteAccount } from "@/lib/dataRights";
import { savedCountry, moveTo, confirmAge, legalAgeFor } from "@/lib/age";
import { KNOWN_COUNTRIES } from "@/lib/jurisdiction";
import { Chip } from "../ui/Chip";
import { VenueLink } from "../ui/VenueLink";
import { ThemeToggle } from "../ui/ThemeToggle";

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
      {/* The profile — how you'd look to someone else. Tapping it opens your public
          page (/u/handle). Everything below is YOUR stuff, then, past the divider,
          your settings — the phone-settings shape you asked for. */}
      <ProfileHeader stats={s} entries={entries} />

      {/* Both only ever appear once you've asked for them (You → Settings) */}
      <WeeklyRecap />
      <BalanceCard entries={entries} />

      {/* Table bookings you've made at partner bars (only shows if you have any). */}
      <MyTables />

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

      {/* The palate map + its trophies and tonight's expedition now live on the Calendar's
          Year view (a companion to the year mosaic) — the most-visible page. And "To try"
          moved to Together, where it sits with the picks your friends inspire. */}

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

        {/* What you keep at home (for Ninkasi later) + a look back over the whole journey. */}
        <Pantry />
        <JourneyTile entries={entries} />

        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search your drinks…"
          className="mb-3 w-full border-b border-line-strong bg-transparent pb-2 text-sm outline-none placeholder:text-faint focus:border-ink"
        />
        {filtered.length === 0 ? (
          <p className="py-6 text-center text-sm text-faint">Nothing here yet.</p>
        ) : (
          // Same-day repeats fold into ONE row with a ×N (six waters is one line, not six),
          // and the whole list scrolls in place so the page never becomes one long ledger.
          <ul className="glass max-h-105 divide-y divide-line overflow-y-auto rounded-tile px-5">
            {groupShelf(filtered).map((g) => (
              <ShelfRow key={g.entry.id} entry={g.entry} count={g.count} />
            ))}
          </ul>
        )}
      </section>

      {/* The line: everything below is settings & account — the phone-settings shelf. */}
      <div className="mt-14 mb-2 border-t border-line pt-2" />
      <Settings />
    </>
  );
}

// The profile card — how you read to someone else. The identity row is a link to your
// public page (/u/handle); the stats sit under it, and a "Share as a card" button turns
// them into a poster for social (see ProfileCard). A guest with no handle sees the same
// card without the link or share (there's no public page to open yet).
function ProfileHeader({ stats: s, entries }: { stats: Stats; entries: Entry[] }) {
  const profile = useProfile();
  const [sharing, setSharing] = useState(false);
  const name = profile?.name?.trim() || "You";
  const handle = profile?.handle || "";
  const initials = name.replace(/[^\p{L}\p{N} ]/gu, "").split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join("") || "Y";

  // The 12-week window that the shared mosaic draws — and how many of those days you logged.
  const counts = useMemo(() => countsByDate(entries), [entries]);
  const activeDays = useMemo(() => {
    const cutoff = toKey(addDays(parseKey(todayKey()), -(12 * 7 - 1)));
    let n = 0;
    for (const k of counts.keys()) if (k >= cutoff) n++;
    return n;
  }, [counts]);
  const ps = useMemo(() => scoreFromEntries(entries), [entries]);

  const identity = (
    <>
      <span aria-hidden className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-accent/12 font-display text-lg text-ink">
        {initials}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate font-display text-2xl leading-tight text-ink">{name}</p>
        {handle && <p className="truncate text-sm text-faint">@{handle}</p>}
      </div>
      {handle && <span aria-hidden className="shrink-0 text-lg text-faint">→</span>}
    </>
  );

  return (
    <div className="glass rounded-tile p-5">
      {handle ? (
        <Link
          href={`/u/${handle}`}
          aria-label="Your public profile"
          className="-m-1 flex items-center gap-3 rounded-ctl p-1 transition-colors hover:bg-ink/3"
        >
          {identity}
        </Link>
      ) : (
        <div className="flex items-center gap-3">{identity}</div>
      )}

      {/* The Palate Score — the same banner the public profile leads with. */}
      {s.total > 0 && (
        <div className="mt-4 border-t border-line pt-4">
          <ScoreBanner ps={ps} size={88} />
        </div>
      )}

      <div className="mt-4 grid grid-cols-3 border-t border-line pt-4">
        <Metric value={s.current} label="streak" />
        <Metric value={s.total} label="logged" />
        <Metric value={s.kinds} label="kinds" />
      </div>
      {s.total > 0 && (
        <div className="mt-4 border-t border-line pt-4">
          <MilestoneMeter total={s.total} />
        </div>
      )}

      {handle && s.total > 0 && (
        <button
          onClick={() => setSharing(true)}
          className="mt-4 w-full rounded-ctl border border-line py-2.5 text-sm text-muted transition-colors hover:border-line-strong hover:text-ink"
        >
          Share as a card
        </button>
      )}

      {sharing && (
        <ProfileCard
          profile={{
            name,
            handle,
            total: s.total,
            kinds: s.kinds,
            activeDays,
            counts,
            score: ps.score,
            title: ps.title,
            level: ps.level,
            longestStreak: s.longest,
          }}
          onClose={() => setSharing(false)}
        />
      )}
    </div>
  );
}

function Settings() {
  const fileRef = useRef<HTMLInputElement>(null);
  const [reminder, setReminder] = useState(false);
  const [collect, setCollect] = useState(true);
  const trainingCount = useTrainingCount();
  const recap = useRecap();
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
      <div className="py-1">
        <p className="text-sm text-ink">Appearance</p>
        <p className="text-xs text-faint">Four looks — pick the one that feels like your notebook.</p>
        <ThemeToggle className="mt-3" />
      </div>

      <div className="mt-4 flex items-center justify-between gap-4 border-t border-line py-3">
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

      <div className="mt-4 flex items-center justify-between gap-4 border-t border-line py-3">
        <div>
          <p className="text-sm text-ink">Weekly look-back</p>
          <p className="text-xs text-faint">
            A quiet card on You: the corners of your palate map you found this week, and one door out of it.
          </p>
        </div>
        <Toggle on={recap.on ?? false} label="Weekly look-back" onToggle={(next) => setRecap(next)} />
      </div>

      {profile && <TrendsOptIn meId={profile.id} />}

      {profile && <CompeteOptIn meId={profile.id} />}

      {profile && <VenueScreenNote />}

      {profile && profile.handle && <HandleCard handle={profile.handle} />}

      {profile && <TrustCard />}

      {profile && <ProfilePrivacy meId={profile.id} handle={profile.handle} />}

      {profile && <ModeratorLink />}

      {profile && <BlockedPeople />}

      {profile && <VenueBooks meId={profile.id} />}

      <WhereYouAre />

      <GoalsSettings />

      <ExtrasSettings />

      {profile && <DataRights />}

      {/* Data & account — real buttons, not a row of near-invisible text links, so these
          actions are actually findable (maintainer's ask: fewer bare clickable words). */}
      <div className="mt-5 border-t border-line pt-4">
        <p className="label mb-3 text-faint">Data &amp; account</p>
        <div className="flex flex-wrap gap-2">
          <FooterButton onClick={exportJson}>Export data</FooterButton>
          <FooterButton onClick={() => fileRef.current?.click()}>Import data</FooterButton>
          <FooterButton onClick={reseed}>Reseed demo</FooterButton>
          <FooterButton onClick={resetAll} danger>
            Reset diary
          </FooterButton>
          {trainingCount > 0 && (
            <FooterButton onClick={clearTraining}>Clear Ninkasi data</FooterButton>
          )}
          {profile ? (
            <FooterButton onClick={handleSignOut}>Sign out</FooterButton>
          ) : (
            <FooterButton onClick={() => router.push("/")}>Sign in</FooterButton>
          )}
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 text-xs text-faint">
          <Link href="/privacy" className="underline-offset-2 transition-colors hover:text-ink hover:underline">
            Privacy
          </Link>
          <Link href="/terms" className="underline-offset-2 transition-colors hover:text-ink hover:underline">
            Terms
          </Link>
        </div>

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

// Your table bookings at partner bars (the Dineout loop's guest side). Only shows
// if you've made one; a booking is confirmed by the venue, never self-confirmed.
const MY_RES_LABEL: Record<ReservationStatus, string> = {
  requested: "Waiting for the venue to confirm",
  confirmed: "Confirmed",
  declined: "The venue couldn't take it",
  cancelled: "Cancelled",
  seated: "Seated",
  no_show: "Marked no-show",
};

function MyTables() {
  const { reservations, loading } = useMyReservations();
  if (loading || reservations.length === 0) return null;

  const prettyDate = (key: string) => {
    const d = new Date(`${key}T00:00:00`);
    return Number.isNaN(d.getTime())
      ? key
      : d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
  };

  return (
    <section className="mt-10">
      <h2 className="label mb-3">Your tables</h2>
      <ul className="space-y-2">
        {reservations.map((r) => {
          const cancellable = r.status === "requested" || r.status === "confirmed";
          const active = r.status === "requested" || r.status === "confirmed" || r.status === "seated";
          return (
            <li key={r.id} className="glass rounded-tile p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="truncate text-[15px] text-ink">{r.venueName}</p>
                  <p className="mt-0.5 text-xs text-faint">
                    {prettyDate(r.date)}
                    {r.time && <> · {r.time.slice(0, 5)}</>} · party of {r.partySize}
                  </p>
                  <p className={clsx("mt-1 text-xs", active ? "text-accent" : "text-faint")}>{MY_RES_LABEL[r.status]}</p>
                </div>
                {cancellable && (
                  <button
                    onClick={() => cancelReservation(r.id)}
                    className="shrink-0 text-xs text-faint transition-colors hover:text-accent"
                  >
                    Cancel
                  </button>
                )}
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/** Transparency: every venue that keeps a first-party note on you, and the button
 *  to erase it. A venue can only note a guest who's been to it (server-enforced),
 *  and the note never includes your diary — but you still get to see and delete it. */
function VenueBooks({ meId }: { meId: string }) {
  const { books, loading, reload } = useMyVenueBooks();
  const [busy, setBusy] = useState<string | null>(null);

  async function forget(venueId: string) {
    setBusy(venueId);
    await forgetVenueBook(meId, venueId);
    setBusy(null);
    reload();
  }

  if (loading || books.length === 0) return null; // nothing kept on you → nothing to show

  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Notes venues keep on you</p>
      <p className="mb-3 text-xs leading-relaxed text-faint">
        A bar you&apos;ve visited can keep its own notes on you — never your diary or what you do elsewhere. Here&apos;s
        every one, and you can erase any of them.
      </p>
      <ul className="space-y-2">
        {books.map((b) => (
          <li key={b.venueId} className="glass rounded-ctl px-3.5 py-2.5">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-sm text-ink">{b.venueName}</p>
                {b.body && <p className="mt-0.5 text-xs leading-relaxed text-muted">{b.body}</p>}
                {b.tags.length > 0 && (
                  <p className="mt-1 flex flex-wrap gap-1">
                    {b.tags.map((t) => (
                      <span key={t} className="text-xs text-faint">
                        #{t}
                      </span>
                    ))}
                  </p>
                )}
              </div>
              <button
                onClick={() => forget(b.venueId)}
                disabled={busy === b.venueId}
                className="shrink-0 text-xs text-faint transition-colors hover:text-accent disabled:opacity-50"
              >
                {busy === b.venueId ? "…" : "Forget"}
              </button>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Opt-in (default OFF) to counting this diary in the anonymous taste trends. */
function TrendsOptIn({ meId }: { meId: string }) {
  const { shareTrends, loaded } = useShareTrends();
  const { hasArea, loaded: geoLoaded, reload } = useTrendsGeo();
  const [on, setOn] = useState(false);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  useEffect(() => {
    if (loaded) setOn(shareTrends);
  }, [loaded, shareTrends]);

  function toggle() {
    const next = !on;
    setOn(next);
    setShareTrends(meId, next);
  }

  async function setArea() {
    setBusy(true);
    setMsg(null);
    const { geohash, error } = await requestLocationGeohash();
    if (error || !geohash) {
      setBusy(false);
      setMsg(error ?? "Couldn't set your area.");
      return;
    }
    const err = await setTrendsGeo(meId, geohash);
    setBusy(false);
    if (err) {
      setMsg("Couldn't save your area — try again.");
      return;
    }
    reload();
  }

  async function clearArea() {
    await setTrendsGeo(meId, null);
    reload();
  }

  return (
    <div className="mt-4 border-t border-line py-3">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-sm text-ink">Anonymous taste trends</p>
          <p className="text-xs text-faint">
            Count my logs in the &quot;what&apos;s pouring&quot; trends — counts only, never my name or notes.
          </p>
        </div>
        <Toggle on={on} label="Anonymous taste trends" onToggle={toggle} />
      </div>

      {/* Optional coarse AREA from your location — lets local bars read their
          neighbourhood's taste. We keep only a ~40 km cell, never your exact spot,
          and nothing shows until ≥5 people share it. */}
      {on && geoLoaded && (
        <div className="mt-3">
          {hasArea ? (
            <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
              <span className="text-accent">Area set</span>
              <span className="text-faint">a rough ~40&nbsp;km cell — never your exact spot</span>
              <button onClick={clearArea} className="text-faint underline-offset-2 transition-colors hover:text-ink hover:underline">
                Clear
              </button>
            </p>
          ) : (
            <>
              <p className="mb-1.5 text-xs text-muted">
                Set your area from your location so nearby bars can read the local taste — never your exact spot.
              </p>
              <button
                onClick={setArea}
                disabled={busy}
                className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                {busy ? "Locating…" : "Set my area from location"}
              </button>
            </>
          )}
          {msg && <p className="mt-2 text-xs text-accent">{msg}</p>}
        </div>
      )}
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

// A quiet doorway to the moderation queue, shown only to moderators (membership is
// seeded by hand, never grantable in-app). Everyone else never sees it — and couldn't
// use it if they did, since every action is re-checked server-side.
function ModeratorLink() {
  const isMod = useIsModerator();
  if (!isMod) return null;
  return (
    <div className="mt-4 border-t border-line py-3">
      <Link href="/moderation" className="flex items-center justify-between gap-3 text-sm text-ink transition-colors hover:text-accent">
        <span>Moderation queue</span>
        <span className="text-faint">Review reports →</span>
      </Link>
    </div>
  );
}

// Your block list — the other half of the block affordance in Plans/Together. Blocking
// is one tap from a person's menu, but until now there was no way to see who you'd
// blocked or to undo it; a block was a one-way door. This is that door's handle.
// The section hides itself entirely when you haven't blocked anyone, so it's never noise.
function BlockedPeople() {
  const { blocked, loading } = useBlocks();
  const [busy, setBusy] = useState<string | null>(null);

  if (loading || blocked.length === 0) return null;

  async function unblock(id: string) {
    setBusy(id);
    await unblockUser(id);
    setBusy(null);
  }

  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Blocked people</p>
      <p className="mb-3 mt-1 text-xs leading-relaxed text-faint">
        You don&apos;t see each other&apos;s plans, and neither of you turns up in the other&apos;s search. Unblock
        to undo that.
      </p>
      <ul className="space-y-2">
        {blocked.map((p) => (
          <li key={p.id} className="flex items-center justify-between gap-3">
            <span className="min-w-0 truncate">
              <span className="text-[15px] text-ink">{p.name}</span>{" "}
              <span className="text-xs text-faint">@{p.handle}</span>
            </span>
            <button
              onClick={() => unblock(p.id)}
              disabled={busy === p.id}
              className="shrink-0 text-sm text-faint transition-colors hover:text-ink disabled:opacity-50"
            >
              {busy === p.id ? "…" : "Unblock"}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

// Your handle, and a button to trade it for a nicer one. We generate the candidate —
// the person never types it — so there's nothing to validate and no way to pick
// something crude; they just keep pressing "try another" until a word lands. Saving
// changes their /u/<handle> url, so it's a deliberate press, never automatic.
function HandleCard({ handle }: { handle: string }) {
  const [candidate, setCandidate] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  // Climbs only when a save loses the "taken" race — it pushes reroll() from clean
  // words toward numbered ones, so a very popular name still finds a free handle
  // rather than offering the same taken words forever.
  const takenRef = useRef(0);

  async function save() {
    if (!candidate) return;
    setBusy(true);
    setNote(null);
    const res = await updateHandle(candidate);
    setBusy(false);
    if (res.ok) {
      setCandidate(null); // the card now shows the new handle from the store
      takenRef.current = 0;
      return;
    }
    // The only expected failure: someone grabbed that exact handle a moment ago.
    if (res.error === "taken") {
      takenRef.current += 1;
      setCandidate((c) => reroll(c ?? handle, takenRef.current));
      setNote("Someone just took that one — here's another.");
      return;
    }
    setNote(res.error);
  }

  return (
    <div className="mt-4 border-t border-line py-3">
      <p className="text-sm text-ink">Your handle</p>
      <p className="mb-3 text-xs text-faint">
        How friends find you, and your address at /u/&lt;handle&gt;. Trade it for another whenever you like — you
        pick from ones we spin up, so it stays clean.
      </p>

      {candidate === null ? (
        <div className="flex items-center justify-between gap-3">
          <span className="font-display text-lg text-ink">@{handle}</span>
          <button
            onClick={() => {
              setNote(null);
              takenRef.current = 0;
              setCandidate(reroll(handle));
            }}
            className="glass glass-press shrink-0 rounded-ctl px-3.5 py-1.5 text-sm text-muted transition-colors hover:text-ink"
          >
            Change
          </button>
        </div>
      ) : (
        <div>
          <div className="flex items-center justify-between gap-3">
            <span className="font-display text-lg text-accent">@{candidate}</span>
            <button
              onClick={() => setCandidate(reroll(candidate, takenRef.current))}
              disabled={busy}
              className="glass glass-press shrink-0 rounded-ctl px-3.5 py-1.5 text-sm text-muted transition-colors hover:text-ink disabled:opacity-50"
            >
              Try another
            </button>
          </div>
          <div className="mt-3 flex items-center gap-3">
            <button
              onClick={save}
              disabled={busy}
              className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
            >
              {busy ? "Saving…" : "Use this"}
            </button>
            <button
              onClick={() => {
                setCandidate(null);
                setNote(null);
              }}
              disabled={busy}
              className="text-sm text-faint transition-colors hover:text-ink disabled:opacity-50"
            >
              Keep @{handle}
            </button>
          </div>
        </div>
      )}
      {note && <p className="mt-2 text-xs text-accent">{note}</p>}
    </div>
  );
}

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
        <div key={e.key}>
          <div className="flex items-center justify-between gap-4 py-2">
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
          {e.key === "water" && (flags.water ?? false) && <WaterMeasure />}
        </div>
      ))}
    </div>
  );
}

// When Water is on, an optional glass size (ml). Set it and the day's water counter
// also shows a volume (3 × 250 ml = 750 ml); leave it blank to just count glasses.
function WaterMeasure() {
  const ml = useWaterMl();
  return (
    <label className="flex items-center justify-between gap-4 pb-2 pl-0">
      <span className="text-xs text-faint">Glass size (ml) — optional, adds a volume</span>
      <input
        type="number"
        inputMode="numeric"
        min={1}
        max={2000}
        value={ml ?? ""}
        onChange={(e) => setWaterMl(e.target.value.trim() === "" ? null : Number(e.target.value))}
        placeholder="glasses"
        aria-label="Water glass size in millilitres"
        className="tnum glass w-24 rounded-ctl px-3 py-1.5 text-sm text-ink placeholder:text-faint"
      />
    </label>
  );
}

/** A visible button for the data/account actions — a bordered chip with a proper touch
 *  target, so these read as controls you can press, not as fine print. */
function FooterButton({
  onClick,
  danger,
  children,
}: {
  onClick: () => void;
  danger?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={clsx(
        "min-h-11 rounded-ctl border px-3.5 py-2 text-sm transition-colors",
        danger
          ? "border-line text-muted hover:border-accent hover:text-accent"
          : "border-line text-muted hover:border-line-strong hover:text-ink",
      )}
    >
      {children}
    </button>
  );
}

/** The switch used across Settings. A larger, clearer control: the knob carries a check
 *  when on and a small dot when off, so the state reads at a glance, not just by colour. */
function Toggle({ on, label, onToggle }: { on: boolean; label: string; onToggle: (next: boolean) => void }) {
  return (
    <button
      onClick={() => onToggle(!on)}
      role="switch"
      aria-checked={on}
      aria-label={label}
      className={clsx(
        "relative inline-flex h-7 w-13 shrink-0 items-center rounded-full transition-colors duration-200 ease-out",
        on
          ? "bg-accent shadow-[inset_0_1px_1px_rgba(0,0,0,0.12)]"
          : "bg-ink/12 shadow-[inset_0_0_0_1.5px_var(--color-line-strong)]",
      )}
    >
      <span
        aria-hidden
        className={clsx(
          "grid h-6 w-6 place-items-center rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.28)] transition-transform duration-200 ease-out",
          on ? "translate-x-6.5" : "translate-x-0.5",
        )}
      >
        {on ? (
          <svg viewBox="0 0 12 12" className="h-3 w-3 text-accent">
            <path d="M2.6 6.4l2.2 2.2 4.6-4.9" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        ) : (
          <span className="h-1.5 w-1.5 rounded-full bg-line-strong" />
        )}
      </span>
    </button>
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

// Your bar — the ingredients you keep at home. Feeds nothing yet; it's the store
// Ninkasi will read to suggest what you can make (see lib/pantry.ts). Tap a chip to
// remove it.
function Pantry() {
  const items = usePantry();
  const [draft, setDraft] = useState("");
  return (
    <div className="glass mb-3 rounded-tile p-4">
      <div className="mb-2 flex items-center justify-between gap-3">
        <p className="label text-faint">Your bar</p>
        <span className="text-xs text-faint">{items.length > 0 ? `${items.length} on hand` : "what's at home"}</span>
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          addIngredient(draft);
          setDraft("");
        }}
        className="flex items-center gap-2"
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Add an ingredient — gin, lime, tonic…"
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
      {items.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {items.map((it) => (
            <button
              key={it}
              onClick={() => removeIngredient(it)}
              aria-label={`Remove ${it}`}
              className="group inline-flex items-center gap-1.5 rounded-ctl border border-line px-2.5 py-1 text-xs text-muted transition-colors hover:border-line-strong hover:text-ink"
            >
              {it}
              <span aria-hidden className="text-faint group-hover:text-ink">×</span>
            </button>
          ))}
        </div>
      )}
      <Tonight pantry={items} />
    </div>
  );
}

// What the shelf can make right now. Only ever things you already have everything for —
// there is deliberately no "you're one ingredient away", because for alcohol a shopping
// prompt is advertising. It suggests something to MAKE, never a second one, and nothing
// here earns a spark, a perk or a streak: the reward is having made it.
function Tonight({ pantry }: { pantry: string[] }) {
  const [open, setOpen] = useState<string | null>(null);
  const options = makeable(pantry);

  if (pantry.length === 0) {
    return (
      <p className="mt-2.5 text-xs text-faint">
        Add what&apos;s on your shelf — {commonStaples(4).join(", ")} — and this turns into
        what you can make.
      </p>
    );
  }
  if (options.length === 0) {
    return (
      <p className="mt-2.5 text-xs text-faint">
        Nothing complete on that shelf yet. Add a little more and things will start appearing.
      </p>
    );
  }

  return (
    <div className="mt-4 border-t border-line pt-3">
      <p className="label mb-2 text-faint">
        Tonight you could make · {options.length}
      </p>
      <div className="flex flex-wrap gap-1.5">
        {options.map(({ recipe, extras }) => {
          const isOpen = open === recipe.name;
          return (
            <button
              key={recipe.name}
              onClick={() => setOpen(isOpen ? null : recipe.name)}
              aria-expanded={isOpen}
              className={clsx(
                "min-h-11 rounded-ctl border px-3 py-2 text-sm transition-colors",
                isOpen
                  ? "border-transparent bg-accent/8 text-ink"
                  : "border-line text-ink hover:border-line-strong",
              )}
            >
              {recipe.name}
              {extras.length > 0 && (
                <span className="ml-2 text-xs text-faint">+{extras.length}</span>
              )}
            </button>
          );
        })}
      </div>

      {open && (
        <div className="animate-rise mt-3 rounded-tile bg-ink/3 p-3">
          {(() => {
            const picked = options.find((o) => o.recipe.name === open);
            if (!picked) return null;
            return (
              <>
                <p className="text-sm leading-relaxed text-muted">{picked.recipe.method}</p>
                <p className="mt-2 text-xs text-faint">
                  {picked.recipe.needs.join(" · ")}
                  {picked.extras.length > 0 && ` — with ${picked.extras.join(", ")}`}
                </p>
              </>
            );
          })()}
        </div>
      )}
    </div>
  );
}

interface Journey {
  places: number;
  people: number;
  drinks: number;
  days: number;
  first: string | null;
}

// A look back over the whole diary — places been, people alongside, drinks met, days
// kept. Everything derived from entries; a tap opens the fuller panel.
function JourneyTile({ entries }: { entries: Entry[] }) {
  const [open, setOpen] = useState(false);
  const j = useMemo<Journey>(() => {
    const places = new Set<string>();
    const people = new Set<string>();
    const drinks = new Set<string>();
    const days = new Set<string>();
    let first: string | null = null;
    for (const e of entries) {
      if (e.venue?.trim()) places.add(e.venue.trim().toLowerCase());
      for (const w of e.whoWith ?? []) if (w.trim()) people.add(w.trim().toLowerCase());
      if (e.drink?.trim() && e.type !== "none") drinks.add(e.drink.trim().toLowerCase());
      days.add(e.date);
      if (!first || e.date < first) first = e.date;
    }
    return { places: places.size, people: people.size, drinks: drinks.size, days: days.size, first };
  }, [entries]);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="glass glass-press mb-3 flex w-full items-center justify-between gap-4 rounded-tile p-4 text-left"
      >
        <div className="min-w-0">
          <p className="label text-faint">Your journey</p>
          <p className="mt-0.5 truncate text-[15px] text-ink">
            {j.days > 0
              ? `${j.places} place${j.places === 1 ? "" : "s"} · ${j.people} ${j.people === 1 ? "person" : "people"} · ${j.drinks} drink${j.drinks === 1 ? "" : "s"}`
              : "Your story so far"}
          </p>
        </div>
        <span className="shrink-0 text-sm font-medium text-accent">Open →</span>
      </button>
      {open && <JourneyPanel j={j} onClose={() => setOpen(false)} />}
    </>
  );
}

function JourneyPanel({ j, onClose }: { j: Journey; onClose: () => void }) {
  const since = j.first ? parseKey(j.first) : null;
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Your journey"
      className="fixed inset-0 z-50 flex items-end justify-center p-4 sm:items-center"
    >
      <button aria-label="Close" onClick={onClose} className="absolute inset-0 bg-ink/30 backdrop-blur-sm" />
      <div className="glass-strong animate-sheet relative w-full max-w-sm rounded-tile p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="label text-faint">Your journey</p>
            <h3 className="mt-1 font-display text-2xl leading-none text-ink">The story so far</h3>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="-mr-1.5 -mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-2xl leading-none text-muted transition-colors hover:text-ink"
          >
            ×
          </button>
        </div>
        <dl className="mt-4 grid grid-cols-2 gap-3">
          <JourneyStat n={j.days} label="days kept" />
          <JourneyStat n={j.drinks} label="drinks met" />
          <JourneyStat n={j.places} label="places been" />
          <JourneyStat n={j.people} label="alongside" />
        </dl>
        {since && (
          <p className="mt-4 text-xs text-faint">
            Since {MONTH_NAMES[since.getMonth()]} {since.getFullYear()}.
          </p>
        )}
      </div>
    </div>
  );
}

function JourneyStat({ n, label }: { n: number; label: string }) {
  return (
    <div className="glass rounded-tile p-4">
      <p className="tnum font-display text-3xl leading-none text-ink">{n}</p>
      <p className="mt-1 text-xs text-faint">{label}</p>
    </div>
  );
}

/** Fold same-day repeats of the same drink into one row (keeps the first entry for
 *  its mood/venue, counts the rest). The order of `filtered` is preserved. */
function groupShelf(entries: Entry[]): { entry: Entry; count: number }[] {
  const out: { entry: Entry; count: number }[] = [];
  const byKey = new Map<string, { entry: Entry; count: number }>();
  for (const e of entries) {
    const key = `${e.date}|${e.drink.trim().toLowerCase()}`;
    const g = byKey.get(key);
    if (g) g.count++;
    else {
      const fresh = { entry: e, count: 1 };
      byKey.set(key, fresh);
      out.push(fresh);
    }
  }
  return out;
}

function ShelfRow({ entry, count }: { entry: Entry; count: number }) {
  const d = parseKey(entry.date);
  const waterMl = useWaterMl();
  const isWater = entry.drink.trim().toLowerCase() === "water";
  // Water with a glass size set reads as a volume — "×6 · 1.5 L" (see lib/waterPref).
  const volume = isWater && waterMl ? formatVolume(count * waterMl) : null;
  return (
    <li className="flex items-baseline justify-between gap-3 py-3">
      <div className="min-w-0">
        <p className="truncate text-[15px] text-ink">
          {entry.drink}
          {count > 1 && <span className="tnum text-muted"> ×{count}</span>}
          {volume && <span className="tnum text-xs text-faint"> · {volume}</span>}
        </p>
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
