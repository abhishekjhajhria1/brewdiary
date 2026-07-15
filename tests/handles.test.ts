import { describe, it, expect } from "vitest";
import { coolHandle, slugName, reroll, handleBase, HANDLE_TRIES } from "../src/lib/handles";

describe("slugName", () => {
  it("lowercases and strips everything but letters and digits", () => {
    expect(slugName("Sekhi Gill!")).toBe("sekhigill");
    expect(slugName("anita.roy_92")).toBe("anitaroy92");
  });
  it("caps length so name_word stays typeable", () => {
    expect(slugName("a".repeat(40)).length).toBe(14);
  });
  it("falls back to 'guest' for an empty or symbol-only seed", () => {
    expect(slugName("")).toBe("guest");
    expect(slugName("!!!")).toBe("guest");
    expect(slugName("你好")).toBe("guest"); // non-latin → nothing survives the slug
  });
});

describe("coolHandle", () => {
  it("is name_word on the first try — no serial-number tail", () => {
    const h = coolHandle("sekhi", 0);
    expect(h).toMatch(/^sekhi_[a-z]+$/);
  });

  it("never emits the old random-gibberish shape on a clean allocation", () => {
    // the whole point: sekhi_geeas2 is gone
    for (let i = 0; i < 200; i++) {
      expect(coolHandle("sekhi", 0)).not.toMatch(/_[a-z0-9]*\d[a-z0-9]*$/);
    }
  });

  it("stays clean for the first couple of attempts, then adds a TRAILING number", () => {
    // attempts 0–1: pure word (the common case). 2+: a number, widening each attempt.
    expect(coolHandle("sekhi", 0)).toMatch(/^sekhi_[a-z]+$/);
    expect(coolHandle("sekhi", 1)).toMatch(/^sekhi_[a-z]+$/);
    expect(coolHandle("sekhi", 2)).toMatch(/^sekhi_[a-z]+\d{2}$/);
    expect(coolHandle("sekhi", 3)).toMatch(/^sekhi_[a-z]+\d{3}$/);
    expect(coolHandle("sekhi", 6)).toMatch(/^sekhi_[a-z]+\d{6}$/);
  });

  it("the number is never a lonely leading zero (e.g. no ember03)", () => {
    for (let i = 0; i < 200; i++) {
      const n = coolHandle("sekhi", 2).match(/\d+$/)![0];
      expect(Number(n)).toBeGreaterThanOrEqual(10); // 2 digits means 10..99, never 0x
    }
  });

  it("never auto-generates the 1488 hate code in a numeric tail", () => {
    // draw a lot of 4-digit tails (where 1488 could appear) and confirm it never does
    for (let i = 0; i < 5000; i++) {
      expect(coolHandle("sekhi", 4)).not.toContain("1488");
    }
  });

  it("NEVER auto-assigns a brand at sign-up (brands are reroll-only)", () => {
    const brands = ["ferrari", "bacardi", "gucci", "tesla", "absolut", "rolex"];
    for (let i = 0; i < 6000; i++) {
      const word = coolHandle("sekhi", 0).split("_")[1];
      expect(brands).not.toContain(word);
    }
  });

  it("scales: a name shared by many still resolves within HANDLE_TRIES", () => {
    // Simulate a hugely popular name — every handle it has already used is taken.
    // The generator must produce a fresh one before the loop gives up.
    const taken = new Set<string>();
    for (let user = 0; user < 5000; user++) {
      let h = "";
      for (let a = 0; a < HANDLE_TRIES; a++) {
        h = coolHandle("raj", a);
        if (!taken.has(h)) break;
      }
      expect(taken.has(h)).toBe(false); // found a free one every time
      taken.add(h);
    }
  });

  it("stays a valid, lowercase, url-safe handle at every attempt", () => {
    for (let a = 0; a < HANDLE_TRIES; a++) {
      const h = coolHandle("Anita Roy", a);
      expect(h).toMatch(/^[a-z0-9]+_[a-z0-9]+$/);
      expect(h).toBe(h.toLowerCase());
    }
  });

  it("draws a real spread of words, not the same one every time", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 300; i++) seen.add(coolHandle("x", 0).split("_")[1]);
    expect(seen.size).toBeGreaterThan(20);
  });
});

describe("handleBase", () => {
  it("takes the name half of an existing handle", () => {
    expect(handleBase("sekhi_geeas2")).toBe("sekhi");
    expect(handleBase("anita_ember")).toBe("anita");
  });
  it("survives a handle with no underscore", () => {
    expect(handleBase("solo")).toBe("solo");
  });
});

describe("reroll", () => {
  it("keeps the name half and offers a clean word on a voluntary press", () => {
    const next = reroll("sekhi_geeas2");
    expect(next).toMatch(/^sekhi_[a-z]+$/);
  });
  it("never hands back the handle you already have", () => {
    // the "try another" button must visibly change something on every press
    for (let i = 0; i < 200; i++) {
      const cur = coolHandle("sekhi", 0);
      expect(reroll(cur)).not.toBe(cur);
    }
  });
  it("escalates to a numbered handle when the name is saturated (attempt climbs)", () => {
    // what the UI does after repeated "taken": push toward numbered candidates.
    expect(reroll("raj_ember", 2)).toMatch(/^raj_[a-z]+\d{2}$/);
  });
  it("CAN surface a brand (reroll is the user-chosen path where brands live)", () => {
    const brands = new Set(["ferrari", "bacardi", "gucci", "tesla", "rolex", "corona"]);
    let sawOne = false;
    for (let i = 0; i < 4000 && !sawOne; i++) {
      if (brands.has(reroll("sekhi_ember").split("_")[1])) sawOne = true;
    }
    expect(sawOne).toBe(true);
  });
});
