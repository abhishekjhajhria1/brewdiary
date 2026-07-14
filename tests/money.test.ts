import { describe, it, expect } from "vitest";
import { formatMoney, currencyForCountry, currencySymbol, spendBand, DEFAULT_CURRENCY } from "../src/lib/money";

// "₹" was hardcoded in eight files. That's fine until a London bar sets a perk and
// the app tells its guests to spend "₹3000". These tests exist so that never comes back.

describe("currencyForCountry", () => {
  it("maps each market we operate in", () => {
    expect(currencyForCountry("IN")).toBe("INR");
    expect(currencyForCountry("GB")).toBe("GBP");
    expect(currencyForCountry("US")).toBe("USD");
    expect(currencyForCountry("IE")).toBe("EUR");
    expect(currencyForCountry("FR")).toBe("EUR");
    expect(currencyForCountry("JP")).toBe("JPY");
    expect(currencyForCountry("TH")).toBe("THB");
    expect(currencyForCountry("AU")).toBe("AUD");
  });

  it("is case-insensitive and falls back to the home currency", () => {
    expect(currencyForCountry("gb")).toBe("GBP");
    expect(currencyForCountry("ZZ")).toBe(DEFAULT_CURRENCY);
    expect(currencyForCountry(null)).toBe(DEFAULT_CURRENCY);
  });
});

describe("formatMoney", () => {
  it("uses the right symbol per currency — never a hardcoded ₹", () => {
    expect(formatMoney(3000, "GBP")).toContain("£");
    expect(formatMoney(3000, "USD")).toContain("$");
    expect(formatMoney(3000, "EUR")).toContain("€");
    expect(formatMoney(3000, "INR")).toContain("₹");
    // the bug this file exists to prevent
    expect(formatMoney(3000, "GBP")).not.toContain("₹");
  });

  it("groups the Indian way for rupees (lakhs), the Western way elsewhere", () => {
    expect(formatMoney(123456, "INR")).toBe("₹1,23,456");
    expect(formatMoney(123456, "USD")).toBe("$123,456");
  });

  it("has no minor units where the currency has none", () => {
    // there is no such thing as 50 sen
    expect(formatMoney(3000, "JPY")).not.toContain(".");
  });

  it("shows paise/cents only when they exist", () => {
    expect(formatMoney(100, "INR")).toBe("₹100");
    expect(formatMoney(100.5, "INR")).toBe("₹100.50");
    expect(formatMoney(100.5, "INR", { round: true })).toBe("₹101");
  });

  it("degrades to a bare number rather than throwing on a bad code", () => {
    expect(formatMoney(42, "NOTACURRENCY")).toBe("42");
  });

  it("exposes a symbol for tight spots (an input prefix)", () => {
    expect(currencySymbol("GBP")).toBe("£");
    expect(currencySymbol("INR")).toBe("₹");
  });
});

// ── flexed tabs are BANDED, never exact ──────────────────────────────────────
// A wall screen in a room of strangers with cameras. An exact tab beside a name is
// a published financial record; it also turns the board into a spending race you win
// by buying one more drink. The band keeps the brag and kills both.
describe("spendBand", () => {
  it("never reveals the exact figure", () => {
    expect(spendBand(2340, "INR")).not.toContain("2,340");
    expect(spendBand(2340, "INR")).toBe("₹1,000+"); // bands are ×1,2,5,10,20 of ₹500
  });

  it("rounds DOWN to the band — you can't round someone up into a bigger flex", () => {
    expect(spendBand(999, "INR")).toBe("₹500+");
    expect(spendBand(1000, "INR")).toBe("₹1,000+");
    expect(spendBand(4999, "INR")).toBe("₹2,500+");
  });

  it("you cannot out-rank anyone by one more drink", () => {
    // The whole anti-spending-race property: +₹1 must never move you up a band, and
    // two people a drink apart must read identically.
    expect(spendBand(2000, "INR")).toBe(spendBand(2001, "INR"));
    expect(spendBand(2000, "INR")).toBe(spendBand(2499, "INR"));
  });

  it("bands in the venue's own money, not rupees", () => {
    expect(spendBand(140, "USD")).toBe("$125+");
    expect(spendBand(60, "GBP")).toBe("£50+");
  });

  it("a small tab is not a flex", () => {
    expect(spendBand(300, "INR")).toBe("under ₹500");
    expect(spendBand(0, "INR")).toBe("under ₹500");
  });

  it("survives nonsense rather than throwing on a wall screen", () => {
    expect(spendBand(NaN, "INR")).toBe("under ₹500");
    expect(spendBand(1200, "ZZZ")).toMatch(/\+$/);
  });
});
