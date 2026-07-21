"use client";

// Cups — the Together gamification room (Phase C-2). A cup is a small, user-made
// exploration competition: you name it, colour it, pick ONE axis to score on, and set a
// window. Friends join and the leaderboard is derived server-side, counts only (cup_board,
// 044). Everything the maker can pick is honest by construction — the axis palette holds NO
// volume/spend option (lib/cups + the DB CHECK), so "who drank most" is not a cup you can
// make. That's rule #6 enforced where it can't rot.
//
// UX note (maintainer's ask): every action here is a real, visible BUTTON — create, join,
// open, share, leave — never a bare clickable line, so the feature is easy to discover.
import { useState } from "react";
import clsx from "clsx";
import { useAuth } from "@/lib/profile";
import {
  useMyCups,
  useCupBoard,
  useCupTeams,
  createCup,
  joinCup,
  leaveCup,
  deleteCup,
  pickTeam,
  CUP_AXES,
  CUP_SKINS,
  axisLabel,
  isValidCupName,
  isValidWindow,
  type Cup,
  type CupAxis,
  type CupSide,
  type CupSkin,
  type JoinPolicy,
} from "@/lib/cups";
import { MONTH_NAMES, parseKey, todayKey, addDays, toKey } from "@/lib/date";

// A cup's chosen colour — a small, tasteful stripe/dot only, never app chrome. "Your cup,
// your colours" is a sanctioned exception to the one-accent rule, kept muted on purpose.
const SKIN_COLOR: Record<CupSkin, string> = {
  classic: "var(--color-accent)",
  amber: "#d98a2b",
  forest: "#4a8065",
  dusk: "#6f6e93",
  rose: "#c07087",
  mono: "var(--color-ink)",
};

const POLICY_LABEL: Record<JoinPolicy, string> = {
  friends: "Friends",
  fof: "Friends of friends",
  invite: "Invite only",
};

// ── ready-made challenges ────────────────────────────────────────────────────
// One-tap templates (Octalysis CD2: a clear quest beats a blank form). Each is just a
// prefilled cup — the maker can still rename/recolour everything before creating. The
// team ones ship with two sides on, feeding CD5: your side needs you, so you invite.
interface Challenge {
  id: string;
  title: string;
  blurb: string;
  axis: CupAxis;
  days: number;
  skin: CupSkin;
  teamA?: string;
  teamB?: string;
}

const CHALLENGES: Challenge[] = [
  {
    id: "fortnight",
    title: "The Fortnight Wander",
    blurb: "Two weeks, most new drinks tried.",
    axis: "drinks",
    days: 14,
    skin: "amber",
  },
  {
    id: "townhop",
    title: "Around the Town",
    blurb: "A month of new places — one street further.",
    axis: "venues",
    days: 30,
    skin: "forest",
  },
  {
    id: "compass",
    title: "The Compass",
    blurb: "Most different kinds — coffee through cocktails.",
    axis: "varied",
    days: 21,
    skin: "dusk",
  },
  {
    id: "steady",
    title: "Steady Hands",
    blurb: "A week you win with easy nights.",
    axis: "dry",
    days: 7,
    skin: "mono",
  },
  {
    id: "housebattle",
    title: "House Battle",
    blurb: "Two sides, two weeks, widest palate wins.",
    axis: "drinks",
    days: 14,
    skin: "rose",
    teamA: "House Amber",
    teamB: "House Slate",
  },
  {
    id: "citysplit",
    title: "The City Split",
    blurb: "Team vs team — most new places in a month.",
    axis: "venues",
    days: 30,
    skin: "classic",
    teamA: "North side",
    teamB: "South side",
  },
];

function fmtDay(key: string): string {
  const d = parseKey(key);
  return `${MONTH_NAMES[d.getMonth()].slice(0, 3)} ${d.getDate()}`;
}

