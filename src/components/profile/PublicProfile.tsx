"use client";

// A public profile — /u/<handle>. The face a stranger meets: a monogram, name + handle,
// a PALATE SCORE with its level/title (lib/score — breadth + consistency, never volume),
// the lifetime stats, and a 12-week streak mosaic. Only what the person made public, and
// only counts — never notes, spend, venue, or location. A non-public or unknown handle
// shows a calm "nothing here" instead of details.
import { useState } from "react";
import Link from "next/link";
import { usePublicProfile } from "@/lib/publicProfile";
import { paletteScore } from "@/lib/score";
import { MONTH_NAMES, parseKey } from "@/lib/date";
import { RecentMosaic } from "../together/RecentMosaic";
import { ScoreBanner } from "../ui/ScoreBanner";
import { ProfileCard } from "../share/ProfileCard";

function socialHref(s: string): string | null {
  return /^https?:\/\/[^\s]+$/i.test(s.trim()) ? s.trim() : null;
}

function monogram(name: string): string {
  return (
    name
      .replace(/[^\p{L}\p{N} ]/gu, "")
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((w) => w[0]!.toUpperCase())
      .join("") || "?"
  );
}

export function PublicProfile({ handle }: { handle: string }) {
  const { profile, loading } = usePublicProfile(handle);
  const [sharing, setSharing] = useState(false);

  if (loading) {
    return (
      <main className="flex-1" aria-hidden>
        <div className="mb-8 flex items-center gap-4">
          <div className="glass h-16 w-16 shrink-0 animate-pulse rounded-full" />
          <div className="flex-1 space-y-2">
            <div className="glass h-6 w-1/2 animate-pulse rounded-ctl" />
            <div className="glass h-4 w-1/3 animate-pulse rounded-ctl" />
          </div>
        </div>
        <div className="glass mb-6 h-40 animate-pulse rounded-tile" />
        <div className="glass h-36 animate-pulse rounded-tile" />
      </main>
    );
  }

  if (!profile) {
    return (
      <main className="flex-1">
        <p className="mt-16 text-center text-sm text-faint">
          Nothing to see here — this profile is private, or the handle doesn&apos;t exist.
        </p>
        <p className="mt-3 text-center">
          <Link href="/" className="text-sm font-medium text-accent transition-opacity hover:opacity-80">
            Go to brewdiary
          </Link>
        </p>
      </main>
    );
  }

  const href = profile.socialHandle ? socialHref(profile.socialHandle) : null;
  const activeInWindow = profile.counts.size; // logged days in the mosaic's 12 weeks
  // Lifetime figures (migration 046). Before it's applied, fall back to what the window shows.
  const activeDays = profile.activeDays ?? activeInWindow;
  const longestStreak = profile.longestStreak ?? 0;
  const monthsActive = profile.monthsActive ?? 1;
  const ps = paletteScore({ kinds: profile.kinds, activeDays, longestStreak, monthsActive });
  const since = profile.firstDate ? parseKey(profile.firstDate) : null;

  // The lifetime stat tiles — only the ones we actually have numbers for.
  const tiles: { value: string; label: string }[] = [
    { value: String(profile.total), label: "logged" },
    { value: String(profile.kinds), label: "kinds" },
  ];
  if (profile.longestStreak !== undefined) tiles.push({ value: String(profile.longestStreak), label: "best streak" });
  if (profile.activeDays !== undefined) tiles.push({ value: String(profile.activeDays), label: "days out" });

  return (
    <main className="flex-1">
      <header className="mb-6">
        <p className="label mb-4 text-faint">A public diary</p>
        <div className="flex items-center gap-4">
          <span
            aria-hidden
            className="grid h-16 w-16 shrink-0 place-items-center rounded-full bg-accent/12 font-display text-2xl text-ink"
          >
            {monogram(profile.displayName)}
          </span>
          <div className="min-w-0">
            <h1 className="truncate font-display text-3xl leading-tight tracking-tight text-ink">
              {profile.displayName}
            </h1>
            <p className="mt-0.5 text-sm text-faint">
              @{profile.handle}
              {since && (
                <span> · since {MONTH_NAMES[since.getMonth()].slice(0, 3)} {since.getFullYear()}</span>
              )}
            </p>
          </div>
        </div>

        {profile.socialHandle && (
          <p className="mt-4 text-sm">
            {href ? (
              <a
                href={href}
                target="_blank"
                rel="noopener noreferrer nofollow"
                className="text-accent underline decoration-line-strong underline-offset-4 hover:opacity-80"
              >
                {profile.socialHandle}
              </a>
            ) : (
              <span className="text-muted">{profile.socialHandle}</span>
            )}
          </p>
        )}
      </header>

      {/* The hero — the Palate Score dial + the level/title it earns. */}
      <div className="glass rounded-tile p-5">
        <ScoreBanner ps={ps} size={120} />

        {/* lifetime stat tiles */}
        <div className="mt-5 grid grid-cols-2 gap-px overflow-hidden rounded-ctl bg-line sm:grid-cols-4">
          {tiles.map((t) => (
            <div key={t.label} className="flex flex-col items-center gap-1 bg-canvas py-4">
              <span className="tnum font-display text-2xl leading-none text-ink">{t.value}</span>
              <span className="label text-faint">{t.label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* The 12 weeks — the mosaic, with its own honest count. */}
      <section className="mt-8">
        <div className="mb-3 flex items-baseline justify-between gap-3">
          <p className="label text-faint">The last 12 weeks</p>
          {activeInWindow > 0 && (
            <span className="tnum text-xs text-faint">
              {activeInWindow} active {activeInWindow === 1 ? "day" : "days"}
            </span>
          )}
        </div>
        <RecentMosaic counts={profile.counts} />
      </section>

      <button
        onClick={() => setSharing(true)}
        className="mt-8 w-full rounded-ctl bg-ink py-3 text-sm font-medium text-paper transition-opacity hover:opacity-90"
      >
        Share as a card
      </button>

      <p className="mt-5 border-t border-line pt-5 text-xs leading-relaxed text-faint">
        A public brewdiary — a score built on how widely and how steadily they explore, never on how
        much they drink. Only the streak, never the notes, the spend, or where they were.
      </p>

      {sharing && (
        <ProfileCard
          profile={{
            name: profile.displayName,
            handle: profile.handle,
            total: profile.total,
            kinds: profile.kinds,
            activeDays: activeInWindow,
            counts: profile.counts,
            score: ps.score,
            title: ps.title,
            level: ps.level,
            longestStreak: profile.longestStreak,
          }}
          onClose={() => setSharing(false)}
        />
      )}
    </main>
  );
}
