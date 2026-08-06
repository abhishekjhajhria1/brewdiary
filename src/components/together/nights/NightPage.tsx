"use client";

// NightPage — one page for the whole life of a night.
//
// There is no mode switch and no second screen: the CONTENT is the state, driven by
// the date alone.
//   upcoming → the invitation (who's coming, requests to let in, the share link)
//   tonight  → the live room  (RSVP, the shared log, the tally, points, house perks)
//   past     → the recap      (what everyone poured, the photo wall)
//
// The room half is not re-implemented here — it IS `PartyRoom`, mounted embedded so
// it drops its own header and delete footer and contributes only room-shaped things.
// A night only gets a room when it needs one (see lib/nights.openNightRoom), so most
// upcoming nights render the invitation alone.
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import clsx from "clsx";
import {
  useMyNights,
  useNightCode,
  openNightRoom,
  nightShareUrl,
  nightPhase,
  prettyTime,
  AUDIENCE_LABEL,
  type Night,
} from "@/lib/nights";
import {
  usePlanRequests,
  usePlanInvitees,
  usePlanSignals,
  useUpcomingPlans,
  respondJoin,
  requestJoin,
  withdrawJoin,
  inviteToPlan,
  uninviteFromPlan,
  setPlanStatus,
  deletePlan,
} from "@/lib/plans";
import { useVenueName } from "@/lib/reservations";
import { PartyRoom } from "../PartyRoom";
import { prettyDate, PersonMenu, SoftSignals, UserSearch } from "./pickers";

export function NightPage({ nightId }: { nightId: string }) {
  const router = useRouter();
  const { nights, loading } = useMyNights();
  const { plans: visible } = useUpcomingPlans();

  const mine = nights.find((n) => n.id === nightId) ?? null;
  // A night I can SEE but haven't joined isn't in my_nights — it's in the visible
  // feed. Shaped into the same object so the page below doesn't care which it was.
  const seen = visible.find((p) => p.id === nightId);
  const night: Night | null =
    mine ??
    (seen
      ? {
          id: seen.id,
          hostId: seen.hostId,
          hostName: seen.hostName,
          title: seen.title,
          date: seen.date,
          time: seen.time,
          city: seen.city,
          venueId: seen.venueId,
          audience: seen.joinPolicy,
          status: "open",
          going: seen.going,
          pending: 0,
          partyId: seen.partyId,
          host: false,
        }
      : null);

  if (loading && !night) {
    return (
      <div className="space-y-3" aria-hidden>
        <div className="glass h-24 animate-pulse rounded-tile" />
        <div className="glass h-40 animate-pulse rounded-tile" />
      </div>
    );
  }

  if (!night) {
    return (
      <div className="mt-10 text-center">
        <p className="text-sm text-faint">This night isn&apos;t yours to see — maybe you left, or the link is stale.</p>
        <Link href="/together/nights" className="mt-4 inline-block text-sm font-medium text-accent hover:opacity-80">
          Back to your nights
        </Link>
      </div>
    );
  }

  const phase = nightPhase(night.date);
  const joinStatus = seen?.myStatus ?? null;

  return (
    <>
      <NightHeader night={night} phase={phase} />

      {night.host && <HostControls night={night} phase={phase} />}

      {!night.host && (
        <HostFacts hostId={night.hostId} hostName={night.hostName} nightId={night.id} />
      )}

      {!night.host && !mine && (
        <AskToCome nightId={night.id} status={joinStatus} audience={night.audience} />
      )}

      {night.partyId ? (
        <PartyRoom partyId={night.partyId} embedded />
      ) : (
        <NoRoomYet night={night} phase={phase} />
      )}

      <div className="mt-8 border-t border-line pt-5 text-sm">
        {night.host ? (
          <CallOff nightId={night.id} onGone={() => router.push("/together/nights")} />
        ) : mine ? (
          <button
            onClick={async () => {
              await withdrawJoin(night.id);
              router.push("/together/nights");
            }}
            className="text-faint transition-colors hover:text-ink"
          >
            I can&apos;t make it
          </button>
        ) : null}
      </div>
    </>
  );
}

