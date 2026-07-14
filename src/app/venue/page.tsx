// The venue/bar dashboard route — served from bar.bwdy.site (middleware rewrites
// the `bar.` subdomain onto /venue). This server component keeps the metadata;
// the interactive dashboard (auth + venues + team) lives in the client VenueApp.
// The consumer TopBar/TabBar hide on /venue (see those components).
import type { Metadata } from "next";
import { VenueApp } from "@/components/venue/VenueApp";

export const metadata: Metadata = {
  title: "brewdiary for venues",
  description: "Turn a night at your bar into a room — sparks, good vibes, and perks that bring people back.",
};

export default function VenuePage() {
  return <VenueApp />;
}
