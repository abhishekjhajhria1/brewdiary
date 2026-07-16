"use client";

// "Near you" — the same k-anonymous taste trends, but scoped to YOUR coarse cell
// (a ~40 km geohash set from your location, never a pin). This is the consumer-side
// reason to opt in: see what your neighbourhood is drinking. Every opt-in also grows
// the pool that Ninkasi reads for local bars — so the card lets you turn it on right
// here. Counts only, ≥5 people before anything shows; never who.
import { useState } from "react";
import { useAuth } from "@/lib/profile";
import {
  useTrendsGeo,
  useAreaTrends,
  setShareTrends,
  requestLocationGeohash,
  setTrendsGeo,
} from "@/lib/trends";

export function NearbyTrends() {
  const me = useAuth().profile?.id;
  const { hasArea, geo, loaded, reload } = useTrendsGeo();
  const { trends, loading } = useAreaTrends(geo, 30);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  // Signed-out visitors can't have a cell; the global "what's pouring" card covers them.
  if (!me || !loaded) return null;

  // Turn it on right here: consent to anonymous trends + set a coarse area from location.
  async function optIn() {
    if (!me) return;
    setBusy(true);
    setMsg(null);
    const { geohash, error } = await requestLocationGeohash();
    if (error || !geohash) {
      setBusy(false);
      setMsg(error ?? "Couldn't set your area.");
      return;
    }
    await setShareTrends(me, true);
    const err = await setTrendsGeo(me, geohash);
    setBusy(false);
    if (err) {
      setMsg("Couldn't save your area — try again.");
      return;
    }
    reload();
  }

  const drinks = trends.filter((t) => t.kind === "drink");
  const moods = trends.filter((t) => t.kind === "mood");

  return (
    <section className="mt-8">
      <p className="label mb-3 text-faint">Near you · last 30 days</p>

      {!hasArea ? (
        <div className="glass rounded-tile p-5">
          <p className="text-[15px] text-ink">See what your neighbourhood is drinking.</p>
          <p className="mt-1.5 max-w-prose text-sm leading-relaxed text-muted">
            Set your area from your location — a rough ~40&nbsp;km cell, never your exact spot — and you&apos;ll see
            the local taste. It also turns on anonymous trends (counts only, never your name or notes).
          </p>
          <button
            onClick={optIn}
            disabled={busy}
            className="mt-3 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {busy ? "Locating…" : "Set my area"}
          </button>
          {msg && <p className="mt-2 text-xs text-accent">{msg}</p>}
        </div>
      ) : loading ? (
        <div className="glass h-16 animate-pulse rounded-tile" aria-hidden />
      ) : drinks.length === 0 ? (
        <p className="text-sm text-faint">
          Quiet in your area so far — local trends appear once at least five people near you have opted in.
        </p>
      ) : (
        <>
          <ul className="divide-y divide-line border-y border-line">
            {drinks.map((t) => (
              <li key={t.name} className="flex items-baseline justify-between py-2.5">
                <span className="text-[15px] text-ink">{t.name}</span>
                <span className="tnum text-xs text-faint">
                  {t.users} {t.users === 1 ? "person" : "people"} · {t.logs} pours
                </span>
              </li>
            ))}
          </ul>
          {moods.length > 0 && (
            <p className="mt-3 text-sm text-muted">
              The mood nearby:{" "}
              {moods.map((m, i) => (
                <span key={m.name}>
                  {i > 0 && <span className="text-faint"> · </span>}
                  <span className="italic">{m.name}</span>
                </span>
              ))}
            </p>
          )}
          <p className="mt-3 text-xs text-faint">
            Anonymous counts from people near you who opted in — a rough area, never an exact spot, never who.
          </p>
        </>
      )}
    </section>
  );
}
