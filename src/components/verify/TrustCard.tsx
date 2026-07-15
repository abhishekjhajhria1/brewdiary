"use client";

// The trust card in You → settings. Shows the person their own trust level and how to
// raise it — a coarse anti-bot standing (are you a real, settled human), NOT a rating
// of you as a person and NOT a public ranking. The camera check and, later, friend
// vouches raise it; photo-ID verification is the paid void, shown as "coming soon"
// rather than a dead button.
import { useState } from "react";
import dynamic from "next/dynamic";
import { useMyTrust, trustScore, TRUST_LABEL, identityVerificationAvailable, type TrustLevel } from "@/lib/verify";
import { useMyVouchCount } from "@/lib/vouch";
import { useProfile } from "@/lib/profile";

// MediaPipe lives inside Liveness — load it only when opened, and never on the server.
const Liveness = dynamic(() => import("./Liveness").then((m) => m.Liveness), { ssr: false });

// The score needed to reach the NEXT band, and what that band is called — so we can
// show honest progress instead of a static badge. Mirrors the thresholds in verify.ts.
const NEXT_AT: Record<TrustLevel, number | null> = { new: 4, active: 14, established: 34, trusted: null };
const NEXT_LEVEL: Record<TrustLevel, TrustLevel | null> = {
  new: "active",
  active: "established",
  established: "trusted",
  trusted: null,
};

export function TrustCard() {
  const profile = useProfile();
  const { level, signals } = useMyTrust();
  const vouches = useMyVouchCount();
  const [checking, setChecking] = useState(false);
  const done = Boolean(profile?.presenceChecked);

  if (!profile) return null;

  const score = trustScore(signals);
  const nextAt = NEXT_AT[level];
  const nextLevel = NEXT_LEVEL[level];
  const pct = nextAt ? Math.min(100, Math.round((score / nextAt) * 100)) : 100;

  return (
    <div className="mt-4 border-t border-line py-3">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-ink">Your standing</p>
        <span className="glass rounded-ctl px-2.5 py-1 text-xs font-medium text-muted">{TRUST_LABEL[level]}</span>
      </div>
      <p className="mb-3 mt-1 text-xs leading-relaxed text-faint">
        A quiet signal that you&apos;re a real, settled person — it grows as you use brewdiary and connect with
        friends. It helps others feel comfortable meeting up. It&apos;s never a score of you as a person, and
        nobody sees a ranking.
      </p>

      {/* The live signals feeding it — so it reads as something computed from what you've
          actually done, not an inert badge. */}
      <dl className="mb-3 grid grid-cols-2 gap-x-6 gap-y-1.5">
        <SignalRow label="Days here" value={signals.tenureDays} />
        <SignalRow label="Days logged" value={signals.activeDays} />
        <SignalRow label="Friends" value={signals.friends} />
        <SignalRow label="Vouches" value={signals.vouches ?? 0} />
      </dl>

      {nextAt !== null && nextLevel && (
        <div className="mb-3">
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-ink/10">
            <div className="h-full rounded-full bg-accent transition-[width] duration-500" style={{ width: `${pct}%` }} />
          </div>
          <p className="mt-1.5 text-xs text-faint">
            Keep logging and connecting to reach <span className="text-muted">{TRUST_LABEL[nextLevel]}</span>.
          </p>
        </div>
      )}

      {done ? (
        <p className="text-sm text-accent">✓ You passed the camera check</p>
      ) : (
        <button
          onClick={() => setChecking(true)}
          className="rounded-ctl bg-ink px-4 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90"
        >
          Do a quick camera check
        </button>
      )}
      {!done && (
        <p className="mt-1.5 text-xs text-faint">
          On-device only — no photo is taken or uploaded. Earns a &ldquo;trusted member&rdquo; mark.
        </p>
      )}

      {vouches > 0 && (
        <p className="mt-3 text-xs text-faint">
          <span className="text-muted">{vouches}</span> {vouches === 1 ? "friend vouches" : "friends vouch"} for you.
        </p>
      )}

      {/* the paid-vendor void — a real row, honestly "later", never a dead button */}
      <p className="mt-3 flex items-center justify-between gap-3 text-xs text-faint">
        <span>Photo-ID verification</span>
        <span>{identityVerificationAvailable ? "Available" : "Coming soon"}</span>
      </p>

      {checking && <Liveness onClose={() => setChecking(false)} />}
    </div>
  );
}

function SignalRow({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex items-center justify-between gap-3 text-xs">
      <dt className="text-faint">{label}</dt>
      <dd className="tnum text-muted">{value}</dd>
    </div>
  );
}
