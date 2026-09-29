// Ninkasi for hosts: the briefing rules (src/lib/hostAdvisor.ts). The Dart twin
// (mobile-bar/lib/logic/host_brief.dart) is tested on the same cases.
import { describe, expect, it } from "vitest";
import { HOST_SYSTEM_PROMPT, coerceHostBrief, hostBriefing, hostFallbackAnswer, summarizeHostBrief } from "@/lib/hostAdvisor";

const brief = coerceHostBrief({
  venueName: "The Amber Room",
  kind: "bar",
  role: "server",
  sellsAlcohol: true,
  counter: false,
  today: "2026-10-01",
  roomOpen: true,
  guestsIn: 6,
  quietTonight: true,
  soldOut: ["Negroni"],
  alcoholFree: ["Kokum Cooler"],
  menuItems: 5,
  perks: [{ reward: "A coffee on us", at: "3 visits" }],
  signals: [
    { kind: "holiday", title: "Dry day: Gandhi Jayanti", startsOn: "2026-10-02", where: "" },
    { kind: "event", title: "Dussehra fair", startsOn: "2026-10-03", endsOn: "2026-10-05", where: "~5 km east" },
    { kind: "price", title: "A craft pint nearby costs ₹350–450", where: "" },
  ],
  area: ["Busiest: your own neighbourhood — 45+ people went out there."],
})!;

describe("Ninkasi for hosts", () => {
  it("briefs the shift, most urgent first", () => {
    expect(hostBriefing(brief)).toEqual([
      "Tomorrow is a dry day (Dry day: Gandhi Jayanti) — let regulars know tonight.",
      "Tonight's room is open, 6 guests in.",
      "It's a quiet night: a visit counts double toward the card. Worth a word to regulars — it's a visit, not a drink, that counts.",
      "86'd: Negroni. Say so before they order.",
      "Alcohol-free tonight: Kokum Cooler. Offer one with every recommendation.",
      "Around you: Dussehra fair (on Saturday, ~5 km east).",
      "Busiest: your own neighbourhood — 45+ people went out there.",
      "Water is free and on every table. If someone's had enough, stop serving alcohol, offer water and food, and get the manager.",
    ]);
  });

  it("on the dry day itself, the law comes first", () => {
    expect(hostBriefing({ ...brief, today: "2026-10-02" })[0]).toBe(
      "Today is a dry day (Dry day: Gandhi Jayanti): no alcohol may be sold. Lead with the alcohol-free list.",
    );
  });

  it("a counter that sells no alcohol gets a till line and nothing about drinking", () => {
    const shop = { ...brief, kind: "sweet_shop", sellsAlcohol: false, counter: true, signals: [], area: [], quietTonight: false };
    const lines = hostBriefing(shop);
    expect(lines[0]).toBe("The till is ready — punch cards once a day per guest.");
    expect(lines.join(" ")).not.toMatch(/alcohol|water is free/i);
  });

  it("answers the hard question the same way every time", () => {
    expect(hostFallbackAnswer(brief, "Someone's had enough — what do I do?")).toMatch(/^Stop serving them alcohol/);
    expect(hostFallbackAnswer(brief, "How do I explain the loyalty card?")).toContain("never how much anyone drinks");
  });

  it("trusts nothing from the wire", () => {
    expect(coerceHostBrief({ today: "yesterday" })).toBeNull();
    const b = coerceHostBrief({ today: "2026-10-01", role: "admin", soldOut: Array(50).fill("x"), guestsIn: -3 })!;
    expect(b.role).toBe("server");
    expect(b.soldOut).toHaveLength(20);
    expect(b.guestsIn).toBeNull();
  });

  it("the prompt holds the lines that must never break", () => {
    expect(HOST_SYSTEM_PROMPT).toMatch(/Never suggest selling more alcohol/);
    expect(HOST_SYSTEM_PROMPT).toMatch(/never guess anyone's age, gender, religion/);
    expect(HOST_SYSTEM_PROMPT).toMatch(/always offer an alcohol-free option/);
    expect(summarizeHostBrief(brief)).toContain("Talking to a server");
  });

  it("nothing in a briefing rewards drinking more", () => {
    for (const l of hostBriefing(brief)) expect(l.toLowerCase()).not.toMatch(/another round|upsell|happy hour|drink more/);
  });
});
