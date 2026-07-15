"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import clsx from "clsx";
import {
  useFeed,
  useFriends,
  useFriendRequests,
  useFriendEntries,
  searchUsers,
  sendRequest,
  acceptRequest,
  declineRequest,
  toggleCheers,
  addComment,
  type FeedEntry,
  type SocialProfile,
} from "@/lib/friends";
import { useAuth } from "@/lib/profile";
import { useCompeteVisible, useFriendsBoard } from "@/lib/points";
import { ScoreCard, type Score } from "../share/ScoreCard";
import { consumePendingPartyCode, joinParty } from "@/lib/parties";
import { useEntries } from "@/lib/store";
import { useWishlist, addWish } from "@/lib/wishlist";
import { friendPicks } from "@/lib/derive";
import { MONTH_NAMES, parseKey, timeOfDayLabel } from "@/lib/date";
import { RecentMosaic } from "./RecentMosaic";
import { useVouchedByMe, vouchFor, unvouch } from "@/lib/vouch";
import { VenueLink } from "../ui/VenueLink";
import { Circles } from "./Circles";
import { Parties } from "./Parties";
import { Plans } from "./Plans";

// The rooms inside Together. The feed leads; circles and parties wait behind
// their own segment instead of stacking into one overwhelming scroll. "Board"
// only exists for people who switched the leaderboard on in You → Settings.
type Room = "feed" | "plans" | "circles" | "parties" | "board";

const BASE_ROOMS: { id: Room; label: string }[] = [
  { id: "feed", label: "Feed" },
  { id: "plans", label: "Plans" },
  { id: "circles", label: "Circles" },
  { id: "parties", label: "Parties" },
];

export function Together() {
  const me = useAuth().profile?.id;
  const { friends } = useFriends();
  const { feed, loading } = useFeed();
  const { competeVisible } = useCompeteVisible();
  const [room, setRoom] = useState<Room>("feed");
  const [openFriend, setOpenFriend] = useState<SocialProfile | null>(null);

  const ROOMS = competeVisible ? [...BASE_ROOMS, { id: "board" as Room, label: "Board" }] : BASE_ROOMS;

  // If they switch the leaderboard back off while standing on it, don't strand them.
  useEffect(() => {
    if (room === "board" && !competeVisible) setRoom("feed");
  }, [room, competeVisible]);

  // A party link opened before signing in — honor it here, on Together itself:
  // the Parties component only mounts on its own tab, so it can't be trusted to run.
  useEffect(() => {
    if (!me) return;
    const pending = consumePendingPartyCode();
    if (pending) joinParty(pending);
  }, [me]);

  return (
    <>
      <header className="mb-6 flex items-end justify-between border-b border-line pb-4">
        <h1 className="font-display text-5xl leading-none tracking-tight">Together</h1>
        <span className="label text-faint">
          {friends.length} {friends.length === 1 ? "friend" : "friends"}
        </span>
      </header>

      <p className="max-w-prose text-[15px] leading-relaxed text-muted">
        Your calendar stays yours and quiet. This is the other room — what friends are pouring.
      </p>

      <div
        role="tablist"
        aria-label="Together rooms"
        className={clsx("glass mt-5 grid rounded-ctl p-1", ROOMS.length === 5 ? "grid-cols-5" : "grid-cols-4")}
      >
        {ROOMS.map((r, i) => (
          <button
            key={r.id}
            id={`room-tab-${r.id}`}
            role="tab"
            aria-selected={room === r.id}
            aria-controls="room-panel"
            tabIndex={room === r.id ? 0 : -1}
            onClick={() => setRoom(r.id)}
            onKeyDown={(e) => {
              // the ARIA tabs pattern: arrow keys move + focus the neighbor tab
              if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
              e.preventDefault();
              const delta = e.key === "ArrowRight" ? 1 : -1;
              const next = ROOMS[(i + delta + ROOMS.length) % ROOMS.length].id;
              setRoom(next);
              document.getElementById(`room-tab-${next}`)?.focus();
            }}
            className={clsx(
              "rounded-[7px] py-3.5 text-[11px] font-medium uppercase tracking-[0.14em] transition-colors",
              room === r.id ? "bg-ink text-paper" : "text-faint hover:text-ink",
            )}
          >
            {r.label}
          </button>
        ))}
      </div>

      <div role="tabpanel" id="room-panel" aria-labelledby={`room-tab-${room}`}>
      {room === "feed" && (
        <>
          <People friends={friends} onOpenFriend={setOpenFriend} />

          <FriendPicks feed={feed} />

          {friends.length === 0 ? (
            <p className="mt-10 text-center text-sm text-faint">
              Add a friend by their handle to see what they&apos;re pouring.
            </p>
          ) : loading ? (
            <ul className="mt-8 space-y-3" aria-hidden>
              {[0, 1, 2].map((i) => (
                <li key={i} className="glass h-28 animate-pulse rounded-tile" />
              ))}
            </ul>
          ) : feed.length === 0 ? (
            <p className="mt-10 text-center text-sm text-faint">
              Quiet so far — nothing shared to friends yet. Share an entry from your diary and it lands here.
            </p>
          ) : (
            <ul className="mt-8 space-y-3">
              {feed.map((item) => (
                <FeedCard key={item.id} item={item} onOpenFriend={setOpenFriend} />
              ))}
            </ul>
          )}
        </>
      )}

      {room === "plans" && <Plans />}

      {room === "circles" && <Circles />}

      {room === "parties" && <Parties />}

      {room === "board" && <FriendsBoard me={me} />}
      </div>

      <Link
        href="/split"
        className="mt-12 flex items-center justify-between border-t border-line pt-5 text-[15px] text-muted transition-colors hover:text-ink"
      >
        <span>Split a tab or a round with friends</span>
        <span className="shrink-0 text-sm font-medium text-accent">Split →</span>
      </Link>

      {openFriend && <FriendSheet friend={openFriend} onClose={() => setOpenFriend(null)} />}
    </>
  );
}

