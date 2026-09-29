// The table's own link (051): codes and the basket's sum.
import { describe, expect, it } from "vitest";
import { basketTotal, parseTableCode, tableUrl } from "@/lib/tableOrder";

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
