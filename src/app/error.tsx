"use client";

// The crash screen. Without this file a render error is a WHITE SCREEN — the worst
// possible thing to show someone holding a diary they care about, because it reads
// as "your data is gone". It isn't: entries live in localStorage or Supabase, never
// in React state alone. This page's whole job is to say that calmly and offer the
// one action that usually works.
//
// (Next.js requires error boundaries to be client components.)
import { useEffect } from "react";

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    // Surface it where a developer will actually see it. When Sentry lands
    // (pre-launch list), this is the line it replaces.
    console.error(error);
  }, [error]);

  return (
    <main className="age-exempt mx-auto flex min-h-[70dvh] max-w-md flex-col items-start justify-center px-6">
      <p className="label text-faint">Something broke</p>
      <h1 className="mt-3 font-display text-3xl leading-tight tracking-tight text-ink">
        Not your diary — just this screen.
      </h1>
      <p className="mt-3 text-[15px] leading-relaxed text-muted">
        Your entries are stored safely and none were touched. Reloading almost always clears this; if it
        keeps happening, tell us at{" "}
        <a href="mailto:hello@bwdy.site" className="text-ink underline underline-offset-2">
          hello@bwdy.site
        </a>
        .
      </p>
      <div className="mt-7 flex items-center gap-4">
        <button
          onClick={reset}
          className="rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90"
        >
          Try again
        </button>
        {/* A hard navigation on purpose: <Link> would client-route INSIDE the tree
            that just crashed and can crash again on arrival. From a broken page, a
            full page load is the reliable way out — so the lint rule yields here. */}
        {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
        <a href="/" className="text-sm text-faint transition-colors hover:text-ink">
          Back to the calendar
        </a>
      </div>
      {error.digest && <p className="mt-6 text-xs text-faint">Error reference: {error.digest}</p>}
    </main>
  );
}