function cupStatus(cup: Cup): { label: string; live: boolean; ended: boolean } {
  const today = todayKey();
  if (today < cup.startsOn) return { label: `starts ${fmtDay(cup.startsOn)}`, live: false, ended: false };
  if (today > cup.endsOn) return { label: "ended", live: false, ended: true };
  return { label: `until ${fmtDay(cup.endsOn)}`, live: true, ended: false };
}

export function Cups() {
  const me = useAuth().profile?.id;
  const { cups, loading } = useMyCups();
  const [pane, setPane] = useState<"none" | "new" | "join">("none");
  const [preset, setPreset] = useState<Challenge | null>(null);
  const [open, setOpen] = useState<Cup | null>(null);

  if (!me) {
    return (
      <p className="mt-10 text-center text-sm text-faint">
        Sign in to make a cup — a little exploration contest with friends.
      </p>
    );
  }

  return (
    <section className="mt-6">
      <p className="max-w-prose text-sm leading-relaxed text-muted">
        A cup is a friendly contest for <span className="text-ink">exploring</span> — most new drinks, most new
        places, most kinds, or the most easy nights. Never who drank the most; that isn&apos;t a cup you can make.
      </p>

      {/* the two doorways in — visible buttons, side by side */}
      <div className="mt-4 grid grid-cols-2 gap-2">
        <button
          onClick={() => {
            setPreset(null);
            setPane(pane === "new" ? "none" : "new");
          }}
          aria-expanded={pane === "new"}
          className={clsx(
            "min-h-11 rounded-ctl px-4 py-2.5 text-sm font-medium transition-colors",
            pane === "new" ? "bg-accent text-accent-contrast" : "bg-ink text-paper hover:opacity-90",
          )}
        >
          + New cup
        </button>
        <button
          onClick={() => setPane(pane === "join" ? "none" : "join")}
          aria-expanded={pane === "join"}
          className={clsx(
            "min-h-11 rounded-ctl border px-4 py-2.5 text-sm font-medium transition-colors",
            pane === "join" ? "border-accent text-accent" : "border-line text-ink hover:border-line-strong",
          )}
        >
          Join by code
        </button>
      </div>

      {/* ready-made challenges — a horizontal rail of one-tap starts */}
      {pane !== "new" && (
        <div className="mt-5">
          <p className="label mb-2 text-faint">Or start from a challenge</p>
          <div className="scrollbar-none -mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
            {CHALLENGES.map((c) => (
              <button
                key={c.id}
                onClick={() => {
                  setPreset(c);
                  setPane("new");
                }}
                className="glass glass-press w-44 shrink-0 rounded-tile p-3.5 text-left"
              >
                <span aria-hidden className="block h-1 w-8 rounded-full" style={{ background: SKIN_COLOR[c.skin] }} />
                <span className="mt-2 block text-sm font-medium leading-tight text-ink">{c.title}</span>
                <span className="mt-1 block text-xs leading-snug text-faint">{c.blurb}</span>
                <span className="mt-2 block text-xs text-muted">
                  {c.days} days{c.teamA ? " · team vs team" : ""}
                </span>
              </button>
            ))}
          </div>
        </div>
      )}

      {pane === "new" && (
        <CupForm
          meId={me}
          preset={preset}
          onDone={() => {
            setPane("none");
            setPreset(null);
          }}
        />
      )}
      {pane === "join" && <JoinForm onJoined={() => setPane("none")} />}

      {/* my cups */}
      {loading ? (
        <div className="mt-6 space-y-2" aria-hidden>
          {[0, 1].map((i) => (
            <div key={i} className="glass h-20 animate-pulse rounded-tile" />
          ))}
        </div>
      ) : cups.length === 0 ? (
        <p className="mt-8 text-center text-sm text-faint">No cups yet — make one, or join with a code.</p>
      ) : (
        <ul className="mt-6 space-y-2">
          {cups.map((cup) => (
            <li key={cup.id}>
              <CupCard cup={cup} onOpen={() => setOpen(cup)} />
            </li>
          ))}
        </ul>
      )}

      {open && <CupSheet cup={open} meId={me} onClose={() => setOpen(null)} />}
    </section>
  );
}

