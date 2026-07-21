"use client";

// Recipes — the community cookbook room (Phase D). Invent a drink (by hand or drafted
// WITH Ninkasi), share it to friends, react to others', and watch a loved one climb the
// ladder: friends → (half your friends back it) → review → public. Medals are derived
// from positive reactions (lib/cookbook.recipeMedals) — creativity is the thing rewarded,
// never consumption, and there is no downvote to weaponise.
//
// UX: every action is a visible button (create, draft, react, delete) — no bare
// clickable text — per the maintainer's discoverability rule.
import { useState } from "react";
import clsx from "clsx";
import { useAuth } from "@/lib/profile";
import {
  useCommunityRecipes,
  useReactionCounts,
  useMyReactions,
  createRecipe,
  deleteRecipe,
  toggleReaction,
  recipeMedals,
  isValidRecipe,
  REACTIONS,
  type CommunityRecipe,
  type MedalTier,
  type ReactionKind,
} from "@/lib/cookbook";

const STATE_LABEL: Record<CommunityRecipe["state"], string> = {
  friends: "with friends",
  pending: "in review",
  public: "public",
};

// Medal tiers in the app's single-accent language: opacity carries the tier, not a
// second colour (LILA — no gold/silver/bronze rainbow).
const TIER_OPACITY: Record<MedalTier, string> = {
  bronze: "opacity-60",
  silver: "opacity-80",
  gold: "opacity-100",
};

