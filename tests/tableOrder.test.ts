// The table's own link (051): codes and the basket's sum.
import { describe, expect, it } from "vitest";
import { basketTotal, isCounterKind, orderLive, orderStep, orderWords, parseOrderStatus, parseTableCode, tableUrl } from "@/lib/tableOrder";

describe("the table link", () => {
  it("accepts an 8-character code and nothing else", () => {
    expect(parseTableCode(" AbC12345 ")).toBe("abc12345");
    expect(parseTableCode("abc1234")).toBeNull();
    expect(parseTableCode("abc12345/extra")).toBeNull();
  });

  it("makes the URL a table's QR carries", () => {
    expect(tableUrl("abc12345")).toBe("https://bwdy.site/t/abc12345");
  });

  it("adds up a basket from the menu's prices", () => {
    const prices = new Map<string, number | undefined>([
      ["a", 300],
      ["b", 90],
      ["c", undefined],
    ]);
    expect(basketTotal(new Map([["a", 2], ["b", 1], ["c", 3]]), prices)).toBe(690);
  });
});

// 059: how an order is followed — the same words and steps as the app's OrderStatus
// (test_m_app/test/order_from_phone_test.dart).
describe("an order, as you follow it (059)", () => {
  it("a pickup order: your number, the steps, the words", () => {
    const o = parseOrderStatus({
      id: "r1",
      status: "making",
      created_at: "2026-10-11T15:30:00Z",
      venue_name: "Third Wave",
      point: "Counter",
      point_kind: "pickup",
      pickup_no: 42,
      lines: [{ name: "Flat white", qty: 2, status: "preparing" }],
    });
    expect(o.pickupNo).toBe(42);
    expect(o.atPickup).toBe(true);
    expect(orderStep(o)).toBe(1);
    expect(orderWords(o)).toBe("being made");
    expect(orderLive(o)).toBe(true);
    expect(orderWords(parseOrderStatus({ id: "r1", status: "ready", point: "Counter", point_kind: "pickup" }))).toBe("ready — collect it at Counter");
    expect(orderWords(parseOrderStatus({ id: "r1", status: "ready" }))).toBe("ready — on its way to you");
    expect(orderWords(parseOrderStatus({ id: "r1", status: "declined", decline_reason: "kitchen's closed" }))).toBe("declined — kitchen's closed");
    expect(orderLive(parseOrderStatus({ id: "r1", status: "served" }))).toBe(false);
  });

  it("counters have a shelf; bars and cafés don't", () => {
    expect(["store", "sweet_shop", "bakery", "shop"].every(isCounterKind)).toBe(true);
    expect(isCounterKind("bar")).toBe(false);
    expect(isCounterKind("cafe")).toBe(false);
  });
});
