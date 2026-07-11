// Discover — the local-discovery / promotion surface. The FUNCTIONAL, key-free parts work today
// (DiscoverLive: a real device compass + geolocation "near me" that opens the maps app). The
// curated in-app listings below are a labelled preview — live ratings/distance arrive when we
// connect a venue-data source (deferred on budget; the "Directions" links already work).
// Sponsored places are labelled; location & data-sharing are opt-in; 21+ — built in from day one.
import Link from "next/link";
import { Trends } from "@/components/discover/Trends";
import { DiscoverLive } from "@/components/discover/DiscoverLive";

interface Venue {
  name: string;
  kind: string;
  rating: number;
  distance: string;
  sponsored?: boolean;
  query: string; // maps search query
}

// Preview listings — a labelled sample of the intended rich UX (incl. sponsored labelling).
// Live nearby results are the "Find places near me" buttons above; these get real data later.
const VENUES: Venue[] = [
  { name: "The Alembic", kind: "Cocktail bar", rating: 4.7, distance: "0.4 km", query: "The Alembic cocktail bar" },
  { name: "Cask & Co.", kind: "Bottle shop", rating: 4.6, distance: "0.9 km", sponsored: true, query: "Cask and Co bottle shop" },
  { name: "Lowlight", kind: "Wine bar", rating: 4.5, distance: "1.2 km", query: "Lowlight wine bar" },
  { name: "Forge", kind: "Club", rating: 4.4, distance: "1.8 km", query: "Forge club" },
];

function mapsHref(query: string) {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}

export default function Page() {
  return (
    <>
      <header className="mb-6">
        <h1 className="display text-ink">Discover</h1>
        <p className="mt-2 text-[15px] text-muted">Point the compass, find a place near you, ask Ninkasi.</p>
      </header>

      {/* Ask Ninkasi — the AI bartender (personalized from your diary). */}
      <Link
        href="/bartender"
        className="glass glass-press mb-6 flex items-center justify-between gap-3 rounded-tile px-5 py-4"
      >
        <div>
          <p className="font-display text-xl text-ink">Ask Ninkasi</p>
          <p className="text-sm text-muted">What should I pour tonight? — she knows what you&apos;ve been logging.</p>
        </div>
        <span className="text-accent" aria-hidden>
          →
        </span>
      </Link>

      {/* Functional, key-free: a real compass + geolocation "near me" (opens the maps app). */}
      <DiscoverLive />

      {/* A preview of curated listings. Live ratings/distance arrive with our venue data
          source; the "Directions" links already open the user's maps app today. */}
      <p className="label mt-9 mb-3 text-faint">A taste — curated listings coming</p>
      <ul className="space-y-3">
        {VENUES.map((v) => (
          <li key={v.name} className="glass flex items-center justify-between gap-3 rounded-tile px-4 py-3.5">
            <div className="min-w-0">
              <p className="flex items-center gap-2 text-[15px] text-ink">
                {v.name}
                {v.sponsored && <span className="label text-faint!">sponsored</span>}
              </p>
              <p className="tnum text-xs text-muted">
                {v.kind} · ★ {v.rating.toFixed(1)} · {v.distance}
              </p>
            </div>
            <a
              href={mapsHref(v.query)}
              target="_blank"
              rel="noopener noreferrer"
              className="glass glass-press shrink-0 rounded-ctl px-3 py-1.5 text-xs uppercase tracking-[0.12em] text-muted hover:text-ink"
            >
              Directions
            </a>
          </li>
        ))}
      </ul>

      {/* live, key-free data: anonymous taste trends across consenting users */}
      <Trends />

      <p className="mt-8 text-xs leading-relaxed text-faint">
        Sponsored places are labelled. Location &amp; data-sharing are opt-in. 21+. The compass and
        &ldquo;near me&rdquo; search work today via your maps app; in-app ratings &amp; distance land with our
        venue-data source.
      </p>
    </>
  );
}
