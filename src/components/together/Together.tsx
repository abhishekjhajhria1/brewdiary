"use client";

// Together — the hub.
//
// ── WHAT CHANGED, AND WHY ───────────────────────────────────────────────────
// This file used to be a two-level tab machine: four sections, seven rooms, all
// mounted in one route behind useState. Three things were wrong with that, and they
// were the reasons the section was hard to use:
//
//   1. Half the features were invisible. Cups, Recipes and the Board existed only if
//      you happened to tap "Play". A label with nothing behind it teaches you not to
//      tap it again.
//   2. Nothing ever said you were needed. Four pending queues sat in four rooms, so
//      the tab never had a reason to be opened.
//   3. Nothing was linkable. Rooms were state, not routes — you couldn't send anyone
//      your cup, and Back went to the calendar.
//
// So the rooms became real routes (/together/nights, /cups, /circles, /recipes,
// /to-try, /board) and this became a hub: one scroll, ordered by how much it wants
// you. Live now → waiting on you → your people → one button to start something →
// the rooms, each with a live digest → the feed.
//
// The ordering is the whole design. Anything that needs a decision from you is above
// anything that merely wants attention, and there is nothing here engineered to be
// checked — no unread state that never resolves, no streak on the social layer.
import Link from "next/link";
import { useEffect, useState } from "react";
import { useFeed, useFriends, type SocialProfile } from "@/lib/friends";
import { useAuth } from "@/lib/profile";
import { consumePendingPartyCode, joinParty } from "@/lib/parties";
import { People, FriendSheet } from "./People";
import { Feed } from "./Feed";
import { NeedsYou } from "./NeedsYou";
import { Tonight, WhosOut, Rooms } from "./Rooms";
import { StartSheet } from "./StartSheet";
import { NightComposer } from "./nights/NightComposer";

export function Together() {
  const me = useAuth().profile?.id;
  const { friends } = useFriends();
  const { feed, loading } = useFeed();
  const [openFriend, setOpenFriend] = useState<SocialProfile | null>(null);
  const [starting, setStarting] = useState(false);
  const [composingNight, setComposingNight] = useState(false);

  // A party link opened before signing in — honored here, on the hub itself, because
  // it's the one component guaranteed to mount when someone lands on Together.
  useEffect(() => {
    if (!me) return;
    const pending = consumePendingPartyCode();
    if (pending) joinParty(pending);
  }, [me]);

  return (
    <>
      <header className="mb-5 flex items-end justify-between border-b border-line pb-4">
        <h1 className="font-display text-5xl leading-none tracking-tight">Together</h1>
        <span className="label text-faint">
          {friends.length} {friends.length === 1 ? "friend" : "friends"}
        </span>
      </header>

      <p className="max-w-prose text-[15px] leading-relaxed text-muted">
        Your calendar stays yours and quiet. This is the other room — what friends are pouring, and what you&apos;re
        doing about it.
      </p>

      <WhosOut />

      {/* Live now, then anything that needs a decision. Both render nothing when
          there's nothing — the hub is quiet on a quiet week, by design. */}
      <Tonight />
      <NeedsYou />

      <button
        onClick={() => setStarting(true)}
        className="mt-6 flex h-12 w-full items-center justify-center gap-2 rounded-ctl bg-ink text-base font-medium text-paper transition-opacity hover:opacity-90"
      >
        <span aria-hidden className="text-lg leading-none">
          +
        </span>
        Start something
      </button>

      <People friends={friends} onOpenFriend={setOpenFriend} />

      <Rooms />

      <section className="mt-10">
        <p className="label mb-1 text-faint">The feed</p>
        <Feed feed={feed} loading={loading} hasFriends={friends.length > 0} onOpenFriend={setOpenFriend} />
      </section>

      {friends.length > 0 && (
        <Link
          href="/together/to-try"
          className="glass glass-press mt-10 flex items-center justify-between gap-4 rounded-tile p-4"
        >
          <div className="min-w-0">
            <p className="label mb-1 text-faint">To try</p>
            <p className="text-[15px] text-ink">Drinks friends poured that you haven&apos;t</p>
          </div>
          <span className="shrink-0 text-sm font-medium text-accent">Open →</span>
        </Link>
      )}

      {openFriend && <FriendSheet friend={openFriend} onClose={() => setOpenFriend(null)} />}
      {starting && <StartSheet onClose={() => setStarting(false)} onStartNight={() => setComposingNight(true)} />}
      {composingNight && <NightComposer onClose={() => setComposingNight(false)} />}
    </>
  );
}
