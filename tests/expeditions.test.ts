import { describe, it, expect } from "vitest";
import type { Entry } from "@/lib/types";
import {
  generateQuests,
  expeditionHand,
  isQuestDone,
  trophies,
  type Quest as ExpeditionQuest,
} from "@/lib/expeditions";

// Build a valid drink Entry with sensible defaults (mirrors passport.test.ts).
let seq = 0;
function entry(p: Partial<Entry> = {}): Entry {
  seq += 1;
  return {
    id: `e${seq}`,
    date: "2026-07-09",
    createdAt: new Date(2026, 6, 9, 20, 0, 0).toISOString(),
    drink: "Latte",
    ...p,
  };
}

const DAY = "2026-07-09";

describe("expeditions — the anti-volume invariant (rule #6, made structural)", () => {
  it("repeating a drink changes nothing — volume earns no quest and no progress", () => {
    const once = expeditionHand({ entries: [entry({ drink: "Latte" })] }, { today: DAY });
    const many = expeditionHand(
      { entries: [entry({ drink: "Latte" }), entry({ drink: "Latte" }), entry({ drink: "latte" })] },
      { today: DAY },
    );
    expect(many.map((q) => q.id)).toEqual(once.map((q) => q.id));
  });

  it("no quest ever points at a family you've already explored (breadth, not repetition)", () => {
    const qs = generateQuests({ entries: [entry({ drink: "Latte" })] });
    expect(qs.some((q) => q.target === "Latte")).toBe(false);
  });

  it("no axis counts volume or spend — the palette is breadth/behaviour only", () => {
    const qs = generateQuests({ entries: [], pantry: ["coffee", "milk", "chocolate"] });
    const axes = new Set(qs.map((q) => q.axis));
    for (const forbidden of ["volume", "count", "spend", "most"]) {
      expect([...axes]).not.toContain(forbidden);
    }
  });
});

describe("expeditions — the hand self-advances (derived completion)", () => {
  it("a family quest is done once the Passport reflects that family", () => {
    const q: ExpeditionQuest = {
      id: "family:Mocha",
      title: "Try a Mocha",
      vibe: "explorer",
      effort: "chill",
      axis: "family",
      where: "any",
      target: "Mocha",
      targetType: "coffee",
    };
    expect(isQuestDone([entry({ drink: "Latte" })], q)).toBe(false);
    expect(isQuestDone([entry({ drink: "Latte" }), entry({ drink: "Mocha" })], q)).toBe(true);
  });

  it("open invitations (offmap, venue) are never 'done' — they are standing doors", () => {
    const qs = generateQuests({ entries: [] });
    const offmap = qs.find((q) => q.axis === "offmap")!;
    const venue = qs.find((q) => q.axis === "venue")!;
    expect(offmap).toBeTruthy();
    expect(venue).toBeTruthy();
    expect(isQuestDone([entry({ drink: "Negroni" })], offmap)).toBe(false);
    expect(isQuestDone([entry({ drink: "Negroni" })], venue)).toBe(false);
  });
});

describe("expeditions — the hand is fun-first, not difficulty-based", () => {
  const ctx = {
    entries: [entry({ drink: "Latte" })],
    pantry: ["coffee", "milk", "chocolate"],
    friendDrinks: [{ drink: "IPA", author: "mara" }],
  };

  it("stays mostly chill — at most one bolder card rides along", () => {
    const hand = expeditionHand(ctx, { n: 3, today: DAY });
    expect(hand.length).toBeLessThanOrEqual(3);
    expect(hand.filter((q) => q.effort !== "chill").length).toBeLessThanOrEqual(1);
  });

  it("values variety — no two cards share an axis when it can avoid it", () => {
    const hand = expeditionHand(ctx, { n: 3, today: DAY });
    const axes = new Set(hand.map((q) => q.axis));
    expect(axes.size).toBe(hand.length);
  });

  it("is deterministic within a day (stable hand), and a hand is not empty", () => {
    const a = expeditionHand(ctx, { today: DAY });
    const b = expeditionHand(ctx, { today: DAY });
    expect(a.map((q) => q.id)).toEqual(b.map((q) => q.id));
    expect(a.length).toBeGreaterThan(0);
  });
});

describe("expeditions — the vibe path shapes the flavour (Pokémon GO 'Choose Your Path')", () => {
  const ctx = { entries: [entry({ drink: "Latte" })], pantry: ["coffee", "milk", "chocolate"] };

  it("a cozy path leads with a make-at-home card when the shelf allows it", () => {
    const cozy = expeditionHand(ctx, { vibe: "cozy", n: 3, today: DAY });
    expect(cozy[0].axis).toBe("make");
  });

  it("an explorer path leads with exploration, not the cozy make card", () => {
    const explorer = expeditionHand(ctx, { vibe: "explorer", n: 3, today: DAY });
    expect(["family", "world"]).toContain(explorer[0].axis);
  });
});

describe("expeditions — trophies are collection (breadth), never volume or difficulty", () => {
  it("first light is earned by exploring once", () => {
    expect(trophies([entry({ drink: "Latte" })]).find((t) => t.id === "first-stamp")!.earned).toBe(true);
  });

  it("five of the SAME drink does not earn Wanderer — it needs five distinct families", () => {
    const fiveLattes = [1, 2, 3, 4, 5].map(() => entry({ drink: "Latte" }));
    expect(trophies(fiveLattes).find((t) => t.id === "wanderer-5")!.earned).toBe(false);

    const fiveFamilies = ["Latte", "IPA", "Negroni", "Cold Brew", "Mojito"].map((d) => entry({ drink: d }));
    expect(trophies(fiveFamilies).find((t) => t.id === "wanderer-5")!.earned).toBe(true);
  });

  it("an off-map find earns the Cartographer trophy", () => {
    const off = trophies([entry({ drink: "Grandma's secret punch" })]).find((t) => t.id === "cartographer")!;
    expect(off.earned).toBe(true);
  });
});
