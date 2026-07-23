"use client";

// The party page — before the night it's the invitation (RSVP, code, guest
// list); as entries get shared in it quietly becomes the recap: drink grid,
// attributed pours (never ranked), mood cloud, photo wall. One page, no mode
// switch — the content is the state.
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import clsx from "clsx";
import {
  usePartyDetail,
  setRsvp,
  leaveParty,
  deleteParty,
  approveGuest,
  declineGuest,
  type Rsvp,
  type PartyEntry,
  type PartyGuest,
} from "@/lib/parties";
import {
  usePointsBoard,
  awardCheckin,
  awardVibe,
  useHasCheckedIn,
  useRoomConsent,
  setRoomConsent,
} from "@/lib/points";
import { usePerkTiers, useQuietNights } from "@/lib/perks";
import { useExtras, setExtra } from "@/lib/features";
import { usePartyCatchUp } from "@/lib/autolog";
import { DayCounters } from "../ui/DayCounters";
import { useRoomStaff, thankStaff, KUDOS_REASONS } from "@/lib/kudos";
import { formatMoney } from "@/lib/money";
import { ScoreCard, type Score } from "../share/ScoreCard";
import { useAuth } from "@/lib/profile";
import { MONTH_NAMES, addDays, parseKey, timeOfDayLabel, toKey, todayKey } from "@/lib/date";

const RSVP_LABEL: Record<Rsvp, string> = { going: "Going", maybe: "Maybe", no: "Can't" };

// Positive-only, always — you can hand these to your table, never dock anyone.
const VIBE_REASONS = ["good sport", "great vibe", "kept it classy", "MVP"] as const;

