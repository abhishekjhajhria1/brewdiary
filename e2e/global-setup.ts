// Warm the dev server before any test runs.
//
// `next dev` compiles a route on its first request. If the browser starts pulling chunks
// while that compile is still in flight it can receive a partial file, which fails to parse
// ("Invalid or unexpected token"), and the page then NEVER hydrates — every click handler is
// dead for the life of that page. Tests fail on an empty, inert app and look exactly like
// real product bugs; that cost a long detour once already.
//
// A production build has no such window. This is purely an artefact of testing against dev,
// so we pay the compile up front instead of racing it.
const ROUTES = ["/", "/you", "/moderation"];

export default async function globalSetup() {
  const base = "http://localhost:3000";
  for (const route of ROUTES) {
    // Twice: the first request triggers the compile, the second waits for a warm one.
    for (let i = 0; i < 2; i++) {
      try {
        await fetch(base + route);
      } catch {
        /* server not up yet — Playwright's webServer wait handles that */
      }
    }
  }
}
