"use client";

// Circles — private rooms inside Together. A circle is a few friends and one
// combined mosaic; you join with a code (no public discovery). Loud stuff lives
// here; the Calendar stays a quiet diary.
import { useEffect, useState } from "react";
import clsx from "clsx";
import {
  useCircles,
  useCircleDetail,
  createCircle,
  joinCircle,
  leaveCircle,
  deleteCircle,
  type Circle,
} from "@/lib/circles";
import { useAuth } from "@/lib/profile";
import {
  useChallenges,
  useChallengeBoard,
  createChallenge,
  joinChallenge,
  leaveChallenge,
  deleteChallenge,
  setChallengeWinner,
  KIND_LABEL,
  KIND_UNIT,
  SCORED_KINDS,
  type Challenge,
  type ChallengeKind,
} from "@/lib/challenges";
import { addDays, MONTH_NAMES, parseKey, toKey, todayKey } from "@/lib/date";
import { RecentMosaic } from "./RecentMosaic";
import { Chip } from "../ui/Chip";
import { VenueLink } from "../ui/VenueLink";

export function Circles() {
  const me = useAuth().profile?.id;
  const { circles, loading } = useCircles();
  const [open, setOpen] = useState<Circle | null>(null);
  const [mode, setMode] = useState<"idle" | "new" | "join">("idle");
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (!me) return null;

  async function submit() {
    if (!me || !draft.trim() || busy) return;
    setBusy(true);
    setError(null);
    if (mode === "new") {
      const err = await createCircle(me, draft);
      if (err) setError(err);
      else {
        setDraft("");
        setMode("idle");
      }
    } else if (mode === "join") {
      const r = await joinCircle(draft);
      if ("error" in r) setError(r.error);
      else {
        setDraft("");
        setMode("idle");
      }
    }
    setBusy(false);
  }

  return (
    <section className="mt-8">
      <div className="mb-3 flex items-baseline justify-between">
        <p className="label text-faint">Circles</p>
        <span className="flex items-center gap-3 text-sm">
          <button
            onClick={() => {
              setMode(mode === "new" ? "idle" : "new");
              setDraft("");
              setError(null);
            }}
            className={clsx("transition-colors", mode === "new" ? "font-medium text-accent" : "text-muted hover:text-ink")}
          >
            New
          </button>
          <button
            onClick={() => {
              setMode(mode === "join" ? "idle" : "join");
              setDraft("");
              setError(null);
            }}
            className={clsx("transition-colors", mode === "join" ? "font-medium text-accent" : "text-muted hover:text-ink")}
          >
            Join with code
          </button>
        </span>
      </div>

      {mode !== "idle" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
          className="mb-3"
        >
          <div className="flex items-center gap-2">
            <input
              autoFocus
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              placeholder={mode === "new" ? "Name the circle — “tuesday tastings”…" : "Paste the invite code"}
              className="glass min-w-0 flex-1 rounded-ctl px-4 py-2.5 text-[15px] outline-none placeholder:text-faint"
            />
            <button
              type="submit"
              disabled={!draft.trim() || busy}
              className={clsx(
                "shrink-0 rounded-ctl px-4 py-2.5 text-sm font-medium transition-colors",
                draft.trim() && !busy ? "bg-ink text-paper hover:bg-ink/90" : "cursor-not-allowed bg-ink/10 text-faint",
              )}
            >
              {mode === "new" ? "Create" : "Join"}
            </button>
          </div>
          {error && <p className="mt-2 px-1 text-sm text-muted">{error}</p>}
        </form>
      )}

      {loading ? (
        <div className="glass h-14 animate-pulse rounded-tile" aria-hidden />
      ) : circles.length === 0 ? (
        mode === "idle" && (
          <p className="text-sm text-faint">
            A circle is a private room — a few friends, one combined mosaic. Start one, or join with a code.
          </p>
        )
      ) : (
        <ul className="space-y-2">
          {circles.map((c) => (
            <li key={c.id}>
              <button
                onClick={() => setOpen(c)}
                className="glass glass-press flex w-full items-center justify-between gap-3 rounded-tile px-4 py-3 text-left"
              >
                <span className="min-w-0 truncate text-[15px] text-ink">{c.name}</span>
                <span className="tnum shrink-0 text-xs text-faint">
                  {c.memberCount} {c.memberCount === 1 ? "member" : "members"}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {open && <CircleSheet circle={open} onClose={() => setOpen(null)} />}
    </section>
  );
}

// ── circle sheet: roster + invite code + combined mosaic + what's been shared ─
function CircleSheet({ circle, onClose }: { circle: Circle; onClose: () => void }) {
  const me = useAuth().profile?.id;
  const { members, entries, loading } = useCircleDetail(circle.id);
  const [copied, setCopied] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const counts = new Map<string, number>();
  for (const e of entries) counts.set(e.date, (counts.get(e.date) ?? 0) + 1);
  const mine = circle.createdBy === me;

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(circle.inviteCode);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard unavailable — the code is visible to copy by hand */
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center" onClick={onClose}>
      <div className="absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div
        onClick={(e) => e.stopPropagation()}
        className="glass-strong animate-sheet relative max-h-[88dvh] w-full max-w-md overflow-y-auto rounded-t-[28px] p-6 sm:rounded-[28px] sm:p-8"
      >
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="font-display text-2xl leading-tight text-ink">{circle.name}</h2>
            <p className="mt-1 text-xs text-faint">
              {members.map((m) => (m.id === me ? "you" : m.name)).join(", ") || "…"}
            </p>
          </div>
          <button onClick={onClose} className="shrink-0 text-sm text-faint transition-colors hover:text-ink">
            Close
          </button>
        </div>

        {/* invite */}
        <div className="mt-6 flex items-center justify-between gap-3 border-y border-line py-3">
          <div className="min-w-0">
            <p className="label mb-0.5 text-faint">Invite code</p>
            <p className="tnum select-all text-[15px] tracking-[0.14em] text-ink">{circle.inviteCode}</p>
          </div>
          <button
            onClick={copyCode}
            className={clsx("shrink-0 text-sm transition-colors", copied ? "font-medium text-accent" : "text-muted hover:text-ink")}
          >
            {copied ? "Copied" : "Copy"}
          </button>
        </div>

        {/* combined mosaic */}
        <p className="label mt-6 mb-3 text-faint">Last 12 weeks, all of you</p>
        <RecentMosaic counts={counts} />

        {/* challenges — the circle's loud corner, opt-in */}
        <CircleChallenges circleId={circle.id} />

        {/* what's been shared in */}
        <p className="label mt-7 mb-2 text-faint">Shared here</p>
        {loading ? (
          <div className="glass h-16 animate-pulse rounded-tile" aria-hidden />
        ) : entries.length === 0 ? (
          <p className="text-sm text-faint">Nothing yet. Share an entry from your diary — tap it, then Circles.</p>
        ) : (
          <ul className="divide-y divide-line border-y border-line">
            {entries.map((e) => (
              <li key={e.id} className="py-2.5">
                <p className="text-[15px] text-ink">
                  {e.drink}
                  {e.mood && <span className="italic text-muted"> · {e.mood}</span>}
                </p>
                <p className="mt-0.5 text-xs text-faint">
                  {e.userId === me ? "you" : e.authorName} · {MONTH_NAMES[parseKey(e.date).getMonth()].slice(0, 3)}{" "}
                  <span className="tnum">{parseKey(e.date).getDate()}</span>
                  {e.venue ? <> · <VenueLink venue={e.venue} /></> : ""}
                </p>
              </li>
            ))}
          </ul>
        )}

        {/* leave / delete circle */}
        <div className="mt-7 text-sm">
          {mine ? (
            confirmDelete ? (
              <span className="flex items-center gap-3">
                <span className="text-muted">Delete for everyone?</span>
                <button
                  onClick={async () => {
                    await deleteCircle(circle.id);
                    onClose();
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
                Delete circle
              </button>
            )
          ) : (
            <button
              onClick={async () => {
                if (me) await leaveCircle(circle.id, me);
                onClose();
              }}
              className="text-faint transition-colors hover:text-ink"
            >
              Leave circle
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ── challenges inside the circle — strictly opt-in, counts only ──────────────
const DURATIONS = [7, 14, 30] as const;

function CircleChallenges({ circleId }: { circleId: string }) {
  const me = useAuth().profile?.id;
  const { challenges, loading } = useChallenges(circleId);
  const [creating, setCreating] = useState(false);
  const [mode, setMode] = useState<"challenge" | "competition">("challenge");
  const [title, setTitle] = useState("");
  const [rule, setRule] = useState("");
  const [kind, setKind] = useState<ChallengeKind>("longest_streak");
  const [nights, setNights] = useState<number>(7);
  const [busy, setBusy] = useState(false);

  // a competition needs a name + a rule; a challenge can start with just a type
  const canStart = mode === "competition" ? Boolean(title.trim() && rule.trim()) : true;

  async function start() {
    if (!me || busy || !canStart) return;
    setBusy(true);
    const startsOn = todayKey();
    const endsOn = toKey(addDays(parseKey(startsOn), Math.max(1, nights) - 1));
    await createChallenge(me, circleId, {
      kind: mode === "competition" ? "freeform" : kind,
      startsOn,
      endsOn,
      title: title.trim() || undefined,
      rule: mode === "competition" ? rule.trim() : undefined,
    });
    setCreating(false);
    setBusy(false);
    setTitle("");
    setRule("");
  }

  return (
    <section className="mt-7">
      <div className="mb-2 flex items-baseline justify-between">
        <p className="label text-faint">Challenges</p>
        <button
          onClick={() => setCreating((v) => !v)}
          className={clsx("text-sm transition-colors", creating ? "font-medium text-accent" : "text-muted hover:text-ink")}
        >
          New
        </button>
      </div>

      {creating && (
        <div className="mb-3 space-y-3 border-y border-line py-3">
          {/* auto-scored challenge, or a free-form competition you judge yourself */}
          <div className="flex gap-1.5">
            <Chip active={mode === "challenge"} onClick={() => setMode("challenge")}>
              Challenge
            </Chip>
            <Chip active={mode === "competition"} onClick={() => setMode("competition")}>
              Competition
            </Chip>
          </div>

          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={
              mode === "competition"
                ? "Name it — e.g. Best homemade cocktail"
                : "Name it (optional) — e.g. Negroni Week"
            }
            className="w-full border-b border-line-strong bg-transparent pb-1.5 text-sm outline-none placeholder:text-faint focus:border-ink"
          />

          {mode === "challenge" ? (
            <div className="flex flex-wrap gap-1.5">
              {SCORED_KINDS.map((k) => (
                <Chip key={k} active={kind === k} onClick={() => setKind(k)}>
                  {KIND_LABEL[k]}
                </Chip>
              ))}
            </div>
          ) : (
            <textarea
              value={rule}
              onChange={(e) => setRule(e.target.value)}
              rows={2}
              placeholder="The rule — e.g. post your best pour; everyone votes on the last night. You pick the winner."
              className="w-full resize-none rounded-ctl border border-line-strong bg-transparent px-3 py-2 text-sm outline-none placeholder:text-faint focus:border-ink"
            />
          )}

          <div className="flex flex-wrap items-center gap-1.5">
            {DURATIONS.map((n) => (
              <Chip key={n} active={nights === n} onClick={() => setNights(n)}>
                {n} nights
              </Chip>
            ))}
            <input
              type="number"
              min={1}
              max={365}
              value={nights}
              onChange={(e) => setNights(Math.max(1, Math.min(365, Number(e.target.value) || 1)))}
              aria-label="Custom length in nights"
              className="tnum w-14 rounded-ctl border border-line-strong bg-transparent px-2 py-1 text-sm outline-none focus:border-ink"
            />
            <span className="text-xs text-faint">nights</span>
            <button
              onClick={start}
              disabled={busy || !canStart}
              className="ml-auto text-sm font-medium text-accent transition-opacity hover:opacity-80 disabled:opacity-40"
            >
              Start tonight →
            </button>
          </div>
        </div>
      )}

      {loading ? (
        <div className="glass h-12 animate-pulse rounded-tile" aria-hidden />
      ) : challenges.length === 0 ? (
        !creating && <p className="text-sm text-faint">None running. Anyone in the circle can start one — joining is opt-in.</p>
      ) : (
        <ul className="space-y-4">
          {challenges.map((c) => (
            <ChallengeBlock key={c.id} challenge={c} meId={me} />
          ))}
        </ul>
      )}
      {challenges.length > 0 && (
        <p className="mt-3 text-xs text-faint">Opt-in — auto-scored challenges count only (never what you poured); competitions are judged by whoever started them. Nothing shows on any calendar.</p>
      )}
    </section>
  );
}

function ChallengeBlock({ challenge, meId }: { challenge: Challenge; meId?: string }) {
  const { board, loading } = useChallengeBoard(challenge);
  const joined = meId ? challenge.participantIds.includes(meId) : false;
  const ended = challenge.endsOn < todayKey();
  const s = parseKey(challenge.startsOn);
  const e = parseKey(challenge.endsOn);
  const top = board.length > 0 ? board[0].value : 0;
  const freeform = challenge.kind === "freeform";
  const isCreator = challenge.createdBy === meId;
  const heading = challenge.title?.trim() || KIND_LABEL[challenge.kind];

  return (
    <li className="border-t border-line pt-3">
      <div className="flex items-baseline justify-between gap-3">
        <p className="text-[15px] text-ink">
          {heading}
          <span className="tnum text-xs text-faint">
            {"  "}
            {MONTH_NAMES[s.getMonth()].slice(0, 3)} {s.getDate()} – {MONTH_NAMES[e.getMonth()].slice(0, 3)} {e.getDate()}
            {ended && " · ended"}
          </span>
        </p>
        <span className="flex shrink-0 items-center gap-3 text-sm">
          {!ended &&
            meId &&
            (joined ? (
              <button onClick={() => leaveChallenge(challenge.id, meId)} className="text-faint hover:text-ink">
                Leave
              </button>
            ) : (
              <button onClick={() => joinChallenge(challenge.id, meId)} className="font-medium text-accent hover:opacity-80">
                Join in
              </button>
            ))}
          {isCreator && (
            <button onClick={() => deleteChallenge(challenge.id)} className="text-faint hover:text-ink">
              Remove
            </button>
          )}
        </span>
      </div>

      {/* the competition's rule, in the creator's words */}
      {freeform && challenge.rule && <p className="mt-1 text-sm italic text-muted">{challenge.rule}</p>}

      {loading ? (
        <p className="mt-2 text-sm text-faint">…</p>
      ) : board.length === 0 ? (
        <p className="mt-2 text-sm text-faint">No one&apos;s in yet.</p>
      ) : freeform ? (
        // free-form: names only, the creator picks the winner (no counts)
        <ul className="mt-2 space-y-1">
          {board.map((row) => {
            const isWinner = challenge.winnerId === row.userId;
            return (
              <li key={row.userId} className="flex items-baseline justify-between gap-3 text-sm">
                <span
                  className={clsx(
                    isWinner ? "font-medium text-accent" : row.userId === meId ? "text-ink" : "text-muted",
                  )}
                >
                  {row.userId === meId ? "you" : row.name}
                  {isWinner && <span className="label ml-1.5 text-accent">winner</span>}
                </span>
                {isCreator && (
                  <button
                    onClick={() => setChallengeWinner(challenge.id, isWinner ? null : row.userId)}
                    className="shrink-0 text-xs text-faint transition-colors hover:text-ink"
                  >
                    {isWinner ? "clear" : "pick winner"}
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      ) : (
        // auto-scored leaderboard
        <ol className="mt-2 space-y-1">
          {board.map((row) => (
            <li key={row.userId} className="flex items-baseline justify-between text-sm">
              <span className={clsx(row.userId === meId ? "text-ink" : "text-muted")}>
                {row.userId === meId ? "you" : row.name}
              </span>
              <span className={clsx("tnum", row.value === top && top > 0 ? "font-medium text-accent" : "text-muted")}>
                {row.value} {KIND_UNIT[challenge.kind]}
              </span>
            </li>
          ))}
        </ol>
      )}
    </li>
  );
}
