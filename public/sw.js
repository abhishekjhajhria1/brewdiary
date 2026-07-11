// brewdiary service worker — offline app shell, done safely.
//
// The rule that avoids stale-asset 404s: NAVIGATIONS ARE NETWORK-FIRST. We always
// fetch fresh HTML (which references the current build's chunks) and only fall back to
// cache when offline. Static assets (content-hashed, immutable) are cache-first. API
// calls and cross-origin requests (Supabase, maps) are never cached. Bump CACHE on any
// strategy change so old caches are purged on activate.
const CACHE = "brewdiary-v2";
const OFFLINE_URL = "/";

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.add(OFFLINE_URL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // Supabase/maps/etc. → straight to network
  if (url.pathname.startsWith("/api/")) return; // never cache API (incl. the AI stream)

  // Navigations → network-first so the HTML always matches the current build.
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(request).then((c) => c || caches.match(OFFLINE_URL))),
    );
    return;
  }

  // Static assets → cache-first (they're hashed/immutable), populate on miss.
  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request)
        .then((res) => {
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(request, copy)).catch(() => {});
          }
          return res;
        })
        .catch(() => Response.error());
    }),
  );
});
