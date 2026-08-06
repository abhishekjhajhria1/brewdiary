"use client";

// Small shared pieces for anything that builds a NIGHT — the composer, the host's
// guest list, the older Plans room. They were private to Plans.tsx; the Nights
// restructure needs the same three in two more places, and a second copy of a
// people-search that must stay block- and sanction-aware is exactly the kind of
// duplicate that rots into a safety hole. So they live here, once.
import { useEffect, useState } from "react";
import { searchUsers } from "@/lib/plans";
import { useAuth } from "@/lib/profile";
import { blockUser, reportUser, REPORT_REASONS, type ReportReason } from "@/lib/safety";
import { useVenueDirectory, type DirectoryVenue } from "@/lib/reservations";
import { MONTH_NAMES, parseKey } from "@/lib/date";

export const inputClass = "glass w-full rounded-ctl px-4 py-2.5 text-[15px] text-ink placeholder:text-faint";

/** "Sat 14 March" — the way a person says a date out loud. */
export function prettyDate(key: string): string {
  const dt = parseKey(key);
  const wd = dt.toLocaleDateString(undefined, { weekday: "short" });
  return `${wd} ${dt.getDate()} ${MONTH_NAMES[dt.getMonth()]}`;
}

export interface PickedUser {
  id: string;
  name: string;
  handle: string;
}

/** Type-a-name autocomplete over the block/sanction-aware user search rpc. Debounced;
 *  picking clears the box. Never lists people on either side of a block — that check is
 *  the server's (`search_users`), not this component's. */
export function UserSearch({ onPick, exclude }: { onPick: (u: PickedUser) => void; exclude?: Set<string> }) {
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
                className="flex min-h-11 w-full items-center justify-between gap-2 rounded-[7px] px-3 py-2 text-left text-sm text-muted transition-colors hover:bg-ink/5 hover:text-ink"
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

/** Attach a real, verified brewdiary venue to a night. Optional — a night is just as
 *  valid with only a free-text city. Picking one is what lets friends book a table. */
export function VenueSearch({
  picked,
  onPick,
}: {
  picked: DirectoryVenue | null;
  onPick: (v: DirectoryVenue | null) => void;
}) {
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
        className="inline-flex min-h-11 items-center gap-1.5 rounded-ctl bg-accent/10 px-3 py-2 text-sm text-ink transition-colors hover:bg-accent/15"
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
                className="flex min-h-11 w-full items-center justify-between gap-2 rounded-[7px] px-3 py-2 text-left text-sm text-muted transition-colors hover:bg-ink/5 hover:text-ink"
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

/** Shown instead of the create/join controls while an account is limited. Says what
 *  is off and when it lifts — a dead button with no explanation is worse than a no. */
export function SanctionBanner({ sanction }: { sanction: { banned: boolean; suspendedUntil: string | null } }) {
  const until = sanction.suspendedUntil ? new Date(sanction.suspendedUntil) : null;
  const untilText =
    until && !Number.isNaN(until.getTime())
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

/** The quiet safety affordance that rides EVERY person shown anywhere in a night —
 *  a host looking at who asked in, a guest looking at the host. Report is one-way
 *  (the subject is never told), block is symmetric and immediate. This is not
 *  optional decoration: a friend-of-a-friend can still be someone you need away from,
 *  which is why it sits on the row itself and not three taps into a settings screen. */
export function PersonMenu({
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
        aria-expanded={open}
        className="min-h-11 rounded-ctl px-2 py-1 text-lg leading-none text-faint transition-colors hover:text-ink"
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
                    className="min-h-11 w-full rounded-[7px] px-3 py-2 text-left text-muted transition-colors hover:bg-ink/5 hover:text-ink"
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
                  className="min-h-11 w-full rounded-[7px] px-3 py-2 text-left text-muted transition-colors hover:bg-ink/5 hover:text-ink"
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
                  className="min-h-11 w-full rounded-[7px] px-3 py-2 text-left text-muted transition-colors hover:bg-ink/5 hover:text-ink"
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

/** Soft, factual comfort cues about a host — mutual friends, shared taste, how long
 *  they've been here. Deliberately NOT a score: there is no number that ranks a human
 *  anywhere in this app, and nothing here gates who may meet whom. */
export function SoftSignals({
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

/** A labelled field. The old create form used placeholders AS labels, which vanish the
 *  moment you type — this keeps the question visible while you answer it. */
export function Field({
  label,
  hint,
  optional,
  children,
  className,
}: {
  label: string;
  hint?: string;
  optional?: boolean;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={className}>
      <p className="label mb-1.5 text-faint">
        {label}
        {optional && <span className="ml-1.5 normal-case tracking-normal text-faint/70">optional</span>}
      </p>
      {children}
      {hint && <p className="mt-1.5 text-xs leading-relaxed text-faint">{hint}</p>}
    </div>
  );
}
