"use client";

// Plans — the "pre-plan a night, let people join" room inside Together.
//
// Two halves: COMING UP (plans I'm allowed to see, and can ask to join) and MINE
// (plans I host, where I approve who comes). A plan is only ever visible to friends
// or friends-of-friends — there's no public/stranger option, and the database
// enforces that, not this file.
//
// SAFETY is first-class in the UI, not an afterthought: every person carries a quiet
// "block / report" affordance, join is a request the host approves (never automatic),
// and "fit" is shown as soft facts (mutual friends, shared taste) — never a rating.
import { useEffect, useMemo, useState } from "react";
import clsx from "clsx";
import { MONTH_NAMES, parseKey } from "@/lib/date";
import { useAuth } from "@/lib/profile";
import {
  useUpcomingPlans,
  useMyPlans,
  usePlanRequests,
  usePlanSignals,
  usePlanInvitees,
  createPlan,
  setPlanStatus,
  deletePlan,
  requestJoin,
  respondJoin,
  withdrawJoin,
  inviteToPlan,
  uninviteFromPlan,
  searchUsers,
  respondInvite,
  type Plan,
  type MyPlan,
  type JoinPolicy,
} from "@/lib/plans";
import { blockUser, reportUser, REPORT_REASONS, type ReportReason } from "@/lib/safety";
import { useMySanction } from "@/lib/moderation";
import { useVenueDirectory, useVenueName, type DirectoryVenue } from "@/lib/reservations";
import { BookTable } from "../discover/PartnerOffers";

// The visibility tiers, most-private first. 'private' keeps a night to yourself;
// 'invite' opens it only to specific friends you name; then the graph tiers.
const POLICIES: { id: JoinPolicy; label: string; hint: string }[] = [
  { id: "private", label: "Only me", hint: "A private note on your calendar — no one else sees it." },
  { id: "invite", label: "Specific friends", hint: "Only the friends you pick can see it and ask to join." },
  { id: "friends", label: "Friends", hint: "Any of your friends can see it and ask to join." },
  { id: "fof", label: "Friends of friends", hint: "Friends, and their friends, can ask to join." },
];
const POLICY_LABEL: Record<JoinPolicy, string> = {
  private: "just me",
  invite: "invite only",
  friends: "friends",
  fof: "friends of friends",
};

const inputClass = "glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint";

function prettyDate(key: string): string {
  const dt = parseKey(key);
  const wd = dt.toLocaleDateString(undefined, { weekday: "short" });
  return `${wd} ${dt.getDate()} ${MONTH_NAMES[dt.getMonth()]}`;
}

/** "18:30" → "6:30 pm". Null for no time. */
function prettyTime(t?: string): string | null {
  if (!t) return null;
  const [h, m] = t.split(":");
  const hr = Number(h);
  if (Number.isNaN(hr)) return null;
  const ampm = hr < 12 ? "am" : "pm";
  const h12 = hr % 12 === 0 ? 12 : hr % 12;
  return `${h12}:${m ?? "00"} ${ampm}`;
}

interface PickedUser {
  id: string;
  name: string;
  handle: string;
}

