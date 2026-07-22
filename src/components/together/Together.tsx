"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
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
import { useEntries, addEntry } from "@/lib/store";
import { useWishlist, addWish, removeWish, type WishItem } from "@/lib/wishlist";
import { DRINKS, canonicalize, normalize } from "@/lib/drinks";
import { friendPicks } from "@/lib/derive";
import { MONTH_NAMES, parseKey, timeOfDayLabel, todayKey } from "@/lib/date";
import { RecentMosaic } from "./RecentMosaic";
import { DayCounters } from "../ui/DayCounters";
import { useVouchedByMe, vouchFor, unvouch } from "@/lib/vouch";
import { VenueLink } from "../ui/VenueLink";
import { Circles } from "./Circles";
import { Parties } from "./Parties";
import { Plans } from "./Plans";
import { Cups } from "./Cups";
import { Recipes } from "./Recipes";

// The rooms inside Together. Seven flat, sideways-scrolling tabs was an overload
// (mobile-nav research: keep top-level to ≤5, CLUSTER the rest into meaningful
// groups, most-used first). So the rooms now live under FOUR sections; two of them
// cluster related rooms behind a small secondary chip row.
//   Feed     — the social glance (leads).
//   Events   — going out: Plans + Parties.
//   Play     — the game layer: Cups + Recipes (+ Board, if opted in).
//   Circles  — private groups.
type Room = "feed" | "plans" | "circles" | "parties" | "cups" | "recipes" | "board";
type Group = "feed" | "events" | "play" | "circles";

const GROUPS: { id: Group; label: string; rooms: { id: Room; label: string }[] }[] = [
  { id: "feed", label: "Feed", rooms: [{ id: "feed", label: "Feed" }] },
  {
    id: "events",
    label: "Events",
    rooms: [
      { id: "plans", label: "Plans" },
      { id: "parties", label: "Parties" },
    ],
  },
  {
    id: "play",
    label: "Play",
    rooms: [
      { id: "cups", label: "Cups" },
      { id: "recipes", label: "Recipes" },
    ],
  },
  { id: "circles", label: "Circles", rooms: [{ id: "circles", label: "Circles" }] },
];

