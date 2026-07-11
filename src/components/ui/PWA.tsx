"use client";

import { useEffect } from "react";

/**
 * Service-worker lifecycle. Registers the SW for offline/installable behaviour in
 * PRODUCTION only. In development a caching SW serves stale HTML that points at
 * old build chunks (→ layout.css / webpack.js / page.js 404s), so we instead
 * unregister any existing SW and clear its caches. No UI.
 */
export function PWA() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    if (process.env.NODE_ENV !== "production") {
      // Dev: make sure no old SW is controlling this page, and drop its caches.
      navigator.serviceWorker.getRegistrations().then((regs) => regs.forEach((r) => r.unregister())).catch(() => {});
      if ("caches" in window) {
        caches.keys().then((keys) => keys.forEach((k) => k.startsWith("brewdiary-") && caches.delete(k))).catch(() => {});
      }
      return;
    }

    const onLoad = () => navigator.serviceWorker.register("/sw.js").catch(() => {});
    window.addEventListener("load", onLoad);
    return () => window.removeEventListener("load", onLoad);
  }, []);

  return null;
}
