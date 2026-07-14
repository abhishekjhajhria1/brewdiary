"use client";

// A public profile — /u/<handle>. Shows only what the person chose to make
// public: their name, streak mosaic (counts), all-time totals, and one optional
// social link. Never notes, spend, venue, or location. Reached by URL (shareable);
// a non-public or unknown handle shows a calm "nothing here" instead of details.
import Link from "next/link";
import { usePublicProfile } from "@/lib/publicProfile";
import { RecentMosaic } from "../together/RecentMosaic";

// Only turn an explicit http(s) URL into a link; anything else stays plain text
// (so a "javascript:" or odd string can never become a clickable href).
function socialHref(s: string): string | null {
  return /^https?:\/\/[^\s]+$/i.test(s.trim()) ? s.trim() : null;
}

export function PublicProfile({ handle }: { handle: string }) {
  const { profile, loading } = usePublicProfile(handle);

  if (loading) {
    return (
      <main className="flex-1" aria-hidden>
        <div className="glass mb-6 h-20 animate-pulse rounded-tile" />
        <div className="glass h-40 animate-pulse rounded-tile" />
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

  return (
    <main className="flex-1">
      <header className="mb-6 border-b border-line pb-5">
        <p className="label mb-1 text-faint">A public diary</p>
        <h1 className="font-display text-4xl leading-tight tracking-tight text-ink">{profile.displayName}</h1>
        <p className="mt-1.5 text-sm text-faint">@{profile.handle}</p>
        {profile.socialHandle && (
          <p className="mt-2 text-sm">
            {href ? (
              <a href={href} target="_blank" rel="noopener noreferrer nofollow" className="text-accent underline decoration-line-strong underline-offset-4 hover:opacity-80">
                {profile.socialHandle}
              </a>
            ) : (
              <span className="text-muted">{profile.socialHandle}</span>
            )}
          </p>
        )}
      </header>

      <div className="mb-7 flex gap-8">
        <div>
          <p className="font-display text-3xl tabular-nums text-ink">{profile.total}</p>
          <p className="label text-faint">logged</p>
        </div>
        <div>
          <p className="font-display text-3xl tabular-nums text-ink">{profile.kinds}</p>
          <p className="label text-faint">kinds</p>
        </div>
      </div>

      <p className="label mb-3 text-faint">The last 12 weeks</p>
      <RecentMosaic counts={profile.counts} />

      <p className="mt-8 border-t border-line pt-5 text-xs leading-relaxed text-faint">
        A public brewdiary — only the streak, never the notes, the spend, or where they were.
      </p>
    </main>
  );
}
