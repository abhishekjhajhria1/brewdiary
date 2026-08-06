"use client";

// NightComposer — the ONE form that starts a night.
//
// It replaces two: "Plan a night" (Plans) and "Host one" (Parties). Those asked the
// user to decide, before they had decided anything, whether the thing in their head
// was a plan or a party — two near-identical forms with different powers and no way
// across. Here there is one form, and the only question that shapes it is the honest
// one: WHO IS THIS FOR.
//
// The audience ladder runs private → open and stops at friends-of-friends. There is
// no stranger tier and the database CHECK refuses one. "Anyone with the link" is not
// a fifth rung — it is a room's invite code, a link the host hands out themselves,
// and whoever follows it still lands in the approval queue.
import { useEffect, useMemo, useState } from "react";
import clsx from "clsx";
import { createPlan, inviteToPlan, type JoinPolicy } from "@/lib/plans";
import { AUDIENCES, openNightRoom, nightShareUrl, fetchNightCode, type Audience } from "@/lib/nights";
import { useAuth } from "@/lib/profile";
import { useMySanction } from "@/lib/moderation";
import { type DirectoryVenue } from "@/lib/reservations";
import { Field, SanctionBanner, UserSearch, VenueSearch, inputClass, type PickedUser } from "./pickers";

export function NightComposer({ onClose, onCreated }: { onClose: () => void; onCreated?: (id: string) => void }) {
  const me = useAuth().profile?.id;
  const sanction = useMySanction();

  const [title, setTitle] = useState("");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("");
  const [city, setCity] = useState("");
  const [venue, setVenue] = useState<DirectoryVenue | null>(null);
  const [note, setNote] = useState("");
  const [drinks, setDrinks] = useState("");
  const [audience, setAudience] = useState<Audience>("friends");
  const [invited, setInvited] = useState<PickedUser[]>([]);
  const [cap, setCap] = useState("");
  const [wantLink, setWantLink] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // Set after a successful create when a link was asked for — the sheet turns into
  // the "here's your link" step rather than closing and hiding the thing you wanted.
  const [link, setLink] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  // Post-mount so the date `min` can't cause an SSR/client hydration mismatch.
  const today = useMemo(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  useEffect(() => {
    if (!copied) return;
    const t = setTimeout(() => setCopied(false), 1600);
    return () => clearTimeout(t);
  }, [copied]);

  const isPrivate = audience === "private";
  const isInvite = audience === "invite";
  // A private night is yours alone, so there is nobody to hand a link to.
  const canShare = !isPrivate;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!me || busy) return;
    setBusy(true);
    setErr(null);

    const res = await createPlan(me, {
      title,
      date,
      time: time || undefined,
      city,
      note,
      drinks: drinks
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean),
      joinPolicy: audience as JoinPolicy,
      capacity: isPrivate || !cap ? undefined : Number(cap),
      venueId: venue?.id,
    });
    if ("error" in res) {
      setBusy(false);
      setErr(res.error);
      return;
    }

    // Invite the named people now that the night exists (the server re-checks each).
    if (isInvite && invited.length > 0) {
      await Promise.all(invited.map((u) => inviteToPlan(res.id, u.id)));
    }

    // Asked for a link → open the room straight away and show it.
    if (wantLink && canShare) {
      const room = await openNightRoom(res.id);
      if ("partyId" in room) {
        const code = await fetchNightCode(room.partyId);
        if (code) {
          setBusy(false);
          setLink(nightShareUrl(code));
          onCreated?.(res.id);
          return;
        }
      }
    }

    setBusy(false);
    onCreated?.(res.id);
    onClose();
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Start a night"
      className="fixed inset-0 z-50 flex items-end justify-center sm:items-center"
    >
      <button aria-label="Close" onClick={onClose} className="animate-fade absolute inset-0 bg-ink/40 backdrop-blur-sm" />
      <div className="glass-strong animate-sheet relative max-h-[92dvh] w-full max-w-md overflow-y-auto rounded-t-[28px] bg-canvas/90 px-5 pb-8 pt-4 sm:rounded-tile">
        <div aria-hidden className="mx-auto mb-4 h-1 w-9 rounded-full bg-line-strong sm:hidden" />

        {link ? (
          // ── the link step ───────────────────────────────────────────────────
          <div>
            <p className="label text-faint">Your night is on</p>
            <p className="mt-1 font-display text-3xl leading-none text-ink">Share the link</p>
            <p className="mt-3 text-sm leading-relaxed text-muted">
              Anyone can open this, account or not. Whoever follows it asks to come in — you still decide.
            </p>
            <p className="glass mt-4 select-all break-all rounded-ctl px-4 py-3 text-sm text-ink">{link}</p>
            <button
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(link);
                  setCopied(true);
                } catch {}
              }}
              className="mt-3 flex h-12 w-full items-center justify-center rounded-ctl bg-ink text-base font-medium text-paper transition-opacity hover:opacity-90"
            >
              {copied ? "Copied" : "Copy link"}
            </button>
            <button
              onClick={onClose}
              className="mt-2 flex h-11 w-full items-center justify-center rounded-ctl text-sm text-faint transition-colors hover:text-ink"
            >
              Done
            </button>
          </div>
        ) : sanction ? (
          <div className="pb-2">
            <SanctionBanner sanction={sanction} />
            <button
              onClick={onClose}
              className="flex h-11 w-full items-center justify-center rounded-ctl text-sm text-faint transition-colors hover:text-ink"
            >
              Close
            </button>
          </div>
        ) : (
          <form onSubmit={submit}>
            <p className="label text-faint">Start a night</p>
            <p className="mt-1 font-display text-3xl leading-none text-ink">What&apos;s the plan?</p>

            <div className="mt-5 space-y-4">
              <Field label="What is it">
                <input
                  autoFocus
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Negronis at Toit"
                  className={inputClass}
                  aria-label="What is it"
                />
              </Field>

              <div className="flex gap-2">
                <Field label="When" className="flex-1">
                  <input
                    type="date"
                    value={date}
                    min={today}
                    onChange={(e) => setDate(e.target.value)}
                    className={clsx(inputClass, "tnum")}
                    aria-label="Date"
                  />
                </Field>
                <Field label="Time" optional className="w-32">
                  <input
                    type="time"
                    value={time}
                    onChange={(e) => setTime(e.target.value)}
                    className={clsx(inputClass, "tnum")}
                    aria-label="Start time"
                  />
                </Field>
              </div>

              <Field label="Where" optional hint="Pick a bar on brewdiary and friends can book a table there.">
                <input
                  value={city}
                  onChange={(e) => setCity(e.target.value)}
                  placeholder="City or area"
                  className={clsx(inputClass, "mb-2")}
                  aria-label="City or area"
                />
                <VenueSearch picked={venue} onPick={setVenue} />
              </Field>

              <Field label="Anything to add" optional>
                <textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Kitchen shuts at 10, come hungry"
                  rows={2}
                  className={clsx(inputClass, "resize-none")}
                  aria-label="Note"
                />
              </Field>

              <Field label="What you fancy" optional hint="Soft tags, comma-separated — they help friends know the shape of it.">
                <input
                  value={drinks}
                  onChange={(e) => setDrinks(e.target.value)}
                  placeholder="negroni, something local"
                  className={inputClass}
                  aria-label="Drinks"
                />
              </Field>

              <Field
                label="Who's it for"
                hint={`${AUDIENCES.find((a) => a.id === audience)?.hint} There's no public option — on purpose.`}
              >
                <div className="grid grid-cols-2 gap-1.5">
                  {AUDIENCES.map((a) => (
                    <button
                      key={a.id}
                      type="button"
                      onClick={() => setAudience(a.id)}
                      aria-pressed={audience === a.id}
                      className={clsx(
                        "min-h-11 rounded-ctl px-3 py-2 text-sm transition-colors",
                        audience === a.id ? "bg-ink text-paper" : "glass glass-press text-muted hover:text-ink",
                      )}
                    >
                      {a.label}
                    </button>
                  ))}
                </div>
              </Field>

              {isInvite && (
                <div className="space-y-2 rounded-ctl border border-line p-3">
                  <p className="text-xs text-faint">They answer you directly — no queue, since you picked them.</p>
                  <UserSearch exclude={new Set(invited.map((u) => u.id))} onPick={(u) => setInvited((p) => (p.some((x) => x.id === u.id) ? p : [...p, u]))} />
                  {invited.length > 0 && (
                    <div className="flex flex-wrap gap-1.5">
                      {invited.map((u) => (
                        <button
                          key={u.id}
                          type="button"
                          onClick={() => setInvited((p) => p.filter((x) => x.id !== u.id))}
                          aria-label={`Remove ${u.name}`}
                          className="inline-flex min-h-9 items-center gap-1.5 rounded-ctl bg-ink px-2.5 py-1 text-xs text-paper transition-opacity hover:opacity-90"
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
                <Field label="Cap the numbers" optional>
                  <input
                    type="number"
                    min={1}
                    max={50}
                    value={cap}
                    onChange={(e) => setCap(e.target.value)}
                    placeholder="Max people"
                    className={clsx(inputClass, "tnum")}
                    aria-label="Maximum people"
                  />
                </Field>
              )}

              {canShare && (
                <button
                  type="button"
                  onClick={() => setWantLink((v) => !v)}
                  aria-pressed={wantLink}
                  className={clsx(
                    "flex w-full items-start gap-3 rounded-ctl border p-3 text-left transition-colors",
                    wantLink ? "border-transparent bg-accent/10" : "border-line hover:border-line-strong",
                  )}
                >
                  <span
                    aria-hidden
                    className={clsx(
                      "mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-md border text-[11px] leading-none",
                      wantLink ? "border-transparent bg-ink text-paper" : "border-line-strong text-transparent",
                    )}
                  >
                    ✓
                  </span>
                  <span className="min-w-0">
                    <span className="block text-sm text-ink">Also give me a share link</span>
                    <span className="mt-0.5 block text-xs leading-relaxed text-faint">
                      For the group chat, and for people not on brewdiary. They still ask to come in.
                    </span>
                  </span>
                </button>
              )}
            </div>

            {err && (
              <p role="alert" className="mt-3 text-sm text-accent">
                {err}
              </p>
            )}

            <button
              type="submit"
              disabled={busy || !title.trim() || !date}
              className="mt-5 flex h-12 w-full items-center justify-center rounded-ctl bg-ink text-base font-medium text-paper transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {busy ? "Starting…" : isPrivate ? "Save to my calendar" : "Start the night"}
            </button>
            <button
              type="button"
              onClick={onClose}
              className="mt-2 flex h-11 w-full items-center justify-center rounded-ctl text-sm text-faint transition-colors hover:text-ink"
            >
              Cancel
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
