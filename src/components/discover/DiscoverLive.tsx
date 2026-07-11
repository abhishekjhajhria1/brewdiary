"use client";

// The functional, KEY-FREE half of Discover: a real device-orientation compass and
// geolocation-powered "near me" discovery that opens the user's Maps app. No Google
// Places bill — we use free browser APIs (Geolocation + DeviceOrientation) and Maps
// deep-links. Rich in-app venue listings/ratings arrive later via a chosen data source.

import { useEffect, useState } from "react";

interface Coords {
  lat: number;
  lng: number;
}

// Categories we can send someone to find, centered on their real location.
const CATEGORIES = [
  { label: "Cocktail bars", q: "cocktail bar" },
  { label: "Bars & pubs", q: "bar pub" },
  { label: "Bottle shops", q: "liquor store bottle shop" },
  { label: "Clubs", q: "night club" },
  { label: "Cafés", q: "coffee cafe" },
  { label: "Wine bars", q: "wine bar" },
];

// Maps search, biased to the user's coordinates when we have them (free deep-link that
// opens Google Maps / Apple Maps on the device).
function nearHref(q: string, c: Coords | null): string {
  if (c) return `https://www.google.com/maps/search/${encodeURIComponent(q)}/@${c.lat},${c.lng},15z`;
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
}

// iOS 13+ gates DeviceOrientation behind a permission call that must run on a tap.
interface OrientationPermissionAPI {
  requestPermission?: () => Promise<"granted" | "denied">;
}

export function DiscoverLive() {
  const [coords, setCoords] = useState<Coords | null>(null);
  const [geo, setGeo] = useState<"idle" | "loading" | "denied" | "ok">("idle");
  const [heading, setHeading] = useState<number | null>(null);

  // Live heading from the device magnetometer (where available + permitted).
  useEffect(() => {
    function onOrient(e: DeviceOrientationEvent) {
      const withWebkit = e as DeviceOrientationEvent & { webkitCompassHeading?: number };
      if (typeof withWebkit.webkitCompassHeading === "number") {
        setHeading(withWebkit.webkitCompassHeading); // iOS: true heading
      } else if (e.alpha != null) {
        setHeading((360 - e.alpha) % 360); // others: derive from alpha
      }
    }
    window.addEventListener("deviceorientation", onOrient, true);
    return () => window.removeEventListener("deviceorientation", onOrient, true);
  }, []);

  async function enable() {
    // Ask for orientation permission on this tap (needed on iOS; harmless elsewhere).
    const DOE = (typeof window !== "undefined" ? window.DeviceOrientationEvent : undefined) as
      | (typeof DeviceOrientationEvent & OrientationPermissionAPI)
      | undefined;
    if (DOE?.requestPermission) {
      try {
        await DOE.requestPermission();
      } catch {
        /* denied — compass just stays static */
      }
    }
    // Get location for the "near me" links.
    if (!("geolocation" in navigator)) {
      setGeo("denied");
      return;
    }
    setGeo("loading");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude });
        setGeo("ok");
      },
      () => setGeo("denied"),
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 60_000 },
    );
  }

  const hasHeading = heading != null;

  return (
    <section className="glass flex flex-col items-center rounded-tile py-8">
      {/* Compass — rotates to real north as you turn the device (when sensors allow). */}
      <div className="glass relative flex h-36 w-36 items-center justify-center rounded-full">
        <div
          className="absolute inset-0 transition-transform duration-150 ease-out"
          style={{ transform: hasHeading ? `rotate(${-heading!}deg)` : undefined }}
        >
          <span className="label absolute left-1/2 top-2 -translate-x-1/2 text-accent">N</span>
          <span className="label absolute bottom-2 left-1/2 -translate-x-1/2">S</span>
          <span className="label absolute left-2.5 top-1/2 -translate-y-1/2">W</span>
          <span className="label absolute right-2.5 top-1/2 -translate-y-1/2">E</span>
        </div>
        {/* fixed needle = the direction the device is facing */}
        <svg width="14" height="104" viewBox="0 0 14 104" aria-hidden>
          <polygon points="7,4 12,54 7,46 2,54" fill="var(--accent)" />
          <polygon points="7,100 12,50 7,58 2,50" fill="var(--line-strong)" />
        </svg>
        <span className="absolute h-2 w-2 rounded-full bg-ink" />
      </div>
      <p className="label mt-5">{hasHeading ? "facing" : "compass"}</p>
      <p className="tnum font-display text-2xl">{hasHeading ? `${Math.round(heading!)}°` : "—"}</p>

      {/* Near-me discovery — opens the user's maps app, no API key needed. */}
      {geo !== "ok" ? (
        <button
          onClick={enable}
          className="glass glass-press mt-5 rounded-ctl px-5 py-2.5 text-sm text-ink transition-colors hover:text-accent"
        >
          {geo === "loading" ? "Locating…" : "Find places near me"}
        </button>
      ) : (
        <p className="label mt-5 text-faint">near you</p>
      )}
      {geo === "denied" && (
        <p className="mt-2 max-w-xs text-center text-xs text-faint">
          Location is off — the links below still open your maps app; allow location for closer results.
        </p>
      )}

      <div className="mt-5 flex w-full flex-wrap justify-center gap-2 px-5">
        {CATEGORIES.map((c) => (
          <a
            key={c.q}
            href={nearHref(c.q, coords)}
            target="_blank"
            rel="noopener noreferrer"
            className="glass glass-press rounded-ctl px-3.5 py-2 text-sm text-muted transition-colors hover:text-ink"
          >
            {c.label}
          </a>
        ))}
      </div>
    </section>
  );
}
