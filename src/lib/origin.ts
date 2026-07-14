// SERVER-ONLY. Same-origin check for state-changing, cookie-authenticated routes.
//
// SameSite=Lax on the session cookie already blocks a cross-site POST in modern
// browsers — this is defense-in-depth, and it holds even if a future cookie config
// loosens that. The rule: every route that CHANGES something on the strength of a
// cookie calls this first. (A GET never needs it; a token-authenticated API never
// needs it; a cookie-authenticated POST always does.)
//
// Extracted from api/auth/password so the next destructive route can't forget it —
// account deletion shipped WITHOUT this while the password route had it, which is
// exactly the drift a shared helper exists to stop.

/** True when the request's Origin matches its Host (or no Origin was sent at all —
 *  same-origin fetches and non-browser clients omit it; browsers always send it on
 *  cross-site POSTs, which is the case we're guarding). */
export function sameOrigin(req: Request): boolean {
  const origin = req.headers.get("origin");
  const host = req.headers.get("host");
  if (!origin || !host) return true;

  // "Origin: null" (sandboxed iframes) and malformed values must fail, not throw.
  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}
