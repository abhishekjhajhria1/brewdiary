// First-run demo history — realistic, contextual content (no Lorem / placeholders),
// built relative to today so the calendar, mosaic, streak and lexicon are alive on
// first open. Some days carry 2–3 logs (intensity); a couple of gaps show streak grace.
import type { Entry, DrinkType } from "./types";
import { addDays, toKey } from "./date";

interface Seed {
  offset: number; // days before today
  hour: number;
  drink: string;
  type: DrinkType;
  mood: string;
  note?: string;
  venue?: string;
}

const SEED: Seed[] = [
  { offset: 0, hour: 8, drink: "Flat white", type: "coffee", mood: "steady" },
  { offset: 0, hour: 21, drink: "Negroni", type: "cocktail", mood: "celebratory", venue: "Bar Termini", note: "Marco's leaving drinks." },
  { offset: 1, hour: 20, drink: "Riesling", type: "wine", mood: "easy" },
  { offset: 2, hour: 9, drink: "Cold brew", type: "coffee", mood: "focused" },
  { offset: 3, hour: 19, drink: "Guinness", type: "beer", mood: "cozy", venue: "The Harp" },
  { offset: 4, hour: 8, drink: "Espresso", type: "coffee", mood: "quick" },
  { offset: 4, hour: 21, drink: "Barolo", type: "wine", mood: "special", note: "With the short rib." },
  { offset: 5, hour: 16, drink: "Matcha", type: "tea", mood: "calm" },
  { offset: 6, hour: 22, drink: "Old Fashioned", type: "cocktail", mood: "warm" },
  // offset 7 — a missed day (grace)
  { offset: 8, hour: 8, drink: "Cortado", type: "coffee", mood: "ordinary" },
  { offset: 9, hour: 19, drink: "Sancerre", type: "wine", mood: "bright" },
  { offset: 9, hour: 23, drink: "Negroni", type: "cocktail", mood: "loose" },
  { offset: 10, hour: 18, drink: "Hazy IPA", type: "beer", mood: "loose" },
  { offset: 12, hour: 9, drink: "Pour-over", type: "coffee", mood: "slow" },
  { offset: 14, hour: 20, drink: "Margarita", type: "cocktail", mood: "fun" },
  { offset: 16, hour: 22, drink: "Chamomile", type: "tea", mood: "sleepy" },
  { offset: 18, hour: 21, drink: "Cabernet", type: "wine", mood: "rich" },
  { offset: 21, hour: 8, drink: "Cappuccino", type: "coffee", mood: "bright" },
  { offset: 25, hour: 17, drink: "Aperol Spritz", type: "cocktail", mood: "sunny" },
  { offset: 28, hour: 19, drink: "Stout", type: "beer", mood: "cozy" },
];

export function seedEntries(): Entry[] {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  return SEED.map((s, i) => {
    const day = addDays(today, -s.offset);
    const created = new Date(day);
    created.setHours(s.hour, (i * 7) % 60, 0, 0);
    return {
      id: `seed_${i}`,
      date: toKey(day),
      createdAt: created.toISOString(),
      drink: s.drink,
      type: s.type,
      mood: s.mood,
      note: s.note,
      venue: s.venue,
    } satisfies Entry;
  });
}