export function PartyRoom({ partyId }: { partyId: string }) {
  const me = useAuth().profile?.id;
  const router = useRouter();
  const { party, guests, entries, loading } = usePartyDetail(partyId);
  const [copied, setCopied] = useState<"code" | "link" | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);

  useEffect(() => {
    if (copied) {
      const t = setTimeout(() => setCopied(null), 1600);
      return () => clearTimeout(t);
    }
  }, [copied]);

  if (loading) {
    return (
      <div className="space-y-3" aria-hidden>
        <div className="glass h-24 animate-pulse rounded-tile" />
        <div className="glass h-40 animate-pulse rounded-tile" />
      </div>
    );
  }
  if (!party) {
    return (
      <p className="mt-10 text-center text-sm text-faint">
        This party isn&apos;t yours to see — maybe you left, or the link is stale.
      </p>
    );
  }

  const d = parseKey(party.date);
  const past = party.date < todayKey();
  const mine = party.hostId === me;
  const meMember = guests.find((g) => g.id === me);
  const myRsvp = meMember?.rsvp;
  const iAmPending = !mine && meMember?.status === "pending";
  const approved = guests.filter((g) => g.status === "approved");
  const pending = guests.filter((g) => g.status === "pending");
  const coming = approved.filter((g) => g.rsvp === "going");
  const maybes = approved.filter((g) => g.rsvp === "maybe");

  async function copy(text: string, which: "code" | "link") {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(which);
    } catch {}
  }

  return (
    <>
      {/* header — name · date · venue → directions */}
      <header className="mb-6 border-b border-line pb-5">
        <p className="label mb-1 text-faint">{past ? "The recap" : "A party"}</p>
        <h1 className="font-display text-4xl leading-tight tracking-tight">{party.name}</h1>
        <p className="mt-2 text-[15px] text-muted">
          <span className="tnum">
            {MONTH_NAMES[d.getMonth()]} {d.getDate()}
          </span>
          {party.venue && (
            <>
              {" · "}
              <a
                href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(party.venue)}`}
                target="_blank"
                rel="noopener noreferrer"
                className="underline decoration-line-strong underline-offset-4 transition-colors hover:text-ink"
              >
                {party.venue}
              </a>
            </>
          )}
        </p>
      </header>

      {/* host: people asking to join via the shared link — you decide who comes in */}
      {mine && pending.length > 0 && (
        <section className="mb-6">
          <p className="label mb-2 text-faint">
            Requests to join · <span className="tnum">{pending.length}</span>
          </p>
          <ul className="space-y-2">
            {pending.map((g) => (
              <li key={g.id} className="glass flex items-center justify-between gap-3 rounded-ctl px-4 py-2.5">
                <span className="min-w-0 truncate text-[15px] text-ink">
                  {g.name} <span className="text-faint">@{g.handle}</span>
                </span>
                <span className="flex shrink-0 items-center gap-3 text-sm">
                  <button onClick={() => approveGuest(party.id, g.id)} className="font-medium text-accent hover:opacity-80">
                    Let in
                  </button>
                  <button onClick={() => declineGuest(party.id, g.id)} className="text-faint hover:text-ink">
                    Decline
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {iAmPending ? (
        // requested via the link — you can see the invitation, but nothing more until the host lets you in
        <section className="glass mb-7 rounded-tile p-5 text-center">
          <p className="font-display text-xl text-ink">Your request is in.</p>
          <p className="mt-1.5 text-sm text-muted">
            Waiting for the host to let you in — you&apos;ll see the night once they do.
          </p>
        </section>
      ) : (
        <>
          {/* rsvp + invite — quiet once the night has passed */}
          {!past && (
            <>
              <div className="mb-5 flex items-center gap-2">
                {(Object.keys(RSVP_LABEL) as Rsvp[]).map((r) => (
                  <button
                    key={r}
                    onClick={() => me && setRsvp(party.id, me, r)}
                    aria-pressed={myRsvp === r}
                    className={clsx(
                      "rounded-ctl px-4 py-2 text-sm transition-colors",
                      myRsvp === r ? "bg-ink font-medium text-paper" : "glass glass-press text-muted hover:text-ink",
                    )}
                  >
                    {RSVP_LABEL[r]}
                  </button>
                ))}
              </div>

              <div className="glass mb-7 flex items-center justify-between gap-3 rounded-tile px-4 py-3">
                <div className="min-w-0">
                  <p className="label mb-0.5 text-faint">Invite</p>
                  <p className="tnum select-all truncate text-[15px] tracking-[0.14em] text-ink">{party.inviteCode}</p>
                </div>
                <span className="flex shrink-0 items-center gap-3 text-sm">
                  <button
                    onClick={() => copy(party.inviteCode, "code")}
                    className={clsx("transition-colors", copied === "code" ? "font-medium text-accent" : "text-muted hover:text-ink")}
                  >
                    {copied === "code" ? "Copied" : "Copy code"}
                  </button>
                  <button
                    onClick={() => copy(`${location.origin}/p/${party.inviteCode}`, "link")}
                    className={clsx("transition-colors", copied === "link" ? "font-medium text-accent" : "text-muted hover:text-ink")}
                  >
                    {copied === "link" ? "Copied" : "Copy link"}
                  </button>
                </span>
              </div>
            </>
          )}

          {/* who's coming / who came */}
          <section className="mb-7">
            <p className="label mb-2 text-faint">{past ? "Who came" : "Who's coming"}</p>
            <p className="text-[15px] leading-relaxed text-ink">
              {coming.length === 0 ? (
                <span className="text-faint">No one yet{myRsvp !== "going" ? " — you could be first." : "."}</span>
              ) : (
                coming.map((g) => (g.id === me ? "you" : g.name)).join(", ")
              )}
              {maybes.length > 0 && (
                <span className="text-faint"> · maybe {maybes.map((g) => (g.id === me ? "you" : g.name)).join(", ")}</span>
              )}
            </p>
          </section>

          {/* the shared party log */}
          {entries.length === 0 ? (
            <p className="mb-7 text-sm text-faint">
              {past
                ? "Nothing was shared in — the night lives on in memory alone."
                : "As people log the night, what they share lands here — tap an entry in your diary, then Share."}
            </p>
          ) : (
            <PartyLog entries={entries} me={me} />
          )}

          {/* Tonight's tally — appears once the table is a group (2+ here) and it's
              actually tonight. A private per-person round counter (pegs/beers), the
              honest-logging half of "count while friends are together". */}
          {party.date === todayKey() && approved.length >= 2 && <PartyTally dateKey={party.date} />}

          {/* The catch-up log — if the tally went quiet for 2h after you'd been
              counting, one more of what you were drinking is added so the day isn't
              blank. Armed for tonight OR last night (you'll open the app the morning
              after), only for a real group, and always removable. */}
          <PartyCatchUp
            partyId={party.id}
            dateKey={party.date}
            enabled={
              approved.length >= 2 &&
              (party.date === todayKey() || party.date === toKey(addDays(parseKey(todayKey()), -1)))
            }
          />

          {/* Tonight's points — the opt-in loud corner. The pours above stay
              unranked; this is the game, and no one is ranked by what they spent. */}
          <PointsBoard partyId={party.id} partyName={party.name} members={approved} me={me} />

          {/* A venue room carries the house perk — your standing toward the reward. */}
          {party.venueId && me && <PerkCard venueId={party.venueId} me={me} date={party.date} />}

          {/* Only a venue has staff to thank, and a wall screen to be on. */}
          {party.venueId && <ThankStaff partyId={party.id} />}

          {party.venueId && me && <ScreenConsent partyId={party.id} me={me} />}
        </>
      )}

      {/* leave / delete */}
      <div className="mt-8 border-t border-line pt-5 text-sm">
        {mine ? (
          confirmDelete ? (
            <span className="flex items-center gap-3">
              <span className="text-muted">Delete for everyone?</span>
              <button
                onClick={async () => {
                  await deleteParty(party.id);
                  router.push("/together");
                }}
                className="font-medium text-accent hover:opacity-80"
              >
                Delete
              </button>
              <button onClick={() => setConfirmDelete(false)} className="text-faint hover:text-ink">
                Keep
              </button>
            </span>
          ) : (
            <button onClick={() => setConfirmDelete(true)} className="text-faint transition-colors hover:text-ink">
              Delete party
            </button>
          )
        ) : (
          <button
            onClick={async () => {
              if (me) await leaveParty(party.id, me);
              router.push("/together");
            }}
            className="text-faint transition-colors hover:text-ink"
          >
            {iAmPending ? "Cancel request" : "Leave party"}
          </button>
        )}
      </div>
    </>
  );
}

// ── tonight's tally: the shared-round counter, when friends are together ─────
// The "peg/beer counter, visible when 2+ friends are together" ask — built the ONLY
// way that survives rule #6: it is EACH PERSON'S OWN private tally on their OWN device,
// not a table leaderboard. Every tap writes a real diary entry (features.ts), so the
// round lands on your calendar AS YOU GO — there is nothing to "close out", and there
// is deliberately no "who drank most": a drink-volume race is the one mechanic this
// whole product refuses (it rewards drinking more, and it's how these nights turn ugly).
function PartyTally({ dateKey }: { dateKey: string }) {
  const extras = useExtras();
  const on = extras.pegs || extras.beers;

  return (
    <section className="mb-7">
      <p className="label mb-1.5 text-faint">Tonight&apos;s tally · your own</p>
      <p className="mb-3 max-w-prose text-xs leading-relaxed text-faint">
        A quiet counter for the round while you&apos;re together. Each tap lands on your own diary as you go —
        nothing to close out, and no one is ranked by it.
      </p>
      {on ? (
        <DayCounters dateKey={dateKey} only={["pegs", "beers"]} />
      ) : (
        <button
          onClick={() => {
            setExtra("pegs", true);
            setExtra("beers", true);
          }}
          className="glass glass-press rounded-ctl px-4 py-2.5 text-sm text-ink transition-colors hover:text-accent"
        >
          Keep count tonight
        </button>
      )}
    </section>
  );
}

// ── the catch-up notice: one auto-added drink after the night went quiet ─────
// See lib/autolog.ts for the honest limits. This is just its face: it appears only
// when something was actually added, and it's always one tap to undo.
function PartyCatchUp({ partyId, dateKey, enabled }: { partyId: string; dateKey: string; enabled: boolean }) {
  const { pending, keep, remove } = usePartyCatchUp(partyId, dateKey, enabled);
  if (!pending) return null;

  return (
    <section className="animate-fade mb-7">
      <div className="glass flex items-start justify-between gap-3 rounded-tile p-4">
        <div className="min-w-0">
          <p className="text-[15px] text-ink">
            Added a <span className="text-accent">{pending.drink}</span> for you.
          </p>
          <p className="mt-0.5 text-xs leading-relaxed text-faint">
            Your tally went quiet — so the night isn&apos;t left blank. If that&apos;s not right, remove it.
          </p>
        </div>
        <span className="flex shrink-0 items-center gap-3 text-sm">
          <button onClick={remove} className="text-faint transition-colors hover:text-accent">
            Remove
          </button>
          <button onClick={keep} className="font-medium text-accent transition-opacity hover:opacity-80">
            Keep
          </button>
        </span>
      </div>
    </section>
  );
}

// ── tonight's points: sparks (fun) + vibe (positive recognition) ─────────────
// Together's loud corner, opt-in. The board is DERIVED (party_points_board sums
// the ledger, counts only); vibe is positive-only and one-per-reason per person.
function PointsBoard({
  partyId,
  partyName,
  members,
  me,
}: {
  partyId: string;
  partyName: string;
  members: PartyGuest[];
  me?: string;
}) {
  const { board } = usePointsBoard(partyId);
  const [openVibe, setOpenVibe] = useState<string | null>(null);
  const [given, setGiven] = useState<Set<string>>(new Set());
  const [checkedIn, setCheckedIn] = useState(false);
  const [sharing, setSharing] = useState<Score | null>(null);

  // Merge every member with their totals (a member on 0 still shows), then rank.
  const byId = new Map(board.map((r) => [r.userId, r]));
  const rows = members
    .map((m) => ({
      id: m.id,
      name: m.id === me ? "you" : m.name,
      sparks: byId.get(m.id)?.sparks ?? 0,
      vibe: byId.get(m.id)?.vibe ?? 0,
      isMe: m.id === me,
    }))
    .sort((a, b) => b.sparks - a.sparks || b.vibe - a.vibe || a.name.localeCompare(b.name));
  const topSparks = Math.max(0, ...rows.map((r) => r.sparks));

  // Read check-in straight off the ledger — NOT "has any spark", since sparks can
  // arrive other ways. Survives a reload; the flag is just the optimistic head start.
  const alreadyCheckedIn = useHasCheckedIn(partyId, me);
  const myRank = rows.findIndex((r) => r.isMe);
  const isCheckedIn = checkedIn || alreadyCheckedIn;

  async function checkIn() {
    if (!me) return;
    setCheckedIn(true); // optimistic; award_checkin is idempotent for the day
    await awardCheckin(partyId);
  }

  async function give(subjectId: string, reason: string) {
    if (!me) return;
    const key = `${subjectId}:${reason}`;
    setGiven((s) => new Set(s).add(key));
    setOpenVibe(null);
    const err = await awardVibe(partyId, me, subjectId, reason);
    if (err)
      setGiven((s) => {
        const n = new Set(s);
        n.delete(key);
        return n;
      });
  }

  return (
    <section className="mb-7">
      <p className="label mb-1.5 text-faint">Tonight&apos;s points · opt-in</p>
      <p className="mb-3 max-w-prose text-xs leading-relaxed text-faint">
        Sparks are for trying something new — a new place, a new drink, a dry day. Coming back to your local doesn&apos;t
        score (that&apos;s what the house perk is for). Vibe is what your table and the bar hand you for good company.
      </p>

      <button
        onClick={checkIn}
        disabled={isCheckedIn}
        className={clsx(
          "glass glass-press rounded-ctl px-4 py-2.5 text-sm transition-colors",
          isCheckedIn ? "text-faint" : "text-ink hover:text-accent",
        )}
      >
        {isCheckedIn ? "Checked in" : "Check in"}
      </button>

      <ul className="mt-4 divide-y divide-line border-y border-line">
        {rows.map((r, i) => {
          const leads = r.sparks > 0 && r.sparks === topSparks;
          return (
            <li key={r.id} className="py-2.5">
              <div className="flex items-center justify-between gap-3">
                <span className="flex min-w-0 items-center gap-2.5">
                  <span className="tnum w-4 text-xs text-faint">{i + 1}</span>
                  <span className="truncate text-[15px] text-ink">{r.name}</span>
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
                  {!r.isMe && (
                    <button
                      onClick={() => setOpenVibe((cur) => (cur === r.id ? null : r.id))}
                      aria-expanded={openVibe === r.id}
                      className={clsx("transition-colors", openVibe === r.id ? "text-accent" : "text-faint hover:text-ink")}
                    >
                      Vibe
                    </button>
                  )}
                </span>
              </div>

              {openVibe === r.id && (
                <div className="mt-2.5 flex flex-wrap gap-1.5">
                  {VIBE_REASONS.map((reason) => {
                    const isGiven = given.has(`${r.id}:${reason}`);
                    return (
                      <button
                        key={reason}
                        disabled={isGiven}
                        onClick={() => give(r.id, reason)}
                        className={clsx(
                          "glass glass-press rounded-ctl px-3 py-2 text-xs transition-colors",
                          isGiven ? "text-faint" : "text-muted hover:text-accent",
                        )}
                      >
                        {reason}
                        {isGiven && " ✓"}
                      </button>
                    );
                  })}
                </div>
              )}
            </li>
          );
        })}
      </ul>

      {myRank >= 0 && (rows[myRank].sparks > 0 || rows[myRank].vibe > 0) && (
        <button
          onClick={() =>
            setSharing({
              name: "you",
              sparks: rows[myRank].sparks,
              vibe: rows[myRank].vibe,
              context: partyName,
              rank: myRank + 1,
              of: rows.length,
            })
          }
          className="mt-4 w-full rounded-ctl border border-line py-2.5 text-sm text-muted transition-colors hover:text-ink"
        >
          Share your score
        </button>
      )}

      {sharing && <ScoreCard score={sharing} onClose={() => setSharing(null)} />}
    </section>
  );
}

// ── thank the people who served you ─────────────────────────────────────────
// Positive-only, like everything else here: you can thank a bartender, you can
// never complain about one. And a manager never sees who was thanked how often —
// that would make this an employee-monitoring tool (GDPR: DPIA + works councils
// in seven EU states). It's a thank-you box, and it stays one.
function ThankStaff({ partyId }: { partyId: string }) {
  const staff = useRoomStaff(partyId);
  const [open, setOpen] = useState<string | null>(null);
  const [sent, setSent] = useState<Set<string>>(new Set());

  if (staff.length === 0) return null;

  async function say(staffId: string, reason: string) {
    const key = `${staffId}:${reason}`;
    setSent((s) => new Set(s).add(key));
    setOpen(null);
    const err = await thankStaff(partyId, staffId, reason);
    if (err)
      setSent((s) => {
        const n = new Set(s);
        n.delete(key);
        return n;
      });
  }

  return (
    <section className="mb-7">
      <p className="label mb-1.5 text-faint">Thank the bar</p>
      <p className="mb-3 max-w-prose text-xs leading-relaxed text-faint">
        Say thanks to whoever looked after you. They see it; their manager only ever sees that the team was
        thanked, never who by or how often. There&apos;s no way to complain about someone here — that&apos;s
        deliberate.
      </p>

      <ul className="divide-y divide-line border-y border-line">
        {staff.map((s) => (
          <li key={s.id} className="py-2.5">
            <div className="flex items-center justify-between gap-3">
              <span className="min-w-0 truncate text-[15px] text-ink">{s.name}</span>
              <button
                onClick={() => setOpen((cur) => (cur === s.id ? null : s.id))}
                aria-expanded={open === s.id}
                className={clsx("shrink-0 text-sm transition-colors", open === s.id ? "text-accent" : "text-faint hover:text-ink")}
              >
                Thank
              </button>
            </div>

            {open === s.id && (
              <div className="mt-2.5 flex flex-wrap gap-1.5">
                {KUDOS_REASONS.map((reason) => {
                  const done = sent.has(`${s.id}:${reason}`);
                  return (
                    <button
                      key={reason}
                      disabled={done}
                      onClick={() => say(s.id, reason)}
                      className={clsx(
                        "glass glass-press rounded-ctl px-3 py-2 text-xs transition-colors",
                        done ? "text-faint" : "text-muted hover:text-accent",
                      )}
                    >
                      {reason}
                      {done && " ✓"}
                    </button>
                  );
                })}
              </div>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

// ── consent to the bar's wall screen — FOR TONIGHT ONLY ─────────────────────
// Granted here, in the room you're actually standing in, and it expires with the
// night. Never a permanent global "put me on bar TVs" flag.
function ScreenConsent({ partyId, me }: { partyId: string; me: string }) {
  const { consent, loaded } = useRoomConsent(partyId);
  const [onBoard, setOnBoard] = useState(false);
  const [showTab, setShowTab] = useState(false);
  useEffect(() => {
    if (loaded) {
      setOnBoard(consent.onBoard);
      setShowTab(consent.showTab);
    }
  }, [loaded, consent.onBoard, consent.showTab]);

  function set(next: { onBoard: boolean; showTab: boolean }) {
    // A tab can never show for someone who isn't on the board.
    const tab = next.onBoard && next.showTab;
    setOnBoard(next.onBoard);
    setShowTab(tab);
    setRoomConsent(partyId, me, { onBoard: next.onBoard, showTab: tab });
  }

  return (
    <section className="mb-7">
      <p className="label mb-1.5 text-faint">The bar&apos;s screen · tonight only</p>

      <button
        onClick={() => set({ onBoard: !onBoard, showTab })}
        aria-pressed={onBoard}
        className={clsx(
          "glass glass-press w-full rounded-ctl px-4 py-3 text-left text-sm transition-colors",
          onBoard ? "text-ink" : "text-muted hover:text-ink",
        )}
      >
        <span className="flex items-center justify-between gap-3">
          <span>Show me on the screen</span>
          <span className={clsx("text-xs", onBoard ? "text-accent" : "text-faint")}>{onBoard ? "On" : "Off"}</span>
        </span>
      </button>

      {onBoard && (
        <button
          onClick={() => set({ onBoard, showTab: !showTab })}
          aria-pressed={showTab}
          className={clsx(
            "glass glass-press mt-2 w-full rounded-ctl px-4 py-3 text-left text-sm transition-colors",
            showTab ? "text-ink" : "text-muted hover:text-ink",
          )}
        >
          <span className="flex items-center justify-between gap-3">
            <span>…and show my tab</span>
            <span className={clsx("text-xs", showTab ? "text-accent" : "text-faint")}>{showTab ? "On" : "Off"}</span>
          </span>
        </button>
      )}

      <p className="mt-2 text-xs leading-relaxed text-faint">
        {onBoard
          ? "Your name and points are on the bar's screen until this night ends — then you're off it automatically."
          : "Nothing of yours is on the bar's screen. This choice is for this room only."}
      </p>
    </section>
  );
}

// ── house perks: the guest's standing on every TIER ─────────────────────────
// A venue can run several rewards now ("3 visits: a coffee. 10: a free pour"), and
// each is its OWN punch-card with its OWN clock — claiming the coffee doesn't wipe
// your progress toward the pour. Progress counts from YOUR LAST CLAIM OF THAT TIER,
// which is what stops one earn being claimed forever.
function PerkCard({ venueId, me, date }: { venueId: string; me?: string; date: string }) {
  const { tiers, loading } = usePerkTiers(venueId, me);
  const quietNights = useQuietNights(venueId);
  if (loading || tiers.length === 0) return null;

  // Postgres dow and JS getDay() agree: 0 = Sunday.
  const quietTonight = quietNights.includes(parseKey(date).getDay());
  const anyVisits = tiers.some((t) => t.kind === "visits");

  return (
    <section className="mb-7">
      <p className="label mb-2 text-faint">{tiers.length > 1 ? "House perks" : "House perk"}</p>

      <ul className="space-y-2">
        {tiers.map((t) => {
          const spend = t.kind === "spend";
          const left = Math.max(0, t.threshold - t.progress);
          const fmt = (n: number) => (spend ? formatMoney(n, t.currency, { round: true }) : `${n}`);

          return (
            <li key={t.id} className="glass rounded-tile p-4">
              {t.earned ? (
                <>
                  <p className="text-[15px] text-ink">
                    You&apos;ve earned <span className="font-medium text-accent">{t.reward}</span>.
                  </p>
                  <p className="mt-1 text-xs text-faint">
                    Ask the bar for it — they&apos;ll mark it claimed, and this one starts again from zero.
                  </p>
                </>
              ) : (
                <>
                  <p className="text-[15px] text-ink">{t.reward}</p>
                  <p className="mt-1 text-xs text-faint">
                    <span className="tnum">{fmt(t.progress)}</span> of <span className="tnum">{fmt(t.threshold)}</span>
                    {spend ? " — " : " visits — "}
                    {fmt(left)} to go.
                  </p>
                </>
              )}

              {t.claims > 0 && (
                <p className="mt-2 border-t border-line pt-2 text-xs text-faint">
                  Claimed {t.claims === 1 ? "once" : `${t.claims} times`} already.
                </p>
              )}
            </li>
          );
        })}
      </ul>

      {anyVisits && quietTonight && (
        <p className="mt-2 text-xs text-accent">Tonight&apos;s a quiet night here — this visit counts double.</p>
      )}
    </section>
  );
}

// ── the recap body: drink grid · attributed list · mood cloud · photo wall ───
function PartyLog({ entries, me }: { entries: PartyEntry[]; me?: string }) {
  const moods = useMemo(() => {
    const m = new Map<string, number>();
    for (const e of entries) {
      const w = e.mood?.trim().toLowerCase();
      if (w) m.set(w, (m.get(w) ?? 0) + 1);
    }
    return [...m.entries()].sort((a, b) => b[1] - a[1]);
  }, [entries]);

  const photos = useMemo(() => entries.flatMap((e) => e.photos.map((p) => ({ ...p, drink: e.drink }))), [entries]);

  return (
    <>
      {/* drink grid — one square per shared drink */}
      <section className="mb-7">
        <p className="label mb-2 text-faint">
          The night in squares · <span className="tnum">{entries.length}</span>
        </p>
        <div className="flex flex-wrap gap-1">
          {entries.map((e) => (
            <span
              key={e.id}
              title={e.drink}
              className="h-4 w-4 rounded-xs"
              style={{ background: "var(--ycell-3)" }}
            />
          ))}
        </div>
      </section>

      {/* attributed but gentle — time order, never ranked */}
      <section className="mb-7">
        <p className="label mb-2 text-faint">Who poured what</p>
        <ul className="divide-y divide-line border-y border-line">
          {entries.map((e) => (
            <li key={e.id} className="py-2.5">
              <p className="text-[15px] text-ink">
                {e.drink}
                {e.mood && <span className="italic text-muted"> · {e.mood}</span>}
              </p>
              <p className="mt-0.5 text-xs text-faint">
                {e.userId === me ? "you" : e.authorName} · {timeOfDayLabel(e.createdAt).toLowerCase()}
              </p>
            </li>
          ))}
        </ul>
      </section>

      {/* mood cloud */}
      {moods.length > 0 && (
        <section className="mb-7">
          <p className="label mb-2 text-faint">How it felt</p>
          <p className="leading-relaxed">
            {moods.map(([word, n], i) => (
              <span
                key={word}
                className={clsx("italic", n >= 3 ? "text-2xl text-ink" : n === 2 ? "text-lg text-ink" : "text-[15px] text-muted")}
              >
                {i > 0 && <span className="not-italic text-faint"> · </span>}
                {word}
              </span>
            ))}
          </p>
        </section>
      )}

      {/* photo wall */}
      {photos.length > 0 && (
        <section className="mb-7">
          <p className="label mb-2 text-faint">The wall</p>
          <div className="grid grid-cols-3 gap-1.5 sm:grid-cols-4">
            {photos.map((p) => (
              // eslint-disable-next-line @next/next/no-img-element
              <img key={p.id} src={p.url} alt={p.drink} className="aspect-square w-full rounded-ctl object-cover" />
            ))}
          </div>
        </section>
      )}
    </>
  );
}
