import { describe, it, expect } from "vitest";
import { trustLevelFrom, trustScore, beginIdentityVerification, identityVerificationAvailable } from "../src/lib/verify";

describe("trustLevelFrom", () => {
  it("a brand-new account is 'new'", () => {
    expect(trustLevelFrom({ tenureDays: 0, activeDays: 0, friends: 0 })).toBe("new");
  });

  it("a week of real use reaches 'active'", () => {
    expect(trustLevelFrom({ tenureDays: 8, activeDays: 6, friends: 1 })).toBe("active");
  });

  it("a settled month with friends is 'established'", () => {
    expect(trustLevelFrom({ tenureDays: 45, activeDays: 25, friends: 4 })).toBe("established");
  });

  it("'trusted' needs sustained use AND a strong signal (liveness or vouches)", () => {
    // sustained use alone tops out below trusted…
    const sustained = { tenureDays: 120, activeDays: 60, friends: 10 };
    expect(trustLevelFrom(sustained)).toBe("established");
    // …a live check pushes it over
    expect(trustLevelFrom({ ...sustained, presenceChecked: true })).toBe("trusted");
    // …or several vouches do
    expect(trustLevelFrom({ ...sustained, vouches: 5 })).toBe("trusted");
  });

  it("no single signal can carry a throwaway account to trusted", () => {
    expect(trustLevelFrom({ tenureDays: 100000, activeDays: 0, friends: 0 })).not.toBe("trusted");
    expect(trustLevelFrom({ tenureDays: 0, activeDays: 0, friends: 100000 })).not.toBe("trusted");
    // even a lone liveness check on an empty account isn't "trusted"
    expect(trustLevelFrom({ tenureDays: 0, activeDays: 0, friends: 0, presenceChecked: true })).not.toBe("trusted");
  });

  it("caps mean the score is bounded and monotonic-ish", () => {
    const low = trustScore({ tenureDays: 1, activeDays: 1, friends: 0 });
    const high = trustScore({ tenureDays: 120, activeDays: 60, friends: 10, presenceChecked: true, vouches: 5 });
    expect(high).toBeGreaterThan(low);
    expect(high).toBeLessThanOrEqual(53); // 10+10+10+8+15
  });
});

describe("the vouch signal", () => {
  it("is capped — a ring of friends can't stack vouches without limit", () => {
    const base = { tenureDays: 10, activeDays: 5, friends: 5 };
    const five = trustScore({ ...base, vouches: 5 });
    const fifty = trustScore({ ...base, vouches: 50 });
    expect(fifty).toBe(five); // beyond 5, extra vouches add nothing
  });

  it("can't carry a throwaway account on its own", () => {
    // maxed vouches but no tenure, no diary use, no friends
    expect(trustLevelFrom({ tenureDays: 0, activeDays: 0, friends: 0, vouches: 5 })).not.toBe("trusted");
  });

  it("is additive — more vouches never lowers the score", () => {
    const base = { tenureDays: 30, activeDays: 10, friends: 3 };
    expect(trustScore({ ...base, vouches: 3 })).toBeGreaterThan(trustScore({ ...base, vouches: 0 }));
  });
});

describe("identity verification void", () => {
  it("is not available until funded", () => {
    expect(identityVerificationAvailable).toBe(false);
  });
  it("begins as 'unavailable' with a friendly reason (never a dead button)", async () => {
    const r = await beginIdentityVerification();
    expect(r.status).toBe("unavailable");
    if (r.status === "unavailable") expect(r.reason.length).toBeGreaterThan(10);
  });
});