// One cup in the list — a tappable card (not a link), with its colour, axis, window/status,
// and a peek at who's leading.
function CupCard({ cup, onOpen }: { cup: Cup; onOpen: () => void }) {
  const { standings } = useCupBoard(cup.id);
  const status = cupStatus(cup);
  const leader = standings[0];

  return (
    <button onClick={onOpen} className="glass glass-press flex w-full items-center gap-3 rounded-tile p-4 text-left">
      <span aria-hidden className="h-10 w-1.5 shrink-0 rounded-full" style={{ background: SKIN_COLOR[cup.skin] }} />
      <div className="min-w-0 flex-1">
        <p className="truncate font-display text-lg leading-tight text-ink">{cup.name}</p>
        <p className="mt-0.5 flex flex-wrap items-center gap-x-2 text-xs text-faint">
          <span className="text-muted">{axisLabel(cup.axis)}</span>
          {cup.teamMode && (
            <>
              <span>·</span>
              <span className="text-accent">team vs team</span>
            </>
          )}
          <span>·</span>
          <span className={clsx(status.live && "text-accent")}>{status.label}</span>
          <span>·</span>
          <span className="tnum">
            {standings.length} {standings.length === 1 ? "player" : "players"}
          </span>
        </p>
        {leader && (
          <p className="mt-1 truncate text-xs text-faint">
            Leading: <span className="text-ink">{leader.name}</span>
            <span className="tnum text-muted"> · {leader.score}</span>
          </p>
        )}
      </div>
      <span aria-hidden className="shrink-0 text-sm font-medium text-accent">Open →</span>
    </button>
  );
}

