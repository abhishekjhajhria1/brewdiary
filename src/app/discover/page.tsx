// Discover — find a place, and see which bars are actually on brewdiary.
//
// Everything here is key-free and REAL. It used to ship four INVENTED venues with
// invented star ratings and a fake "sponsored" tag — placeholder copy that had gone
// live. Fabricated listings mislead, and a "sponsored" label implies paid alcohol
// promotion we do not have and would not take. They're gone.
//
// What a listing may say is a legal line, not a taste one: a bar's NAME and CITY is
// a directory entry (Maps does it). Its OFFER is alcohol advertising — illegal in
// India, banned outright in Thailand/Norway/Lithuania. So we never show a perk here.
// See VenuesNearby.tsx and 027_discover_venues.sql.
import Link from "next/link";
import { Trends } from "@/components/discover/Trends";
import { DiscoverLive } from "@/components/discover/DiscoverLive";
import { VenuesNearby } from "@/components/discover/VenuesNearby";

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

      {/* Real, verified bars on brewdiary — the bar, never its offer. */}
      <VenuesNearby />

      {/* live, key-free data: anonymous taste trends across consenting users */}
      <Trends />

      <p className="mt-8 text-xs leading-relaxed text-faint">
        Nothing here is paid for, and no bar can pay to appear. Location is opt-in and never leaves your
        device — the compass and &ldquo;near me&rdquo; search hand your maps app a query, nothing more.
      </p>
    </>
  );
}
