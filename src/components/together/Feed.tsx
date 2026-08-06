"use client";

// The feed — what friends are pouring. Lifted out of Together.tsx unchanged when
// that file became a hub.
//
// Note what is NOT here: the pegs/beers round counter. It belongs to a night you're
// actually at, so it lives inside a night's room and never on this open feed.
import { useState } from "react";
import clsx from "clsx";
import { toggleCheers, addComment, type FeedEntry, type SocialProfile } from "@/lib/friends";
import { useAuth } from "@/lib/profile";
import { addWish } from "@/lib/wishlist";
import { MONTH_NAMES, parseKey, timeOfDayLabel } from "@/lib/date";
import { VenueLink } from "../ui/VenueLink";

export function Feed({
  feed,
  loading,
  hasFriends,
  onOpenFriend,
}: {
  feed: FeedEntry[];
  loading: boolean;
  hasFriends: boolean;
  onOpenFriend: (f: SocialProfile) => void;
}) {
  if (!hasFriends) {
    return (
      <p className="mt-10 text-center text-sm text-faint">
        Add a friend by their handle to see what they&apos;re pouring.
      </p>
    );
  }
  if (loading) {
    return (
      <ul className="mt-8 space-y-3" aria-hidden>
        {[0, 1, 2].map((i) => (
          <li key={i} className="glass h-28 animate-pulse rounded-tile" />
        ))}
      </ul>
    );
  }
  if (feed.length === 0) {
    return (
      <p className="mt-10 text-center text-sm text-faint">
        Quiet so far — nothing shared to friends yet. Share an entry from your diary and it lands here.
      </p>
    );
  }
  return (
    <ul className="mt-4 space-y-3">
      {feed.map((item) => (
        <FeedCard key={item.id} item={item} onOpenFriend={onOpenFriend} />
      ))}
    </ul>
  );
}

function FeedCard({ item, onOpenFriend }: { item: FeedEntry; onOpenFriend: (f: SocialProfile) => void }) {
  const me = useAuth().profile?.id;
  const [showComments, setShowComments] = useState(false);
  const [draft, setDraft] = useState("");
  const [saved, setSaved] = useState(false);

  return (
    <li className="glass rounded-tile p-5">
      <div className="flex items-baseline justify-between gap-3">
        <button onClick={() => onOpenFriend(item.author)} className="text-[15px] text-ink transition-colors hover:text-accent">
          {item.author.name}
        </button>
        <span className="tnum shrink-0 text-xs text-faint">
          {timeOfDayLabel(item.createdAt).toLowerCase()} · {MONTH_NAMES[parseKey(item.date).getMonth()].slice(0, 3)}{" "}
          {parseKey(item.date).getDate()}
        </span>
      </div>

      <p className="mt-1.5 font-display text-2xl leading-tight text-ink">
        {item.drink}
        {item.mood && <span className="text-xl italic text-muted"> · {item.mood}</span>}
      </p>

      {item.note && <p className="mt-1.5 text-[15px] leading-relaxed text-muted">{item.note}</p>}
      {item.venue && (
        <p className="mt-1 text-xs text-faint">
          <VenueLink venue={item.venue} />
        </p>
      )}

      <div className="mt-3 flex items-center gap-5 text-sm">
        <button
          onClick={() => me && toggleCheers(item.id, me, item.cheered)}
          aria-pressed={item.cheered}
          className={clsx("min-h-11 transition-colors", item.cheered ? "font-medium text-accent" : "text-muted hover:text-ink")}
        >
          {item.cheered ? "Cheered" : "Cheers"}
          {item.cheers > 0 && <span className="tnum"> {item.cheers}</span>}
        </button>

        <button onClick={() => setShowComments((v) => !v)} className="min-h-11 text-muted transition-colors hover:text-ink">
          {item.comments.length > 0 ? (
            <>
              Comments<span className="tnum"> {item.comments.length}</span>
            </>
          ) : (
            "Comment"
          )}
        </button>

        <button
          onClick={() => {
            addWish(item.drink);
            setSaved(true);
          }}
          disabled={saved}
          title="Save this drink to your to-try list"
          className={clsx("ml-auto min-h-11 transition-colors", saved ? "text-faint" : "text-muted hover:text-accent")}
        >
          {saved ? "On your list ✓" : "To try"}
        </button>
      </div>

      {showComments && (
        <div className="mt-4 border-l border-line pl-4">
          {item.comments.length > 0 && (
            <ul className="mb-3 space-y-2.5">
              {item.comments.map((c) => (
                <li key={c.id} className="text-sm">
                  <span className="text-ink">{c.authorName}</span> <span className="text-muted">{c.body}</span>
                </li>
              ))}
            </ul>
          )}
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (me) addComment(item.id, me, draft);
              setDraft("");
            }}
            className="flex items-center gap-2"
          >
            <input
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder="Add a comment…"
              aria-label="Add a comment"
              className="flex-1 border-b border-line-strong bg-transparent pb-1.5 text-sm outline-none placeholder:text-faint focus:border-ink"
            />
            <button
              type="submit"
              disabled={!draft.trim()}
              className={clsx(
                "min-h-11 shrink-0 text-xs uppercase tracking-[0.12em] transition-colors",
                draft.trim() ? "text-ink hover:text-accent" : "cursor-not-allowed text-faint",
              )}
            >
              Post
            </button>
          </form>
        </div>
      )}
    </li>
  );
}