// Type-a-name autocomplete over block/sanction-aware user search. Used to invite people
// by username (create form + the host's guest list). Debounced; picking clears the box.
function UserSearch({ onPick, exclude }: { onPick: (u: PickedUser) => void; exclude?: Set<string> }) {
  const [q, setQ] = useState("");
  const [results, setResults] = useState<PickedUser[]>([]);

  useEffect(() => {
    let active = true;
    if (q.trim().replace(/^@/, "").length < 2) {
      setResults([]);
      return;
    }
    const t = setTimeout(async () => {
      const r = await searchUsers(q);
      if (active) setResults(r);
    }, 250);
    return () => {
      active = false;
      clearTimeout(t);
    };
  }, [q]);

  const shown = exclude ? results.filter((u) => !exclude.has(u.id)) : results;

  return (
    <div>
      <input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Type a name or @handle"
        aria-label="Find a person to invite"
        className={inputClass}
      />
      {shown.length > 0 && (
        <ul className="glass mt-1 rounded-ctl p-1">
          {shown.map((u) => (
            <li key={u.id}>
              <button
                type="button"
                onClick={() => {
                  onPick(u);
                  setQ("");
                  setResults([]);
                }}
                className="flex w-full items-center justify-between gap-2 rounded-[7px] px-3 py-2 text-left text-sm text-muted transition-colors hover:bg-ink/5 hover:text-ink"
              >
                <span className="truncate">{u.name}</span>
                <span className="shrink-0 text-xs text-faint">@{u.handle}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

// Attach a real, verified brewdiary venue to a plan. Debounced search over the
// public venue directory; picking one sets it, and it can be cleared. Optional —
// a plan is still just as valid with only a free-text city.
function VenueSearch({ picked, onPick }: { picked: DirectoryVenue | null; onPick: (v: DirectoryVenue | null) => void }) {
  const [q, setQ] = useState("");
  const [debounced, setDebounced] = useState<string | null>(null);
  const { venues } = useVenueDirectory(debounced);

  useEffect(() => {
    if (picked || q.trim().length < 2) {
      setDebounced(null);
      return;
    }
    const t = setTimeout(() => setDebounced(q), 250);
    return () => clearTimeout(t);
  }, [q, picked]);

  if (picked) {
    return (
      <button
        type="button"
        onClick={() => {
          onPick(null);
          setQ("");
        }}
        aria-label={`Remove ${picked.name}`}
        className="inline-flex items-center gap-1.5 rounded-ctl bg-accent/10 px-3 py-2 text-sm text-ink transition-colors hover:bg-accent/15"
      >
        {picked.name}
        {picked.city && <span className="text-xs text-faint">{picked.city}</span>}
        <span aria-hidden className="text-muted">
          ×
        </span>
      </button>
    );
  }

  return (
    <div>
      <input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Search a bar on brewdiary (optional)"
        aria-label="Find a venue"
        className={inputClass}
      />
      {venues.length > 0 && (
        <ul className="glass mt-1 rounded-ctl p-1">
          {venues.map((v) => (
            <li key={v.id}>
              <button
                type="button"
                onClick={() => {
                  onPick(v);
                  setQ("");
                  setDebounced(null);
                }}
                className="flex w-full items-center justify-between gap-2 rounded-[7px] px-3 py-2 text-left text-sm text-muted transition-colors hover:bg-ink/5 hover:text-ink"
              >
                <span className="truncate">{v.name}</span>
                {v.city && <span className="shrink-0 text-xs text-faint">{v.city}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function Plans() {
  const [half, setHalf] = useState<"coming" | "mine">("coming");
  const [creating, setCreating] = useState(false);
  const sanction = useMySanction();

  return (
    <div className="mt-6">
      {sanction && <SanctionBanner sanction={sanction} />}
      <div className="mb-4 flex items-center justify-between gap-3">
        <div className="glass grid grid-cols-2 gap-1 rounded-ctl p-1">
          {(["coming", "mine"] as const).map((h) => (
            <button
              key={h}
              onClick={() => setHalf(h)}
              aria-pressed={half === h}
              className={clsx(
                "rounded-[7px] px-4 py-2 text-[11px] font-medium uppercase tracking-[0.12em] transition-colors",
                half === h ? "bg-ink text-paper" : "text-faint hover:text-ink",
              )}
            >
              {h === "coming" ? "Coming up" : "Mine"}
            </button>
          ))}
        </div>
        {!sanction && (
          <button
            onClick={() => setCreating((c) => !c)}
            className="shrink-0 rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90"
          >
            {creating ? "Close" : "Plan a night"}
          </button>
        )}
      </div>

      {creating && !sanction && <CreatePlan onDone={() => setCreating(false)} />}

      {half === "coming" ? <ComingUp /> : <Mine />}
    </div>
  );
}

// An honest banner instead of a silent RLS refusal: a limited account can still look,
// but can't create or join. We say so plainly, and when a suspension lifts, we say when.
function SanctionBanner({ sanction }: { sanction: { banned: boolean; suspendedUntil: string | null } }) {
  const until = sanction.suspendedUntil ? new Date(sanction.suspendedUntil) : null;
  const untilText = until && !Number.isNaN(until.getTime())
    ? until.toLocaleDateString(undefined, { month: "short", day: "numeric" })
    : null;
  return (
    <div className="glass mb-4 rounded-tile p-4">
      <p className="text-[15px] text-ink">
        {sanction.banned ? "Your account is limited." : "Your account is paused for now."}
      </p>
      <p className="mt-1 text-sm text-faint">
        You can still look around, but planning and joining are off
        {!sanction.banned && untilText ? ` until ${untilText}` : ""}. If you think this is a mistake, reach out through
        the help link.
      </p>
    </div>
  );
}

// ── COMING UP — plans I can see and ask to join ──────────────────────────────
function ComingUp() {
  const { plans, loading } = useUpcomingPlans();

  if (loading) {
    return (
      <ul className="space-y-3" aria-hidden>
        {[0, 1].map((i) => (
          <li key={i} className="glass h-36 animate-pulse rounded-tile" />
        ))}
      </ul>
    );
  }
  if (plans.length === 0) {
    return (
      <p className="mt-8 text-center text-sm leading-relaxed text-faint">
        No plans from your circle yet. When a friend (or a friend of a friend) plans a night, it shows up
        here — or start one yourself with “Plan a night”.
      </p>
    );
  }
  return (
    <ul className="space-y-3">
      {plans.map((p) => (
        <DiscoverCard key={p.id} plan={p} />
      ))}
    </ul>
  );
}

function DiscoverCard({ plan }: { plan: Plan }) {
  const me = useAuth().profile?.id;
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [menu, setMenu] = useState(false);
  const [booking, setBooking] = useState(false);
  const venueName = useVenueName(plan.venueId);
  const signals = usePlanSignals(plan.id);

  const full = plan.capacity != null && plan.going >= plan.capacity;
  const pending = plan.myStatus === "requested";
  const approved = plan.myStatus === "approved";
  const isInvite = plan.joinPolicy === "invite";

  async function ask() {
    setBusy(true);
    setErr(null);
    const e = await requestJoin(plan.id);
    setBusy(false);
    if (e) setErr(e);
  }
  async function leave() {
    setBusy(true);
    await withdrawJoin(plan.id);
    setBusy(false);
  }
  // Invite plans: the guest RSVPs directly (the host already chose them).
  async function rsvp(going: boolean) {
    setBusy(true);
    setErr(null);
    const e = await respondInvite(plan.id, going);
    setBusy(false);
    if (e) setErr(e);
  }

  return (
    <li className="glass rounded-tile p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-display text-xl leading-tight text-ink">{plan.title}</p>
          <p className="mt-0.5 text-xs text-faint">
            {prettyDate(plan.date)}
            {plan.time && <> · {prettyTime(plan.time)}</>}
            {plan.city && <> · {plan.city}</>} · {plan.hostName} <span className="text-faint">@{plan.hostHandle}</span>
          </p>
        </div>
        <PersonMenu
          open={menu}
          onToggle={() => setMenu((m) => !m)}
          subjectId={plan.hostId}
          subjectName={plan.hostName}
          planId={plan.id}
          disabled={plan.hostId === me}
        />
      </div>

      {plan.note && <p className="mt-3 text-[15px] leading-relaxed text-muted">{plan.note}</p>}

      {(plan.drinks.length > 0 || plan.vibeTags.length > 0) && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {plan.drinks.map((d) => (
            <span key={`d-${d}`} className="glass rounded-ctl px-2.5 py-1 text-xs text-muted">
              {d}
            </span>
          ))}
          {plan.vibeTags.map((t) => (
            <span key={`v-${t}`} className="rounded-ctl border border-line px-2.5 py-1 text-xs text-faint">
              {t}
            </span>
          ))}
        </div>
      )}

      {plan.venueId && (
        <div className="mt-3 flex items-center justify-between gap-3 rounded-ctl border border-line px-3 py-2">
          <span className="min-w-0 truncate text-sm text-ink">{venueName ?? "At a venue on brewdiary"}</span>
          <button
            onClick={() => setBooking(true)}
            className="shrink-0 text-xs uppercase tracking-[0.12em] text-accent transition-opacity hover:opacity-80"
          >
            Book a table
          </button>
        </div>
      )}

      <SoftSignals
        mutual={signals?.mutualFriends}
        sharedDrinks={signals?.sharedDrinks}
        verified={signals?.hostVerified}
        vouches={signals?.hostVouches}
        since={signals?.hostSince}
      />

      <div className="mt-4 flex items-center justify-between gap-3">
        <span className="text-xs text-faint">
          {plan.going} going{plan.capacity != null && <> · {Math.max(plan.capacity - plan.going, 0)} spots left</>}
        </span>
        {isInvite ? (
          approved ? (
            <span className="flex items-center gap-3 text-sm">
              <span className="text-accent">You&apos;re going</span>
              <button onClick={() => rsvp(false)} disabled={busy} className="text-faint transition-colors hover:text-ink">
                Can&apos;t make it
              </button>
            </span>
          ) : plan.myStatus === "declined" ? (
            <span className="flex items-center gap-3 text-sm">
              <span className="text-faint">Not going</span>
              <button onClick={() => rsvp(true)} disabled={busy || full} className="text-accent transition-opacity hover:opacity-80 disabled:opacity-50">
                Going
              </button>
            </span>
          ) : full ? (
            <span className="text-sm text-faint">Full</span>
          ) : (
            <span className="flex items-center gap-3 text-sm">
              <span className="text-muted">You&apos;re invited</span>
              <button onClick={() => rsvp(false)} disabled={busy} className="text-faint transition-colors hover:text-ink">
                Can&apos;t make it
              </button>
              <button
                onClick={() => rsvp(true)}
                disabled={busy}
                className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
              >
                {busy ? "…" : "Going"}
              </button>
            </span>
          )
        ) : approved ? (
          <span className="flex items-center gap-3 text-sm">
            <span className="text-accent">You&apos;re in</span>
            <button onClick={leave} disabled={busy} className="text-faint transition-colors hover:text-ink">
              Leave
            </button>
          </span>
        ) : pending ? (
          <span className="flex items-center gap-3 text-sm">
            <span className="text-muted">Asked · waiting</span>
            <button onClick={leave} disabled={busy} className="text-faint transition-colors hover:text-ink">
              Cancel
            </button>
          </span>
        ) : plan.myStatus === "declined" ? (
          <span className="text-sm text-faint">Not this time</span>
        ) : full ? (
          <span className="text-sm text-faint">Full</span>
        ) : (
          <button
            onClick={ask}
            disabled={busy}
            className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
          >
            {busy ? "…" : "Ask to join"}
          </button>
        )}
      </div>
      {err && <p className="mt-2 text-xs text-accent">{err}</p>}
      {booking && plan.venueId && (
        <BookTable
          group={{ venueId: plan.venueId, name: venueName ?? "the venue", offers: [] }}
          onClose={() => setBooking(false)}
        />
      )}
    </li>
  );
}

// Soft, factual comfort cues — never a score on a person.
function SoftSignals({
  mutual,
  sharedDrinks,
  verified,
  vouches,
  since,
}: {
  mutual?: number;
  sharedDrinks?: number;
  verified?: boolean;
  vouches?: number;
  since?: string;
}) {
  const bits: string[] = [];
  if (mutual && mutual > 0) bits.push(`${mutual} mutual friend${mutual === 1 ? "" : "s"}`);
  if (vouches && vouches > 0) bits.push(`${vouches} vouch${vouches === 1 ? "" : "es"}`);
  if (sharedDrinks && sharedDrinks > 0) bits.push(`${sharedDrinks} shared taste${sharedDrinks === 1 ? "" : "s"}`);
  if (since) {
    const yr = new Date(since).getFullYear();
    if (!Number.isNaN(yr)) bits.push(`on brewdiary since ${yr}`);
  }
  if (bits.length === 0 && !verified) return null;
  return (
    <p className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-faint">
      {verified && <span className="text-accent">✓ verified</span>}
      {verified && bits.length > 0 && <span aria-hidden>·</span>}
      {bits.join(" · ")}
    </p>
  );
}

// ── MINE — plans I host ──────────────────────────────────────────────────────
function Mine() {
  const { plans, loading } = useMyPlans();

  if (loading) {
    return (
      <ul className="space-y-3" aria-hidden>
        {[0, 1].map((i) => (
          <li key={i} className="glass h-32 animate-pulse rounded-tile" />
        ))}
      </ul>
    );
  }
  if (plans.length === 0) {
    return (
      <p className="mt-8 text-center text-sm leading-relaxed text-faint">
        You haven&apos;t planned a night yet. “Plan a night” up top — pick a day, say what you fancy, and let
        friends (or friends of friends) ask to come.
      </p>
    );
  }
  return (
    <ul className="space-y-3">
      {plans.map((p) => (
        <MyPlanCard key={p.id} plan={p} />
      ))}
    </ul>
  );
}

function MyPlanCard({ plan }: { plan: MyPlan }) {
  const [openReqs, setOpenReqs] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [booking, setBooking] = useState(false);
  const venueName = useVenueName(plan.venueId);
  const cancelled = plan.status === "cancelled";
  const isPrivate = plan.joinPolicy === "private";
  const isInvite = plan.joinPolicy === "invite";

  return (
    <li className={clsx("glass rounded-tile p-5", cancelled && "opacity-60")}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="font-display text-xl leading-tight text-ink">{plan.title}</p>
          <p className="mt-0.5 text-xs text-faint">
            {prettyDate(plan.date)}
            {plan.time && <> · {prettyTime(plan.time)}</>}
            {plan.city && <> · {plan.city}</>} · {POLICY_LABEL[plan.joinPolicy]}
          </p>
        </div>
        <span className={clsx("shrink-0 text-xs", cancelled ? "text-faint" : "text-muted")}>
          {cancelled
            ? "cancelled"
            : isPrivate
              ? "private"
              : plan.status === "closed"
                ? "closed"
                : `${plan.going} going`}
        </span>
      </div>

      {plan.note && <p className="mt-3 text-[15px] leading-relaxed text-muted">{plan.note}</p>}

      {plan.venueId && !cancelled && (
        <div className="mt-3 flex items-center justify-between gap-3 rounded-ctl border border-line px-3 py-2">
          <span className="min-w-0 truncate text-sm text-ink">{venueName ?? "At a venue on brewdiary"}</span>
          <button
            onClick={() => setBooking(true)}
            className="shrink-0 text-xs uppercase tracking-[0.12em] text-accent transition-opacity hover:opacity-80"
          >
            Book a table
          </button>
        </div>
      )}

      {isPrivate && !cancelled && (
        <p className="mt-3 text-sm text-faint">Only you can see this — a quiet note on your calendar.</p>
      )}

      {isInvite && !cancelled && <Guests planId={plan.id} />}

      {!cancelled && !isPrivate && (
        <button
          onClick={() => setOpenReqs((o) => !o)}
          className="mt-3 block text-sm text-accent transition-opacity hover:opacity-80"
        >
          {plan.pending > 0 ? `${plan.pending} waiting to join` : "Requests"} {openReqs ? "▴" : "▾"}
        </button>
      )}
      {openReqs && <Requests planId={plan.id} />}

      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-line pt-3 text-sm">
        {plan.status === "open" && (
          <button onClick={() => setPlanStatus(plan.id, "closed")} className="text-faint transition-colors hover:text-ink">
            Stop taking people
          </button>
        )}
        {plan.status === "closed" && (
          <button onClick={() => setPlanStatus(plan.id, "open")} className="text-faint transition-colors hover:text-ink">
            Reopen
          </button>
        )}
        {!cancelled && (
          <button onClick={() => setPlanStatus(plan.id, "cancelled")} className="text-faint transition-colors hover:text-ink">
            Call it off
          </button>
        )}
        {confirmDelete ? (
          <span className="flex items-center gap-3">
            <span className="text-muted">Delete for good?</span>
            <button onClick={() => deletePlan(plan.id)} className="font-medium text-accent hover:opacity-80">
              Delete
            </button>
            <button onClick={() => setConfirmDelete(false)} className="text-faint hover:text-ink">
              Keep
            </button>
          </span>
        ) : (
          <button onClick={() => setConfirmDelete(true)} className="text-faint transition-colors hover:text-ink">
            Delete
          </button>
        )}
      </div>
      {booking && plan.venueId && (
        <BookTable
          group={{ venueId: plan.venueId, name: venueName ?? "the venue", offers: [] }}
          onClose={() => setBooking(false)}
        />
      )}
    </li>
  );
}

function Requests({ planId }: { planId: string }) {
  const { requests, loading } = usePlanRequests(planId);
  const live = requests.filter((r) => r.status === "requested");
  const approved = requests.filter((r) => r.status === "approved");

  if (loading) return <p className="mt-2 text-xs text-faint">Loading…</p>;
  if (requests.length === 0) return <p className="mt-2 text-xs text-faint">No one has asked yet.</p>;

  return (
    <div className="mt-3 space-y-3">
      {live.length > 0 && (
        <ul className="space-y-2">
          {live.map((r) => (
            <li key={r.joinId} className="glass rounded-ctl p-3">
              <div className="flex items-start justify-between gap-3">
                <span className="min-w-0">
                  <span className="text-[15px] text-ink">{r.name}</span>{" "}
                  <span className="text-xs text-faint">@{r.handle}</span>
                  {r.message && <span className="mt-1 block text-sm text-muted">“{r.message}”</span>}
                </span>
                <span className="flex shrink-0 items-center gap-3 text-sm">
                  <button
                    onClick={() => respondJoin(r.joinId, true)}
                    className="font-medium text-accent transition-opacity hover:opacity-80"
                  >
                    Approve
                  </button>
                  <button
                    onClick={() => respondJoin(r.joinId, false)}
                    className="text-faint transition-colors hover:text-ink"
                  >
                    Decline
                  </button>
                </span>
              </div>
            </li>
          ))}
        </ul>
      )}
      {approved.length > 0 && (
        <p className="text-xs text-faint">
          Going: {approved.map((r) => r.name).join(", ")}
        </p>
      )}
    </div>
  );
}

// ── the guest list for an 'invite' plan (host adds anyone by username) ──────────
function Guests({ planId }: { planId: string }) {
  const [open, setOpen] = useState(false);
  const { invitees } = usePlanInvitees(open ? planId : null);
  const invitedIds = new Set(invitees.map((i) => i.userId));

  return (
    <div className="mt-3">
      <button onClick={() => setOpen((o) => !o)} className="block text-sm text-accent transition-opacity hover:opacity-80">
        Guests{invitees.length ? ` · ${invitees.length}` : ""} {open ? "▴" : "▾"}
      </button>
      {open && (
        <div className="mt-2 space-y-3">
          {invitees.length > 0 ? (
            <ul className="space-y-1.5">
              {invitees.map((g) => (
                <li key={g.userId} className="flex items-center justify-between gap-3 text-sm">
                  <span className="min-w-0 truncate">
                    <span className="text-ink">{g.name}</span> <span className="text-xs text-faint">@{g.handle}</span>
                  </span>
                  <button
                    onClick={() => uninviteFromPlan(planId, g.userId)}
                    className="shrink-0 text-faint transition-colors hover:text-ink"
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-xs text-faint">No one invited yet.</p>
          )}

          <div>
            <p className="mb-1.5 text-xs text-faint">Invite someone by name or @handle</p>
            <UserSearch exclude={invitedIds} onPick={(u) => inviteToPlan(planId, u.id)} />
          </div>
        </div>
      )}
    </div>
  );
}

// ── the quiet safety affordance on every person ──────────────────────────────
function PersonMenu({
  open,
  onToggle,
  subjectId,
  subjectName,
  planId,
  disabled,
}: {
  open: boolean;
  onToggle: () => void;
  subjectId: string;
  subjectName: string;
  planId?: string;
  disabled?: boolean;
}) {
  const me = useAuth().profile?.id;
  const [reporting, setReporting] = useState(false);
  const [done, setDone] = useState<string | null>(null);

  if (disabled) return null;

  return (
    <div className="relative shrink-0">
      <button
        onClick={onToggle}
        aria-label={`Options for ${subjectName}`}
        className="rounded-ctl px-2 py-1 text-lg leading-none text-faint transition-colors hover:text-ink"
      >
        ⋯
      </button>
      {open && (
        <div className="glass-strong absolute right-0 z-10 mt-1 w-44 rounded-ctl p-1 text-sm shadow-sm">
          {done ? (
            <p className="px-3 py-2 text-xs text-accent">{done}</p>
          ) : reporting ? (
            <ul>
              {REPORT_REASONS.map((r) => (
                <li key={r.id}>
                  <button
                    onClick={async () => {
                      if (me) await reportUser(me, subjectId, r.id as ReportReason, { planId });
                      setDone("Reported. Thank you — we'll look.");
                    }}
                    className="w-full rounded-[7px] px-3 py-2 text-left text-muted transition-colors hover:bg-ink/5 hover:text-ink"
                  >
                    {r.label}
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <ul>
              <li>
                <button
                  onClick={() => setReporting(true)}
                  className="w-full rounded-[7px] px-3 py-2 text-left text-muted transition-colors hover:bg-ink/5 hover:text-ink"
                >
                  Report
                </button>
              </li>
              <li>
                <button
                  onClick={async () => {
                    await blockUser(subjectId);
                    setDone("Blocked. You won't see each other.");
                  }}
                  className="w-full rounded-[7px] px-3 py-2 text-left text-muted transition-colors hover:bg-ink/5 hover:text-ink"
                >
                  Block {subjectName}
                </button>
              </li>
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

// ── create ───────────────────────────────────────────────────────────────────
function CreatePlan({ onDone }: { onDone: () => void }) {
  const me = useAuth().profile?.id;
  const [title, setTitle] = useState("");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [city, setCity] = useState("");
  const [venue, setVenue] = useState<DirectoryVenue | null>(null);
  const [note, setNote] = useState("");
  const [drinks, setDrinks] = useState("");
  const [policy, setPolicy] = useState<JoinPolicy>("friends");
  const [invited, setInvited] = useState<PickedUser[]>([]);
  const [cap, setCap] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // Computed post-mount so there's no SSR/client hydration mismatch on the date max.
  const today = useMemo(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }, []);

  const isPrivate = policy === "private";
  const isInvite = policy === "invite";

  function addInvite(u: PickedUser) {
    setInvited((prev) => (prev.some((x) => x.id === u.id) ? prev : [...prev, u]));
  }
  function removeInvite(id: string) {
    setInvited((prev) => prev.filter((x) => x.id !== id));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!me) return;
    setBusy(true);
    setErr(null);
    const res = await createPlan(me, {
      title,
      date,
      time: time || undefined,
      city,
      note,
      drinks: drinks.split(",").map((s) => s.trim()).filter(Boolean),
      joinPolicy: policy,
      capacity: isPrivate || !cap ? undefined : Number(cap),
      venueId: venue?.id,
    });
    if ("error" in res) {
      setBusy(false);
      setErr(res.error);
      return;
    }
    // Invite the chosen people now that the plan exists (server re-checks each).
    if (isInvite && invited.length > 0) {
      await Promise.all(invited.map((u) => inviteToPlan(res.id, u.id)));
    }
    setBusy(false);
    onDone();
  }

  return (
    <form onSubmit={submit} className="glass mb-4 rounded-tile p-5">
      <p className="label mb-3 text-faint">Plan a night</p>
      <div className="space-y-2.5">
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="What's the plan?" className={inputClass} aria-label="Title" />
        <div className="flex gap-2">
          <input
            type="date"
            value={date}
            min={today}
            onChange={(e) => setDate(e.target.value)}
            className={clsx(inputClass, "flex-1")}
            aria-label="Date"
          />
          <input
            type="time"
            value={time}
            onChange={(e) => setTime(e.target.value)}
            className={clsx(inputClass, "w-32")}
            aria-label="Start time (optional)"
          />
        </div>
        <input value={city} onChange={(e) => setCity(e.target.value)} placeholder="City or area (optional)" className={inputClass} aria-label="City" />
        <div>
          <p className="mb-1.5 text-xs text-faint">At a venue? Pick a bar on brewdiary — friends can book a table there.</p>
          <VenueSearch picked={venue} onPick={setVenue} />
        </div>
        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="What do you fancy doing? (optional)"
          rows={2}
          className={clsx(inputClass, "resize-none")}
          aria-label="Note"
        />
        <input value={drinks} onChange={(e) => setDrinks(e.target.value)} placeholder="Drinks, comma-separated (optional)" className={inputClass} aria-label="Drinks" />

        <div>
          <p className="mb-1.5 text-xs text-faint">Who can see it</p>
          <div className="glass grid grid-cols-2 gap-1 rounded-ctl p-1">
            {POLICIES.map((o) => (
              <button
                key={o.id}
                type="button"
                onClick={() => setPolicy(o.id)}
                aria-pressed={policy === o.id}
                className={clsx(
                  "rounded-[7px] px-3 py-2 text-sm transition-colors",
                  policy === o.id ? "bg-ink text-paper" : "text-faint hover:text-ink",
                )}
              >
                {o.label}
              </button>
            ))}
          </div>
          <p className="mt-1.5 text-xs text-faint">
            {POLICIES.find((p) => p.id === policy)?.hint} No public or stranger option — on purpose.
          </p>
        </div>

        {isInvite && (
          <div className="space-y-2 rounded-ctl border border-line p-3">
            <p className="text-xs text-faint">Invite people by name or @handle</p>
            <UserSearch exclude={new Set(invited.map((u) => u.id))} onPick={addInvite} />
            {invited.length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {invited.map((u) => (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() => removeInvite(u.id)}
                    aria-label={`Remove ${u.name}`}
                    className="inline-flex items-center gap-1.5 rounded-ctl bg-ink px-2.5 py-1 text-xs text-paper transition-opacity hover:opacity-90"
                  >
                    {u.name}
                    <span aria-hidden>×</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        {!isPrivate && (
          <input
            type="number"
            min={1}
            max={50}
            value={cap}
            onChange={(e) => setCap(e.target.value)}
            placeholder="Max people (optional)"
            className={inputClass}
            aria-label="Capacity"
          />
        )}
      </div>

      {err && <p className="mt-2.5 text-sm text-accent">{err}</p>}

      <div className="mt-4 flex items-center gap-3">
        <button
          type="submit"
          disabled={busy || !title.trim() || !date}
          className="rounded-ctl bg-ink px-4 py-2.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "Creating…" : isPrivate ? "Save to my calendar" : "Create plan"}
        </button>
        <button type="button" onClick={onDone} className="text-sm text-faint transition-colors hover:text-ink">
          Cancel
        </button>
      </div>
    </form>
  );
}