// ── the leaderboard: friends who ALSO opted in, ranked by sparks ─────────────
// Opt-in on both sides — friends who haven't switched it on simply aren't here,
// so nobody is ranked in front of their friends without asking. Never spend.
function FriendsBoard({ me }: { me?: string }) {
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
          className="mt-4 w-full rounded-ctl border border-line py-2.5 text-sm text-muted transition-colors hover:text-ink"
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

// ── people: requests + search + friend rail ──────────────────────────────────
function People({ friends, onOpenFriend }: { friends: SocialProfile[]; onOpenFriend: (f: SocialProfile) => void }) {
  const me = useAuth().profile?.id;
  const requests = useFriendRequests();
  const [adding, setAdding] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SocialProfile[]>([]);
  const [requested, setRequested] = useState<Set<string>>(new Set());
  const [searching, setSearching] = useState(false);

  // With no friends yet, the search IS the section — keep it open.
  const searchOpen = adding || friends.length === 0;

  // debounced search
  useEffect(() => {
    if (!me || query.trim().length < 2) {
      setResults([]);
      return;
    }
    setSearching(true);
    const t = setTimeout(async () => {
      const r = await searchUsers(query);
      setResults(r);
      setSearching(false);
    }, 300);
    return () => clearTimeout(t);
  }, [query, me]);

  async function add(id: string) {
    if (!me) return;
    setRequested((s) => new Set(s).add(id));
    const err = await sendRequest(me, id);
    if (err) {
      // request didn't land (e.g. already sent) — don't leave a misleading "Requested"
      setRequested((s) => {
        const n = new Set(s);
        n.delete(id);
        return n;
      });
    }
  }

  const friendIds = new Set(friends.map((f) => f.id));

  return (
    <section className="mt-6">
      {/* incoming requests */}
      {requests.length > 0 && (
        <div className="mb-5">
          <p className="label mb-3 text-faint">Friend requests</p>
          <ul className="space-y-2">
            {requests.map((r) => (
              <li key={r.friendshipId} className="glass flex items-center justify-between gap-3 rounded-ctl px-4 py-2.5">
                <span className="min-w-0 truncate text-[15px] text-ink">
                  {r.profile.name} <span className="text-faint">@{r.profile.handle}</span>
                </span>
                <span className="flex shrink-0 items-center gap-3 text-sm">
                  <button onClick={() => acceptRequest(r.friendshipId)} className="font-medium text-accent hover:opacity-80">
                    Accept
                  </button>
                  <button onClick={() => declineRequest(r.friendshipId)} className="text-faint hover:text-ink">
                    Ignore
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* friend rail + the add toggle */}
      <div className="flex items-center gap-5 overflow-x-auto pb-1">
        {friends.map((f) => (
          <button key={f.id} onClick={() => onOpenFriend(f)} className="flex shrink-0 flex-col items-center gap-2">
            <span className="glass glass-press flex h-12 w-12 items-center justify-center rounded-full font-display text-lg text-ink">
              {f.name[0]?.toUpperCase()}
            </span>
            <span className="text-xs text-muted">{f.name}</span>
          </button>
        ))}
        {friends.length > 0 && (
          <button
            onClick={() => {
              setAdding((v) => !v);
              setQuery("");
            }}
            aria-expanded={adding}
            className="flex shrink-0 flex-col items-center gap-2"
          >
            <span
              className={clsx(
                "glass glass-press flex h-12 w-12 items-center justify-center rounded-full text-lg transition-colors",
                adding ? "text-accent" : "text-muted",
              )}
            >
              +
            </span>
            <span className="text-xs text-muted">{adding ? "Close" : "Add"}</span>
          </button>
        )}
      </div>

      {/* add friends */}
      {searchOpen && (
        <div className="mt-4">
          <input
            autoFocus={adding}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Add a friend by name or @handle"
            className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] outline-none placeholder:text-faint"
          />
          {query.trim().length >= 2 && (
          <ul className="mt-2 space-y-2">
            {searching && results.length === 0 && <li className="px-1 text-sm text-faint">Searching…</li>}
            {!searching && results.length === 0 && <li className="px-1 text-sm text-faint">No one by that name or handle.</li>}
            {results.map((p) => {
              const isFriend = friendIds.has(p.id);
              const isRequested = requested.has(p.id);
              return (
                <li key={p.id} className="flex items-center justify-between gap-3 px-1">
                  <span className="min-w-0 truncate text-[15px] text-ink">
                    {p.name} <span className="text-faint">@{p.handle}</span>
                  </span>
                  <button
                    disabled={isFriend || isRequested}
                    onClick={() => add(p.id)}
                    className={clsx(
                      "shrink-0 text-sm transition-colors",
                      isFriend || isRequested ? "cursor-default text-faint" : "font-medium text-accent hover:opacity-80",
                    )}
                  >
                    {isFriend ? "Friends" : isRequested ? "Requested" : "Add"}
                  </button>
                </li>
              );
            })}
          </ul>
          )}
        </div>
      )}
    </section>
  );
}

// ── friend recommendations: "to try, from friends" ───────────────────────────
// The regulars half of the recommendation spec — drinks friends pour that you
// haven't logged, most-shared first, one tap to save to your to-try list.
function FriendPicks({ feed }: { feed: FeedEntry[] }) {
  const myEntries = useEntries();
  const wishlist = useWishlist();
  const [added, setAdded] = useState<Set<string>>(new Set());

  const picks = friendPicks(
    feed.map((f) => ({ drink: f.drink, author: f.author.id })),
    myEntries.map((e) => e.drink),
    wishlist.map((w) => w.drink),
    4,
  );
  if (picks.length === 0) return null;

  return (
    <section className="mt-8">
      <p className="label mb-3 text-faint">To try, from friends</p>
      <div className="flex flex-wrap gap-2">
        {picks.map((drink) => {
          const key = drink.toLowerCase();
          const isAdded = added.has(key);
          return (
            <button
              key={key}
              onClick={() => {
                addWish(drink);
                setAdded((s) => new Set(s).add(key));
              }}
              disabled={isAdded}
              className={clsx(
                "glass glass-press rounded-ctl px-3.5 py-2 text-sm transition-colors",
                isAdded ? "text-faint" : "text-ink hover:text-accent",
              )}
            >
              {drink} <span className={isAdded ? "text-faint" : "text-accent"}>{isAdded ? "✓" : "+"}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}

// ── feed card ─────────────────────────────────────────────────────────────────
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
          className={clsx("transition-colors", item.cheered ? "font-medium text-accent" : "text-muted hover:text-ink")}
        >
          {item.cheered ? "Cheered" : "Cheers"}
          {item.cheers > 0 && <span className="tnum"> {item.cheers}</span>}
        </button>

        <button onClick={() => setShowComments((v) => !v)} className="text-muted transition-colors hover:text-ink">
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
          className={clsx("ml-auto transition-colors", saved ? "text-faint" : "text-muted hover:text-accent")}
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
              className="flex-1 border-b border-line-strong bg-transparent pb-1.5 text-sm outline-none placeholder:text-faint focus:border-ink"
            />
            <button
              type="submit"
              disabled={!draft.trim()}
              className={clsx(
                "shrink-0 text-xs uppercase tracking-[0.12em] transition-colors",
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

function FriendSheet({ friend, onClose }: { friend: SocialProfile; onClose: () => void }) {
  const rows = useFriendEntries(friend.id);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const counts = new Map<string, number>();
  for (const r of rows) counts.set(r.date, (counts.get(r.date) ?? 0) + 1);
  const total = rows.length;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center" onClick={onClose}>
      <div className="absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div
        onClick={(e) => e.stopPropagation()}
        className="glass-strong animate-sheet relative max-h-[88dvh] w-full max-w-md overflow-y-auto rounded-t-[28px] p-6 sm:rounded-[28px] sm:p-8"
      >
        <div className="flex items-center gap-3">
          <span className="glass flex h-11 w-11 items-center justify-center rounded-full font-display text-lg text-ink">
            {friend.name[0]?.toUpperCase()}
          </span>
          <div>
            <h2 className="font-display text-2xl leading-none text-ink">{friend.name}</h2>
            <p className="mt-1 text-xs text-faint">
              @{friend.handle} · <span className="tnum">{total}</span> shared
            </p>
          </div>
          <button onClick={onClose} className="ml-auto text-sm text-faint transition-colors hover:text-ink">
            Close
          </button>
        </div>

        <p className="label mt-7 mb-3 text-faint">Their last 12 weeks</p>
        <RecentMosaic counts={counts} />

        <VouchRow friend={friend} />

        <p className="mt-6 text-xs text-faint">
          Peeking at a friend&apos;s mosaic — never their scores. Together is for the glance, not the scoreboard.
        </p>
      </div>
    </div>
  );
}

// Vouch for a friend — stake your word that they're a real person. It's OTHER-only
// (you can't vouch for yourself), a count and never a rating, and it nudges their
// trust standing up a little. Undoable.
function VouchRow({ friend }: { friend: SocialProfile }) {
  const me = useAuth().profile?.id;
  const vouched = useVouchedByMe();
  const [busy, setBusy] = useState(false);
  const has = vouched.has(friend.id);

  if (!me) return null;

  async function toggle() {
    if (!me || busy) return;
    setBusy(true);
    if (has) await unvouch(me, friend.id);
    else await vouchFor(me, friend.id);
    setBusy(false);
  }

  return (
    <div className="mt-6 border-t border-line pt-4">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-ink">Vouch for {friend.name}</p>
        <button
          onClick={toggle}
          disabled={busy}
          aria-pressed={has}
          className={clsx(
            "rounded-ctl px-3.5 py-1.5 text-sm font-medium transition-opacity disabled:opacity-50",
            has ? "glass text-muted" : "bg-ink text-paper hover:opacity-90",
          )}
        >
          {has ? "Vouched ✓" : "Vouch"}
        </button>
      </div>
      <p className="mt-1.5 text-xs leading-relaxed text-faint">
        Stake your word that they&apos;re a real person you know — it gently raises their standing. It&apos;s a count,
        never a rating, and you can undo it any time.
      </p>
    </div>
  );
}
