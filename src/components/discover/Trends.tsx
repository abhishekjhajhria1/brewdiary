"use client";

// "What's pouring" — the first LIVE Discover data: k-anonymous taste trends
// across users who opted in (You → Settings). Counts only, never who.
import { useTasteTrends } from "@/lib/trends";

export function Trends() {
  const { trends, loading } = useTasteTrends();
  const drinks = trends.filter((t) => t.kind === "drink");
  const moods = trends.filter((t) => t.kind === "mood");

  return (
    <section className="mt-8">
      <p className="label mb-3 text-faint">What&apos;s pouring · last two weeks</p>

      {loading ? (
        <div className="glass h-16 animate-pulse rounded-tile" aria-hidden />
      ) : drinks.length === 0 ? (
        <p className="text-sm text-faint">
          Quiet so far — trends appear once enough guests opt in (You → Settings → anonymous taste trends).
        </p>
      ) : (
        <>
          <ul className="divide-y divide-line border-y border-line">
            {drinks.map((t) => (
              <li key={t.name} className="flex items-baseline justify-between py-2.5">
                <span className="text-[15px] text-ink">{t.name}</span>
                <span className="tnum text-xs text-faint">
                  {t.users} {t.users === 1 ? "guest" : "guests"} · {t.logs} pours
                </span>
              </li>
            ))}
          </ul>
          {moods.length > 0 && (
            <p className="mt-3 text-sm text-muted">
              The mood around the bar:{" "}
              {moods.map((m, i) => (
                <span key={m.name}>
                  {i > 0 && <span className="text-faint"> · </span>}
                  <span className="italic">{m.name}</span>
                </span>
              ))}
            </p>
          )}
          <p className="mt-3 text-xs text-faint">Anonymous counts from guests who opted in — never who poured what.</p>
        </>
      )}
    </section>
  );
}