export function Together() {
  const me = useAuth().profile?.id;
  const { friends } = useFriends();
  const { feed, loading } = useFeed();
  const { competeVisible } = useCompeteVisible();
  const [group, setGroup] = useState<Group>("feed");
  // Remember the last room chosen inside each clustered section, so returning to
  // "Play" lands where you left it rather than always resetting to the first chip.
  const [subByGroup, setSubByGroup] = useState<Partial<Record<Group, Room>>>({});
  const [openFriend, setOpenFriend] = useState<SocialProfile | null>(null);

  // The leaderboard is an opt-in extra room inside Play — folded in only when the
  // user switched it on (You → Settings). Turning it off makes the derived `room`
  // below fall back to the first chip automatically — no stranding, no effect needed.
  const groups = useMemo(
    () =>
      competeVisible
        ? GROUPS.map((g) =>
            g.id === "play" ? { ...g, rooms: [...g.rooms, { id: "board" as Room, label: "Board" }] } : g,
          )
        : GROUPS,
    [competeVisible],
  );

  const activeGroup = groups.find((g) => g.id === group) ?? groups[0];
  const wanted = subByGroup[group];
  const room: Room = wanted && activeGroup.rooms.some((r) => r.id === wanted) ? wanted : activeGroup.rooms[0].id;
  const pickRoom = (r: Room) => setSubByGroup((s) => ({ ...s, [group]: r }));

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

      {/* Primary sections — four, fixed, no sideways scroll (they all fit a phone row). */}
      <div role="tablist" aria-label="Together sections" className="glass mt-5 grid grid-cols-4 gap-1 rounded-ctl p-1">
        {groups.map((g, i) => (
          <button
            key={g.id}
            id={`group-tab-${g.id}`}
            role="tab"
            aria-selected={group === g.id}
            aria-controls="room-panel"
            tabIndex={group === g.id ? 0 : -1}
            onClick={() => setGroup(g.id)}
            onKeyDown={(e) => {
              if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
              e.preventDefault();
              const delta = e.key === "ArrowRight" ? 1 : -1;
              const next = groups[(i + delta + groups.length) % groups.length].id;
              setGroup(next);
              document.getElementById(`group-tab-${next}`)?.focus();
            }}
            className={clsx(
              "min-h-11 rounded-[7px] px-1 py-2.5 text-center text-[11px] font-medium uppercase tracking-[0.08em] transition-colors",
              group === g.id ? "bg-ink text-paper" : "text-faint hover:text-ink",
            )}
          >
            {g.label}
          </button>
        ))}
      </div>

      {/* Secondary rooms — only for a section that clusters more than one. */}
      {activeGroup.rooms.length > 1 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {activeGroup.rooms.map((r) => (
            <button
              key={r.id}
              onClick={() => pickRoom(r.id)}
              aria-pressed={room === r.id}
              className={clsx(
                "min-h-9 rounded-ctl border px-4 py-1.5 text-xs font-medium transition-colors",
                room === r.id
                  ? "border-transparent bg-accent/10 text-ink"
                  : "border-line text-muted hover:border-line-strong hover:text-ink",
              )}
            >
              {r.label}
            </button>
          ))}
        </div>
      )}

      <div role="tabpanel" id="room-panel" aria-labelledby={`group-tab-${group}`} className="mt-4">
      {room === "feed" && (
        <>
          {/* Tonight's drink tallies (pegs, beers — enabled in You › Extras) live HERE,
              where a night out happens, not on the quiet calendar home. Each tap still
              writes a real diary entry; repeats never move a score or a board. */}
          <DayCounters dateKey={todayKey()} only={["pegs", "beers"]} className="mt-6" />

          <People friends={friends} onOpenFriend={setOpenFriend} />

          <FriendPicks feed={feed} />

          <ToTry />

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

      {room === "cups" && <Cups />}

      {room === "recipes" && <Recipes />}

      {room === "board" && <FriendsBoard me={me} />}
      </div>

      <Link
        href="/split"
        className="glass glass-press mt-12 flex items-center justify-between gap-4 rounded-tile p-4"
      >
        <div className="min-w-0">
          <p className="label mb-1 text-faint">Split</p>
          <p className="text-[15px] text-ink">Split a tab or a round with friends</p>
        </div>
        <span className="shrink-0 text-sm font-medium text-accent">Open →</span>
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

// ── your "to try" list ────────────────────────────────────────────────────────
// Your wishlist of drinks to get to. It lives HERE, in Together, right under the picks
// your friends inspire (FriendPicks) — the two feed each other: a friend pours something,
// you save it, it lands on this list. Add by hand, take one at random, or tap one to write
// it into the diary. Personal + local-or-remote via lib/wishlist (same API either way).
function ToTry() {
  const items = useWishlist();
  const entries = useEntries();
  const [draft, setDraft] = useState("");
  const [logging, setLogging] = useState<WishItem | null>(null);

  // Suggestions: every dictionary drink you haven't logged and haven't listed yet.
  // A stand-in for the personalised pick Ninkasi will make once the app matures — for
  // now a shuffle of what's known, and it never repeats something already yours, so
  // the top tile stays useful as the list below fills up.
  const suggestions = useMemo(() => {
    const seen = new Set<string>();
    for (const e of entries) seen.add(normalize(e.drink));
    for (const w of items) seen.add(normalize(w.drink));
    return DRINKS.map((d) => d.canonical).filter((name) => !seen.has(normalize(name)));
  }, [entries, items]);

  const [pick, setPick] = useState<string | null>(null);
  useEffect(() => {
    // Keep a valid pick: choose one initially, and re-choose if the current pick just
    // left the pool (you logged it or added it to the list).
    if (suggestions.length === 0) {
      setPick(null);
      return;
    }
    setPick((cur) => (cur && suggestions.includes(cur) ? cur : suggestions[Math.floor(Math.random() * suggestions.length)]));
  }, [suggestions]);

  function another() {
    if (suggestions.length === 0) return;
    setPick((cur) => {
      if (suggestions.length === 1) return suggestions[0];
      let n = cur;
      while (n === cur) n = suggestions[Math.floor(Math.random() * suggestions.length)];
      return n;
    });
  }

  return (
    <section className="mt-10">
      <p className="label mb-3 text-faint">To try, your list</p>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          addWish(draft);
          setDraft("");
        }}
        className="mb-3 flex items-center gap-2"
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Add a drink you're curious about…"
          className="flex-1 border-b border-line-strong bg-transparent pb-2 text-sm outline-none placeholder:text-faint focus:border-ink"
        />
        <button
          type="submit"
          disabled={!draft.trim()}
          className={clsx(
            "rounded-ctl px-3 py-1.5 text-xs uppercase tracking-[0.12em] transition-colors",
            draft.trim() ? "bg-ink text-paper hover:bg-ink/90" : "cursor-not-allowed bg-ink/10 text-faint",
          )}
        >
          Add
        </button>
      </form>

      {!pick && items.length === 0 ? (
        <p className="py-2 text-sm text-faint">Nothing to try yet — add a drink above, or save one from a friend&apos;s pour.</p>
      ) : (
        // Scrolls once it grows; the suggestion sits at the very top of the list.
        <ul className="glass max-h-80 divide-y divide-line overflow-y-auto rounded-tile px-5">
          {pick && (
            <li className="flex items-center justify-between gap-3 py-2.5">
              <div className="min-w-0">
                <p className="label text-faint">suggested</p>
                <p className="truncate text-[15px] text-ink">{pick}</p>
              </div>
              <div className="flex shrink-0 items-center gap-3">
                <button type="button" onClick={another} className="text-xs text-faint transition-colors hover:text-ink">
                  Another
                </button>
                <button
                  type="button"
                  onClick={() => addWish(pick)}
                  className="rounded-ctl bg-ink px-3 py-1.5 text-xs uppercase tracking-[0.12em] text-paper transition-colors hover:bg-ink/90"
                >
                  Add
                </button>
              </div>
            </li>
          )}
          {items.map((w) => (
            <li key={w.id} className="flex items-center justify-between gap-3 py-2.5">
              <button
                onClick={() => setLogging(w)}
                className="flex min-w-0 flex-1 items-center gap-2.5 text-left"
                aria-label={`Log ${w.drink} to your diary`}
              >
                <span
                  aria-hidden
                  className="flex h-4 w-4 shrink-0 items-center justify-center rounded-[3px] border border-line-strong text-[10px] leading-none text-transparent"
                >
                  ✓
                </span>
                <span className="truncate text-[15px] text-ink">{w.drink}</span>
              </button>
              <button
                onClick={() => removeWish(w.id)}
                aria-label={`Remove ${w.drink}`}
                className="shrink-0 text-sm text-faint transition-colors hover:text-ink"
              >
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}

      {logging && <LogWishPopup item={logging} onClose={() => setLogging(null)} />}
    </section>
  );
}

// Tapping a "to try" drink offers to write it into the diary — the calendar is the home,
// so trying something new belongs on a day. Pick the day (today by default); it logs the
// entry and takes the drink OFF the list. Kind is pre-derived from the name. Styled to
// match the log sheet so it feels like the rest of the app.
function LogWishPopup({ item, onClose }: { item: WishItem; onClose: () => void }) {
  const [date, setDate] = useState(todayKey());

  function log() {
    const canon = canonicalize(item.drink);
    addEntry({ date, drink: item.drink, type: canon.type });
    void removeWish(item.id); // logged → off the to-try list
    onClose();
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Log ${item.drink}`}
      className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
    >
      <button aria-label="Close" onClick={onClose} className="animate-fade absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div className="glass-strong animate-sheet relative w-full max-w-md rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4 sm:rounded-tile">
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong sm:hidden" />
        <p className="label text-faint">Log to your diary</p>
        <p className="mt-1 font-display text-3xl leading-none text-ink">{item.drink}</p>
        <label className="mt-5 block">
          <span className="mb-1.5 block text-xs text-muted">Which day</span>
          <input
            type="date"
            value={date}
            max={todayKey()}
            onChange={(e) => setDate(e.target.value)}
            className="glass w-full rounded-ctl px-4 py-3 text-[15px] text-ink"
          />
        </label>
        <button
          onClick={log}
          className="mt-5 flex h-12 w-full items-center justify-center rounded-ctl bg-ink text-base font-medium text-paper transition-opacity hover:opacity-90"
        >
          Log it
        </button>
        <button
          onClick={onClose}
          className="mt-2 flex h-11 w-full items-center justify-center rounded-ctl text-sm text-faint transition-colors hover:text-ink"
        >
          Cancel
        </button>
      </div>
    </div>
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
