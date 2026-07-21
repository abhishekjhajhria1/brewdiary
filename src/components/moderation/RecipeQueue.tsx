"use client";

// The recipe queue — community recipes that crossed the friends threshold (≥50% of ≥3
// friends backed them) and now await the human gate to the public surface (045). Approve
// → public; reject → back to friends (never deleted — rejection isn't punishment).
// The screen is UX only: review_recipe() re-derives is_moderator() server-side.
import { useState } from "react";
import { usePendingRecipes, reviewRecipe, type PendingRecipe } from "@/lib/cookbook";

export function RecipeQueue() {
  const { pending, reload } = usePendingRecipes();

  if (pending.length === 0) {
    return <p className="text-sm text-faint">No recipes waiting. They arrive once enough friends back one.</p>;
  }

  return (
    <ul className="space-y-3">
      {pending.map((r) => (
        <PendingCard key={r.id} recipe={r} onDone={reload} />
      ))}
    </ul>
  );
}

function PendingCard({ recipe, onDone }: { recipe: PendingRecipe; onDone: () => void }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function act(approve: boolean) {
    setBusy(true);
    setErr(null);
    const e = await reviewRecipe(recipe.id, approve);
    setBusy(false);
    if (e) setErr(e);
    else onDone();
  }

  return (
    <li className="glass rounded-tile p-5">
      <p className="font-display text-lg leading-tight text-ink">{recipe.name}</p>
      {recipe.ingredients.length > 0 && (
        <p className="mt-1 text-xs text-faint">{recipe.ingredients.join(" · ")}</p>
      )}
      <p className="mt-2 text-sm leading-relaxed text-muted">{recipe.method}</p>

      <div className="mt-4 flex gap-2">
        <button
          onClick={() => act(true)}
          disabled={busy}
          className="min-h-11 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          Approve — make it public
        </button>
        <button
          onClick={() => act(false)}
          disabled={busy}
          className="min-h-11 rounded-ctl border border-line px-4 py-2 text-sm text-muted transition-colors hover:text-ink disabled:opacity-50"
        >
          Back to friends
        </button>
      </div>
      {err && <p className="mt-2 text-xs text-accent">{err}</p>}
    </li>
  );
}