// Create a cup. Name → axis (the honest palette) → look → who can join → window →
// optionally two named sides (a team battle, 047). A preset challenge prefills it all.
function CupForm({ meId, preset, onDone }: { meId: string; preset: Challenge | null; onDone: () => void }) {
  const [name, setName] = useState(preset?.title ?? "");
  const [axis, setAxis] = useState<CupAxis>(preset?.axis ?? "drinks");
  const [skin, setSkin] = useState<CupSkin>(preset?.skin ?? "classic");
  const [policy, setPolicy] = useState<JoinPolicy>("friends");
  const [startsOn, setStartsOn] = useState(todayKey());
  const [endsOn, setEndsOn] = useState(toKey(addDays(parseKey(todayKey()), preset?.days ?? 14)));
  const [teams, setTeams] = useState(!!preset?.teamA);
  const [teamA, setTeamA] = useState(preset?.teamA ?? "");
  const [teamB, setTeamB] = useState(preset?.teamB ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [made, setMade] = useState<{ code: string } | null>(null);

  const teamsValid = !teams || (teamA.trim().length > 0 && teamB.trim().length > 0);
  const valid = isValidCupName(name) && isValidWindow(startsOn, endsOn) && teamsValid;

  async function submit() {
    setBusy(true);
    setError(null);
    const res = await createCup(meId, {
      name,
      axis,
      skin,
      joinPolicy: policy,
      startsOn,
      endsOn,
      teamA: teams ? teamA : undefined,
      teamB: teams ? teamB : undefined,
    });
    setBusy(false);
    if ("error" in res) {
      setError(res.error);
      return;
    }
    setMade({ code: res.inviteCode });
  }

  if (made) {
    return (
      <div className="glass mt-3 rounded-tile p-4">
        <p className="text-sm text-ink">Cup created 🎉</p>
        <p className="mt-1 text-xs text-faint">Share this code so friends can join:</p>
        <div className="mt-3 flex items-center gap-2">
          <code className="tnum flex-1 rounded-ctl bg-ink/5 px-3 py-2.5 text-center text-lg tracking-[0.2em] text-ink">
            {made.code || "—"}
          </code>
          <CopyButton text={made.code} />
        </div>
        <button
          onClick={onDone}
          className="mt-3 min-h-11 w-full rounded-ctl border border-line py-2.5 text-sm text-muted transition-colors hover:text-ink"
        >
          Done
        </button>
      </div>
    );
  }

  return (
    <div className="glass mt-3 space-y-4 rounded-tile p-4">
      <div>
        <label className="mb-1.5 block text-xs text-muted">Name your cup</label>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={40}
          placeholder="The Autumn Wander"
          className="w-full rounded-ctl bg-ink/4 px-3.5 py-2.5 text-[15px] text-ink outline-none placeholder:text-faint focus:bg-ink/6"
        />
      </div>

      <div>
        <p className="mb-1.5 text-xs text-muted">Score it on</p>
        <div className="space-y-1.5">
          {CUP_AXES.map((a) => {
            const active = axis === a.id;
            return (
              <button
                key={a.id}
                onClick={() => setAxis(a.id)}
                aria-pressed={active}
                className={clsx(
                  "flex w-full items-start gap-3 rounded-ctl border p-3 text-left transition-colors",
                  active ? "border-accent bg-accent/8" : "border-line hover:border-line-strong",
                )}
              >
                <span
                  aria-hidden
                  className={clsx(
                    "mt-0.5 grid h-4 w-4 shrink-0 place-items-center rounded-full border-2",
                    active ? "border-accent" : "border-line-strong",
                  )}
                >
                  {active && <span className="h-2 w-2 rounded-full bg-accent" />}
                </span>
                <span className="min-w-0">
                  <span className={clsx("block text-sm", active ? "text-ink" : "text-muted")}>{a.label}</span>
                  <span className="mt-0.5 block text-xs text-faint">{a.blurb}</span>
                </span>
              </button>
            );
          })}
        </div>
      </div>

      <div>
        <p className="mb-1.5 text-xs text-muted">Colour</p>
        <div className="flex flex-wrap gap-2">
          {CUP_SKINS.map((s) => (
            <button
              key={s}
              onClick={() => setSkin(s)}
              aria-label={s}
              aria-pressed={skin === s}
              className={clsx(
                "h-8 w-8 rounded-full border-2 transition-transform hover:scale-110",
                skin === s ? "border-ink" : "border-transparent",
              )}
              style={{ background: SKIN_COLOR[s] }}
            />
          ))}
        </div>
      </div>

      <div>
        <p className="mb-1.5 text-xs text-muted">Who can join</p>
        <div className="flex flex-wrap gap-1.5">
          {(["friends", "fof", "invite"] as JoinPolicy[]).map((p) => (
            <button
              key={p}
              onClick={() => setPolicy(p)}
              aria-pressed={policy === p}
              className={clsx(
                "min-h-11 rounded-ctl border px-3 py-2 text-sm transition-colors",
                policy === p ? "border-accent bg-accent/8 text-ink" : "border-line text-muted hover:text-ink",
              )}
            >
              {POLICY_LABEL[p]}
            </button>
          ))}
        </div>
      </div>

      {/* team battle — two named sides; members pick one after joining */}
      <div>
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="text-sm text-ink">Team battle</p>
            <p className="text-xs text-faint">Two sides — everyone who joins picks one.</p>
          </div>
          <button
            onClick={() => setTeams((t) => !t)}
            role="switch"
            aria-checked={teams}
            aria-label="Team battle"
            className={clsx(
              "relative inline-flex h-7 w-13 shrink-0 items-center rounded-full transition-colors",
              teams ? "bg-accent" : "bg-ink/12 shadow-[inset_0_0_0_1.5px_var(--color-line-strong)]",
            )}
          >
            <span
              className={clsx(
                "h-6 w-6 rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.28)] transition-transform",
                teams ? "translate-x-6.5" : "translate-x-0.5",
              )}
            />
          </button>
        </div>
        {teams && (
          <div className="mt-2.5 flex gap-2">
            <input
              value={teamA}
              onChange={(e) => setTeamA(e.target.value)}
              maxLength={24}
              placeholder="Side one — e.g. North side"
              aria-label="First team name"
              className="w-full flex-1 rounded-ctl bg-ink/4 px-3 py-2.5 text-sm text-ink outline-none placeholder:text-faint focus:bg-ink/6"
            />
            <input
              value={teamB}
              onChange={(e) => setTeamB(e.target.value)}
              maxLength={24}
              placeholder="Side two"
              aria-label="Second team name"
              className="w-full flex-1 rounded-ctl bg-ink/4 px-3 py-2.5 text-sm text-ink outline-none placeholder:text-faint focus:bg-ink/6"
            />
          </div>
        )}
      </div>

      <div className="flex gap-3">
        <label className="flex-1">
          <span className="mb-1.5 block text-xs text-muted">Starts</span>
          <input
            type="date"
            value={startsOn}
            onChange={(e) => setStartsOn(e.target.value)}
            className="w-full rounded-ctl bg-ink/4 px-3 py-2.5 text-[15px] text-ink"
          />
        </label>
        <label className="flex-1">
          <span className="mb-1.5 block text-xs text-muted">Ends</span>
          <input
            type="date"
            value={endsOn}
            min={startsOn}
            onChange={(e) => setEndsOn(e.target.value)}
            className="w-full rounded-ctl bg-ink/4 px-3 py-2.5 text-[15px] text-ink"
          />
        </label>
      </div>

      {error && <p className="text-sm text-accent">{error}</p>}

      <button
        onClick={submit}
        disabled={!valid || busy}
        className="min-h-11 w-full rounded-ctl bg-accent py-3 text-sm font-medium text-accent-contrast transition-opacity hover:opacity-90 disabled:opacity-50"
      >
        {busy ? "Creating…" : "Create cup"}
      </button>
    </div>
  );
}

function JoinForm({ onJoined }: { onJoined: () => void }) {
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setError(null);
    const res = await joinCup(code);
    setBusy(false);
    if ("error" in res) {
      setError(res.error);
      return;
    }
    onJoined();
  }

  return (
    <div className="glass mt-3 rounded-tile p-4">
      <label className="mb-1.5 block text-xs text-muted">Enter a cup&apos;s code</label>
      <div className="flex items-center gap-2">
        <input
          value={code}
          onChange={(e) => setCode(e.target.value)}
          placeholder="e.g. amber-fox"
          className="tnum flex-1 rounded-ctl bg-ink/4 px-3.5 py-2.5 text-[15px] tracking-widest text-ink outline-none placeholder:text-faint placeholder:tracking-normal focus:bg-ink/6"
        />
        <button
          onClick={submit}
          disabled={!code.trim() || busy}
          className="min-h-11 shrink-0 rounded-ctl bg-ink px-4 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
        >
          {busy ? "…" : "Join"}
        </button>
      </div>
      {error && <p className="mt-2 text-sm text-accent">{error}</p>}
    </div>
  );
}

