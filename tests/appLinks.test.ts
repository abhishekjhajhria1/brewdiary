// App links: the right app for the right host, and nothing until the keys are set.
import { describe, expect, it } from "vitest";
import { appleAssociation, assetLinks } from "@/lib/appLinks";

const FP = Array(32).fill("AB").join(":");

describe("app links", () => {
  it("say nothing until a fingerprint / team id is configured", () => {
    expect(assetLinks("bwdy.site", {})).toBeNull();
    expect(assetLinks("bwdy.site", { ANDROID_CERT_SHA256_GUEST: "not-a-fingerprint" })).toBeNull();
    expect(appleAssociation("bwdy.site", { APPLE_TEAM_ID: "short" })).toBeNull();
  });

  it("bwdy.site belongs to the guest app, bar.bwdy.site to the venue app", () => {
    const env = { ANDROID_CERT_SHA256_GUEST: FP.toLowerCase(), ANDROID_CERT_SHA256_BAR: FP, APPLE_TEAM_ID: "abcde12345" };
    expect(assetLinks("bwdy.site", env)).toEqual([
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: { namespace: "android_app", package_name: "site.bwdy.brewdiary", sha256_cert_fingerprints: [FP] },
      },
    ]);
    expect(JSON.stringify(assetLinks("bar.bwdy.site", env))).toContain("site.bwdy.bar");
    expect(appleAssociation("bwdy.site", env)).toEqual({
      applinks: { details: [{ appIDs: ["ABCDE12345.site.bwdy.brewdiary"], components: [{ "/": "/p/*" }, { "/": "/u/*" }, { "/": "/party/*" }, { "/": "/m/*" }] }] },
    });
    expect(JSON.stringify(appleAssociation("bar.bwdy.site", env))).toContain("ABCDE12345.site.bwdy.bar");
  });
});
