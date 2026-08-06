"use client";

// The people half of Together: the friend rail, adding someone by handle, and the
// sheet you get when you tap a friend. Lifted out of Together.tsx when that file
// stopped being a tab machine and became a hub — it was doing four unrelated jobs
// in one component, and this is one of them.
import { useEffect, useState } from "react";
import clsx from "clsx";
import {
  useFriendRequests,
  searchUsers,
  sendRequest,
  acceptRequest,
  declineRequest,
  useFriendEntries,
  type SocialProfile,
} from "@/lib/friends";
import { useAuth } from "@/lib/profile";
import { useVouchedByMe, vouchFor, unvouch } from "@/lib/vouch";
import { RecentMosaic } from "./RecentMosaic";

export function People({
  friends,
  onOpenFriend,
}: {
  friends: SocialProfile[];
  onOpenFriend: (f: SocialProfile) => void;
}) {
  const me = useAuth().profile?.id;
  const requests = useFriendRequests();
  const [adding, setAdding] = useState(false);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SocialProfile[]>([]);
  const [requested, setRequested] = useState<Set<string>>(new Set());
  const [searching, setSearching] = useState(false);

  // With no friends yet, the search IS the section — keep it open.
  const searchOpen = adding || friends.length === 0;

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
      {/* Incoming friend requests ALSO appear in "Needs you" above. They stay here
          too: this is where you come when you're thinking about people, and a request
          you've scrolled past shouldn't be findable in only one place. */}
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
                  <button
                    onClick={() => acceptRequest(r.friendshipId)}
                    className="min-h-11 font-medium text-accent hover:opacity-80"
                  >
                    Accept
                  </button>
                  <button
                    onClick={() => declineRequest(r.friendshipId)}
                    className="min-h-11 text-faint hover:text-ink"
                  >
                    Ignore
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

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

      {searchOpen && (
        <div className="mt-4">
          <input
            autoFocus={adding}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Add a friend by name or @handle"
            aria-label="Find a friend"
            className="glass w-full rounded-ctl px-4 py-2.5 text-[15px] outline-none placeholder:text-faint"
          />
          {query.trim().length >= 2 && (
            <ul className="mt-2 space-y-2">
              {searching && results.length === 0 && <li className="px-1 text-sm text-faint">Searching…</li>}
              {!searching && results.length === 0 && (
                <li className="px-1 text-sm text-faint">No one by that name or handle.</li>
              )}
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
                        "min-h-11 shrink-0 text-sm transition-colors",
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

export function FriendSheet({ friend, onClose }: { friend: SocialProfile; onClose: () => void }) {
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
          <button onClick={onClose} className="ml-auto min-h-11 text-sm text-faint transition-colors hover:text-ink">
            Close
          </button>
        </div>

        <p className="label mb-3 mt-7 text-faint">Their last 12 weeks</p>
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
            "min-h-11 rounded-ctl px-3.5 py-1.5 text-sm font-medium transition-opacity disabled:opacity-50",
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
