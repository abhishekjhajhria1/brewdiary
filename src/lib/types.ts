// Phase 1 data shapes — a subset of reference/data-model.md (local-only, no backend yet).
// Only `Entry` rows are ever written; the mosaic, streaks, milestones, lexicon and
// recent-drinks are all DERIVED from entries (see lib/derive.ts), never stored.

export type DrinkType =
  | "coffee"
  | "tea"
  | "beer"
  | "wine"
  | "cocktail"
  | "spirit"
  | "soft"
  | "other";

export interface Photo {
  id: string;
  url: string; // object URL / data URL in Phase 1
}

export interface Entry {
  id: string;
  /** The calendar day this entry is FOR (YYYY-MM-DD). Backfillable. The mosaic & streaks count THIS. */
  date: string;
  /** Actual moment it was created (ISO). Drives time-of-day; distinct from `date`. */
  createdAt: string;
  /** What it was. */
  drink: string;
  type?: DrinkType;
  /** One word for how the moment felt — never a rating. */
  mood?: string;
  note?: string;
  photos?: Photo[];
  venue?: string;
  /** Free-text names in Phase 1 (real friends arrive in Phase 3). */
  whoWith?: string[];
  /** Who can see it. Default private; "friends" surfaces it in the Together feed. */
  visibility?: "private" | "friends";
}

export const DRINK_TYPES: { value: DrinkType; label: string }[] = [
  { value: "coffee", label: "Coffee" },
  { value: "tea", label: "Tea" },
  { value: "beer", label: "Beer" },
  { value: "wine", label: "Wine" },
  { value: "cocktail", label: "Cocktail" },
  { value: "spirit", label: "Spirit" },
  { value: "soft", label: "Soft" },
  { value: "other", label: "Other" },
];
