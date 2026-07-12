// Tiny in-memory rate limiter — the first, dependency-free line of defense for the
// AI route once a real (paid) key is live. It caps how often a single client can hit
// an endpoint, so a runaway loop or a bad actor can't burn the Groq budget or hammer
// the provider. Sliding window, keyed by whatever string you pass (an IP, a user id).
//
// SCOPE / LIMITS (be honest about this):
// - This lives in one server process's memory. On a single long-running server it works
//   well. On serverless/multi-instance hosting (e.g. Vercel), each instance keeps its own
//   counter and cold starts reset it — so it's a soft cap, not a hard guarantee.
// - For a hard, shared limit in production, back this with Upstash Redis / a durable KV
//   and keep the SAME function signature. This file is the seam for that swap.

interface Hit {
  count: number;
  resetAt: number; // epoch ms when the current window ends
}

const buckets = new Map<string, Hit>();

// Opportunistic cleanup so the map can't grow unbounded on a busy server.
let lastSweep = 0;
function sweep(now: number) {
  if (now - lastSweep < 60_000) return;
  lastSweep = now;
  for (const [k, v] of buckets) if (v.resetAt <= now) buckets.delete(k);
}

export interface RateResult {
  ok: boolean;
  remaining: number;
  /** seconds until the window resets (for a Retry-After header) */
  retryAfter: number;
}

/**
 * Allow up to `limit` requests per `windowMs` for a given `key`.
 * Call once per request; if `ok` is false, reject with 429.
 */
export function rateLimit(key: string, limit = 20, windowMs = 60_000): RateResult {
  const now = Date.now();
  sweep(now);
  const hit = buckets.get(key);

  if (!hit || hit.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return { ok: true, remaining: limit - 1, retryAfter: 0 };
  }

  if (hit.count >= limit) {
    return { ok: false, remaining: 0, retryAfter: Math.ceil((hit.resetAt - now) / 1000) };
  }

  hit.count += 1;
  return { ok: true, remaining: limit - hit.count, retryAfter: 0 };
}

/** Best-effort client identifier from proxy headers, falling back to a shared bucket.
 *  Prefers x-real-ip (set by the platform proxy, e.g. Vercel) over x-forwarded-for,
 *  which a direct client can spoof to rotate buckets when self-hosted without a proxy.
 *  Keys are length-capped so a hostile header can't bloat the bucket map. */
export function clientKey(req: Request): string {
  const ip = req.headers.get("x-real-ip") || req.headers.get("x-forwarded-for")?.split(",")[0].trim();
  return (ip || "anon").slice(0, 64);
}
