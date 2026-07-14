"use client";

// Which app is this? The venue dashboard is the SAME deployment as the diary —
// middleware rewrites any `bar.*` host onto /venue and the browser's URL stays on
// the subdomain. That's the trap: `usePathname()` on bar.bwdy.site returns "/",
// NOT "/venue". So anything that hides itself "on the venue app" cannot ask the
// path — it has to ask the HOST. (This is exactly how the consumer nav bar leaked
// onto the bar dashboard in production.)
import { useEffect, useState } from "react";

/** True on bar.* — the venue dashboard, whatever the path happens to say. */
export function useIsVenueApp(): boolean {
  const [isVenue, setIsVenue] = useState(false);
  useEffect(() => {
    setIsVenue(
      window.location.host.startsWith("bar.") || window.location.pathname.startsWith("/venue"),
    );
  }, []);
  return isVenue;
}
