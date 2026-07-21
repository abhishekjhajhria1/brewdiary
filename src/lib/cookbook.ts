"use client";

// Community recipes (Phase D, migration 045) — the client. Make a drink of your own (by
// hand, or drafted WITH Ninkasi — the AI co-writes, the author owns the final), share it
// to friends, and earn MEDALS from other people's positive reactions.
//
// The reward spine, mirrored from the DB:
//  • Reactions are POSITIVE-ONLY ('made' / 'love' / 'totry') and one-of-each-kind per
//    person (the PK) — no downvote exists, no farming works.
//  • Medals are DERIVED from reaction counts (recipeMedals below) — never stored, and
//    they celebrate CREATIVITY (people liked what you invented), never consumption.
//  • Visibility ladder is server-owned: created 'friends' → auto-'pending' at ≥50% of
//    ≥3 friends → moderator approves to 'public'. No client can touch `state`.
import { useEffect, useState } from "react";
import { supabase } from "./supabase";
import { useAuth } from "./profile";

export type ReactionKind = "made" | "love" | "totry";
export type RecipeState = "friends" | "pending" | "public";

export interface CommunityRecipe {
  id: string;
  authorId: string;
  authorName: string;
  name: string;
  ingredients: string[];
  method: string;
  source: "self" | "ninkasi";
  state: RecipeState;
  createdAt: string;
}

export interface ReactionCounts {
  made: number;
  love: number;
  totry: number;
}

export const REACTIONS: { kind: ReactionKind; label: string; doneLabel: string }[] = [
  { kind: "made", label: "I made it", doneLabel: "Made it" },
  { kind: "love", label: "Love it", doneLabel: "Loved" },
  { kind: "totry", label: "To try", doneLabel: "On your list" },
];

// ── medals (pure, unit-tested) ───────────────────────────────────────────────
export type MedalTier = "bronze" | "silver" | "gold";

export interface Medal {
  id: string;
  tier: MedalTier;
  /** e.g. "House pour" */
  title: string;
  /** which reaction kind earned it */
  kind: ReactionKind;
}

// Thresholds per tier — the same ladder for every kind, so no kind is worth "more".
const TIERS: { tier: MedalTier; at: number }[] = [
  { tier: "bronze", at: 3 },
  { tier: "silver", at: 10 },
  { tier: "gold", at: 25 },
];

const MEDAL_TITLE: Record<ReactionKind, Record<MedalTier, string>> = {
  made: { bronze: "Poured by friends", silver: "House pour", gold: "A classic now" },
  love: { bronze: "Warmly received", silver: "Crowd favourite", gold: "Beloved" },
  totry: { bronze: "On a few lists", silver: "Widely wished", gold: "The one to try" },
};

/** The highest medal per reaction kind, derived from counts. Empty below bronze. */
export function recipeMedals(counts: ReactionCounts): Medal[] {
  const out: Medal[] = [];
  for (const kind of ["made", "love", "totry"] as ReactionKind[]) {
    const n = counts[kind];
    let best: MedalTier | null = null;
    for (const t of TIERS) if (n >= t.at) best = t.tier;
    if (best) out.push({ id: `${kind}-${best}`, tier: best, title: MEDAL_TITLE[kind][best], kind });
  }
  return out;
}

// ── shared refresh signal (same pattern as cups.ts) ──────────────────────────
let version = 0;
const subs = new Set<() => void>();
function bump() {
  version++;
  subs.forEach((s) => s());
}
function useVersion(): number {
  const [, set] = useState(0);
  useEffect(() => {
    const cb = () => set((n) => n + 1);
    subs.add(cb);
    return () => {
      subs.delete(cb);
    };
  }, []);
  return version;
}

// ── reads ────────────────────────────────────────────────────────────────────
/** Every recipe visible to me (RLS decides: mine + friends' + circle-mates' + public). */
export function useCommunityRecipes(): { recipes: CommunityRecipe[]; loading: boolean } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [recipes, setRecipes] = useState<CommunityRecipe[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase || !me) {
      setRecipes([]);
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!
        .from("recipes")
        .select("id, author_id, name, ingredients, method, source, state, created_at, author:profiles(display_name)")
        .order("created_at", { ascending: false });
      if (!active) return;
      setRecipes(
        ((data ?? []) as Record<string, unknown>[]).map((r) => ({
          id: r.id as string,
          authorId: r.author_id as string,
          authorName: ((r.author as { display_name?: string } | null)?.display_name as string) ?? "someone",
          name: r.name as string,
          ingredients: (r.ingredients as string[]) ?? [],
          method: r.method as string,
          source: (r.source as "self" | "ninkasi") ?? "self",
          state: (r.state as RecipeState) ?? "friends",
          createdAt: r.created_at as string,
        })),
      );
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { recipes, loading };
}

