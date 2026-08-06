"use client";

// The leaderboard: friends who ALSO opted in, ranked by sparks.
//
// Opt-in on both sides — friends who haven't switched it on simply aren't here, so
// nobody is ranked in front of their friends without asking. Sparks come from variety
// (a new place, a new drink, a dry day), never from frequency or volume, and nobody is
// ever ranked by what they spent. Moved to its own route with the rest of the rooms;
// it only appears in the hub at all when the You → Settings toggle is on.
import { useState } from "react";
import clsx from "clsx";
import { useFriendsBoard } from "@/lib/points";
import { useAuth } from "@/lib/profile";
import { ScoreCard, type Score } from "../share/ScoreCard";

export function FriendsBoard() {
  const me = useAuth().profile?.id;
  const { board, loading } = useFriendsBoard(true);
  const [sharing, setSharing] = useState<Score | null>(null);
  const top = board[0]?.sparks ?? 0;
  const mine = board.findIndex((r) => r.userId === me);

  if (loading) {
    return (
      <div className="mt-8 space-y-2" aria-hidden>
        {[0, 1, 2].map((i) => (
          <div key={i} className="glass h-12 animate-pulse rounded-ctl" />
        ))}
      </div>
    );
  }

  if (board.length === 0) {
    return (
      <p className="mt-10 text-center text-sm text-faint">
        Quiet board. Sparks come from showing up; vibe is what your table and the bar hand you.
      </p>
    );
  }

  return (
    <section className="mt-8">
      <p className="label mb-2 text-faint">You and the friends who opted in</p>
      <ul className="divide-y divide-line border-y border-line">
        {board.map((r, i) => {
          const leads = r.sparks > 0 && r.sparks === top;
          return (
            <li key={r.userId} className="flex items-center justify-between gap-3 py-2.5">
              <span className="flex min-w-0 items-center gap-2.5">
                <span className="tnum w-4 text-xs text-faint">{i + 1}</span>
                <span className="truncate text-[15px] text-ink">{r.userId === me ? "you" : r.name}</span>
              </span>
              <span className="flex shrink-0 items-center gap-3 text-sm">
                <span className={clsx("tnum", leads ? "text-accent" : "text-muted")}>
                  {r.sparks} <span className="text-xs text-faint">sparks</span>
                </span>
                {r.vibe > 0 && (
                  <span className="tnum text-muted">
                    {r.vibe} <span className="text-xs text-faint">vibe</span>
                  </span>
                )}
              </span>
            </li>
          );
        })}
      </ul>

      {mine >= 0 && (
        <button
          onClick={() =>
            setSharing({
              name: "you",
              sparks: board[mine].sparks,
              vibe: board[mine].vibe,
              context: "with friends",
              rank: mine + 1,
              of: board.length,
            })
          }
          className="mt-4 min-h-11 w-full rounded-ctl border border-line py-2.5 text-sm text-muted transition-colors hover:text-ink"
        >
          Share your score
        </button>
      )}

      <p className="mt-4 text-xs leading-relaxed text-faint">
        Nobody is ranked by what they spent. Switch this off any time in You → Settings.
      </p>

      {sharing && <ScoreCard score={sharing} onClose={() => setSharing(null)} />}
    </section>
  );
}
