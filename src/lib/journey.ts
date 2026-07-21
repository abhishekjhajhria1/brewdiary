// The Passport journey — your exploration told as ONE winding road of landmarks, the
// Duolingo/level-map pattern (a single linear path where reaching one milestone reveals
// the next). Pure + derived from the Passport, like everything else: delete it and it
// recomputes identically.
//
// Design principles (researched — Duolingo learning path + game wayfinding theory):
//  • ONE path, not a grid — "how far you've come, and what's ahead", made concrete.
//  • Landmarks, not a wall of checkboxes — a handful of distinctive, ordered milestones.
//  • Golden-vs-dim — reached nodes are lit; ahead ones are dim invitations, never a nag.
//  • Breadth, never volume — every milestone is a COUNT of distinct families/worlds or a
//    behaviour (a balanced week). Logging the same drink again advances nothing (rule #6).
import type { Entry } from "./types";
import { passport } from "./passport";
import { weekBalance } from "./derive";

export interface JourneyNode {
  id: string;
  /** Short name shown when the marker rests on this node. */
  label: string;
  /** One line of flavour — the caption under the road. */
  hint: string;
  /** Lit (golden) once true; a dim landmark ahead until then. */
  reached: boolean;
}

export interface Journey {
  nodes: JourneyNode[];
  /** Index of the furthest reached node — where "you are". -1 before the first stamp. */
  frontier: number;
  /** The breadth headline (distinct families), a COUNT, never a percentage. */
  exploredFamilies: number;
}

/**
 * Build the journey for a diary. The order is a gentle difficulty ramp; a couple of nodes
 * (off-map, a balanced week) are side-landmarks that may light out of order — that reads as
 * "a spot you can double back for", the same way a path game leaves optional bonus nodes.
 */
export function journey(entries: Entry[], today?: string): Journey {
  const p = passport(entries);
  const fam = p.exploredFamilies;
  const worlds = p.worlds.filter((w) => w.exploredCount > 0).length;
  const totalWorlds = p.worlds.length;
  const offMap = p.offMap.length;
  const wb = weekBalance(entries, today);

  const nodes: JourneyNode[] = [
    { id: "first", label: "First pour", hint: "Your very first stamp lit up.", reached: fam >= 1 },
    { id: "fam3", label: "3 families", hint: "Three corners of the map.", reached: fam >= 3 },
    { id: "world2", label: "A second world", hint: "You crossed into a new kind of drink.", reached: worlds >= 2 },
    { id: "fam5", label: "5 families", hint: "Five, and still wandering.", reached: fam >= 5 },
    { id: "fam8", label: "8 families", hint: "The map is filling in.", reached: fam >= 8 },
    { id: "world3", label: "Three worlds", hint: "Coffee to cocktails and beyond.", reached: worlds >= 3 },
    { id: "offmap", label: "Off the map", hint: "You found a drink the map had never seen.", reached: offMap >= 1 },
    { id: "fam12", label: "12 families", hint: "A wide palate, this.", reached: fam >= 12 },
    { id: "balance", label: "An easy week", hint: "A week with a night off in it.", reached: wb.dryDays >= 1 && wb.drinks >= 1 },
    { id: "fam18", label: "18 families", hint: "Far-wandered.", reached: fam >= 18 },
    { id: "fam25", label: "25 families", hint: "A serious map now.", reached: fam >= 25 },
    { id: "allworlds", label: "Every world", hint: "A stamp in every world there is.", reached: totalWorlds > 0 && worlds === totalWorlds },
    { id: "fam40", label: "40 families", hint: "Cartographer of your own taste.", reached: fam >= 40 },
  ];

  let frontier = -1;
  nodes.forEach((n, i) => {
    if (n.reached) frontier = i;
  });

  return { nodes, frontier, exploredFamilies: fam };
}
