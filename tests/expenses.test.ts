import { describe, it, expect } from "vitest";
import { computeBalances, type Expense, type Settlement } from "@/lib/expenses";

const ME = "me";
function expense(payerId: string, shares: [string, number][], amount = 0): Expense {
  return {
    id: `x${Math.random()}`,
    payerId,
    description: "tab",
    amount: amount || shares.reduce((n, [, a]) => n + a, 0),
    createdAt: "2026-07-09T20:00:00Z",
    shares: shares.map(([userId, a]) => ({ userId, amount: a })),
  };
}
function settlement(fromId: string, toId: string, amount: number): Settlement {
  return { id: `s${Math.random()}`, fromId, toId, amount, createdAt: "2026-07-09T21:00:00Z" };
}

describe("computeBalances", () => {
  it("positive means they owe me when I paid", () => {
    // I paid 100, split me/A/B = 40/30/30
    const bal = computeBalances([expense(ME, [[ME, 40], ["A", 30], ["B", 30]])], [], ME);
    expect(bal.get("A")).toBe(30);
    expect(bal.get("B")).toBe(30);
    expect(bal.has(ME)).toBe(false); // I never owe myself
  });

  it("negative means I owe the payer", () => {
    // A paid 100, split A/me = 50/50
    const bal = computeBalances([expense("A", [["A", 50], [ME, 50]])], [], ME);
    expect(bal.get("A")).toBe(-50);
  });

  it("nets opposite expenses between the same pair", () => {
    const bal = computeBalances(
      [expense(ME, [[ME, 40], ["A", 30], ["B", 30]]), expense("A", [["A", 50], [ME, 50]])],
      [],
      ME,
    );
    expect(bal.get("A")).toBe(-20); // 30 owed to me minus 50 I owe = I owe 20
    expect(bal.get("B")).toBe(30);
  });

  it("settlements reduce a balance and drop it when ~zero", () => {
    const expenses = [expense(ME, [[ME, 40], ["A", 30], ["B", 30]]), expense("A", [["A", 50], [ME, 50]])];
    // I owe A 20 → I pay A back 20 → balance clears and is dropped
    const bal = computeBalances(expenses, [settlement(ME, "A", 20)], ME);
    expect(bal.has("A")).toBe(false);
    expect(bal.get("B")).toBe(30);
  });

  it("a payer's own share never creates a debt", () => {
    const bal = computeBalances([expense(ME, [[ME, 100]])], [], ME);
    expect(bal.size).toBe(0);
  });
});
