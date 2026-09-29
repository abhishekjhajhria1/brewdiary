// Outside signals: places and happenings in, people out (src/lib/signals.ts).
import { describe, expect, it } from "vitest";
import { cleanBatch, cleanSignal, redact } from "@/lib/signals";
import { encodeGeohash } from "@/lib/geohash";

const NOW = new Date("2026-09-29T12:00:00Z");
const base = { kind: "event", title: "Dussehra fair at the grounds", geohash: "tdr1v9", source: "city-events", starts_on: "2026-10-02" };
const clean = (r: object) => cleanSignal(r, encodeGeohash, NOW);

describe("outside signals", () => {
  it("keeps a clean public event", () => {
    const c = clean(base);
    expect(c.ok).toBe(true);
    if (!c.ok) return;
    expect(c.row.area).toBe("tdr1");
    expect(c.row.cell).toBe("tdr1v9");
    expect(c.row.expires_at).toBe("2026-10-03T00:00:00.000Z");
    expect(c.row.dedupe_key).toBe("city-events:event:tdr1:dussehra fair at the grounds:2026-10-02");
  });

  it("takes contact details out of text, and keeps dates", () => {
    expect(redact("Call +91 98450 12345 or mail ravi@example.com, see @ravi_k on 2026-10-02")).toBe(
      "Call [removed] or mail [removed], see [removed] on 2026-10-02",
    );
    expect(redact("Tickets at https://tix.example.com/e/123?ref=abc today")).toBe("Tickets at today");
  });

  it("refuses records ABOUT a person", () => {
    for (const kind of ["review", "person", "profile", "post", "comment"]) {
      expect(clean({ ...base, kind })).toEqual({ ok: false, reason: "about a person, not a place" });
    }
  });

  it("drops fact keys that name a person, keeps the numbers about a place", () => {
    const c = clean({ ...base, kind: "venue", facts: { rating: 4.4, review_count: 812, owner_name: "Ravi", reviewer: "x", average_price: 450, nested: { a: 1 } } });
    expect(c.ok && c.row.facts).toEqual({ rating: 4.4, review_count: 812, average_price: 450 });
  });

  it("turns coordinates into a ~1 km cell and never keeps them", () => {
    const c = clean({ ...base, geohash: undefined, lat: 12.9716, lon: 77.5946 });
    expect(c.ok && c.row.cell).toBe("tdr1v9");
    expect(JSON.stringify(c)).not.toContain("12.97");
  });

  it("keeps only an https link, without its query string", () => {
    expect(clean({ ...base, url: "https://events.example.com/e/1?utm=x&uid=42#top" }).ok && clean({ ...base, url: "https://events.example.com/e/1?utm=x&uid=42#top" })).toMatchObject({
      row: { source_url: "https://events.example.com/e/1" },
    });
    const plain = clean({ ...base, url: "http://events.example.com/e/1" });
    expect(plain.ok && plain.row.source_url).toBeNull();
  });

  it("needs a place, a title, a source and a known kind", () => {
    expect(clean({ ...base, geohash: "tdra" }).ok).toBe(false);
    expect(clean({ ...base, title: "hi" }).ok).toBe(false);
    expect(clean({ ...base, title: "ravi@example.com" }).ok).toBe(false);
    expect(clean({ ...base, source: "" }).ok).toBe(false);
    expect(clean({ ...base, kind: "rumour" }).ok).toBe(false);
    expect(clean({ ...base, kind: "festival" }).ok).toBe(true);
  });

  it("expires: after the event, or by how long a kind of fact stays true", () => {
    expect(clean({ ...base, starts_on: "2026-09-01" })).toEqual({ ok: false, reason: "already over" });
    const price = clean({ ...base, kind: "price", starts_on: undefined });
    expect(price.ok && price.row.expires_at).toBe("2026-12-28T12:00:00.000Z");
    expect(clean({ ...base, starts_on: "2099-01-01" })).toEqual({ ok: false, reason: "a date more than 3 years ahead" });
    const news = clean({ ...base, kind: "news", starts_on: undefined });
    expect(news.ok && news.row.expires_at).toBe("2026-10-02T12:00:00.000Z");
  });

  it("a batch keeps the last of duplicates and reports every refusal", () => {
    const b = cleanBatch([base, { ...base, detail: "updated" }, { ...base, kind: "review" }, "junk"], encodeGeohash, NOW);
    expect(b.rows).toHaveLength(1);
    expect(b.rows[0].detail).toBe("updated");
    expect(b.refused.map((r) => r.index)).toEqual([2, 3]);
  });
});
