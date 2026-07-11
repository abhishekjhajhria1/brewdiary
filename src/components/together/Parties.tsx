"use client";

// Parties — events inside Together. Host one, invite with a code or the /p/<code>
// link (works for non-users), RSVP, and the party page collects everything
// guests share in. The list lives here; the room itself is /party/<id>.
import Link from "next/link";
import { useEffect, useState } from "react";
import clsx from "clsx";
import { useParties, createParty, joinParty, consumePendingPartyCode, type Party } from "@/lib/parties";
import { useAuth } from "@/lib/profile";
import { MONTH_NAMES, parseKey, todayKey } from "@/lib/date";

export function Parties() {
  const me = useAuth().profile?.id;
  const { parties, loading } = useParties();
  const [mode, setMode] = useState<"idle" | "new" | "join">("idle");
  const [name, setName] = useState("");
  const [date, setDate] = useState(todayKey());
  const [venue, setVenue] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // a party link opened before signing in — honor it now
  useEffect(() => {
    if (!me) return;
    const pending = consumePendingPartyCode();
    if (pending) joinParty(pending);
  }, [me]);

  if (!me) return null;

  async function submit() {
    if (!me || busy) return;
    setBusy(true);
    setError(null);
    if (mode === "new") {
      const r = await createParty(me, { name, date, venue });
      if ("error" in r) setError(r.error);
      else {
        setName("");
        setVenue("");
        setDate(todayKey());
        setMode("idle");
      }
    } else if (mode === "join") {
      const r = await joinParty(code);
      if ("error" in r) setError(r.error);
      else {
        setCode("");
        setMode("idle");
      }
    }
    setBusy(false);
  }

  const today = todayKey();
  const upcoming = parties.filter((p) => p.date >= today);
  const past = parties.filter((p) => p.date < today);

  return (
    <section className="mt-8">
      <div className="mb-3 flex items-baseline justify-between">
        <p className="label text-faint">Parties</p>
        <span className="flex items-center gap-3 text-sm">
          <button
            onClick={() => {
              setMode(mode === "new" ? "idle" : "new");
              setError(null);
            }}
            className={clsx("transition-colors", mode === "new" ? "font-medium text-accent" : "text-muted hover:text-ink")}
          >
            Host one
          </button>
          <button
            onClick={() => {
              setMode(mode === "join" ? "idle" : "join");
              setError(null);
            }}
            className={clsx("transition-colors", mode === "join" ? "font-medium text-accent" : "text-muted hover:text-ink")}
          >
            Join with code
          </button>
        </span>
      </div>

      {mode === "new" && (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
          className="glass mb-3 space-y-3 rounded-tile p-4"
        >
          <div>
            <label className="label mb-1.5 block" htmlFor="party-name">
              What&apos;s the occasion?
            </label>
            <input
              id="party-name"
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Housewarming, friday tasting…"
              className="w-full border-b border-line-strong bg-transparent pb-1.5 text-[15px] outline-none placeholder:text-faint focus:border-ink"
            />
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="label mb-1.5 block" htmlFor="party-date">
                When
              </label>
              <input
                id="party-date"
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="tnum w-full border-b border-line-strong bg-transparent pb-1.5 text-[15px] outline-none focus:border-ink"
              />
            </div>
            <div className="flex-1">
              <label className="label mb-1.5 block" htmlFor="party-venue">
                Where <span className="normal-case text-faint">(optional)</span>
              </label>
              <input
                id="party-venue"
                value={venue}
                onChange={(e) => setVenue(e.target.value)}
                placeholder="A bar, a flat…"
                className="w-full border-b border-line-strong bg-transparent pb-1.5 text-[15px] outline-none placeholder:text-faint focus:border-ink"
              />
            </div>
          </div>
          <button
            type="submit"
            disabled={!name.trim() || !date || busy}
            className={clsx(
              "mt-1 rounded-ctl px-4 py-2 text-sm font-medium transition-colors",
              name.trim() && date && !busy ? "bg-ink text-paper hover:bg-ink/90" : "cursor-not-allowed bg-ink/10 text-faint",
            )}
          >
            Host it
          </button>
          {error && <p className="text-sm text-muted">{error}</p>}
        </form>
      )}

      {mode === "join" && (
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
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="Paste the party code"
              className="glass min-w-0 flex-1 rounded-ctl px-4 py-2.5 text-[15px] outline-none placeholder:text-faint"
            />
            <button
              type="submit"
              disabled={!code.trim() || busy}
              className={clsx(
                "shrink-0 rounded-ctl px-4 py-2.5 text-sm font-medium transition-colors",
                code.trim() && !busy ? "bg-ink text-paper hover:bg-ink/90" : "cursor-not-allowed bg-ink/10 text-faint",
              )}
            >
              Join
            </button>
          </div>
          {error && <p className="mt-2 px-1 text-sm text-muted">{error}</p>}
        </form>
      )}

      {loading ? (
        <div className="glass h-14 animate-pulse rounded-tile" aria-hidden />
      ) : parties.length === 0 ? (
        mode === "idle" && (
          <p className="text-sm text-faint">
            Host a night or join one with a code — everyone logs, the party page becomes the recap.
          </p>
        )
      ) : (
        <>
          <PartyList parties={upcoming} />
          {past.length > 0 && (
            <>
              {upcoming.length > 0 && <p className="label mb-2 mt-4 text-faint">Recaps</p>}
              <PartyList parties={past} muted />
            </>
          )}
        </>
      )}
    </section>
  );
}

function PartyList({ parties, muted }: { parties: Party[]; muted?: boolean }) {
  if (parties.length === 0) return null;
  return (
    <ul className="space-y-2">
      {parties.map((p) => {
        const d = parseKey(p.date);
        return (
          <li key={p.id}>
            <Link
              href={`/party/${p.id}`}
              className="glass glass-press flex w-full items-center justify-between gap-3 rounded-tile px-4 py-3"
            >
              <span className={clsx("min-w-0 truncate text-[15px]", muted ? "text-muted" : "text-ink")}>{p.name}</span>
              <span className="tnum shrink-0 text-xs text-faint">
                {MONTH_NAMES[d.getMonth()].slice(0, 3)} {d.getDate()} · {p.going} going
              </span>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