export function Recipes() {
  const me = useAuth().profile?.id;
  const { recipes, loading } = useCommunityRecipes();
  const mine = useMyReactions();
  const [creating, setCreating] = useState(false);

  if (!me) {
    return (
      <p className="mt-10 text-center text-sm text-faint">
        Sign in to share a recipe of your own — and to pour your friends&apos;.
      </p>
    );
  }

  return (
    <section className="mt-6">
      <p className="max-w-prose text-sm leading-relaxed text-muted">
        Drinks your friends invented, and yours. If half your friends back one of yours, it goes to
        review — approved, it&apos;s public, and the medals follow the love.
      </p>

      <button
        onClick={() => setCreating((c) => !c)}
        aria-expanded={creating}
        className={clsx(
          "mt-4 min-h-11 w-full rounded-ctl px-4 py-2.5 text-sm font-medium transition-colors",
          creating ? "bg-accent text-accent-contrast" : "bg-ink text-paper hover:opacity-90",
        )}
      >
        + New recipe
      </button>

      {creating && <RecipeForm meId={me} onDone={() => setCreating(false)} />}

      {loading ? (
        <div className="mt-6 space-y-2" aria-hidden>
          {[0, 1].map((i) => (
            <div key={i} className="glass h-28 animate-pulse rounded-tile" />
          ))}
        </div>
      ) : recipes.length === 0 ? (
        <p className="mt-8 text-center text-sm text-faint">
          No recipes yet — invent the first one, or add friends who pour.
        </p>
      ) : (
        <ul className="mt-6 space-y-3">
          {recipes.map((r) => (
            <li key={r.id}>
              <RecipeCard recipe={r} meId={me} myKinds={mine.get(r.id) ?? new Set()} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

// ── one recipe ───────────────────────────────────────────────────────────────
function RecipeCard({ recipe, meId, myKinds }: { recipe: CommunityRecipe; meId: string; myKinds: Set<ReactionKind> }) {
  const { counts } = useReactionCounts(recipe.id);
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const isMine = recipe.authorId === meId;
  const medals = recipeMedals(counts);

  return (
    <div className="glass rounded-tile p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-display text-xl leading-tight text-ink">{recipe.name}</p>
          <p className="mt-0.5 text-xs text-faint">
            by {isMine ? "you" : recipe.authorName}
            {recipe.source === "ninkasi" && <span> · with Ninkasi</span>}
            <span> · {STATE_LABEL[recipe.state]}</span>
          </p>
        </div>
        <button
          onClick={() => setOpen((o) => !o)}
          aria-expanded={open}
          className="min-h-9 shrink-0 rounded-ctl border border-line px-3 text-xs text-muted transition-colors hover:border-line-strong hover:text-ink"
        >
          {open ? "Close" : "Recipe"}
        </button>
      </div>

      {/* medals — earned from reactions, opacity carries the tier */}
      {medals.length > 0 && (
        <div className="mt-2.5 flex flex-wrap gap-1.5">
          {medals.map((m) => (
            <span
              key={m.id}
              className={clsx(
                "inline-flex items-center gap-1 rounded-ctl bg-accent/10 px-2 py-1 text-xs text-accent",
                TIER_OPACITY[m.tier],
              )}
            >
              <span aria-hidden>✦</span>
              {m.title}
            </span>
          ))}
        </div>
      )}

      {open && (
        <div className="animate-rise mt-4 border-t border-line pt-4">
          {recipe.ingredients.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {recipe.ingredients.map((i) => (
                <span key={i} className="rounded-ctl border border-line px-2.5 py-1 text-xs text-muted">
                  {i}
                </span>
              ))}
            </div>
          )}
          <p className="mt-3 text-sm leading-relaxed text-muted">{recipe.method}</p>
        </div>
      )}

      {/* reactions — positive only, one of each kind, real buttons */}
      <div className="mt-4 flex flex-wrap items-center gap-1.5">
        {REACTIONS.map(({ kind, label, doneLabel }) => {
          const on = myKinds.has(kind);
          const n = counts[kind];
          return (
            <button
              key={kind}
              onClick={() => toggleReaction(meId, recipe.id, kind, !on)}
              aria-pressed={on}
              disabled={isMine}
              title={isMine ? "Your own recipe — reactions come from others" : undefined}
              className={clsx(
                "min-h-9 rounded-ctl border px-3 py-1.5 text-xs transition-colors disabled:opacity-40",
                on ? "border-transparent bg-accent/10 text-accent" : "border-line text-muted hover:border-line-strong hover:text-ink",
              )}
            >
              {on ? doneLabel : label}
              {n > 0 && <span className="tnum ml-1.5 opacity-70">{n}</span>}
            </button>
          );
        })}

        {isMine && (
          <button
            onClick={() => setConfirming(true)}
            className="ml-auto min-h-9 rounded-ctl border border-line px-3 py-1.5 text-xs text-muted transition-colors hover:border-accent hover:text-accent"
          >
            Delete
          </button>
        )}
      </div>

      {confirming && (
        <div className="mt-3 flex items-center gap-2 rounded-ctl bg-ink/4 px-3 py-2">
          <span className="flex-1 text-xs text-muted">Delete this recipe for everyone?</span>
          <button
            onClick={() => deleteRecipe(recipe.id)}
            className="min-h-9 rounded-ctl bg-accent px-3 text-xs font-medium text-accent-contrast hover:opacity-90"
          >
            Delete
          </button>
          <button
            onClick={() => setConfirming(false)}
            className="min-h-9 rounded-ctl border border-line px-3 text-xs text-muted hover:text-ink"
          >
            Keep
          </button>
        </div>
      )}
    </div>
  );
}

// ── the form — by hand, or drafted with Ninkasi ──────────────────────────────
function RecipeForm({ meId, onDone }: { meId: string; onDone: () => void }) {
  const [name, setName] = useState("");
  const [ingredients, setIngredients] = useState(""); // comma-separated in the field
  const [method, setMethod] = useState("");
  const [drafted, setDrafted] = useState(false); // did Ninkasi co-write this?
  const [drafting, setDrafting] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const parsedIngredients = ingredients.split(",").map((i) => i.trim()).filter(Boolean);
  const valid = isValidRecipe({ name, method });

  // Ask Ninkasi for a draft method from the name + ingredients. Streams into the method
  // field; the author edits and owns the final (source records the co-writing honestly).
  async function draftWithNinkasi() {
    if (drafting) return;
    setDrafting(true);
    setError(null);
    try {
      const ask = `Draft a short home recipe method (under 90 words, plain steps, no brand names) for a drink called "${name.trim() || "my invention"}"${parsedIngredients.length ? ` using: ${parsedIngredients.join(", ")}` : ""}. Method only — no preamble.`;
      const res = await fetch("/api/bartender", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: [{ role: "user", content: ask }] }),
      });
      if (!res.ok || !res.body) throw new Error("Ninkasi is away from the bar.");
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let text = "";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        text += decoder.decode(value, { stream: true });
        setMethod(text.slice(0, 800)); // live-stream into the field, DB bound respected
      }
      setDrafted(true);
    } catch {
      setError("Couldn't reach Ninkasi — write it by hand, or try again.");
    } finally {
      setDrafting(false);
    }
  }

  async function submit() {
    setBusy(true);
    setError(null);
    const err = await createRecipe(meId, {
      name,
      ingredients: parsedIngredients,
      method,
      source: drafted ? "ninkasi" : "self",
    });
    setBusy(false);
    if (err) {
      setError(err);
      return;
    }
    onDone();
  }

  return (
    <div className="glass mt-3 space-y-4 rounded-tile p-4">
      <div>
        <label className="mb-1.5 block text-xs text-muted">Name your drink</label>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={80}
          placeholder="The Monsoon Fizz"
          className="w-full rounded-ctl bg-ink/4 px-3.5 py-2.5 text-[15px] text-ink outline-none placeholder:text-faint focus:bg-ink/6"
        />
      </div>

      <div>
        <label className="mb-1.5 block text-xs text-muted">Ingredients — comma-separated</label>
        <input
          value={ingredients}
          onChange={(e) => setIngredients(e.target.value)}
          placeholder="gin, lime, soda, mint"
          className="w-full rounded-ctl bg-ink/4 px-3.5 py-2.5 text-[15px] text-ink outline-none placeholder:text-faint focus:bg-ink/6"
        />
      </div>

      <div>
        <div className="mb-1.5 flex items-center justify-between gap-3">
          <label className="text-xs text-muted">Method</label>
          <button
            onClick={draftWithNinkasi}
            disabled={drafting}
            className="min-h-9 rounded-ctl border border-line px-3 text-xs text-muted transition-colors hover:border-line-strong hover:text-ink disabled:opacity-50"
          >
            {drafting ? "Ninkasi is thinking…" : "Draft with Ninkasi"}
          </button>
        </div>
        <textarea
          value={method}
          onChange={(e) => setMethod(e.target.value)}
          maxLength={800}
          rows={5}
          placeholder="Shake the gin and lime over ice…"
          className="w-full resize-y rounded-ctl bg-ink/4 px-3.5 py-2.5 text-[15px] leading-relaxed text-ink outline-none placeholder:text-faint focus:bg-ink/6"
        />
        {drafted && <p className="mt-1 text-xs text-faint">Drafted with Ninkasi — edit it until it&apos;s yours.</p>}
      </div>

      {error && <p className="text-sm text-accent">{error}</p>}

      <div className="flex gap-2">
        <button
          onClick={submit}
          disabled={!valid || busy}
          className="min-h-11 flex-1 rounded-ctl bg-accent py-3 text-sm font-medium text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "Sharing…" : "Share with friends"}
        </button>
        <button
          onClick={onDone}
          disabled={busy}
          className="min-h-11 rounded-ctl border border-line px-4 text-sm text-muted transition-colors hover:text-ink disabled:opacity-50"
        >
          Cancel
        </button>
      </div>
      <p className="text-xs leading-relaxed text-faint">
        It starts with your friends. If half of them back it, it goes to review — approved, anyone can
        pour it.
      </p>
    </div>
  );
}
