"use client";

// The header every Together room wears now that rooms are real routes rather than
// tabs. It carries the one thing a tab rail gave for free and a route does not: a
// way back. Ordinary link, ordinary back button — no history games.
import Link from "next/link";

export function RoomHeader({ title, blurb }: { title: string; blurb?: string }) {
  return (
    <header className="mb-2">
      <Link
        href="/together"
        className="inline-flex min-h-11 items-center gap-1.5 text-sm text-faint transition-colors hover:text-ink"
      >
        <span aria-hidden>←</span> Together
      </Link>
      <h1 className="mt-1 font-display text-5xl leading-none tracking-tight">{title}</h1>
      {blurb && <p className="mt-3 max-w-prose text-[15px] leading-relaxed text-muted">{blurb}</p>}
    </header>
  );
}
