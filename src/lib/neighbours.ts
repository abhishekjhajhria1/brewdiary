"use client";

// Palate neighbours — "people whose maps look like yours wandered here next."
// The client half of migration 048: one k-anon rpc (counts only, opt-in both
// ways, k ≥ 5 — see supabase/048_palate_neighbours.sql) hands back raw drink
// names; THIS file folds them into dictionary families (canonicalization is a
// TS concern) and drops anything the caller has already explored, so what
// surfaces is always a door, never an echo.
//
// Rule #6 note: ranking is neighbour-count alone — the rpc never sees volume,
// and a chamomile door outranks a whisky one whenever more neighbours went there.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";
import { drinkFamily } from "./drinks";

export interface NeighbourDoor {
  /** The dictionary family (or the raw name, for an off-map find). */
  family: string;
  /** Distinct neighbours who wandered there — always ≥ 5 (the rpc's k). */
  users: number;
}

/** The crowd's doors, folded to families and filtered to ones I haven't opened.
 *  `enabled` gates the fetch — the surface is opt-in (share_trends), and callers
 *  pass their explored families so an already-lit stamp never comes back. */
export function usePalateNeighbours(
  enabled: boolean,
  exploredFamilies: Set<string>,
): { doors: NeighbourDoor[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const [doors, setDoors] = useState<NeighbourDoor[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!supabase || !me || !enabled) {
      setDoors([]);
      return;
    }
    let active = true;
    setLoading(true);
    (async () => {
      const { data } = await supabase!.rpc("palate_neighbours", { lim: 8 });
      if (!active) return;
      // Fold raw names → families, keep the strongest count per family, drop mine.
      const byFamily = new Map<string, number>();
      for (const row of (data ?? []) as { name: string; users: number }[]) {
        const fam = drinkFamily(row.name);
        if (exploredFamilies.has(fam)) continue;
        byFamily.set(fam, Math.max(byFamily.get(fam) ?? 0, row.users));
      }
      setDoors(
        [...byFamily.entries()]
          .map(([family, users]) => ({ family, users }))
          .sort((a, b) => b.users - a.users || a.family.localeCompare(b.family))
          .slice(0, 4),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
    // exploredFamilies is a fresh Set each render; its SIZE is the honest dep.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [me, enabled, exploredFamilies.size]);

  return { doors, loading };
}
