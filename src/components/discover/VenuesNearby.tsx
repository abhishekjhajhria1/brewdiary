"use client";

// Bars that are actually ON brewdiary — verified, real, and listed by name.
//
// ── THE WALL ─────────────────────────────────────────────────────────────────
// A LISTING is a directory entry: Google Maps lists bars and nobody calls that
// alcohol advertising. An OFFER — "free pour at Toit tonight!" — IS alcohol
// advertising, and in India that is specifically illegal (surrogate-ad rules,
// penalties to ₹50 lakh). It's banned outright in Thailand, Norway, Lithuania,
// Türkiye and Poland too.
//
// So this shows a name, a city, and whether a room is running. It does NOT show
// the perk, the reward, a price, a drink, or a discount — and the database backs
// that up: discover_venues() never joins venue_perks. If you're ever tempted to
// add "and here's what they're offering tonight", that is the line, and crossing
// it turns a diary into an advertising platform.
//
// A venue only appears where the bar layer is lawful at all (Class A/B).
import { useEffect, useState } from "react";
import { useDiscoverVenues } from "@/lib/venues";
import { savedCountry } from "@/lib/age";

export function VenuesNearby() {
  const [country, setCountry] = useState<string | null>(null);
  useEffect(() => setCountry(savedCountry()), []);
  const { venues, loading } = useDiscoverVenues(country);

  if (loading || venues.length === 0) return null;

  return (
    <section className="mt-9">
      <p className="label mb-3 text-faint">On brewdiary</p>
      <ul className="space-y-3">
        {venues.map((v) => (
          <li key={v.slug} className="glass flex items-center justify-between gap-3 rounded-tile px-4 py-3.5">
            <div className="min-w-0">
              <p className="truncate text-[15px] text-ink">{v.name}</p>
              <p className="text-xs text-muted">
                {/* A shop, not a bar — worth saying, because you can't sit down in one.
                    Still just a directory fact: never what it sells or what it offers. */}
                {v.kind === "store" ? "Bottle shop" : v.city || "A brewdiary venue"}
                {v.kind === "store" && v.city && <> · {v.city}</>}
                {v.openTonight && <span className="text-accent"> · a room is open</span>}
              </p>
            </div>
            <a
              href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
                `${v.name} ${v.city ?? ""}`.trim(),
              )}`}
              target="_blank"
              rel="noopener noreferrer"
              className="glass glass-press shrink-0 rounded-ctl px-3 py-1.5 text-xs uppercase tracking-[0.12em] text-muted hover:text-ink"
            >
              Directions
            </a>
          </li>
        ))}
      </ul>
      <p className="mt-3 text-xs leading-relaxed text-faint">
        Verified bars using brewdiary. If one is running a room, you can join it when you get there — ask
        for the code or scan the card on the table.
      </p>
    </section>
  );
}
