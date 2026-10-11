// Scanning — the twin of packages/brewdiary_core/test/links_test.dart (same cases).
import { describe, expect, it } from "vitest";
import { classifyScan, guestCardQr, guestCodeFromScan, packId, parseShopList, readyUrl, shopListQr, unpackId } from "@/lib/scanCodes";

const a = "3f2b8c1e-9d4a-4e6b-8f00-1a2b3c4d5e6f";
const b = "00000000-0000-4000-8000-000000000001";

describe("a scan is read for what it is", () => {
  it("our links: a table, a menu, the ready board", () => {
    expect(classifyScan("https://bwdy.site/t/ab12cd34")).toEqual({ kind: "table", value: "ab12cd34" });
    expect(classifyScan("https://www.bwdy.site/m/the-amber-room")).toEqual({ kind: "menu", value: "the-amber-room" });
    expect(classifyScan("https://bwdy.site/ready/ab12cd34")).toEqual({ kind: "ready", value: "ab12cd34" });
    expect(readyUrl("ab12cd34")).toBe("https://bwdy.site/ready/ab12cd34");
  });

  it("a look-alike host, another scheme, or a stale code is nothing", () => {
    expect(classifyScan("https://bwdy.site.evil.com/t/ab12cd34").kind).toBe("unknown");
    expect(classifyScan("ftp://bwdy.site/t/ab12cd34").kind).toBe("unknown");
    expect(classifyScan("https://bwdy.site/t/short").kind).toBe("unknown");
    expect(classifyScan("hello").kind).toBe("unknown");
  });

  it("a guest card: the 6 letters, scanned or typed", () => {
    expect(guestCardQr("k7m2pq")).toBe("bwdy:g:K7M2PQ");
    expect(classifyScan("bwdy:g:K7M2PQ")).toEqual({ kind: "guestCard", value: "K7M2PQ" });
    expect(guestCodeFromScan(" k7m2pq ")).toBe("K7M2PQ");
    expect(guestCodeFromScan("bwdy:g:K7M2P0")).toBeNull();
    expect(classifyScan("bwdy:g:nope").kind).toBe("unknown");
  });
});

describe("a shopping list", () => {
  it("ids pack to 22 characters and back", () => {
    expect(packId(a)).toHaveLength(22);
    expect(unpackId(packId(a))).toBe(a);
    expect(unpackId(packId(b))).toBe(b);
    expect(unpackId("short")).toBeNull();
  });

  it("round trip: the shop and its lines; the same product twice adds up", () => {
    const qr = shopListQr("Cellar-Door", [
      { productId: a, qty: 2 },
      { productId: b, qty: 1 },
      { productId: a, qty: 1 },
    ]);
    expect(qr.startsWith("bwdy:l:cellar-door:")).toBe(true);
    expect(parseShopList(qr)).toEqual({ slug: "cellar-door", lines: [{ productId: a, qty: 3 }, { productId: b, qty: 1 }] });
    expect(classifyScan(qr).kind).toBe("shopList");
  });

  it("quantities stay 1–99; a broken list is nothing", () => {
    expect(parseShopList(shopListQr("shop", [{ productId: a, qty: 250 }]))!.lines[0].qty).toBe(99);
    expect(parseShopList(`bwdy:l:shop:${packId(a)}.0`)).toBeNull();
    expect(parseShopList("bwdy:l:shop:")).toBeNull();
    expect(parseShopList(`bwdy:l:Bad Slug:${packId(a)}.1`)).toBeNull();
    expect(parseShopList("bwdy:l:shop:zzz.1")).toBeNull();
  });

  it("packs the same as the apps (a list made on the web scans at the till)", () => {
    expect(packId(a)).toBe("PyuMHp1KTmuPABorPE1ebw");
  });
});