// The cup sheet — the full standings board (plus the two-sided tug-of-war in a team
// battle), the invite code to share, and leave/delete.
function CupSheet({ cup, meId, onClose }: { cup: Cup; meId: string; onClose: () => void }) {
  const { standings, loading } = useCupBoard(cup.id);
  const status = cupStatus(cup);
  const isOwner = cup.createdBy === meId;
  const top = standings[0]?.score ?? 0;

  async function handleLeave() {
    await leaveCup(cup.id, meId);
    onClose();
  }
  async function handleDelete() {
    await deleteCup(cup.id);
    onClose();
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={cup.name}
      className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
    >
      <button aria-label="Close" onClick={onClose} className="animate-fade absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div className="glass-strong animate-sheet relative max-h-[88dvh] w-full max-w-md overflow-y-auto rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4 sm:rounded-[28px] sm:p-8">
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong sm:hidden" />

        <div className="flex items-start gap-3">
          <span aria-hidden className="mt-1 h-10 w-1.5 shrink-0 rounded-full" style={{ background: SKIN_COLOR[cup.skin] }} />
          <div className="min-w-0 flex-1">
            <h2 className="font-display text-2xl leading-tight text-ink">{cup.name}</h2>
            <p className="mt-0.5 text-xs text-faint">
              {axisLabel(cup.axis)} · <span className={clsx(status.live && "text-accent")}>{status.label}</span> ·{" "}
              {POLICY_LABEL[cup.joinPolicy]}
            </p>
          </div>
          <button onClick={onClose} className="shrink-0 text-sm text-faint transition-colors hover:text-ink">
            Close
          </button>
        </div>

        {/* the two sides — only in a team battle */}
        {cup.teamMode && <TeamPanel cup={cup} ended={status.ended} />}

        {/* the board */}
        <p className="label mt-6 mb-2 text-faint">Standings</p>
        {loading ? (
          <div className="space-y-2" aria-hidden>
            {[0, 1, 2].map((i) => (
              <div key={i} className="glass h-11 animate-pulse rounded-ctl" />
            ))}
          </div>
        ) : standings.length === 0 ? (
          <p className="py-4 text-center text-sm text-faint">No scores yet — the board fills as players explore.</p>
        ) : (
          <ul className="divide-y divide-line border-y border-line">
            {standings.map((s, i) => {
              const leads = s.score > 0 && s.score === top;
              const mine = s.userId === meId;
              return (
                <li key={s.userId} className="flex items-center justify-between gap-3 py-2.5">
                  <span className="flex min-w-0 items-center gap-2.5">
                    <span className="tnum w-4 text-xs text-faint">{i + 1}</span>
                    <span className={clsx("truncate text-[15px]", mine ? "text-accent" : "text-ink")}>
                      {mine ? "you" : s.name}
                    </span>
                  </span>
                  <span className={clsx("tnum shrink-0 text-sm", leads ? "text-accent" : "text-muted")}>{s.score}</span>
                </li>
              );
            })}
          </ul>
        )}

        <p className="mt-3 text-xs leading-relaxed text-faint">
          Scored on {axisLabel(cup.axis).toLowerCase()} — counts only, from each player&apos;s own diary. No one is
          ranked by what they drank or spent.
        </p>

        {/* share the code */}
        <div className="mt-6 border-t border-line pt-4">
          <p className="label mb-2 text-faint">Invite code</p>
          <div className="flex items-center gap-2">
            <code className="tnum flex-1 rounded-ctl bg-ink/5 px-3 py-2.5 text-center text-lg tracking-[0.2em] text-ink">
              {cup.inviteCode || "—"}
            </code>
            <CopyButton text={cup.inviteCode} />
          </div>
        </div>

        {/* leave / delete */}
        <div className="mt-6 flex gap-3">
          {isOwner ? (
            <button
              onClick={handleDelete}
              className="min-h-11 flex-1 rounded-ctl border border-line py-2.5 text-sm text-muted transition-colors hover:border-accent hover:text-accent"
            >
              Delete cup
            </button>
          ) : (
            <button
              onClick={handleLeave}
              className="min-h-11 flex-1 rounded-ctl border border-line py-2.5 text-sm text-muted transition-colors hover:border-accent hover:text-accent"
            >
              Leave cup
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// The two sides of a team battle: a tug-of-war bar (widths = share of the combined
// score), each side's players + total, and the JOIN-A-SIDE buttons. Your side needs
// you — that's the whole social engine — but it needs your EXPLORING: a side's score
// is the sum of members' distinct-count scores, so drinking more moves nothing.
function TeamPanel({ cup, ended }: { cup: Cup; ended: boolean }) {
  const { teams, mySide, loading } = useCupTeams(cup);
  const [busy, setBusy] = useState<CupSide | null>(null);
  const [error, setError] = useState<string | null>(null);

  const a = teams.find((t) => t.team === "a") ?? { team: "a" as CupSide, players: 0, score: 0 };
  const b = teams.find((t) => t.team === "b") ?? { team: "b" as CupSide, players: 0, score: 0 };
  const total = a.score + b.score;
  const aShare = total > 0 ? a.score / total : 0.5;

  async function join(side: CupSide) {
    setBusy(side);
    setError(null);
    const err = await pickTeam(cup.id, side);
    setBusy(null);
    if (err) setError(err);
  }

  const SIDES: { side: CupSide; name: string; standing: typeof a }[] = [
    { side: "a", name: cup.teamA ?? "Side one", standing: a },
    { side: "b", name: cup.teamB ?? "Side two", standing: b },
  ];

  return (
    <div className="mt-6 rounded-tile bg-ink/3 p-4">
      <p className="label mb-3 text-faint">The battle</p>

      {loading ? (
        <div className="h-16 animate-pulse rounded-ctl bg-ink/5" aria-hidden />
      ) : (
        <>
          {/* tug-of-war — one bar, split by share of the combined score */}
          <div className="flex h-2.5 overflow-hidden rounded-full bg-ink/8">
            <div
              className="h-full bg-accent transition-[width] duration-700 ease-out motion-reduce:transition-none"
              style={{ width: `${aShare * 100}%` }}
            />
            <div className="h-full flex-1 bg-line-strong/60" />
          </div>

          <div className="mt-3 grid grid-cols-2 gap-3">
            {SIDES.map(({ side, name, standing }) => {
              const mine = mySide === side;
              const leads = total > 0 && standing.score > (side === "a" ? b.score : a.score);
              return (
                <div key={side} className={clsx("rounded-ctl border p-3", mine ? "border-accent bg-accent/6" : "border-line")}>
                  <p className="flex items-baseline justify-between gap-2">
                    <span className={clsx("truncate text-sm", leads ? "font-medium text-accent" : "text-ink")}>{name}</span>
                    <span className={clsx("tnum shrink-0 text-lg", leads ? "text-accent" : "text-ink")}>{standing.score}</span>
                  </p>
                  <p className="mt-0.5 flex items-center justify-between gap-2 text-xs text-faint">
                    <span className="tnum">
                      {standing.players} {standing.players === 1 ? "player" : "players"}
                    </span>
                    {mine && <span className="text-accent">your side</span>}
                  </p>
                  {!ended && !mine && (
                    <button
                      onClick={() => join(side)}
                      disabled={busy !== null}
                      className="mt-2 min-h-9 w-full rounded-ctl bg-ink py-1.5 text-xs font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
                    >
                      {busy === side ? "…" : mySide ? "Switch here" : "Join this side"}
                    </button>
                  )}
                </div>
              );
            })}
          </div>

          {!mySide && !ended && (
            <p className="mt-2.5 text-xs text-faint">Pick a side — your exploring counts for it from then on.</p>
          )}
          {error && <p className="mt-2 text-sm text-accent">{error}</p>}
        </>
      )}
    </div>
  );
}

function CopyButton({ text }: { text: string }) {
  const [done, setDone] = useState(false);
  return (
    <button
      onClick={() => {
        if (!text) return;
        navigator.clipboard?.writeText(text).then(
          () => {
            setDone(true);
            setTimeout(() => setDone(false), 1400);
          },
          () => {},
        );
      }}
      disabled={!text}
      className="min-h-11 shrink-0 rounded-ctl border border-line px-4 text-sm text-muted transition-colors hover:text-ink disabled:opacity-50"
    >
      {done ? "Copied ✓" : "Copy"}
    </button>
  );
}
