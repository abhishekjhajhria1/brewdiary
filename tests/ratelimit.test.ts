import { describe, it, expect } from "vitest";
import { rateLimit, clientKey } from "@/lib/ratelimit";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe("rateLimit", () => {
  it("allows up to the limit, then blocks", () => {
    const key = `t-${Math.random()}`;
    expect(rateLimit(key, 3, 60_000).ok).toBe(true);
    expect(rateLimit(key, 3, 60_000).ok).toBe(true);
    const third = rateLimit(key, 3, 60_000);
    expect(third.ok).toBe(true);
    expect(third.remaining).toBe(0);
    const fourth = rateLimit(key, 3, 60_000);
    expect(fourth.ok).toBe(false);
    expect(fourth.retryAfter).toBeGreaterThan(0);
  });

  it("counts each client key separately", () => {
    const a = `a-${Math.random()}`;
    const b = `b-${Math.random()}`;
    rateLimit(a, 1, 60_000);
    expect(rateLimit(a, 1, 60_000).ok).toBe(false); // a exhausted
    expect(rateLimit(b, 1, 60_000).ok).toBe(true); // b independent
  });

  it("resets after the window passes", async () => {
    const key = `w-${Math.random()}`;
    expect(rateLimit(key, 1, 60).ok).toBe(true);
    expect(rateLimit(key, 1, 60).ok).toBe(false);
    await sleep(90);
    expect(rateLimit(key, 1, 60).ok).toBe(true); // window rolled over
  });
});

describe("clientKey", () => {
  it("takes the first x-forwarded-for ip", () => {
    const req = new Request("http://x", { headers: { "x-forwarded-for": "1.2.3.4, 5.6.7.8" } });
    expect(clientKey(req)).toBe("1.2.3.4");
  });

  it("falls back to a shared bucket when no ip header", () => {
    expect(clientKey(new Request("http://x"))).toBe("anon");
  });
});