/** Reaction tallies for one recipe — counts only (the rpc never says who). */
export function useReactionCounts(recipeId: string): { counts: ReactionCounts; loading: boolean } {
  const v = useVersion();
  const [counts, setCounts] = useState<ReactionCounts>({ made: 0, love: 0, totry: 0 });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("recipe_reaction_counts", { rid: recipeId });
      if (!active) return;
      const next: ReactionCounts = { made: 0, love: 0, totry: 0 };
      for (const row of (data ?? []) as { kind: ReactionKind; n: number }[]) next[row.kind] = row.n;
      setCounts(next);
      setLoading(false);
    })();
    return () => {
      active = false;
    };
  }, [recipeId, v]);

  return { counts, loading };
}

/** MY reactions across all recipes (the read policy only ever returns my own rows). */
export function useMyReactions(): Map<string, Set<ReactionKind>> {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [mine, setMine] = useState<Map<string, Set<ReactionKind>>>(new Map());

  useEffect(() => {
    if (!supabase || !me) {
      setMine(new Map());
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.from("recipe_reactions").select("recipe_id, kind").eq("user_id", me);
      if (!active) return;
      const m = new Map<string, Set<ReactionKind>>();
      for (const r of (data ?? []) as { recipe_id: string; kind: ReactionKind }[]) {
        let set = m.get(r.recipe_id);
        if (!set) m.set(r.recipe_id, (set = new Set()));
        set.add(r.kind);
      }
      setMine(m);
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return mine;
}

// ── writes ───────────────────────────────────────────────────────────────────
export interface NewRecipe {
  name: string;
  ingredients: string[];
  method: string;
  source: "self" | "ninkasi";
}

export function isValidRecipe(r: Pick<NewRecipe, "name" | "method">): boolean {
  const n = r.name.trim();
  const m = r.method.trim();
  return n.length >= 1 && n.length <= 80 && m.length >= 1 && m.length <= 800;
}

export async function createRecipe(meId: string, input: NewRecipe): Promise<string | null> {
  if (!supabase) return "offline";
  if (!isValidRecipe(input)) return "Give it a name (≤80 chars) and a method (≤800).";
  // Client-generated id + no .select() (definer-backed read policy — the PostgREST
  // RETURNING gotcha). State is forced 'friends' by the insert policy either way.
  const { error } = await supabase.from("recipes").insert({
    id: crypto.randomUUID(),
    author_id: meId,
    name: input.name.trim(),
    ingredients: input.ingredients.map((i) => i.trim()).filter(Boolean),
    method: input.method.trim(),
    source: input.source,
  });
  bump();
  return error ? error.message : null;
}

export async function deleteRecipe(recipeId: string) {
  if (!supabase) return;
  await supabase.from("recipes").delete().eq("id", recipeId);
  bump();
}

/** Toggle one of MY reactions. Plain insert/delete — no upsert/ignoreDuplicates (the
 *  RLS + ON CONFLICT trap), and the caller passes the current state so we never guess. */
export async function toggleReaction(meId: string, recipeId: string, kind: ReactionKind, on: boolean): Promise<void> {
  if (!supabase) return;
  if (on) {
    await supabase.from("recipe_reactions").insert({ recipe_id: recipeId, user_id: meId, kind });
  } else {
    await supabase.from("recipe_reactions").delete().eq("recipe_id", recipeId).eq("user_id", meId).eq("kind", kind);
  }
  bump();
}

// ── the moderator queue (renders empty for everyone else) ────────────────────
export interface PendingRecipe {
  id: string;
  name: string;
  ingredients: string[];
  method: string;
  createdAt: string;
}

export function usePendingRecipes(): { pending: PendingRecipe[]; reload: () => void } {
  const me = useAuth().profile?.id;
  const v = useVersion();
  const [pending, setPending] = useState<PendingRecipe[]>([]);

  useEffect(() => {
    if (!supabase || !me) {
      setPending([]);
      return;
    }
    let active = true;
    (async () => {
      const { data } = await supabase!.rpc("pending_recipes");
      if (!active) return;
      setPending(
        ((data ?? []) as Record<string, unknown>[]).map((r) => ({
          id: r.id as string,
          name: r.name as string,
          ingredients: (r.ingredients as string[]) ?? [],
          method: r.method as string,
          createdAt: r.created_at as string,
        })),
      );
    })();
    return () => {
      active = false;
    };
  }, [me, v]);

  return { pending, reload: bump };
}

export async function reviewRecipe(recipeId: string, approve: boolean): Promise<string | null> {
  if (!supabase) return "offline";
  const { error } = await supabase.rpc("review_recipe", { rid: recipeId, approve });
  bump();
  return error ? error.message : null;
}
