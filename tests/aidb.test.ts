import { describe, it, expect } from "vitest";
import { pseudonymize } from "@/lib/aidb";

describe("pseudonymize", () => {
  it("is deterministic for the same user", () => {
    expect(pseudonymize("user-1")).toBe(pseudonymize("user-1"));
  });

  it("differs for different users", () => {
    expect(pseudonymize("user-1")).not.toBe(pseudonymize("user-2"));
  });

  it("never returns the raw id", () => {
    expect(pseudonymize("user-1")).not.toBe("user-1");
  });

  it("is a 64-char hex hash", () => {
    expect(pseudonymize("user-1")).toMatch(/^[0-9a-f]{64}$/);
  });
});
