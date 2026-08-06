"use client";

// Nights — the room that lists your nights out.
//
// It replaces two rooms (Plans and Parties) with one list, ordered the way you
// actually care: what's on TONIGHT, then what's COMING UP, then the RECAPS. Under
// that sits what your friends have going that you could ask into.
//
// Everything here is a real, visible button — create, join, open — never a bare
// clickable line. That's the maintainer's standing discoverability rule, and it is
// most of why this section was hard to use.
import { useState } from "react";
import Link from "next/link";
import clsx from "clsx";
import { useAuth } from "@/lib/profile";
import { useMyNights, groupNights, prettyTime, type Night } from "@/lib/nights";
import { useUpcomingPlans, type Plan } from "@/lib/plans";
import { joinParty } from "@/lib/parties";
import { useMySanction } from "@/lib/moderation";
import { useVenueName } from "@/lib/reservations";
import { NightComposer } from "./NightComposer";
import { prettyDate, SanctionBanner, inputClass } from "./pickers";

export function Nights() {
  const me = useAuth().profile?.id;
  const { nights, loading } = useMyNights();
  const sanction = useMySanction();
  const [composing, setComposing] = useState(false);

  if (!me) return null;

  const { tonight, upcoming, past } = groupNights(nights);

  return (
    <section className="mt-6">
      {sanction && <SanctionBanner sanction={sanction} />}

      {!sanction && (
        <div className="mb-6 flex flex-wrap items-center gap-2">
          <button
            onClick={() => setComposing(true)}
            className="min-h-11 flex-1 rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90"
          >
            Start a night
          </button>
          <JoinByCode />
        </div>
      )}

      {loading ? (
        <ul className="space-y-2" aria-hidden>
          {[0, 1, 2].map((i) => (
            <li key={i} className="glass h-17.5 animate-pulse rounded-tile" />
          ))}
        </ul>
      ) : (
        <>
          {tonight.length > 0 && (
            <NightGroup label="Tonight" nights={tonight} live />
          )}
          {upcoming.length > 0 && <NightGroup label="Coming up" nights={upcoming} />}
          {past.length > 0 && <NightGroup label="Recaps" nights={past} muted />}

          {nights.length === 0 && (
            <div className="glass rounded-tile p-6 text-center">
              <p className="font-display text-2xl leading-tight text-ink">Nothing on yet.</p>
              <p className="mx-auto mt-2 max-w-[34ch] text-sm leading-relaxed text-muted">
                Start a night — a quiet one for yourself, a few friends, or a link you paste in the group chat. It
                becomes the room on the day, and the recap after.
              </p>
            </div>
          )}
        </>
      )}

      <FriendsNights />

      {composing && <NightComposer onClose={() => setComposing(false)} />}
    </section>
  );
}

function NightGroup({
  label,
  nights,
  live,
  muted,
}: {
  label: string;
  nights: Night[];
  live?: boolean;
  muted?: boolean;
}) {
  return (
    <div className="mb-7">
      <p className={clsx("label mb-2", live ? "text-accent" : "text-faint")}>{label}</p>
      <ul className="space-y-2">
        {nights.map((n) => (
          <li key={n.id}>
            <NightRow night={n} muted={muted} />
          </li>
        ))}
      </ul>
    </div>
  );
}

function NightRow({ night, muted }: { night: Night; muted?: boolean }) {
  const venueName = useVenueName(night.venueId ?? null);
  const place = venueName ?? night.city;
  const when = prettyTime(night.time);

  return (
    <Link
      href={`/together/night/${night.id}`}
      className="glass glass-press flex items-center justify-between gap-3 rounded-tile px-4 py-3.5"
    >
      <span className="min-w-0">
        <span className={clsx("block truncate text-[15px]", muted ? "text-muted" : "text-ink")}>{night.title}</span>
        <span className="mt-0.5 block truncate text-xs text-faint">
          <span className="tnum">{prettyDate(night.date)}</span>
          {when && <span className="tnum"> · {when}</span>}
          {place && ` · ${place}`}
          {!night.host && ` · ${night.hostName}'s`}
        </span>
      </span>
      <span className="flex shrink-0 items-center gap-2.5 text-xs">
        {night.pending > 0 && (
          <span className="tnum rounded-ctl bg-accent/15 px-2 py-1 font-medium text-ink">
            {night.pending} asking
          </span>
        )}
        <span className="tnum text-faint">{night.going} going</span>
      </span>
    </Link>
  );
}

// ── join by code — the other half of a shared link ───────────────────────────
function JoinByCode() {
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="glass glass-press min-h-11 shrink-0 rounded-ctl px-4 py-2.5 text-sm text-ink"
      >
        Join with a code
      </button>
    );
  }

  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        if (!code.trim() || busy) return;
        setBusy(true);
        setErr(null);
        const r = await joinParty(code);
        setBusy(false);
        if ("error" in r) setErr(r.error);
        else {
          setCode("");
          setOpen(false);
        }
      }}
      className="w-full"
    >
      <div className="flex items-center gap-2">
        <input
          autoFocus
          value={code}
          onChange={(e) => setCode(e.target.value)}
          placeholder="Paste the code"
          aria-label="Night code"
          className={clsx(inputClass, "min-w-0 flex-1")}
        />
        <button
          type="submit"
          disabled={!code.trim() || busy}
          className="min-h-11 shrink-0 rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "…" : "Join"}
        </button>
        <button
          type="button"
          onClick={() => {
            setOpen(false);
            setErr(null);
          }}
          className="min-h-11 shrink-0 px-1 text-sm text-faint transition-colors hover:text-ink"
        >
          Cancel
        </button>
      </div>
      {err && (
        <p role="alert" className="mt-2 px-1 text-sm text-accent">
          {err}
        </p>
      )}
    </form>
  );
}

// ── what friends have on that I could ask into ───────────────────────────────
// Only ever nights already visible to me under the join policy — the server decides
// that (upcoming_plans → plan_visible_to), never this component.
function FriendsNights() {
  const { plans, loading } = useUpcomingPlans();
  const open = plans.filter((p) => p.myStatus === null || p.myStatus === "withdrawn");

  if (loading || open.length === 0) return null;

  return (
    <div className="mt-2 border-t border-line pt-6">
      <p className="label mb-2 text-faint">Friends have these on</p>
      <ul className="space-y-2">
        {open.map((p) => (
          <li key={p.id}>
            <FriendNightRow plan={p} />
          </li>
        ))}
      </ul>
    </div>
  );
}

function FriendNightRow({ plan }: { plan: Plan }) {
  const venueName = useVenueName(plan.venueId ?? null);
  const place = venueName ?? plan.city;
  const when = prettyTime(plan.time);

  return (
    <Link
      href={`/together/night/${plan.id}`}
      className="glass glass-press flex items-center justify-between gap-3 rounded-tile px-4 py-3.5"
    >
      <span className="min-w-0">
        <span className="block truncate text-[15px] text-ink">{plan.title}</span>
        <span className="mt-0.5 block truncate text-xs text-faint">
          {plan.hostName} · <span className="tnum">{prettyDate(plan.date)}</span>
          {when && <span className="tnum"> · {when}</span>}
          {place && ` · ${place}`}
        </span>
      </span>
      <span className="shrink-0 text-sm font-medium text-accent">Ask →</span>
    </Link>
  );
}
