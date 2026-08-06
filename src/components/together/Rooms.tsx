"use client";

// The hub's two live sections: what's on TONIGHT, and the rooms with a digest on each.
//
// ── WHY A DIGEST ────────────────────────────────────────────────────────────
// The old tab rail said "Cups" and nothing else, forever. A label with no state is a
// door with no window: you have to open it to find out whether anything is behind it,
// and after two empty openings you stop. Each tile now carries the one live fact that
// makes it worth (or not worth) a tap — how many are asking, where you stand, how many
// days are left.
//
// Every digest counts NIGHTS, PEOPLE or DAYS. None counts drinks, rounds or money —
// a tile that said "14 drinks this month" would turn the hub into a scoreboard for
// consumption, which is the one thing this product refuses.
import Link from "next/link";
import clsx from "clsx";
import { useMyNights, groupNights, prettyTime, type Night } from "@/lib/nights";
import { useMyCups } from "@/lib/cups";
import { useCircles } from "@/lib/circles";
import { useWishlist } from "@/lib/wishlist";
import { useCompeteVisible } from "@/lib/points";
import { useVenueName } from "@/lib/reservations";
import { useFeed } from "@/lib/friends";
import { todayKey } from "@/lib/date";
import { prettyDate } from "./nights/pickers";

// ── TONIGHT ──────────────────────────────────────────────────────────────────
// The "is anything happening" glance. Shows the night that's on now, else the next
// one up. Never more than two rows — this is a glance, not a second list.
export function Tonight() {
  const { nights, loading } = useMyNights();
  if (loading) return null;

  const { tonight, upcoming } = groupNights(nights);
  const rows = tonight.length > 0 ? tonight.slice(0, 2) : upcoming.slice(0, 1);
  if (rows.length === 0) return null;

  const live = tonight.length > 0;

  return (
    <section className="mt-6">
      <p className={clsx("label mb-2", live ? "text-accent" : "text-faint")}>{live ? "Tonight" : "Next up"}</p>
      <ul className="space-y-2">
        {rows.map((n) => (
          <li key={n.id}>
            <TonightRow night={n} live={live} />
          </li>
        ))}
      </ul>
    </section>
  );
}

function TonightRow({ night, live }: { night: Night; live: boolean }) {
  const venueName = useVenueName(night.venueId ?? null);
  const place = venueName ?? night.city;
  const when = prettyTime(night.time);

  return (
    <Link
      href={`/together/night/${night.id}`}
      className={clsx(
        "glass glass-press flex items-center justify-between gap-3 rounded-tile px-4 py-3.5",
        live && "ring-1 ring-accent/25",
      )}
    >
      <span className="min-w-0">
        <span className="block truncate text-[15px] text-ink">{night.title}</span>
        <span className="mt-0.5 block truncate text-xs text-faint">
          {live ? (
            <>
              {when && <span className="tnum">{when}</span>}
              {when && place && " · "}
              {place}
              {!when && !place && "on now"}
            </>
          ) : (
            <>
              <span className="tnum">{prettyDate(night.date)}</span>
              {when && <span className="tnum"> · {when}</span>}
              {place && ` · ${place}`}
            </>
          )}
        </span>
      </span>
      <span className="shrink-0 text-sm font-medium text-accent">{live ? "Open →" : "→"}</span>
    </Link>
  );
}

// ── WHO'S OUT ────────────────────────────────────────────────────────────────
// Friends who logged something today. Derived from the feed you can already see —
// no new read, no presence tracking, nobody's location. A name only appears because
// that person chose to share an entry with friends.
export function WhosOut() {
  const { feed, loading } = useFeed();
  if (loading) return null;

  const today = todayKey();
  const names: string[] = [];
  for (const item of feed) {
    if (item.date !== today) continue;
    if (!names.includes(item.author.name)) names.push(item.author.name);
  }
  if (names.length === 0) return null;

  const shown = names.slice(0, 4);
  const rest = names.length - shown.length;

  return (
    <p className="mt-4 text-sm leading-relaxed text-muted">
      <span className="text-faint">Out tonight · </span>
      {shown.join(", ")}
      {rest > 0 && <span className="text-faint"> +{rest} more</span>}
    </p>
  );
}

// ── THE ROOMS ────────────────────────────────────────────────────────────────
interface Room {
  href: string;
  label: string;
  digest?: string;
  /** Something is waiting on you in there — worth the amber. */
  urgent?: boolean;
}

export function Rooms() {
  const { nights } = useMyNights();
  const { cups } = useMyCups();
  const { circles } = useCircles();
  const wishlist = useWishlist();
  const { competeVisible } = useCompeteVisible();

  const today = todayKey();
  const { tonight, upcoming } = groupNights(nights);
  const asking = nights.reduce((n, x) => n + x.pending, 0);
  const liveCups = cups.filter((c) => c.endsOn >= today);
  const closing = liveCups
    .map((c) => Math.round((new Date(c.endsOn).getTime() - new Date(today).getTime()) / 86_400_000))
    .filter((d) => d >= 0)
    .sort((a, b) => a - b)[0];

  const rooms: Room[] = [
    {
      href: "/together/nights",
      label: "Nights",
      urgent: asking > 0,
      digest:
        asking > 0
          ? `${asking} asking to come`
          : tonight.length > 0
            ? "on tonight"
            : upcoming.length > 0
              ? `${upcoming.length} coming up`
              : "nothing on yet",
    },
    {
      href: "/together/cups",
      label: "Cups",
      digest:
        liveCups.length === 0
          ? "none running"
          : closing === 0
            ? "ends today"
            : closing === 1
              ? "1 day left"
              : `${closing} days left`,
    },
    {
      href: "/together/circles",
      label: "Circles",
      digest: circles.length === 0 ? "none yet" : `${circles.length}`,
    },
    { href: "/together/recipes", label: "Recipes", digest: "friends' inventions" },
    {
      href: "/together/to-try",
      label: "To try",
      digest: wishlist.length === 0 ? "nothing saved" : `${wishlist.length} saved`,
    },
    { href: "/split", label: "Split", digest: "a tab or a round" },
  ];

  if (competeVisible) rooms.push({ href: "/together/board", label: "Board", digest: "you and friends" });

  return (
    <section className="mt-8">
      <p className="label mb-2 text-faint">Rooms</p>
      <ul className="grid grid-cols-2 gap-2">
        {rooms.map((r) => (
          <li key={r.href}>
            <Link
              href={r.href}
              className="glass glass-press flex min-h-[74px] flex-col justify-between rounded-tile px-4 py-3"
            >
              <span className="text-[15px] text-ink">{r.label}</span>
              {r.digest && (
                <span className={clsx("mt-1 truncate text-xs", r.urgent ? "text-accent" : "text-faint")}>
                  {r.digest}
                </span>
              )}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
