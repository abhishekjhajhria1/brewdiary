import { describe, it, expect } from "vitest";
import { formatMoney, currencyForCountry, currencySymbol, DEFAULT_CURRENCY } from "../src/lib/money";

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