// ── the header: what, when, where, and which part of its life it's in ────────
function NightHeader({ night, phase }: { night: Night; phase: ReturnType<typeof nightPhase> }) {
  const venueName = useVenueName(night.venueId ?? null);
  const place = venueName ?? night.city;
  const when = prettyTime(night.time);

  return (
    <header className="mb-6 border-b border-line pb-5">
      <p className="label mb-1 text-faint">
        {phase === "tonight" ? (
          <span className="text-accent">Tonight</span>
        ) : phase === "past" ? (
          "The recap"
        ) : (
          "Coming up"
        )}
        {!night.host && <span className="text-faint"> · {night.hostName}&apos;s</span>}
      </p>
      <h1 className="font-display text-4xl leading-tight tracking-tight">{night.title}</h1>
      <p className="mt-2 text-[15px] text-muted">
        <span className="tnum">{prettyDate(night.date)}</span>
        {when && <span className="tnum"> · {when}</span>}
        {place && (
          <>
            {" · "}
            <a
              href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(place)}`}
              target="_blank"
              rel="noopener noreferrer"
              className="underline decoration-line-strong underline-offset-4 transition-colors hover:text-ink"
            >
              {place}
            </a>
          </>
        )}
      </p>
      <p className="mt-1.5 text-xs text-faint">
        <span className="tnum">{night.going}</span> {night.going === 1 ? "person" : "people"} · for {AUDIENCE_LABEL[night.audience]}
      </p>
    </header>
  );
}

// ── who you'd be going out with ──────────────────────────────────────────────
// Facts, not a rating: mutual friends, shared taste, how long they've been here.
// Alongside them, the block/report menu — reachable before you commit to anything,
// which is the point of putting it here rather than in a settings screen.
function HostFacts({ hostId, hostName, nightId }: { hostId: string; hostName: string; nightId: string }) {
  const signals = usePlanSignals(nightId);
  const [menu, setMenu] = useState(false);

  return (
    <section className="mb-6 flex items-start justify-between gap-3 border-b border-line pb-5">
      <div className="min-w-0">
        <p className="label mb-1 text-faint">Hosted by</p>
        <p className="text-[15px] text-ink">{hostName}</p>
        <SoftSignals
          mutual={signals?.mutualFriends}
          sharedDrinks={signals?.sharedDrinks}
          verified={signals?.hostVerified}
          vouches={signals?.hostVouches}
          since={signals?.hostSince}
        />
      </div>
      <PersonMenu
        open={menu}
        onToggle={() => setMenu((m) => !m)}
        subjectId={hostId}
        subjectName={hostName}
        planId={nightId}
      />
    </section>
  );
}

// ── the host's half: who's asking, who's invited, the link ───────────────────
function HostControls({ night, phase }: { night: Night; phase: ReturnType<typeof nightPhase> }) {
  const { requests } = usePlanRequests(night.id);
  const waiting = requests.filter((r) => r.status === "requested");
  const [menu, setMenu] = useState<string | null>(null);

  return (
    <>
      {waiting.length > 0 && (
        <section className="mb-6">
          <p className="label mb-2 text-faint">
            Asking to come · <span className="tnum">{waiting.length}</span>
          </p>
          <ul className="space-y-2">
            {waiting.map((r) => (
              <li key={r.joinId} className="glass rounded-ctl px-4 py-2.5">
                <div className="flex items-center justify-between gap-3">
                  <span className="min-w-0 truncate text-[15px] text-ink">
                    {r.name} <span className="text-faint">@{r.handle}</span>
                  </span>
                  <span className="flex shrink-0 items-center gap-3 text-sm">
                    <button
                      onClick={() => respondJoin(r.joinId, true)}
                      className="min-h-9 font-medium text-accent transition-opacity hover:opacity-80"
                    >
                      Let in
                    </button>
                    <button
                      onClick={() => respondJoin(r.joinId, false)}
                      className="min-h-9 text-faint transition-colors hover:text-ink"
                    >
                      Not this time
                    </button>
                    <PersonMenu
                      open={menu === r.userId}
                      onToggle={() => setMenu((m) => (m === r.userId ? null : r.userId))}
                      subjectId={r.userId}
                      subjectName={r.name}
                      planId={night.id}
                    />
                  </span>
                </div>
                {r.message && <p className="mt-1 text-sm leading-relaxed text-muted">{r.message}</p>}
              </li>
            ))}
          </ul>
        </section>
      )}

      {night.audience === "invite" && phase !== "past" && <InviteList nightId={night.id} />}

      {night.audience !== "private" && phase !== "past" && <ShareLink night={night} />}
    </>
  );
}

// ── the named-guest list, for an invite-only night ───────────────────────────
function InviteList({ nightId }: { nightId: string }) {
  const { invitees } = usePlanInvitees(nightId);

  return (
    <section className="mb-6">
      <p className="label mb-2 text-faint">Invited</p>
      {invitees.length > 0 && (
        <ul className="mb-2 flex flex-wrap gap-1.5">
          {invitees.map((u) => (
            <li key={u.userId}>
              <button
                onClick={() => uninviteFromPlan(nightId, u.userId)}
                aria-label={`Uninvite ${u.name}`}
                className="glass glass-press inline-flex min-h-9 items-center gap-1.5 rounded-ctl px-3 py-1.5 text-sm text-ink"
              >
                {u.name}
                <span aria-hidden className="text-faint">
                  ×
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
      <UserSearch exclude={new Set(invitees.map((u) => u.userId))} onPick={(u) => inviteToPlan(nightId, u.id)} />
    </section>
  );
}

// ── the share link — created on demand, never before it's wanted ─────────────
function ShareLink({ night }: { night: Night }) {
  const code = useNightCode(night.partyId);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1600);
    return () => clearTimeout(t);
  }, [copied]);

  async function make() {
    setBusy(true);
    setErr(null);
    const r = await openNightRoom(night.id);
    setBusy(false);
    if ("error" in r) setErr(r.error);
  }

  if (!night.partyId) {
    return (
      <section className="mb-6">
        <button
          onClick={make}
          disabled={busy}
          className="glass glass-press flex w-full items-center justify-between gap-3 rounded-tile px-4 py-3.5 disabled:opacity-50"
        >
          <span className="min-w-0 text-left">
            <span className="block text-[15px] text-ink">{busy ? "Making a link…" : "Get a share link"}</span>
            <span className="mt-0.5 block text-xs leading-relaxed text-faint">
              For the group chat, and for people not on brewdiary. They still ask to come in.
            </span>
          </span>
          <span aria-hidden className="shrink-0 text-sm text-accent">
            →
          </span>
        </button>
        {err && (
          <p role="alert" className="mt-2 text-sm text-accent">
            {err}
          </p>
        )}
      </section>
    );
  }

  if (!code) return null;
  const url = nightShareUrl(code);

  return (
    <section className="glass mb-6 flex items-center justify-between gap-3 rounded-tile px-4 py-3">
      <div className="min-w-0">
        <p className="label mb-0.5 text-faint">Share link</p>
        <p className="tnum select-all truncate text-[15px] tracking-[0.14em] text-ink">{code}</p>
      </div>
      <span className="flex shrink-0 items-center gap-3 text-sm">
        <button
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(url);
              setCopied(true);
            } catch {}
          }}
          className={clsx(
            "min-h-9 transition-colors",
            copied ? "font-medium text-accent" : "text-muted hover:text-ink",
          )}
        >
          {copied ? "Copied" : "Copy link"}
        </button>
      </span>
    </section>
  );
}

// ── a night I can see but am not in yet ──────────────────────────────────────
function AskToCome({
  nightId,
  status,
  audience,
}: {
  nightId: string;
  status: string | null;
  audience: Night["audience"];
}) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [message, setMessage] = useState("");

  if (status === "requested") {
    return (
      <section className="glass mb-7 rounded-tile p-5 text-center">
        <p className="font-display text-xl text-ink">Your ask is in.</p>
        <p className="mt-1.5 text-sm text-muted">The host decides who comes — you&apos;ll see the night once they do.</p>
      </section>
    );
  }
  if (status === "declined") {
    return <p className="glass mb-7 rounded-tile p-5 text-center text-sm text-muted">Not this one. There&apos;ll be others.</p>;
  }

  return (
    <section className="glass mb-7 rounded-tile p-5">
      <p className="text-[15px] text-ink">Fancy it?</p>
      <p className="mt-1 text-sm leading-relaxed text-muted">
        {audience === "fof"
          ? "You can see this through a mutual friend. Ask, and the host decides."
          : "Ask to come along — the host decides."}
      </p>
      <input
        value={message}
        onChange={(e) => setMessage(e.target.value)}
        placeholder="Say hello (optional)"
        aria-label="A note for the host"
        className="glass mt-3 w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint"
      />
      <button
        onClick={async () => {
          setBusy(true);
          setErr(null);
          const e = await requestJoin(nightId, message);
          setBusy(false);
          if (e) setErr(e);
        }}
        disabled={busy}
        className="mt-3 flex h-11 w-full items-center justify-center rounded-ctl bg-ink text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
      >
        {busy ? "Asking…" : "Ask to come"}
      </button>
      {err && (
        <p role="alert" className="mt-2 text-sm text-accent">
          {err}
        </p>
      )}
    </section>
  );
}

// ── no room yet ──────────────────────────────────────────────────────────────
// A room is the live log + tally + points. It costs nothing to not have one, so an
// upcoming night says nothing at all about it. On the day, the host gets one button.
function NoRoomYet({ night, phase }: { night: Night; phase: ReturnType<typeof nightPhase> }) {
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  if (phase === "past") {
    return (
      <p className="text-sm leading-relaxed text-faint">
        No room was opened for this one, so there&apos;s nothing to look back on — it lives on in memory alone.
      </p>
    );
  }
  if (phase === "upcoming") return null;
  if (!night.host) {
    return <p className="text-sm text-faint">Waiting on the host to open the room for tonight.</p>;
  }

  return (
    <section>
      <button
        onClick={async () => {
          setBusy(true);
          setErr(null);
          const r = await openNightRoom(night.id);
          setBusy(false);
          if ("error" in r) setErr(r.error);
        }}
        disabled={busy}
        className="flex h-12 w-full items-center justify-center rounded-ctl bg-ink text-base font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
      >
        {busy ? "Opening…" : "Open the room"}
      </button>
      <p className="mt-2 text-xs leading-relaxed text-faint">
        The room is where tonight lands — what everyone pours, the round counter, the sparks. It becomes the recap
        tomorrow.
      </p>
      {err && (
        <p role="alert" className="mt-2 text-sm text-accent">
          {err}
        </p>
      )}
    </section>
  );
}

// ── calling it off ───────────────────────────────────────────────────────────
function CallOff({ nightId, onGone }: { nightId: string; onGone: () => void }) {
  const [confirming, setConfirming] = useState(false);

  if (!confirming) {
    return (
      <button onClick={() => setConfirming(true)} className="text-faint transition-colors hover:text-ink">
        Call it off
      </button>
    );
  }

  return (
    <span className="flex flex-wrap items-center gap-3">
      <span className="text-muted">Call it off for everyone?</span>
      <button
        onClick={async () => {
          await setPlanStatus(nightId, "cancelled");
          onGone();
        }}
        className="font-medium text-accent transition-opacity hover:opacity-80"
      >
        Call it off
      </button>
      <button
        onClick={async () => {
          await deletePlan(nightId);
          onGone();
        }}
        className="text-faint transition-colors hover:text-ink"
      >
        Delete it
      </button>
      <button onClick={() => setConfirming(false)} className="text-faint transition-colors hover:text-ink">
        Keep it
      </button>
    </span>
  );
}
