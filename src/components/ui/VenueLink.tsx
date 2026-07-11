// A venue name that opens the user's maps app for directions. Used wherever an
// entry's place is shown (diary shelf, feeds, circles). stopPropagation so tapping
// it inside a clickable card doesn't also trigger the card. Maps deep-link is a
// plain search URL — no API key, opens Google/Apple Maps on the device.
"use client";

export function VenueLink({ venue, className }: { venue: string; className?: string }) {
  return (
    <a
      href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(venue)}`}
      target="_blank"
      rel="noopener noreferrer"
      onClick={(e) => e.stopPropagation()}
      title={`Open ${venue} in Maps`}
      className={className ?? "underline decoration-transparent underline-offset-2 transition-colors hover:decoration-inherit"}
    >
      {venue}
    </a>
  );
}
