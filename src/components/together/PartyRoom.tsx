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
} from "@/lib/parties";
import { useAuth } from "@/lib/profile";
import { MONTH_NAMES, parseKey, timeOfDayLabel, todayKey } from "@/lib/date";

const RSVP_LABEL: Record<Rsvp, string> = { going: "Going", maybe: "Maybe", no: "Can't" };

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
