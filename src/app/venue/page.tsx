// The venue/bar dashboard route — served from bar.bwdy.site (middleware rewrites
// the `bar.` subdomain onto /venue). This server component keeps the metadata;
// the interactive dashboard (auth + venues + team) lives in the client VenueApp.
//
// The consumer chrome (TopBar/TabBar) hides itself by HOST, not by path — on
// bar.bwdy.site the rewrite is internal, so the browser's path is still "/" and a
// path check silently fails. See src/lib/host.ts.
import type { Metadata } from "next";
import { VenueApp } from "@/components/venue/VenueApp";

export const metadata: Metadata = {
  title: { absolute: "brewdiary for bars" }, // its own product name on the bar. subdomain
  description:
    "The bar's side of brewdiary: open a room for the night, let your staff thank the good ones, and set a perk that brings your regulars back. Free, no till to touch.",
};

export default function VenuePage() {
  return <VenueApp />;
}
